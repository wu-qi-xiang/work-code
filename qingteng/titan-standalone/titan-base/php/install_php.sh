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
QT_PACKAGE_DIR="/data/qt_base/php"
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

is_php_installed(){
    if [ -e "${QT_INSTALL_DIR}/php/bin/php" ]; then
        info_log "PHP installed already"
        rm -rf /usr/local/php && ln -sF ${QT_INSTALL_DIR}/php /usr/local/
        return 1
    fi
    return 0
}

is_php_ext_installed(){
    local ext=$1
    local ret=`find ${QT_INSTALL_DIR}/php/ -name ${ext}.so`
    if [ -z ${ret} ]; then
        return 0
    else
        info_log "${ext} installed already"
        return 1
    fi
}

## --------------------Tar Packets Install------------------------ ##

install_php(){
    #is_php_installed
    #if [ $? -eq 1 ]; then
    #    return
    #fi

    info_log "Install PHP...."
    yum clean all
    /usr/local/bin/mysqldump --version || yum -y install qingteng-percona
    /usr/sbin/nginx -V && rpm -aq|grep nginx |xargs -i yum remove -y {}
    yum -y install  qingteng-php qingteng-nginx unzip qingteng-jdk nginx
    yum -y update  qingteng-php qingteng-nginx qingteng-jdk nginx
    check "Install PHP"
}

## the "/usr/local/php/bin/php-config" was specified
## when php installed with parameter "--prefix=/usr/local/php"
## --with-php-config=/usr/local/php/bin/php-config
install_gearman(){

    is_php_ext_installed "gearman"
    if [ $? -eq 1 ]; then
        return
    fi

    remove_dir ${QT_PACKAGE_DIR}/gearman-1.1.1/
    info_log "Install Gearmand...."

    tar xzf ${QT_PACKAGE_DIR}/php_extend/gearman-1.1.1.tgz -C ${QT_PACKAGE_DIR} || exit 1
    cd ${QT_PACKAGE_DIR}/gearman-1.1.1/
    # generate configure file
    ${QT_INSTALL_DIR}/php/bin/phpize
    make clean
    ./configure --prefix=${QT_INSTALL_DIR}/gearman-1.1.1 --with-php-config=${QT_INSTALL_DIR}/php/bin/php-config
    make && make install
    check "Install Gearmand"
}

install_msgpack(){

    is_php_ext_installed "msgpack"
    if [ $? -eq 1 ]; then
        return
    fi

    remove_dir ${QT_PACKAGE_DIR}/msgpack-0.5.7/
    info_log "Install Msgpack"

    tar xzf ${QT_PACKAGE_DIR}/php_extend/msgpack-0.5.7.tgz -C ${QT_PACKAGE_DIR} || exit 1
    cd ${QT_PACKAGE_DIR}/msgpack-0.5.7/

    ${QT_INSTALL_DIR}/php/bin/phpize
    make clean
    ./configure --prefix=${QT_INSTALL_DIR}/msgpack-0.5.7 --with-php-config=${QT_INSTALL_DIR}/php/bin/php-config
    make && make install

    check "Install Msgpack"
}

install_redis(){

    is_php_ext_installed "redis"
    if [ $? -eq 1 ]; then
        return
    fi

    remove_dir ${QT_PACKAGE_DIR}/redis-2.2.8/
    info_log "Install Redis-Driver"
    tar xzf ${QT_PACKAGE_DIR}/php_extend/redis-2.2.8.tgz -C ${QT_PACKAGE_DIR} || exit 1

    cd ${QT_PACKAGE_DIR}/redis-2.2.8/
    ${QT_INSTALL_DIR}/php/bin/phpize
    make clean
    ./configure --prefix=${QT_INSTALL_DIR}/redis-2.2.8 --with-php-config=${QT_INSTALL_DIR}/php/bin/php-config
    make && make install
    check "Install PHP Redis-Driver"
}

