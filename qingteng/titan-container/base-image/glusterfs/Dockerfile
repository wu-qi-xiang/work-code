FROM registry.qingteng.cn/titan-container/ubuntu:focal-20220302

ENV LANG='en_US.UTF-8'

RUN sed -i 's/ports.ubuntu.com/mirrors.aliyun.com/g' /etc/apt/sources.list \
    && sed -i 's/archive.ubuntu.com/cn.archive.ubuntu.com/g' /etc/apt/sources.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends tzdata curl gnupg2  \
    && cp /usr/share/zoneinfo/Asia/Shanghai /etc/localtime && echo "Asia/Shanghai" > /etc/timezone \
    && rm -rf /var/lib/apt/lists/*

RUN apt-key adv --keyserver keyserver.ubuntu.com --recv-keys F7C73FCC930AC9F83B387A5613E01B7B3FE869A9; \
    echo 'deb http://ppa.launchpad.net/gluster/glusterfs-8/ubuntu focal main' >> /etc/apt/sources.list; \
    apt-get update && apt-get install -y --no-install-recommends glusterfs-server nfs-common; \
    rm -rf /var/lib/apt/lists/*;

EXPOSE 24007 

ENTRYPOINT ["/bin/sh", "-c"]
CMD ["/usr/sbin/glusterd -N"]
