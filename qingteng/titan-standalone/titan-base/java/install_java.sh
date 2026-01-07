#!/bin/bash

## --------------------Marco Define------------------------------- ##
# error hint
COLOR_G="\x1b[0;32m"  # green
COLOR_R="\x1b[1;31m"  # red
RESET="\x1b[0m"

## sys
QT_PACKAGE_ROOT="/data/qt_base"
QT_SYS_CONF="${QT_PACKAGE_ROOT}/base/config"

## java
QT_PACKAGE_DIR="/data/qt_base/java"
QT_CONF="${QT_PACKAGE_DIR}/config"

## installation directory
QT_INSTALL_DIR=/usr/local/qingteng

QT_ZK_DIR=zookeeper
QT_ZK_DATA=/data/zk-data

QT_KAFKA_DIR=kafka
QT_KAFKA_LOG=/data/kafka-logs
QT_KAFKA_PARTITIONS_NUM=3

QT_ARTHAS_DIR=arthas

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

remove_dir(){
    local dir=$1
    if [ -e ${dir} ]; then
        rm -rf ${dir}
        info_log "remove dir ${dir}"
    fi
}

## --------------------Tar Packets Install------------------------ ##

install_python(){
    # python2.7 -V
    # if [ $? -ne 0 ]; then
    local pip_packages_dir=${QT_PACKAGE_DIR}/pip_packages
        info_log "Install Python2.7...."
        /usr/local/bin/mysqldump --version || yum -y install qingteng-percona
        yum -y install  qingteng-python
        yum -y update  qingteng-python
        check "Install Python2.7"
    info_log "Install Python Offline dependency ..."
    /usr/local/qingteng/python2.7/bin/pip install --no-index --find-links ${pip_packages_dir}/ -r ${pip_packages_dir}/requirements.txt
    check "Install Python Offline dependency ..."
    # else
        #python_path=`which python2.7`
        #if [ "$python_path" != "/usr/local/sbin/python2.7" ] || [ "$python_path" != "/usr/local/bin/python2.7" ];then
            #python_dir=`dirname $python_path`
            #mv $python_path $python_dir/python27
            
            #info_log "Install Python2.7...."
            #mysqldump --version || yum -y install qingteng-percona
            #yum -y install  qingteng-python
            #yum -y update  qingteng-python
            #check "Install Python2.7"
        #fi
    #fi
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

install_nmap(){
    info_log "Install nmap...."
    yum -y install nmap
    yum -y update nmap
    if [ -z "`grep nmap /etc/sudoers`" ];then
        chmod u+w /etc/sudoers
        echo "titan        ALL=(root)       NOPASSWD:/usr/bin/nmap" >> /etc/sudoers
        chmod u-w /etc/sudoers
    fi
    check "Install nmap"
}

install_zk(){
        info_log "Install Zookeeper...."
        rpm -q qingteng-zookeeper-* >/dev/null && is_update="yes" && service zookeeperd stop
        install_jdk
        yum -y install qingteng-zookeeper
        yum -y update qingteng-zookeeper
        update_config "${QT_CONF}/zoo.cfg" /usr/local/qingteng/zookeeper/conf/
        if [ "${is_update}" == "yes" ];then
            [ -d "/data/zk-data" ] && cp -ar /data/zk-data /data/zk-data-bak$(date '+%Y%m%d%H%M%S')
            update_config "${QT_CONF}/snapshot.0" /data/zk-data/version-2/
            echo "authProvider.1=org.apache.zookeeper.server.auth.SASLAuthenticationProvider" >> /usr/local/qingteng/zookeeper/conf/zoo.cfg
            service zookeeperd restart
        fi
        chmod 755 -R /usr/local/qingteng/zookeeper
        check "Install Zookeeper"
}

install_kafka(){
        info_log "Install Kafka...."
        yum clean all
        rpm -q qingteng-kafka-* >/dev/null && service kafkad stop
        install_jdk
        yum -y install qingteng-kafka
        yum -y update qingteng-kafka
        update_config "${QT_CONF}/server.properties" /usr/local/qingteng/kafka/config/
        chmod 755 -R /usr/local/qingteng/kafka
        check "Install Kafka"
        #change default kafka memory to 2G
}

install_arthas(){
    if [ ! -d /usr/local/qingteng/arthas ];then
        mkdir -p /usr/local/qingteng/arthas
        chmod 755 /usr/local/qingteng
        rsync --delete -rz ${QT_PACKAGE_DIR}/arthas-packaging-3.4.6-bin/* /usr/local/qingteng/arthas/ && chmod 755 -R /usr/local/qingteng/arthas && bash /usr/local/qingteng/arthas/install-local.sh
        check "Install arthas"
        return
    else
        info_log "arthas already exits: ${QT_INSTALL_DIR}/${QT_ARTHAS_DIR}"
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

    [ -f ${qt_conf} ] || exit 1

    if [ ! -z ${dest_dir} ]
    then
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

add_service_zk(){
    if [ -f /etc/init.d/zookeeperd ]; then
        chmod +x /etc/init.d/zookeeperd
        chkconfig --add zookeeperd
        chkconfig zookeeperd on
    fi
}

add_service_kafka(){
    if [ -f /etc/init.d/kafkad ]; then
        chmod +x /etc/init.d/kafkad
        chkconfig --add kafkad
        chkconfig kafkad on
    fi
}

check_hostname(){
    info_log "check hostname"
    local hostname=`hostname`
    [ -z "`grep 127.0.0.1 /etc/hosts|grep ${hostname}`" ] && \
    echo -e "127.0.0.1  ${hostname}" >> /etc/hosts
    cat /etc/hosts
}

kafka_ip(){
    if [ "$1" != "" ];then
        sed -i "s#PLAINTEXT://.*:9092#PLAINTEXT://$1:9092#g" /usr/local/qingteng/kafka/config/server.properties
        info_log "change default kafka memory..."
        sed -i "s#-Xmx1G -Xms1G#-Xmx2G -Xms1G#g" /usr/local/qingteng/kafka/bin/kafka-server-start.sh 
        service kafkad restart >/dev/null
    fi
}

kafka_bak_recover_file(){
    local status=$1
    local kafka_server_file="/usr/local/qingteng/kafka/bin/kafka-server-start.sh"
    local kafka_server_file_bak="/tmp/kafka-server-start.sh"
    if [ -f $kafka_server_file -a $(grep jmx_path $kafka_server_file |wc -l) -gt 0 ];then
        if [ $status == "bak" ];then
            rm -rf $kafka_server_file_bak && rsync -rz --delete $kafka_server_file $kafka_server_file_bak
        else
            if [ -f $kafka_server_file_bak ];then
                rsync -rz --delete $kafka_server_file_bak $kafka_server_file
            fi
        fi
    fi
}

all_java(){
    # python2.7 
    install_python

    #openjdk for webshell 
    install_openjdk 
    #jdk
    install_jdk
    #nmap
    install_nmap
    check_hostname
    # sys config
    init_sys
    # app config
    chmod 755 /data  &>/dev/null

}

## -------------------------Starting------------------------------ ##
if [ "$1" == "upconfig" ];then
    config_conf ${QT_CONF}
    service zookeeperd restart
    service kafkad restart
    exit 0
fi

if [ "$1" == "upconfig-local" ];then
    config_conf ${QT_PACKAGE_DIR}/config-local
    service zookeeperd restart
    service kafkad restart
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


case $1 in
    java|ms_srv|event_srv)
	yum clean all
        all_java
        install_arthas
        ;;
    zookeeper)
	yum clean all
        install_zk
        add_service_zk
        service zookeeperd restart
        ;;
    kafka)
	yum clean all
        kafka_bak_recover_file bak
        install_kafka
        add_service_kafka
        kafka_bak_recover_file recover
        kafka_ip $2
        ;;
    arthas)
        yum clean all
        install_arthas
        ;;
    openjdk)
        yum  clean all
        install_openjdk
        ;;
    python)
        install_python
        ;;
    *)
        echo "Usage: {java|zookeeper|kafka}"
        exit 1
        ;;
esac

info_log "Done"
