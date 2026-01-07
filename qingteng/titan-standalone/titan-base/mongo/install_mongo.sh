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

## mongodb
QT_PACKET_DIR="/data/qt_base/mongo"
QT_CONF="${QT_PACKET_DIR}/config"
QT_WISTERIA_ASSETS="${QT_PACKET_DIR}/win_patch.zip"

## installation and configuration directory
# installation directory
QT_INSTALL_DIR="/usr/local/qingteng"
QT_MONGO_DIR="mongodb"
QT_MONGO_CONF="${QT_MONGO_DIR}/conf"
# logs and data
QT_MONGO_DATA="/data/mongodb/data"
QT_MONGO_LOG="/data/mongodb/logs"

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

## --------------------Tar Packets Install------------------------ ##
is_mongo_installed(){

    if [ -e ${QT_INSTALL_DIR}/${QT_MONGO_DIR}/bin/mongod ]; then
        /usr/local/bin/mongod --version
        if [ $? -ne 0 ]; then
            # not
            return 0
        fi
        info_log "Mongodb installed already"
        return 1
    fi
    return 0
}

install_mongo(){
    if [ $(is_mongo_installed > /dev/null 2>&1;echo $? ) != 0 ]; then
        sed -i "s/authorization:.*/authorization: disabled/" ${QT_INSTALL_DIR}/${QT_MONGO_CONF}/mongod.conf
        return
    fi
    
    info_log "Install MongoDB...."
    yum clean all
    yum -y install  qingteng-mongodb
    yum -y update  qingteng-mongodb
    check "Install Mongodb"
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
    local conf="${conf_path}/conf.conf"

    if [ -f ${conf} ]; then
        (IFS=$'\n';for line in `cat $conf`; do
             local file=`echo ${line} | awk -F " " '{print $1}'`
             local dest=`echo ${line} | awk -F" " '{print $2}'`
             update_config ${conf_path}/${file} ${dest}
        done)
    fi
}

## -------------------------Launch Services----------------------- ##

remove_old_base(){
    # set support MongoDB-CR authentication
    ${QT_INSTALL_DIR}/${QT_MONGO_DIR}/bin/mongo admin --eval "db.system.version.remove({_id: \"authSchema\"});\
    db.system.version.insert({_id:\"authSchema\",currentVersion:3});"
    ${QT_INSTALL_DIR}/${QT_MONGO_DIR}/bin/mongo admin --eval "db.system.users.remove({user:\"qingteng\"})"
}

remove_old_erlang(){
    remove_old_base
    ${QT_INSTALL_DIR}/${QT_MONGO_DIR}/bin/mongo admin --eval "db.system.users.remove({user:\"rwuser\"})"
}

init_database_erlang(){
    remove_old_erlang
    ${QT_INSTALL_DIR}/${QT_MONGO_DIR}/bin/mongo admin --eval "db.createUser({user:\"qingteng\", pwd:\"9pbsoq6hoNhhTzl\", roles:[\"root\"]})"
    ${QT_INSTALL_DIR}/${QT_MONGO_DIR}/bin/mongo cvelib --eval "db.createUser({user:\"rwuser\", pwd:\"titan7vc65x\", roles:[{role:\"readWrite\", db:\"cvelib\"}]})"
    ${QT_INSTALL_DIR}/${QT_MONGO_DIR}/bin/mongo assets --eval "db.createUser({user:\"rwuser\", pwd:\"titan7vc65x\", roles:[{role:\"readWrite\", db:\"assets\"}]})"
    ${QT_INSTALL_DIR}/${QT_MONGO_DIR}/bin/mongo core --eval "db.createUser({user:\"rwuser\", pwd:\"titan7vc65x\", roles:[{role:\"readWrite\", db:\"core\"}]})"
    ${QT_INSTALL_DIR}/${QT_MONGO_DIR}/bin/mongo vine_dev --eval "db.createUser({user:\"rwuser\", pwd:\"titan7vc65x\", roles:[{role:\"readWrite\", db:\"vine_dev\"}]})"
    # For V3.0
    ${QT_INSTALL_DIR}/${QT_MONGO_DIR}/bin/mongo job --eval "db.createUser({user:\"rwuser\", pwd:\"titan7vc65x\", roles:[{role:\"readWrite\", db:\"job\"}]})"
    ${QT_INSTALL_DIR}/${QT_MONGO_DIR}/bin/mongo job_error --eval "db.createUser({user:\"rwuser\", pwd:\"titan7vc65x\", roles:[{role:\"readWrite\", db:\"job_error\"}]})"
    check "Init Erlang Mongodb"
}

