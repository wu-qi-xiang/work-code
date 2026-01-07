#!/bin/bash
## --------------------Marco Define------------------------------- ##
# error hint
COLOR_G="\x1b[0;32m"  # green
COLOR_R="\x1b[1;31m"  # red
RESET="\x1b[0m"

QT_PACKAGE_ROOT="/data/qt_base"
#QT_PACKET_DIR="/data/qt_base/redis"
#
#QT_SYS_CONF="${QT_PACKAGE_ROOT}/base/config"
#QT_CONF="${QT_PACKET_DIR}/config"
#
#QT_INSTALL_DIR="/usr/local/qingteng"

#QT_REDIS_LOG="/data/redis"

## --------------------Utils-------------------------------------- ##
help() {
    echo "----------------------------------------------------------"
    echo "                   Usage information                      "
    echo "----------------------------------------------------------"
    echo "                                                          "
    echo "./install_redis_cluster.sh [Options]                              "
    echo "                                                          "
    echo "Options:                                                  "
    echo "  redis_erlang    redis-server with port: 6379            "
    echo "  redis_php       redis-server with port: 6380            "
    echo "  redis_java      redis-server with port: 6381            "
    echo "                                                          "
    echo "----------------------------------------------------------"
    exit 1
}

info_log(){
    echo -e "${COLOR_G}[Info] ${1}${RESET}"
}

error_log(){
    echo -e "${COLOR_R}[Error] ${1}${RESET}"
}

check(){
    if [ $? -eq 0 ];then
        info_log "$1 Successfully"
    else
        error_log "$1 Failed"
        exit 1
    fi
}


init_redis(){
	local port1=$1
	local port2=$2
	local port3=$3
	chkconfig redis${port1}d on
	service redis${port1}d restart
    chkconfig redis${port2}d on
	service redis${port2}d restart
    chkconfig redis${port3}d on
	service redis${port3}d restart

    touch /data/titan-logs/redis/${port1}-redis.log 
    touch /data/titan-logs/redis/${port2}-redis.log 
    touch /data/titan-logs/redis/${port3}-redis.log 

    chown -R redis:redis   /data/redis/  &>/dev/null
    chown -R redis:redis   /data/titan-logs/redis/  &>/dev/null
    chown -R redis:redis   /etc/redis/  &>/dev/null
    chmod -R 755 /etc/redis/  &>/dev/null
    chmod 755  /data/titan-logs/redis/  &>/dev/null

    sed -i '1295s/yes_or_die/#yes_or_die/g' /usr/local/sbin/redis-trib.rb	
}

install_redis(){
    info_log "Install Rediscluster...."
    yum clean all
    yum -y install   qingteng-rediscluster
    check "Install RedisCluster"

}

[ $# -gt 0 ] || help $*
if [ ! -f "/etc/yum.repos.d/qingteng.repo" ];then
    if [ ! -d "/etc/yum.repos.d/qingteng-bak" ];then
        mkdir /etc/yum.repos.d/qingteng-bak
        mv /etc/yum.repos.d/*.repo  /etc/yum.repos.d/qingteng-bak
    fi
cat >/etc/yum.repos.d/qingteng.repo<<EOF
[qingteng]
name=qingteng
baseurl=file://${QT_PACKAGE_ROOT}/base/qingteng
enabled=1
gpgcheck=0
EOF
yum clean all
fi

chmod 755 /data 
install_redis


case $1 in
    redis_erlang)
        init_redis 6379 6479 6579
        ;;
    redis_php)
        init_redis 6380 6480 6580
        ;;
    redis_java)
        init_redis 6381 6481 6581
        ;;
    *)
        help $*
        exit
        ;;
esac
info_log "Done"