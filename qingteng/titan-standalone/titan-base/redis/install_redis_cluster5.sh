#!/bin/bash
## --------------------Marco Define------------------------------- ##
# error hint
COLOR_G="\x1b[0;32m"  # green
COLOR_R="\x1b[1;31m"  # red
RESET="\x1b[0m"

QT_PACKAGE_ROOT="/data/qt_base"
QT_PACKET_DIR="/data/qt_base/redis"
QT_SYS_CONF="${QT_PACKAGE_ROOT}/base/config"
QT_CONF="${QT_PACKET_DIR}/config-cluster5"

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

ensure_dir_exists(){
    local dir=$1
    if [ ! -d ${dir} ]
    then
        info_log "Creating directory"
        mkdir -p ${dir}
        check "${dir} created"
    fi
}

## -------------------------Configure------------------------------ ##
init_sys(){
    # sys config
    config_conf ${QT_SYS_CONF}
    sed -i '/^*/d' /etc/security/limits.d/*.conf
    modprobe bridge && sysctl -p || true
    sysctl -a > /root/qingteng_sysctl.log
    if [ `command -v abrtd` ]; then
        [ -f /etc/abrt/abrt-action-save-package-data.conf ] && \
        sed -i 's/ProcessUnpackaged = no/ProcessUnpackaged = yes/' /etc/abrt/abrt-action-save-package-data.conf
        service abrtd restart
    fi
    check "Load sys config"
}

update_config(){
    local qt_conf=$1
    local dest_dir=$2

    if [ ! -z ${dest_dir} ]
    then
        ensure_dir_exists ${dest_dir}
        cp -b ${qt_conf} ${dest_dir}
        check "Copy ${qt_conf} to ${dest_dir}"
    fi
}

config_conf(){
    local conf_path=$1
    local conf=${conf_path}/conf.conf

    if [ -f ${conf} ]; then
        local content=`cat ${conf}`
        if [ ${conf_path} = ${QT_CONF} ] && [ "$2" != "" ]; then
            content=`cat ${conf} |grep $2`
        fi

        (IFS=$'\n';for line in ${content}; do
            local file=`echo ${line} | awk -F " " '{print $1}'`
            local dest=`echo ${line} | awk -F " " '{print $2}'`
            update_config ${conf_path}/${file} ${dest}
        done)
    fi
}

init_redis(){
    local port1=$1
    local port2=$2
    local port3=$3

    config_conf ${QT_CONF} ${port1}
    config_conf ${QT_CONF} ${port2}
    config_conf ${QT_CONF} ${port3}

    mkdir -p /data/redis/$1
    mkdir -p /data/redis/$2
    mkdir -p /data/redis/$3

    chown -R redis:redis /data/redis/

    chmod +x /etc/init.d/redis${1}d
    chmod +x /etc/init.d/redis${2}d
    chmod +x /etc/init.d/redis${3}d

    touch /data/titan-logs/redis/${port1}-redis.log
    touch /data/titan-logs/redis/${port2}-redis.log
    touch /data/titan-logs/redis/${port3}-redis.log

    chown -R redis:redis /data/titan-logs/redis/
    chown -R redis:redis /etc/redis/
    chmod -R 755 /etc/redis/
    chmod 755 /data/titan-logs/redis/

    chkconfig redis${port1}d on
    ps -ef|grep redis|grep ${port1}|grep -v grep|awk '{print $2}'|xargs -i  kill -9 {}
    service redis${port1}d restart
    chkconfig redis${port2}d on
    ps -ef|grep redis|grep ${port2}|grep -v grep|awk '{print $2}'|xargs -i  kill -9 {}
    service redis${port2}d restart
    chkconfig redis${port3}d on
    ps -ef|grep redis|grep ${port3}|grep -v grep|awk '{print $2}'|xargs -i  kill -9 {}
    service redis${port3}d restart

}

install_redis(){
    info_log "Install Rediscluster...."
    yum clean all
    yum -y install qingteng-redis
    yum -y update qingteng-redis
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
init_sys
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
