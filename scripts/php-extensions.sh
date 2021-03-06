#!/bin/bash
set -e
source /scripts/buildconfig

echo -e "\n[i] Install PHP-Extensions\n"
mv /usr/local/etc/php/php.ini-production /usr/local/etc/php/php.ini

# Build packages will be added during the build, but will be removed at the end.
BUILD_PACKAGES="gettext gnupg libcurl4-openssl-dev libfreetype6-dev libicu-dev libjpeg62-turbo-dev \
  libldap2-dev libmariadbclient-dev libmemcached-dev libpng-dev libpq-dev libxml2-dev libxslt-dev \
  unixodbc-dev libzip-dev libsqlite3-dev libgeoip-dev libmagickwand-dev libpspell-dev"

# Packages for Postgres.
PACKAGES_POSTGRES="libpq5"

# Packages for MariaDB and MySQL.
PACKAGES_MYMARIA="libmariadbclient18"

# Packages for other Moodle runtime dependenices.
PACKAGES_RUNTIME="ghostscript libaio1 libcurl3 libgss3 libicu57 libmcrypt-dev libxml2 libxslt1.1 locales sassc unzip unixodbc"

# Packages for Memcached.
PACKAGES_MEMCACHED="libmemcached11 libmemcachedutil2"

# Packages for LDAP.
PACKAGES_LDAP="libldap-2.4-2"

apt-get update
savedAptMark="$(apt-mark showmanual)"
$minimal_apt_get_install \
    $BUILD_PACKAGES \
    $PACKAGES_POSTGRES \
    $PACKAGES_MYMARIA \
    $PACKAGES_RUNTIME \
    $PACKAGES_MEMCACHED \
    $PACKAGES_LDAP

debMultiarch="$(dpkg-architecture --query DEB_BUILD_MULTIARCH)"
docker-php-ext-configure gd --with-freetype-dir=/usr/include/ --with-png-dir=/usr --with-jpeg-dir=/usr
docker-php-ext-configure ldap --with-libdir="lib/$debMultiarch"
docker-php-ext-install \
	exif \
	fileinfo \
        gd \
        intl \
	json \
        ldap \
	mbstring \
	opcache \
	pcntl \
	mysqli \
	pdo \
        pdo_mysql \
        pdo_pgsql \
        pdo_sqlite \
	session \
	simplexml \
	soap \
	xsl \
	xmlrpc \
	zip

# Memcached, Redis, APCu, igbinary.
pecl install memcached redis apcu igbinary
docker-php-ext-enable memcached redis apcu igbinary

# Imagemagick
pecl install imagick
docker-php-ext-enable imagick

# Additional PHP modules
docker-php-ext-install iconv mcrypt pspell

# Microsoft SQL Server Driver
pecl install sqlsrv
docker-php-ext-enable sqlsrv

# set recommended PHP.ini settings
echo 'opcache.enable=1' >> /usr/local/etc/php/conf.d/opcache-recommended.ini
echo 'opcache.enable_cli=1' >> /usr/local/etc/php/conf.d/opcache-recommended.ini
echo 'opcache.interned_strings_buffer=8' >> /usr/local/etc/php/conf.d/opcache-recommended.ini
echo 'opcache.max_accelerated_files=10000' >> /usr/local/etc/php/conf.d/opcache-recommended.ini
echo 'opcache.memory_consumption=128' >> /usr/local/etc/php/conf.d/opcache-recommended.ini
echo 'opcache.save_comments=1' >> /usr/local/etc/php/conf.d/opcache-recommended.ini
echo 'opcache.revalidate_freq=1' >> /usr/local/etc/php/conf.d/opcache-recommended.ini
echo 'apc.enable_cli=1' >> /usr/local/etc/php/conf.d/docker-php-ext-apcu.ini
echo 'memory_limit=512M' > /usr/local/etc/php/conf.d/memory-limit.ini
sed -i 's*; display_errors*display_errors = off*g' /usr/local/etc/php/php.ini

# reset apt-mark's "manual" list so that "purge --auto-remove" will remove all build dependencies
apt-mark auto '.*' > /dev/null;
apt-mark manual $savedAptMark;
ldd "$(php -r 'echo ini_get("extension_dir");')"/*.so \
        | awk '/=>/ { print $3 }' \
        | sort -u \
	| xargs -r dpkg-query -S \
	| cut -d: -f1 \
	| sort -u \
	| xargs -rt apt-mark manual
apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false $BUILD_PACKAGES

exit 0
