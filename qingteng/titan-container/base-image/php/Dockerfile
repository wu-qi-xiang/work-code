FROM php:7.4.30-fpm-alpine

COPY docker-php-extension-installer /usr/local/bin/
RUN sed -i 's/dl-cdn.alpinelinux.org/mirrors.aliyun.com/g' /etc/apk/repositories && \
    chmod +x /usr/local/bin/install-php-extensions && \
    apk update && apk add --no-cache nginx supervisor gmp m4 autoconf make gcc g++ linux-headers shadow && \
    pear upgrade -Z Archive_Tar && \
    IPE_KEEP_SYSPKG_CACHE=1 /usr/local/bin/install-php-extensions @fix_letsencrypt redis pdo_mysql opcache mysqli yac yaf-3.0.9 bcmath gd gettext gmp ldap mcrypt rdkafka pcntl shmop soap sockets sysvsem xmlrpc zip && \
    touch /run/nginx/nginx.pid && \
    usermod -u 101 nginx && \
    apk del m4 autoconf make gcc g++ linux-headers shadow

RUN apk add --no-cache tzdata && cp /usr/share/zoneinfo/Asia/Shanghai /etc/localtime \
    && echo "Asia/Shanghai" > /etc/timezone \
    && apk del tzdata && rm -rf /var/cache/apk/* && rm -f /usr/local/lib/php/build/run-tests.php


# install glibc, 现在php没有yara后，这个不需要了，否则还需要考虑ARM64下的glibc
# COPY ./sgerrand.rsa.pub /etc/apk/keys/
# COPY glibc-2.32-r0.apk /root/
# RUN apk add /root/glibc-2.32-r0.apk

COPY php.ini /usr/local/etc/php/
