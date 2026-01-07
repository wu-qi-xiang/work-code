FROM registry.qingteng.cn/k8s/x86/gitlab/centos7:7.9

MAINTAINER leilei.zhai "leilei.zhai@qingteng.cn"

COPY offline-qingteng.repo /etc/yum.repos.d/offline-qingteng.txt

RUN rm -rf /etc/yum.repos.d/*.repo \
&& curl -o /etc/yum.repos.d/qt-centos-base.repo https://mirror.qingteng.cn/repository/qt-offline/repo/7/qt-centos-base.repo \
&& curl -o /etc/yum.repos.d/qingteng-centos-epel.repo https://mirror.qingteng.cn/repository/qt-offline/repo/7/qingteng-centos-epel.repo \
&& yum makecache \
&& yum install -y pigz createrepo openssh-clients python-pip wget unzip jq gettext \
&& rm -rf /etc/yum.repos.d/*.repo \
&& mv /etc/yum.repos.d/offline-qingteng.txt /etc/yum.repos.d/offline-qingteng.repo \
&& yum makecache \
&& yum downgrade -y openssl-libs \
&& yum clean all \
&& rm -rf /var/cache/yum/*
