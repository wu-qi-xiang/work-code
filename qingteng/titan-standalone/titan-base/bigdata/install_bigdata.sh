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
QT_PACKAGE_DIR="/data/qt_base/bigdata"
QT_CONF="${QT_PACKAGE_DIR}/config"

## installation directory
QT_INSTALL_DIR="/usr/local/qingteng"

##system version
SYSTEM_VERSION=`cat /etc/redhat-release | tr -cd '[0-9,\.]'|cut -d "." -f 1`

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
restore_nginx_config(){
    if [ -f /usr/local/qingteng/bigdata/other/default.conf ];then
	rsync --delete -rz /usr/local/qingteng/bigdata/other/default.conf /etc/nginx/conf.d/default.conf
    fi
}
init_logstash_config(){
    local logstash_conf_dir="${QT_INSTALL_DIR}/logstash"
    mkdir -p /data/titan-logs/logstash
    mkdir -p /data/logstash/ruby_codes
    rsync --delete -rz /etc/logstash ${QT_INSTALL_DIR}
    rsync --delete -rz ${QT_CONF}/conf.d ${logstash_conf_dir}
    rsync --delete -rz ${QT_CONF}/logstash.yml ${logstash_conf_dir}
    rsync --delete -rz ${QT_CONF}/pipelines.yml ${logstash_conf_dir}
    rsync --delete -rz ${QT_CONF}/net_connect_parser.rb /data/logstash/ruby_codes/
    rsync --delete -rz ${QT_CONF}/logstash_env $logstash_conf_dir/logstash
    chown -R logstash.logstash /data/titan-logs/logstash
    chown -R logstash.logstash /data/logstash
    sed -i "s/1g/4g/g" ${logstash_conf_dir}/jvm.options
    sed -i "s/node.name:.*/node.name:\ node-${host}/g" $logstash_conf_dir/logstash.yml
    if [ $SYSTEM_VERSION == '7' ];then
        rsync --delete -rz ${QT_CONF}/logstash.service /etc/systemd/system/
        systemctl daemon-reload
        systemctl restart logstash
    else
        rsync --delete -rz ${QT_CONF}/logstash /etc/init.d/
        chmod +x /etc/init.d/logstash
        /etc/init.d/logstash stop
        /etc/init.d/logstash start
    fi     
}

## --------------------Tar Packets Install------------------------ ##

install_bigdata(){
    if [ $roles == "bigdata" ];then
        info_log "Install bigdata env...."
        yum clean all
        /usr/sbin/nginx -V && rpm -aq|grep nginx |xargs -i yum remove -y {}
        yum -y install  bigdata-python nginx librdkafka-devel
        yum -y update  bigdata-python nginx
        install_openjdk
        install_jdk
        check "Install bigdata- env"
        install_logstash
        restore_nginx_config
        check "restore nginx config "
    elif [ $roles == "logstash" ];then
        info_log "Install logstash env...."
        yum clean all
        yum -y install  bigdata-python librdkafka-devel
        yum -y update  bigdata-python
        install_openjdk
        install_jdk
        install_logstash
        check "Install logstash"
    elif [ $roles == "viewer" ];then
        info_log "Install viewer env...."
        yum clean all
        /usr/sbin/nginx -V && rpm -aq|grep nginx |xargs -i yum remove -y {}
        yum -y install  bigdata-python nginx
        yum -y update  bigdata-python nginx 
        check "Install viewer"
        restore_nginx_config
        check "restore nginx config"
    fi

}

install_openjdk(){
        info_log "Install openjdk...."
        yum -y install qingteng-openjdk
        yum -y update qingteng-openjdk
        check "Install openjdk"
}
install_jdk(){
        info_log "Install jdk...."
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
install_logstash(){
        info_log "Instasll logstash..."
        yum -y install logstash
        yum -y update logstash
        check "Install logstash"
        init_logstash_config
        check "init logstash config"
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

init_sys(){
    # sys config
    config_conf ${QT_SYS_CONF}
    sed -i '/^*/d' /etc/security/limits.d/*.conf
    modprobe bridge && sysctl -p || true
    if [ -z "`cat  /etc/sysctl.conf |grep -w "vm.swappiness"`" ];then echo "vm.swappiness = 1" >> /etc/sysctl.conf && sysctl -p || true ;else sed -i 's#vm.swappiness.*#vm.swappiness = 1#g' /etc/sysctl.conf && sysctl -p || true;fi
    sysctl -a > /root/qingteng_sysctl.log
    if [ `command -v abrtd` ]; then
        [ -f /etc/abrt/abrt-action-save-package-data.conf ] && \
        sed -i 's/ProcessUnpackaged = no/ProcessUnpackaged = yes/' /etc/abrt/abrt-action-save-package-data.conf
        service abrtd restart
    fi
    check "Load sys config"
}

## -------------------------Starting------------------------------ ##

roles=$1
host=$2

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


install_bigdata

init_sys

chmod 755 /data 

if [ $roles == "viewer" ];then	
	chkconfig nginx on
	service  nginx restart
fi

info_log "Done"