init_database_java(){
    remove_old_base
    ${QT_INSTALL_DIR}/${QT_MONGO_DIR}/bin/mongo admin --eval "db.system.version.remove({_id: \"authSchema\"})"
    ${QT_INSTALL_DIR}/${QT_MONGO_DIR}/bin/mongo admin --eval "db.createUser({user:\"qingteng\", pwd:\"9pbsoq6hoNhhTzl\", roles:[\"root\"]})"
    check "Init Java Mongodb"
}

enable_auth(){
    sed -i "s/authorization:.*/authorization: enabled/" ${QT_INSTALL_DIR}/${QT_MONGO_CONF}/mongod.conf
    check "Enable MongoDB auth"
    service mongod restart
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

launch_mongod(){
    #sed -i "s/bind_ip=127.0.0.1/bind_ip=127.0.0.1,0.0.0.0/g" ${QT_INSTALL_DIR}/${QT_MONGO_CONF}/mongod.conf
    if [ -z `cat /etc/selinux/config|grep -w "SELINUX=disabled"` ];then
        setenforce 0
        sed -i "s/^SELINUX=.*/SELINUX=disabled/g" /etc/selinux/config
        #sed -i '/SELINUX/s/enforcing/disabled/' /etc/selinux/config
    fi
    chmod +x /etc/init.d/mongod
    chkconfig --add mongod
    chkconfig mongod on
    service mongod restart
}

restore_wisteria_assets(){
    [ -f ${QT_WISTERIA_ASSETS} ] && unzip ${QT_WISTERIA_ASSETS} -d ${QT_PACKET_DIR} && \
    cd ${QT_PACKET_DIR} && ${QT_INSTALL_DIR}/${QT_MONGO_DIR}/bin/mongorestore -d wisteria_assets win_patch/wisteria_assets
}

## -------------------------Starting------------------------------ ##


# Increase the cachesize of single mongo in multi-node deployment
mongo_bigcache=$2

if [ "${mongo_bigcache}" == "enable" ];then
    sed -i "s/cacheSizeGB:.*/cacheSizeGB: 16/" ${QT_CONF}/mongod.conf
fi

#setting mongo_ms_srv mongod cachesize 10
if [ "$1" == "mongo_ms_srv" ];then
    sed -i 's/cacheSizeGB:.*/cacheSizeGB: 10/g' $QT_PACKET_DIR/config/mongod.conf
    sed -i 's/cacheSizeGB:.*/cacheSizeGB: 10/g' $QT_PACKET_DIR/config-local/mongod.conf
fi

if [ "$1" == "upconfig" ];then
    config_conf ${QT_CONF}
    service mongod restart
    exit 0
fi

if [ "$1" == "upconfig-local" ];then
    config_conf ${QT_PACKET_DIR}/config-local
    service mongod restart
    exit 0
fi


[ $# -gt 0 ] || `echo "Usage: $0 [mongo_erlang|mongo_java|mongo_ms_srv]" exit 1`

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
install_mongo

init_sys

# app config
config_conf ${QT_CONF}

if [ ! -d /data/mongodb ]; then
   mkdir -p  /data/mongodb/data 
fi
chown -R mongodb:mongodb /data/mongodb/  &>/dev/null
if [ ! -d /data/titan-logs/mongodb ]; then
   mkdir -p /data/titan-logs/mongodb
fi
chown -R mongodb:mongodb /data/titan-logs/mongodb/  &>/dev/null
chown -R mongodb:mongodb /usr/local/qingteng/mongodb/conf/  &>/dev/null
chmod 644 /etc/logrotate.d/mongo_logrotate &>/dev/null
chmod 755  /usr/local/qingteng/mongodb/conf/*.conf &>/dev/null
chmod 755 /data/titan-logs/mongodb/  &>/dev/null

chmod 755 /etc/init.d/disable-transparent-hugepages &>/dev/null
chkconfig --add disable-transparent-hugepages &>/dev/null
/etc/init.d/disable-transparent-hugepages start

launch_mongod

case $1 in
    mongo_erlang)
            init_database_erlang
        ;;
    mongo_java|mongo_ms_srv)
            init_database_java
        ;;
    enable_auth)
            enable_auth
        ;;
    *)
        echo "Usage: $0 [mongo_erlang|mongo_java|mongo_ms_srv]"
        exit 1
        ;;
esac

info_log "Done"
