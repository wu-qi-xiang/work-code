# openjdk 镜像构建

以 ubuntu:focal 为基础， 使用 buildx来构建
为了加快构建，里面 openjdk的压缩包是放到了内部的17.201机器上，避免从公网下载很慢的情况

docker buildx build --platform linux/amd64,linux/arm64 --push -t registry.qingteng.cn/titan-container/titan-openjdk:8u292-20220318 .
