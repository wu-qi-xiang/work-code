FROM alpine:3.12

RUN sed -i 's/dl-cdn.alpinelinux.org/mirrors.aliyun.com/g' /etc/apk/repositories \
        && apk add --no-cache openssl && rm -rf /var/cache/apk/* 

WORKDIR /root
COPY script/dockerize /root/script/dockerize
COPY script/mkcert-v1.4.3-linux-amd64 /root/script/mkcert
COPY script/prepare.sh /prepare.sh
COPY config /root/config
