#!/bin/bash

## --------------------Marco Define------------------------------- ##
# error hint
COLOR_G="\x1b[0;32m"  # green
COLOR_R="\x1b[1;31m"  # red
RESET="\x1b[0m"

QT_PACKAGE_ROOT="/data/qt_base"
QT_PACKET_DIR="/data/qt_base/redis"

QT_SYS_CONF="${QT_PACKAGE_ROOT}/base/config"
QT_CONF="${QT_PACKET_DIR}/config"

QT_INSTALL_DIR="/usr/local/qingteng"

QT_REDIS_LOG="/data/redis"

## --------------------Utils-------------------------------------- ##
help() {
    echo "----------------------------------------------------------"
    echo "                   Usage information                      "
    echo "----------------------------------------------------------"
    echo "                                                          "
    echo "./install_redis.sh [Options]                              "
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

remove_dir(){
    local dir=$1
    if [ -e ${dir} ]; then
        rm -rf ${dir}
        info_log "remove dir ${dir}"
    fi
}

## --------------------Tar Packets Install------------------------ ##

is_redis_installed(){
    if [ -e ${QT_INSTALL_DIR}/redis/bin/redis-server ]; then
        ${QT_INSTALL_DIR}/redis/bin/redis-server -v
        if [ $? -ne 0 ]; then
            # not
            return 0
        fi
        info_log "Redis installed already"
        return 1
    fi
    return 0
}



install_redis(){
    #is_redis_installed

    #if [ $? -eq 1 ]; then
    #    return
    #fi
    info_log "Install Redis...."
    yum clean all
    yum -y install --skip-broken  qingteng-redis
    yum -y update --skip-broken  qingteng-redis
    check "Install Redis"
}

install_tar_packets(){
    ensure_dir_exists ${QT_INSTALL_DIR}
    install_redis
}

## -------------------------Configure------------------------------ ##

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

## -------------------------Launch Services----------------------- ##

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

init_redis(){
    local port=$1

    config_conf ${QT_CONF} ${port}

    #ensure_dir_exists ${QT_REDIS_LOG}/${port}

    chmod +x /etc/init.d/redis${port}d
    chkconfig --add redis${port}d
    chkconfig redis${port}d on

    touch /data/titan-logs/redis/${port}-redis.log 

    chown -R redis:redis   /data/redis/  &>/dev/null
    chown -R redis:redis   /data/titan-logs/redis/  &>/dev/null
    chown -R redis:redis   /etc/redis/  &>/dev/null
    chmod -R 755 /etc/redis/  &>/dev/null
    chmod 755 /usr/local/qingteng &>/dev/null
    chmod 755  /data/titan-logs/redis/  &>/dev/null

    service redis${port}d restart
}

stop_redis(){
    local port=$1
    local role=$2
    ps -fe|grep redis-server |grep $port |grep -v grep
    if [ $? -ne 1 ];then
        ps -ef|grep redis-server|grep $port|grep -v grep|awk '{print $2}'|xargs -i  kill -9 {}
	check "Clean up the redis${port}d history process"
    fi

}

## -------------------------Starting------------------------------ ##
if [ "$1" == "upconfig" ];then
    config_conf ${QT_CONF}
    case $2 in
        redis_erlang)
            service redis6379d restart
            ;;
        redis_php)
            service redis6380d restart
            ;;
        redis_java)
            service redis6381d restart
            ;;
    esac
    exit 0
fi

if [ "$1" == "upconfig-local" ];then
    config_conf ${QT_PACKET_DIR}/config-local
    case $2 in
        redis_erlang)
            service redis6379d restart
            ;;
        redis_php)
            service redis6380d restart
            ;;
        redis_java)
            service redis6381d restart
            ;;
    esac
    exit 0
fi

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

chmod 755 /data   &>/dev/null

case $1 in
    redis_erlang)
        stop_redis 6379
        ;;
    redis_php)
        stop_redis 6380
        ;;
    redis_java)
        stop_redis 6381
        ;;
    *)
        help $*
        exit
        ;;
esac

install_redis

init_sys


case $1 in
    redis_erlang)
        init_redis 6379
        ;;
    redis_php)
        init_redis 6380
        ;;
    redis_java)
        init_redis 6381
        ;;
    *)
        help $*
        exit
        ;;
esac

info_log "Done"
