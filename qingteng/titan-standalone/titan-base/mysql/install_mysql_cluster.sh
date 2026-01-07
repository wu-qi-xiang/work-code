#!/bin/bash

## --------------------Marco Define------------------------------- ##
# error hint
COLOR_G="\x1b[0;32m"  # green
COLOR_R="\x1b[1;31m"  # red
RESET="\x1b[0m"
QT_PACKAGE_ROOT="/data/qt_base"
## mysql
QT_PACKET_DIR="/data/qt_base/mysql"
QT_CONF="${QT_PACKET_DIR}/config"
##log&&data
QT_LOGS_DIR="/data/titan-logs/mysql"
QT_DATA_DIR="/data/mysql"
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
        chmod 755 -R ${dir}
        check "${dir} created"
    fi
}

install_mysql_cluster(){
	yum -y install Percona-XtraDB-Cluster-server-5* Percona-XtraDB-Cluster-client-5* 
    chkconfig --add mysqld
    chkconfig mysqld on
}
set_config(){
	cp -f $QT_CONF/my1.cnf /etc/my.cnf && chmod 755 /etc/my.cnf
	ensure_dir_exists ${QT_LOGS_DIR}
	ensure_dir_exists ${QT_DATA_DIR}
	if [ ! -f ${QT_LOGS_DIR}/error.log ];then touch /data/titan-logs/mysql/error.log;fi
	chown -R mysql.mysql /data/titan-logs/mysql /data/mysql
    sed -i "s/server_id=.*/server_id=${server_id}/g" /etc/my.cnf
	sed -i "s#wsrep_cluster_address=.*#wsrep_cluster_address=gcomm://${mysql_conect}#g" /etc/my.cnf
	sed -i "s#wsrep_node_address=.*#wsrep_node_address=${host}#g" /etc/my.cnf
	check "set_my.cnf "
	if [ ${mysql_master_status} == "master" ];then
		touch /tmp/init.sql && chmod 755 /tmp/init.sql
		echo "SET PASSWORD FOR 'root'@'localhost' = PASSWORD('${init_pwd}');" > /tmp/init.sql
		sed -i '/\[mysqld\]/a init-file=/tmp/init.sql' /etc/my.cnf
		chkconfig mysql on
		if [ ${SYSTEM_VERSION} == "7" ];then
			service mysql@bootstrap start
		else
			/etc/init.d/mysql bootstrap-pxc
                fi
		sleep 30
		sed -i '/init-file=.*/d' /etc/my.cnf && rm -f /tmp/init.sql
		/usr/bin/mysql -uroot -p${init_pwd} -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '9pbsoq6hoNhhTzl'"
		/usr/bin/mysql -uroot -p${init_pwd} -e "grant all on *.* to 'qingteng'@'localhost' identified by 'qttest';"
		/usr/bin/mysql -uroot -p${init_pwd} -e "FLUSH PRIVILEGES;"
	else
	    chkconfig mysql on
		service mysql restart
		sleep 30
	fi
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

host=$2
server_id=`echo ${host} | cut -d "." -f 4`
mysql_conect=$3
mysql_master_status=$4
init_pwd="9pbsoq6hoNhhTzl"

chmod 755 /data
install_mysql_cluster
set_config 
info_log "Done"

