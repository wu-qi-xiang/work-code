FROM registry.qingteng.cn/titan-container/golang:1.16 as gobuilder

WORKDIR /root

ENV GO111MODULE on
ENV GOPROXY https://goproxy.cn/,direct

COPY / /root/

RUN go mod download && go build -buildmode=c-shared -o out.so out.go

FROM registry.qingteng.cn/titan-container/fluentbit-base:1.8.5

COPY --from=gobuilder /root/out.so /fluent-bit/bin/

EXPOSE 2020

CMD ["/fluent-bit/bin/fluent-bit", "--plugin", "/fluent-bit/bin/out.so", "--config", "/fluent-bit/etc/fluent-bit.conf"]

