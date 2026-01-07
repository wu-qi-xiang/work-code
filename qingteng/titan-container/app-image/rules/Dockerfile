FROM registry.qingteng.cn/titan-container/alpine:3.14
RUN sed -i 's/dl-cdn.alpinelinux.org/mirrors.aliyun.com/g' /etc/apk/repositories && \
    apk update && apk add --no-cache pv
COPY ./titan-rules-3.4.0.3-20210824.tar.gz /mysql.tar.gz
