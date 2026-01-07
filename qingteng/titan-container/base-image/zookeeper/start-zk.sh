#!/bin/bash

set -e

ZK_USER=${ZK_USER:-"zookeeper"}
ZK_LOG_LEVEL=${ZK_LOG_LEVEL:-"INFO"}
ZK_DATA_DIR=${ZK_DATA_DIR:-"/data/zk-data"}
ZK_DATA_LOG_DIR=${ZK_DATA_LOG_DIR:-"/data/zk-data"}
ZK_LOG_DIR=${ZK_LOG_DIR:-"/data/titan-logs/zookeeper"}
ZK_CONF_DIR=${ZK_CONF_DIR:-"/usr/local/qingteng/zookeeper/conf"}
ZK_CLIENT_PORT=${ZK_CLIENT_PORT:-2181}
ZK_SERVER_PORT=${ZK_SERVER_PORT:-2888}
ZK_ELECTION_PORT=${ZK_ELECTION_PORT:-3888}
ID_FILE="$ZK_DATA_DIR/myid"
ZK_CONFIG_FILE="$ZK_CONF_DIR/zoo.cfg"
JAVA_ENV_FILE="$ZK_CONF_DIR/java.env"
HOST=`hostname -s`
DOMAIN=`hostname -d`

function print_servers() {
    for (( i=1; i<=$ZK_REPLICAS; i++ ))
    do
        echo "server.$i=$NAME-$((i-1)).$DOMAIN:$ZK_SERVER_PORT:$ZK_ELECTION_PORT"
    done
}

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

function create_config() {

    if [ -z $ZK_REPLICAS ]; then
        echo "ZK_REPLICAS not set use default 1"
        ZK_REPLICAS=1
    fi

    if [[ $HOST =~ (.*)-([0-9]+)$ ]]; then
        NAME=${BASH_REMATCH[1]}
        ORD=${BASH_REMATCH[2]}
    else
        NAME=$HOST
        ORD="0"
    fi

    MY_ID=$((ORD+1))
    if [ ! -f $ID_FILE ]; then
        echo $MY_ID >> $ID_FILE
    fi

    if [ $ZK_REPLICAS -gt 1 ]; then
        print_servers >> $ZK_CONFIG_FILE
    fi

    echo "Wrote ZooKeeper configuration file to $ZK_CONFIG_FILE"
}

echo "$(id -u)"
create_config

# set zookeeper password
file_env 'ZK_PASSWORD'
sed -i "s/{zk_password}/$ZK_PASSWORD/g" $ZK_CONF_DIR/jaas_zk.conf
unset ZK_PASSWORD

# copy snap
snap_files=$(ls $ZK_DATA_DIR/version-2/snapshot* 2> /dev/null | wc -l)
if [ "$snap_files" == "0" ] ;then  #如果不存在文件
    if [ -d "$ZK_DATA_DIR/version-2" ];then
        cp -arp $ZK_CONF_DIR/snapshot.0 $ZK_DATA_DIR/version-2/
    fi
fi
# Allow the container to be started with `--user`
if [[ "$(id -u)" = '0' ]]; then
    mkdir -p $ZK_DATA_DIR && mkdir -p $ZK_DATA_LOG_DIR && mkdir -p $ZK_LOG_DIR && mkdir -p $ZK_CONF_DIR
    chown -R $ZK_USER:$ZK_USER "$ZK_DATA_DIR" "$ZK_DATA_LOG_DIR" "$ZK_LOG_DIR" "$ZK_CONF_DIR"
    exec gosu zookeeper zkServer.sh start-foreground
else
    zkServer.sh start-foreground
fi

