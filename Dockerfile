FROM php:7.2-apache

# If building on a RPi, use --build-arg cores=3 to use all cores when compiling
# to speed up the image build
ARG CORES
ENV CORES ${CORES:-1}

ENV FIREFLY_PATH=/var/www/firefly-iii/ CURL_VERSION=7.60.0 OPENSSL_VERSION=1.1.1-pre6 COMPOSER_ALLOW_SUPERUSER=1
LABEL version="1.2" maintainer="thegrumpydictator@gmail.com"

# install packages
RUN apt-get update -y && \
    apt-get install -y --no-install-recommends libcurl4-openssl-dev \
                                               zlib1g-dev \
                                               libjpeg62-turbo-dev \
                                               wget \
                                               libpng-dev \
                                               libicu-dev \
                                               libldap2-dev \
                                               libedit-dev \
                                               libtidy-dev \
                                               libxml2-dev \
                                               unzip \
                                               libsqlite3-dev \
                                               nano \
                                               curl \
                                               openssl \
                                               libpq-dev \
                                               libbz2-dev \
                                               gettext-base \
                                               cron \
                                               rsyslog \
                                               supervisor \
                                               locales && \
                                               apt-get clean && \
                                               rm -rf /var/lib/apt/lists/* && \
                                               docker-php-ext-configure ldap --with-libdir=lib/x86_64-linux-gnu/ && \
                                               docker-php-ext-install ldap


# Make sure that libcurl is using the newer curl libaries
#RUN echo "/usr/local/lib" >> /etc/ld.so.conf.d/00-curl.conf && ldconfig

# Mimic the Debian/Ubuntu config file structure for supervisor
COPY .deploy/docker/supervisord.conf /etc/supervisor/supervisord.conf
RUN mkdir -p /etc/supervisor/conf.d /var/log/supervisor

# copy Firefly III supervisor conf file.
COPY ./.deploy/docker/firefly-iii.conf /etc/supervisor/conf.d/firefly-iii.conf

# copy cron job supervisor conf file.
COPY ./.deploy/docker/cronjob.conf /etc/supervisor/conf.d/cronjob.conf

# copy ca certs to correct location
COPY ./.deploy/docker/cacert.pem /usr/local/ssl/cert.pem

# test crons added via crontab
RUN echo "0 3 * * * /usr/local/bin/php /var/www/firefly-iii/artisan firefly:cron" | crontab -
#RUN (crontab -l ; echo "*/1 * * * * free >> /var/www/firefly-iii/public/cron.html") 2>&1 | crontab -

# Install PHP exentions, install composer, update languages.
RUN docker-php-ext-install -j$(nproc) gd intl tidy zip curl bcmath pdo_mysql bz2 pdo_pgsql && \
    curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer && \
    echo "en_US.UTF-8 UTF-8\nde_DE.UTF-8 UTF-8\nfr_FR.UTF-8 UTF-8\nit_IT.UTF-8 UTF-8\nnl_NL.UTF-8 UTF-8\npl_PL.UTF-8 UTF-8\npt_BR.UTF-8 UTF-8\nru_RU.UTF-8 UTF-8\ntr_TR.UTF-8 UTF-8\n\n" > /etc/locale.gen && locale-gen

# copy Apache config to correct spot.
COPY ./.deploy/docker/apache2.conf /etc/apache2/apache2.conf

# Enable apache mod rewrite and mod ssl..
RUN a2enmod rewrite && a2enmod ssl

# Create volumes
VOLUME $FIREFLY_PATH/storage/export $FIREFLY_PATH/storage/upload

# Enable default site (Firefly III)
COPY ./.deploy/docker/apache-firefly.conf /etc/apache2/sites-available/000-default.conf

# Make sure we own Firefly III directory
RUN chown -R www-data:www-data /var/www && chmod -R 775 $FIREFLY_PATH/storage

# Copy in Firefly Source
WORKDIR $FIREFLY_PATH
ADD . $FIREFLY_PATH

# Fix the link to curl:
#RUN rm -rf /usr/local/lib/libcurl.so.4 && ln -s /usr/lib/x86_64-linux-gnu/libcurl.so.4.4.0 /usr/local/lib/libcurl.so.4

# Run composer
RUN composer install --prefer-dist --no-dev --no-scripts --no-suggest

# Expose port 80
EXPOSE 80

# Run entrypoint thing
ENTRYPOINT [".deploy/docker/entrypoint.sh"]