install_yac(){

    is_php_ext_installed "yac"
    if [ $? -eq 1 ]; then
        return
    fi

    remove_dir ${QT_INSTALL_DIR}/yac-0.9.2/
    info_log "Install Yac"

    tar xzf ${QT_PACKAGE_DIR}/php_extend/yac-0.9.2.tgz -C ${QT_PACKAGE_DIR} || exit 1
    cd ${QT_PACKAGE_DIR}/yac-0.9.2/
    ${QT_INSTALL_DIR}/php/bin/phpize
    make clean
    ./configure --prefix=${QT_INSTALL_DIR}/yac-0.9.2 --with-php-config=${QT_INSTALL_DIR}/php/bin/php-config
    make && make install
    check "Install Yac"
}

install_yaf(){

    is_php_ext_installed "yaf"
    if [ $? -eq 1 ]; then
        return
    fi

    remove_dir ${QT_INSTALL_DIR}/yaf-2.3.5/
    info_log "Install Yaf"

    tar xzf ${QT_PACKAGE_DIR}/php_extend/yaf-2.3.5.tgz -C ${QT_PACKAGE_DIR} || exit 1
    cd ${QT_PACKAGE_DIR}/yaf-2.3.5/
    ${QT_INSTALL_DIR}/php/bin/phpize
    make clean
    ./configure --prefix=${QT_INSTALL_DIR}/yaf-2.3.5 --with-php-config=${QT_INSTALL_DIR}/php/bin/php-config
    make && make install
    check "Install Yaf"
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

    touch /data/titan-logs/php-fpm/php-fpm.log

    chown nginx:nginx /data/app/conf
    chown -R nginx:nginx /data/titan-logs/nginx
    chown -R nginx:nginx /data/titan-logs/supervisor
    chown -R nginx:nginx /data/titan-logs/php-fpm
    chown -R nginx:nginx /usr/local/qingteng/php
    chown -R nginx:nginx /var/log/nginx
    [ -d /var/lib/nginx ] && chown nginx:nginx /var/lib/nginx && chmod 700 /var/lib/nginx
    [ -d /var/lib/nginx/tmp ] && chown nginx:nginx /var/lib/nginx/tmp && chmod 700 /var/lib/nginx/tmp && chown nginx:root /var/lib/nginx/tmp/*

    chmod 755 -R /data/app/conf
    chmod 755 -R /data/titan-logs/
    chmod 755 /usr/local/qingteng
    chmod 755 -R /usr/local/qingteng/php
    chmod 755 -R /var/log/nginx


    chmod 644 /etc/supervisord.conf

    chkconfig --add php-fpm
    chkconfig php-fpm on

    chkconfig --add nginx
    chkconfig nginx on

    chkconfig supervisord on
    #service supervisord restart

    service php-fpm restart
    service nginx restart

    chmod 777 /dev/shm/php-fpm.sock
}

launch_nginx() {
    nginx -t
    grep -q nginx /etc/rc.local || echo "nginx -c /etc/nginx/nginx.conf" >> /etc/rc.local
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
    service php-fpm restart
    service supervisord restart
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


chmod 755 /data
install_php

init_sys


# app config
config_conf ${QT_CONF}
if [ "$1" != "" ];then
    sed -i "s#http://127.0.0.1:6000#http://$1:6000#g" /data/app/conf/nginx.servers.conf
    sed -i "s#\(http://\).*\(:6130\)#\1$1\2#g" /data/app/conf/proxy/nginx.proxy.conf 
fi
#fix nginx restart bug
if [ -f "/usr/lib/systemd/system/nginx.service" ];then
    [ `grep -c "sleep" /usr/lib/systemd/system/nginx.service` -eq '0' ] && sed -i '/ExecStart=/a\ExecStartPost=/bin/sleep 0.1' /usr/lib/systemd/system/nginx.service
    systemctl daemon-reload      >/dev/null 2>&1
fi
#change nginx uid and gid 3020
if [ "`id -u nginx`" != "3020" -a "`ps aux | grep nginx | grep -v grep |wc -l`" == "0" ];then 
    usermod -u 3020 nginx && groupmod -g 3020 nginx 
fi

launch_service

info_log "Done"
