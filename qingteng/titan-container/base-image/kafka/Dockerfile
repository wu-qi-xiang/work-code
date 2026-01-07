FROM registry.qingteng.cn/titan-container/titan-openjdk:8u292-20220318

ARG kafka_version=2.3.1
ARG scala_version=2.12

LABEL org.label-schema.name="kafka" \
      org.label-schema.description="Apache Kafka" \
      org.label-schema.version="${scala_version}_${kafka_version}" \
      org.label-schema.schema-version="1.0" \
      maintainer="qingteng"

ENV KAFKA_VERSION=$kafka_version \
    SCALA_VERSION=$scala_version \
    KAFKA_HOME=/usr/local/qingteng/kafka

ENV PATH=${PATH}:${KAFKA_HOME}/bin

VOLUME ["/data/titan-logs/kafka","/data/kafka-data"]

# Add a user with an explicit UID/GID and create necessary directories
RUN set -eux; \
    groupadd -g 1000 kafka  \
    && useradd -u 1000 -g kafka kafka

RUN sed -i 's/ports.ubuntu.com/mirrors.aliyun.com/g' /etc/apt/sources.list \
    && sed -i 's/archive.ubuntu.com/cn.archive.ubuntu.com/g' /etc/apt/sources.list \
    && apt-get update && apt install -y --no-install-recommends gosu && apt clean && rm -rf /var/lib/apt/lists/*

ADD --chown=kafka:kafka ./kafka_2.12-2.3.1 /usr/local/qingteng/kafka/
COPY --chown=kafka:kafka ./start-kafka.sh /usr/local/qingteng/kafka/bin/start-kafka.sh
COPY --chown=kafka:kafka ./config/* /usr/local/qingteng/kafka/config/

CMD ["start-kafka.sh"]
