FROM registry.qingteng.cn/titan-container/titan-dockerize:3.4.0-20220330 as dockerize
FROM registry.qingteng.cn/titan-container/titan-php:7.4.30-20220817

COPY --from=dockerize /usr/local/bin/dockerize /usr/bin/
RUN apk add --no-cache bash && rm -rf /var/cache/apk/* && /bin/bash

# for php config
COPY --chown=nginx:nginx config/php/php.ini /usr/local/etc/php/php.ini
COPY --chown=nginx:nginx config/php/php-fpm.conf /usr/local/etc/php-fpm.conf
COPY --chown=nginx:nginx config/php/supervisord.conf /etc/supervisord.conf

COPY docker-run.sh /

#for nginx config
COPY --chown=nginx:nginx config/nginx/nginx.conf /etc/nginx/nginx.conf
COPY --chown=nginx:nginx config/conf/ /data/app/conf-inner

COPY nginx_log_split.sh /usr/bin/nginx_log_split.sh

# for titan-web,split vendor and code, to create smaller patch
COPY --chown=nginx:nginx web-ins/titan-web-conf /data/app/www/titan-web/conf
COPY --chown=nginx:nginx web-ins/titan-web-vendor /data/app/www/titan-web/vendor
COPY --chown=nginx:nginx web-ins/titan-web /data/app/www/titan-web

# for frontend
COPY --chown=nginx:nginx ./titan-frontend /data/app/www/titan-frontend

# ensure /usr/local/php/bin/php exists
RUN ln -s /usr/local/bin/ /usr/local/php/ && chmod +x /usr/bin/nginx_log_split.sh \
    && echo '59 23 * * * /usr/bin/nginx_log_split.sh' > /var/spool/cron/crontabs/root

WORKDIR /
ENTRYPOINT ["/docker-run.sh"]

