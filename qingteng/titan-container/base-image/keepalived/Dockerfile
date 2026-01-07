FROM registry.qingteng.cn/titan-container/alpine:3.14

RUN sed -i 's/dl-cdn.alpinelinux.org/mirrors.aliyun.com/g' /etc/apk/repositories \
        && apk add --no-cache keepalived && rm -rf /var/cache/apk/*

CMD /usr/sbin/keepalived -P -d -D -f /etc/keepalived/keepalived.conf --dont-fork --log-console
