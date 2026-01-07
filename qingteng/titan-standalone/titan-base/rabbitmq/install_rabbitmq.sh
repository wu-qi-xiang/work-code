#!/bin/bash

## --------------------Marco Define------------------------------- ##
# error hint
COLOR_G="\x1b[0;32m"  # green
COLOR_R="\x1b[1;31m"  # red
RESET="\x1b[0m"

## sys
QT_PACKAGE_ROOT="/data/qt_base"
QT_SYS_CONF="${QT_PACKAGE_ROOT}/base/config"
Erlang_Cookie=`tr -dc "A-Za-z0-9"</dev/urandom | head -c 255`
## rabbitmq
QT_PACKAGE_DIR="/data/qt_base/rabbitmq"
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

install_rabbitmq(){
    info_log "Install rabbitmq...."
    if [ ! -x "$(which openssl)" ];then
        yum -y install openssl
    fi
    if [ -d /data/servers/rabbitmq_data ]; then
        service rabbitmq-server stop
        old_otp_dir=$(echo /data/app/titan-rabbitmq/titan-rabbitmq-v* | awk '{print $1}')
        if [ $(ps aux | grep -v grep | grep -w -c titan_otp) -ge 1 ];then
            ps aux | grep -v grep | grep -w titan_otp | awk '{print $2}' | xargs kill -9
        fi
        mkdir -p /data/backup/rabbitmq_backup
        mv /data/servers/rabbitmq_data /data/backup/rabbitmq_backup/rabbitmq_data-bak$(date '+%Y%m%d%H%M%S')
        check "backup rabbitmq data and stop rabbitmq"
    fi
    yum clean all
    yum -y install titan-rabbitmq
    yum -y update titan-rabbitmq
    echo $Erlang_Cookie >/data/app/titan-rabbitmq/.erlang.cookie 
    chmod 400 /data/app/titan-rabbitmq/.erlang.cookie && chown rabbitmq:rabbitmq /data/app/titan-rabbitmq/.erlang.cookie
	\cp -rf /data/app/titan-rabbitmq/.erlang.cookie /root/.erlang.cookie
    if [ -d ${old_otp_dir} ] && [ $(ls /data/app/titan-rabbitmq|grep -c titan-rabbitmq-v) == 2 ]; then
        mkdir -p /data/backup/rabbitmq_backup
        mv ${old_otp_dir}  /data/backup/rabbitmq_backup/otp-bak$(date '+%Y%m%d%H%M%S')
    fi
    check "Install rabbitmq"
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

launch_service(){
    #disable selinux
    sed -i '/SELINUX/s/enforcing/disabled/' /etc/selinux/config
    setenforce 0
    info_log "selinux is disabled !"
    chkconfig --add rabbitmq-server
    chkconfig rabbitmq-server on
    chown rabbitmq:rabbitmq -R /data/servers/rabbitmq_data
    chown rabbitmq:rabbitmq -R /data/servers/rabbitmq_root
    chown rabbitmq:rabbitmq -R /data/app/titan-rabbitmq/

    [ -d /data/app/titan-rabbitmq/init_log ] && chmod 755 -R /data/app/titan-rabbitmq/init_log/
    chmod 777 /data/servers

	if [ "${rabbitmq_status}" != "cluster" ];then
		service rabbitmq-server restart || exit 1 
                chmod 644 /data/servers/rabbitmq_root/etc/rabbitmq/enabled_plugins 
                umask 0022 && /data/app/titan-rabbitmq/bin/rabbitmq-plugins disable rabbitmq_management
	else
		if [ "${rabbit_master_status}" == "master" ];then 
			info_log "start rabbitmq-server!"
			service rabbitmq-server start || exit 1;
			if [ "`/etc/init.d/rabbitmq-server status|grep Error|wc -l`" != 0 ];then ps -ef | grep rabbitmq | grep -v install | grep -v grep | awk '{print $2}' | xargs kill -9  ;service rabbitmq-server start;sleep 10;fi
			sleep 5;
			check "start rabbit_master"
		else
		        info_log "start rabbit_nodes"
		fi
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

rabbitmq_status=$2
rabbitmq_master_ip=$3
rabbit_master_status=$4
chmod 755 /data
install_rabbitmq
if [ "${rabbitmq_status}" != "cluster" ];then init_sys ;fi

launch_service

info_log "Done"
