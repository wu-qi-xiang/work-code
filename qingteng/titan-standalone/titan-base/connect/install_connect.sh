#!/bin/bash

## --------------------Marco Define------------------------------- ##
# error hint
COLOR_G="\x1b[0;32m"  # green
COLOR_R="\x1b[1;31m"  # red
RESET="\x1b[0m"

## sys
QT_PACKAGE_ROOT="/data/qt_base"
QT_SYS_CONF="${QT_PACKAGE_ROOT}/base/config"

## connect
QT_PACKAGE_DIR="/data/qt_base/connect"
QT_CONF="${QT_PACKAGE_DIR}/config"

## installation directory
QT_INSTALL_DIR="/usr/local/qingteng"
##
QT_ARTHAS_DIR="arthas"
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

install_connect(){
    info_log "Install jdk...."
    yum clean all
    yum -y install qingteng-jdk
    yum -y update qingteng-jdk
    oracle_jdk_name=$(rpm -qa | grep ^jdk1.8.0)
    if [ "${oracle_jdk_name}" != "" ];then
        rpm -e ${oracle_jdk_name}
    fi
    err_jdk_name=$(rpm -qa | grep ^openjdk-1.8.0_312-1)
    if [ "${err_jdk_name}" != "" ];then
        rpm -e ${err_jdk_name}
    fi
    yum -y install openjdk-1.8.0_312
    /bin/ln -sf /usr/local/qingteng/openjdk1.8.0_312 /usr/java/latest
    /bin/ln -sf /usr/java/latest /usr/java/default
    /bin/ln -sf /usr/local/qingteng/openjdk1.8.0_312/jre/bin/java /usr/bin/java
    yum -y install fontconfig
    check "Install jdk"
}

install_arthas(){
    if [ ! -d /usr/local/qingteng/arthas ];then
	mkdir -p /usr/local/qingteng/arthas
    fi
    info_log "starting install arthas"
    chmod 755 /usr/local/qingteng
    rsync --delete -rz ${QT_PACKAGE_DIR}/arthas-packaging-3.4.6-bin/* /usr/local/qingteng/arthas/ && chmod 755 -R /usr/local/qingteng/arthas&& bash /usr/local/qingteng/arthas/install-local.sh
    check "Install arthas"
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
install_connect
install_arthas
init_sys

info_log "Done"
