#!/bin/bash

## --------------------Marco Define------------------------------- ##
# error hint
COLOR_G="\x1b[0;32m"  # green
COLOR_R="\x1b[1;31m"  # red
RESET="\x1b[0m"

## sys
QT_PACKAGE_ROOT="/data/qt_base"
QT_SYS_CONF="${QT_PACKAGE_ROOT}/base/config"

## php
QT_PACKAGE_DIR="/data/qt_base/erproxy"
QT_CONF="${QT_PACKAGE_DIR}/config"

## installation directory
QT_INSTALL_DIR="/usr/local/qingteng"

## --------------------Utils-------------------------------------- ##

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

is_erproxy_installed(){
    if [ -f "/data/app/conf/proxy/nginx.proxy.conf" ]; then
        info_log "erproxy installed already"
        return 1
    fi
    return 0
}


## --------------------Tar Packets Install------------------------ ##

install_erproxy(){
    #is_erproxy_installed
    #if [ $? -eq 1 ]; then
    #    return
    #fi

    info_log "Install nginx...."
    yum -y install nginx
    yum -y update  nginx
    check "Install nginx"
}


## -------------------------Configure------------------------------ ##

update_config(){
    local qt_conf=$1
    local dest_dir=$2

    mkdir -p ${dest_dir}
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
        (IFS=$'\n';for line in `cat $conf`; do
             local file=`echo ${line} | awk -F " " '{print $1}'`
             local dest=`echo ${line} | awk -F" " '{print $2}'`
             update_config "${conf_path}/${file}" ${dest}
        done)
    fi
}

## --------------------------------------------------------------- ##

launch_service(){
    #disable selinux
    sed -i '/SELINUX/s/enforcing/disabled/' /etc/selinux/config
    setenforce 0
    info_log "selinux is disabled !"

    /sbin/chkconfig --add nginx
    /sbin/chkconfig  nginx  on
    
    service nginx restart
}

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

## -------------------------Starting------------------------------ ##
if [ "$1" == "upconfig" ];then
    config_conf ${QT_CONF}
    if [ "$2" != "" ];then
        sed -i "s#\(http://\).*\(:8443\)#\1$2\2#g" /data/app/conf/proxy/nginx.proxy.conf 
    fi
    service nginx restart
    exit 0
fi


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


install_erproxy

init_sys

# app config
config_conf ${QT_CONF}
if [ -d "/data/app/conf" ];then
    scp -rp $QT_PACKAGE_DIR/conf/* /data/app/conf/
else
    mkdir -p /data/app/conf
    scp -rp $QT_PACKAGE_DIR/conf/* /data/app/conf/ 
fi
scp -rp $QT_PACKAGE_DIR/conf/cert/nginx.conf /etc/nginx/nginx.conf
if [ "$1" != "" ];then
    sed -i "s#\(http://\).*\(:6130\)#\1$1\2#g" /data/app/conf/proxy/nginx.proxy.conf 
fi
[ -d "/data/titan-logs/nginx" ] || mkdir -p /data/titan-logs/nginx
chown nginx:nginx /data/titan-logs/nginx

chmod 755 /data
chmod 755 -R /data/app/conf/
launch_service

info_log "Done"
