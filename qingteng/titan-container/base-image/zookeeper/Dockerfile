FROM registry.qingteng.cn/titan-container/titan-openjdk:8u292-20220318

ENV ZK_USER=zookeeper \
    PATH=${PATH}:/usr/local/qingteng/zookeeper/bin

RUN mkdir -p /usr/local/qingteng/zookeeper/ \
    && set -x \
    && groupadd -g 1000 zookeeper  \
    && useradd -u 1000 -g zookeeper zookeeper

RUN sed -i 's/ports.ubuntu.com/mirrors.aliyun.com/g' /etc/apt/sources.list \
    && sed -i 's/archive.ubuntu.com/cn.archive.ubuntu.com/g' /etc/apt/sources.list \
    && apt-get update && apt install -y --no-install-recommends gosu netcat && apt clean && rm -rf /var/lib/apt/lists/* 

COPY --chown=zookeeper:zookeeper ./apache-zookeeper-3.6.3-bin /usr/local/qingteng/zookeeper/

# Copy configuration generator script to bin
COPY start-zk.sh zkOk.sh /usr/local/qingteng/zookeeper/bin/
COPY ./conf/* /usr/local/qingteng/zookeeper/conf/

RUN mkdir -p $ZK_DATA_DIR $ZK_DATA_LOG_DIR $ZK_LOG_DIR /usr/share/zookeeper /tmp/zookeeper \
    && chown -R "$ZK_USER:$ZK_USER" $ZK_DATA_DIR $ZK_LOG_DIR $ZK_DATA_LOG_DIR /tmp/zookeeper /usr/local/qingteng/zookeeper/ \
    && chmod +x /usr/local/qingteng/zookeeper/bin/*

CMD ["start-zk.sh"]
