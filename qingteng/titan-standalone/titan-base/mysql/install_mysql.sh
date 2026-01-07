#!/bin/bash
set -e
## --------------------Marco Define------------------------------- ##
# error hint
COLOR_G="\x1b[0;32m"  # green
COLOR_R="\x1b[1;31m"  # red
RESET="\x1b[0m"

## sys
QT_PACKAGE_ROOT="/data/qt_base"
QT_SYS_CONF="${QT_PACKAGE_ROOT}/base/config"

## mysql
QT_PACKET_DIR="/data/qt_base/mysql"
QT_CONF="${QT_PACKET_DIR}/config"

# data and logs
QT_MYSQL_LOG="/data/logs/mysql"
QT_MYSQL_DATA="/data/mysql"

# installation directory
QT_INSTALL_DIR="/usr/local/qingteng"
QT_MYSQL_DIR="mysql"

## --------------------Utils-------------------------------------- ##

IS_SLAVE=false

if [ -n "`echo $*|grep slave`" ]; then
    IS_SLAVE=true
fi



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

create_user(){
    info_log "Create mysql user"
    useradd -M mysql -s /sbin/nologin -c "MySql Server"
}

is_mysql_installed(){
    if [ -e "${QT_INSTALL_DIR}/${QT_MYSQL_DIR}/bin/mysql" ]; then
        /usr/local/qingteng/mysql/bin/mysql --version 
        if [ $? -ne 0 ]; then
            return 0
        fi
        info_log "MySQL installed already"
        return 1
    fi
    return 0
}

install_percona(){
    if [ $(is_mysql_installed > /dev/null 2>&1;echo $?) != 0 ]; then
        chkconfig --add mysqld
        chkconfig mysqld on
        config_conf ${QT_CONF}
        return
    fi
 
    yum clean all
    yum -y install  qingteng-percona
    yum -y update  qingteng-percona
    config_conf ${QT_CONF}
    
    chkconfig --add mysqld
    chkconfig mysqld on

    grep "CentOS Linux release 7" /etc/redhat-release && yum -y install perl-Data-Dumper 
    ${QT_INSTALL_DIR}/mysql/bin/mysqld --initialize-insecure   --user=mysql --datadir=${QT_MYSQL_DATA} --basedir=${QT_INSTALL_DIR}/${QT_MYSQL_DIR}
    #${QT_INSTALL_DIR}/mysql/scripts/mysql_install_db --defaults-file=/etc/my.cnf  \
    #--user=mysql \
    #--datadir=${QT_MYSQL_DATA} \
    #--basedir=${QT_INSTALL_DIR}/${QT_MYSQL_DIR}

    check "MySQL install init"
}

modify_pwd(){
    info_log "Modify Mysql password"
    [ ! -f /tmp/mysql.tmp ] && /usr/local/qingteng/mysql/bin/mysqladmin -uroot password 9pbsoq6hoNhhTzl && touch /tmp/mysql.tmp
    /usr/local/qingteng/mysql/bin/mysql -uroot -p9pbsoq6hoNhhTzl -e "flush privileges"
    check "Modify Mysql password"
}

## -------------------------Configure------------------------------ ##

update_config(){
    local qt_conf=$1
    local dest_dir=$2

    if [ ! -z ${dest_dir} ]
    then
        ensure_dir_exists ${dest_dir}
        /bin/cp -b ${qt_conf} ${dest_dir}
        check "config ${qt_conf}"
    fi
}

config_conf(){
    local conf_path=$1
    local conf=${conf_path}/conf.conf

    [ ${IS_SLAVE} = "true" ] && sed -i "s/server-id.*/server-id = 2/" ${conf_path}/my.cnf

    if [ -f ${conf} ]; then
        (IFS=$'\n';for line in `cat ${conf}`; do
             local file=`echo ${line} | awk -F " " '{print $1}'`
             local dest=`echo ${line} | awk -F" " '{print $2}'`
             update_config "${conf_path}/${file}" ${dest}
        done)
    fi
}

