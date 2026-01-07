#!/bin/bash

WEB_PATH="/data/app/www/titan-web"
PHP_EXEC="/usr/local/php/bin/php"

usage() {
    cat <<_EOF_
docker run [-it] <container name> <options>
Options:
  start     start the container
  help                  show this help
_EOF_
}

start() {
    # 启动前检查nginx server配置文件不存在则复制过去
    test -f /data/app/conf/nginx.servers.conf || /bin/cp -rf /data/app/conf-inner/*  /data/app/conf/

    mkdir -p /data/titan-logs/php /data/titan-logs/php-fpm /data/titan-logs/nginx
    chown -R nginx:nginx /data/app/www /data/app/conf /data/titan-logs/php /data/titan-logs/php-fpm /data/titan-logs/nginx /var/log/nginx
    chown -R nginx:nginx /var/log/nginx

    su -s /bin/sh -c "php-fpm --fpm-config /usr/local/etc/php-fpm.conf --pid /data/titan-logs/php-fpm/php-fpm.pid" nginx
    nginx -g "daemon off;"
}

action=$1
echo "Action is $action"

case $action in
    start)
        start
        exit 0
        ;;
    help)
        usage
        exit 0
        ;;
    *)
        printf "Wrong option or empty option...nn" 1>&2
        usage
        exec "$@"
        ;;
esac

