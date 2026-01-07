FROM registry.qingteng.cn/k8s/x86/gitlab/centos6:6.10

MAINTAINER leilei.zhai "leilei.zhai@qingteng.cn"

COPY offline-qingteng.repo /etc/yum.repos.d/offline-qingteng.txt

RUN rm -rf /etc/yum.repos.d/*.repo \
&& curl -o /etc/yum.repos.d/qt-centos-base.repo  https://mirror.qingteng.cn/repository/qt-offline/repo/6/qt-centos-base.repo \
&& curl -o /etc/yum.repos.d/qingteng-centos-epel.repo https://mirror.qingteng.cn/repository/qt-offline/repo/6/qingteng-centos-epel.repo \
&& yum makecache \
&& yum install yum-utils zlib-devel gcc gcc-c++ createrepo openssh-clients wget unzip jq pigz -y \
&& yum clean all \
&& rm -rf /etc/yum.repos.d/*.repo \
&& mv /etc/yum.repos.d/offline-qingteng.txt /etc/yum.repos.d/offline-qingteng.repo \
&& yum clean all \
&& yum install qingteng-python -y \
&& yum clean all \
&& rm -rf /var/cache/yum/*
