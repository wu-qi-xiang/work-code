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
#QT_PACKAGE_DIR="/data/qt_base/php"
#QT_CONF="${QT_PACKAGE_DIR}/config"

##keepalived
QT_PACKAGE_DIR="/data/qt_base/keepalived"
QT_CONF="${QT_PACKAGE_DIR}/config"

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

is_keepalived_installed(){
    if [ -e "/etc/keepalived/keepalived.conf" ]; then
        info_log "keepalived installed already"
        rm -rf /etc/keepalived/keepalived.conf
        return 1
    fi
    return 0
}

## --------------------Tar Packets Install------------------------ ##

install_keepalived(){
    
    info_log "Install keepalived...."
    yum clean all
    keepalived --version || yum -y install qingteng-percona
    yum -y install  keepalived unzip qingteng-jdk
    yum -y update  keepalived qingteng-jdk 
    check "Install keepalived"
}

## -------------------------Configure------------------------------ ##
update_config(){
    local qt_conf=$1
    local dest_dir=$2
    local vip=$3
    local localip=$4
    echo -e "qt_conf=${qt_conf},dest_dir=${dest_dir},vip=${vip}"
    #取服务器ip的最后一位作为keepalived的优先级
    local priority=`echo ${localip}|awk -F"." '{print $NF}'`
    local network_name=`ip a|grep -B 2 "${localip}"|xargs|cut -d " " -f2|sed 's/[:]*$//g'`
    echo -e "现在的优先级是：${priority}"
    mv -f ${dest_dir} ${dest_dir}.bak
    \cp -bf ${qt_conf} ${dest_dir}
    sed -i "s#priority 100#priority ${priority}#g" ${dest_dir}
    sed -i "s#10.169.132.181#${vip}#g" ${dest_dir}
    sed -i "s#interface.*#interface ${network_name}#g" ${dest_dir}
    check "Copy ${qt_conf} to ${dest_dir}"
    #fi
}

config_conf(){
    local conf_path=${QT_CONF}
    local conf=${conf_path}/conf.conf
    local vip=$2
    local localip=$1 
    if [ -f ${conf} ]; then

        local content=`cat ${conf}`
        (IFS=$'\n';for line in ${content}; do
            local file=`echo ${line} | awk -F " " '{print $1}'`
            local dest=`echo ${line} | awk -F " " '{print $2}'`
            update_config "${QT_CONF}/${file}" ${dest} ${vip} ${localip}
        done)
     fi
}


launch_service(){
    #disable selinux
    sed -i '/SELINUX/s/enforcing/disabled/' /etc/selinux/config
    setenforce 0
    info_log "selinux is disabled !"

    #chkconfig --add keepalived
    chkconfig keepalived on
    service  keepalived restart

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

localip=$1
vip=$2


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


#install_keepalived
echo -e "----------------------install keepalived----------------------"
install_keepalived

init_sys


# app config
echo -e "---------------------configure keepalived---------------------"
config_conf $localip $vip


launch_service

info_log "Done"

