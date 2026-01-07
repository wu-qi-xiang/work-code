#!/bin/bash -e

HOSTNAME=`hostname -s`
# Store original IFS config, so we can restore it at various stages
ORIG_IFS=$IFS

if [[ -z "$KAFKA_LOG_DIRS" ]]; then
    export KAFKA_LOG_DIRS="/data/kafka-data/$HOSTNAME"
fi

if [[ -z "$LOG_DIR" ]]; then
    export LOG_DIR="/data/titan-logs/kafka/$HOSTNAME"
fi

if [[ $HOSTNAME =~ (.*)-([0-9]+)$ ]]; then
    NAME=${BASH_REMATCH[1]}
    ORD=${BASH_REMATCH[2]}
else
    NAME=$HOSTNAME
    ORD="0"
fi


# Allow the container to be started with `--user`
if [[ "$(id -u)" = '0' ]]; then
    mkdir -p $KAFKA_LOG_DIRS && mkdir -p $LOG_DIR
    chown -R kafka:kafka $KAFKA_LOG_DIRS $LOG_DIR
    echo "mkdir of kafka"
    exec gosu kafka "$0" "$@"
fi

if [[ -z "$KAFKA_OPTS" ]]; then
    export KAFKA_OPTS="-Dzookeeper.sasl.client=true -Dzookeeper.sasl.clientconfig=ZkClient -Dzookeeper.sasl.client.username=qingteng -Djava.security.auth.login.config=/usr/local/qingteng/kafka/config/kafka_server_jaas.conf"
fi

sed -i "s#^broker.id=.*#broker.id=$ORD#g" $KAFKA_HOME/config/server.properties
sed -i "s#^log.dirs=.*#log.dirs=$KAFKA_LOG_DIRS#g" $KAFKA_HOME/config/server.properties

# usage: file_env VAR [DEFAULT]
#    ie: file_env 'XYZ_DB_PASSWORD' 'example'
# (will allow for "$XYZ_DB_PASSWORD_FILE" to fill in the value of
#  "$XYZ_DB_PASSWORD" from a file, especially for Docker's secrets feature)
file_env() {
	local var="$1"
	local fileVar="${var}_FILE"
	local def="${2:-}"
	if [ "${!var:-}" ] && [ "${!fileVar:-}" ]; then
		echo >&2 "error: both $var and $fileVar are set (but are exclusive)"
		exit 1
	fi
	local val="$def"
	if [ "${!var:-}" ]; then
		val="${!var}"
	elif [ "${!fileVar:-}" ]; then
		val="$(< "${!fileVar}")"
	fi
	export "$var"="$val"
	unset "$fileVar"
}

file_env 'ZK_PASSWORD'
file_env 'KAFKA_QTPASSWD'

# set zookeeper password
sed -i "s/{zk_password}/$ZK_PASSWORD/g" $KAFKA_HOME/config/kafka_server_jaas.conf
# set kafka password
sed -i "s/{kafka_passwd}/$KAFKA_QTPASSWD/g" $KAFKA_HOME/config/kafka_server_jaas.conf
sed -i "s/{kafka_passwd}/$KAFKA_QTPASSWD/g" $KAFKA_HOME/config/producer.properties
sed -i "s/{kafka_passwd}/$KAFKA_QTPASSWD/g" $KAFKA_HOME/config/consumer.properties
unset ZK_PASSWORD KAFKA_QTPASSWD

args="$@"
echo $EXTERNAL_KAFKA_SERVERS
if [ -n "$EXTERNAL_KAFKA_SERVERS" ]; then
    external_kafka_array=($EXTERNAL_KAFKA_SERVERS)
    echo ${external_kafka_array[ORD]}
    args=$args" --override listener.security.protocol.map=SASL_PLAINTEXT:SASL_PLAINTEXT,EXTERNAL:SASL_PLAINTEXT --override listeners=SASL_PLAINTEXT://:9092,EXTERNAL://:9093 --override advertised.listeners=SASL_PLAINTEXT://:9092,EXTERNAL://${external_kafka_array[ORD]}"
fi

exec kafka-server-start.sh "/usr/local/qingteng/kafka/config/server.properties" $args