## -------------------------Launch Services----------------------- ##

launch_mysql(){
    if [ -z $(cat /etc/selinux/config|grep -w "SELINUX=disabled") ];then
        setenforce 0
        sed -i "s/^SELINUX=.*/SELINUX=disabled/g" /etc/selinux/config
        #sed -i '/SELINUX/s/enforcing/disabled/' /etc/selinux/config
    fi
    service mysqld restart
    sleep 1
    modify_pwd
    service mysqld restart
}

install_tar_packets(){
    ensure_dir_exists ${QT_INSTALL_DIR}
    create_user
    install_percona
}

init_sys(){
    # sys config
    config_conf ${QT_SYS_CONF}
    sed -i '/^*/d' /etc/security/limits.d/*.conf
    modprobe bridge && sysctl -p || true
    sysctl -a > /root/qingteng_sysctl.log
    if [ $(command -v abrtd;echo $?) == "0" ]; then
        [ -f /etc/abrt/abrt-action-save-package-data.conf ] && \
        sed -i 's/ProcessUnpackaged = no/ProcessUnpackaged = yes/' /etc/abrt/abrt-action-save-package-data.conf
        service abrtd restart
    fi
    check "Load sys config"
}

remove_old(){
    [ ! -z "$(/usr/local/qingteng/mysql/bin/mysql -uroot -p9pbsoq6hoNhhTzl -e "show databases ;"|grep -w "base")" ] && /usr/local/qingteng/mysql/bin/mysql -uroot -p9pbsoq6hoNhhTzl -e "drop database base;" || echo "databases base does not exist"
    [ ! -z "$(/usr/local/qingteng/mysql/bin/mysql -uroot -p9pbsoq6hoNhhTzl -e "show databases ;"|grep -w "core")" ] && /usr/local/qingteng/mysql/bin/mysql -uroot -p9pbsoq6hoNhhTzl -e "drop database core;" || echo "databases core does not exist"
}

init_mysql(){
    info_log "Init mysql database"
    /usr/local/qingteng/mysql/bin/mysql -uroot -p9pbsoq6hoNhhTzl -e "grant all privileges on *.* to 'root'@'%' identified by '9pbsoq6hoNhhTzl' with grant option;"
    /usr/local/qingteng/mysql/bin/mysql -uroot -p9pbsoq6hoNhhTzl -e "grant all privileges on *.* to 'root'@'localhost' identified by '9pbsoq6hoNhhTzl' with grant option;"
    /usr/local/qingteng/mysql/bin/mysql -uroot -p9pbsoq6hoNhhTzl -e "grant all privileges on *.* to 'root'@'127.0.0.1' identified by '9pbsoq6hoNhhTzl' with grant option;"

    /usr/local/qingteng/mysql/bin/mysql -uroot -p9pbsoq6hoNhhTzl -e "flush privileges;"

    remove_old
    /usr/local/qingteng/mysql/bin/mysql -uroot -p9pbsoq6hoNhhTzl -e "create database base;"
    /usr/local/qingteng/mysql/bin/mysql -uroot -p9pbsoq6hoNhhTzl -e "create database core;"

    check "Init Mysql"
}
## -------------------------Starting------------------------------ ##
if [ "$1" == "upconfig" ];then
    config_conf ${QT_CONF}
    service mysqld restart
    exit 0
fi

if [ "$1" == "upconfig-local" ];then
    config_conf ${QT_PACKET_DIR}/config-local
    service mysqld restart
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


chmod 755 /data   &>/dev/null
install_percona

init_sys


chown -R mysql:mysql /data/mysql/ &>/dev/null
chown -R mysql:mysql /data/titan-logs/mysql/ &>/dev/null
chmod 755 /data/mysql/  &>/dev/null

launch_mysql

init_mysql

info_log "Done"
