FROM registry.qingteng.cn/titan-container/titan-php:7.4.9-1

RUN apk add --no-cache bash && rm -rf /var/cache/apk/* && /bin/bash
COPY docker-run.sh /

#for nginx config
COPY --chown=nginx:nginx config/nginx/nginx.conf /etc/nginx/nginx.conf
COPY --chown=nginx:nginx config/conf/ /data/app/conf-inner

# for php config
COPY --chown=nginx:nginx config/php/php.ini /usr/local/etc/php/php.ini
COPY --chown=nginx:nginx config/php/php-fpm.conf /usr/local/etc/php-fpm.conf

# for titan-web
COPY --chown=nginx:nginx web/ /data/app/www/titan-web/

VOLUME ["/data/app/conf", "/data/app/www/titan-web/conf/product", "/data/titan-logs"]

# ensure /usr/local/php/bin/php exists
RUN ln -s /usr/local/bin/ /usr/local/php/

WORKDIR /
ENTRYPOINT ["/docker-run.sh"]

