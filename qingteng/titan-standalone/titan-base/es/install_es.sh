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
QT_PACKAGE_DIR="/data/qt_base/es"
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

is_es_installed(){
    if [ -e "${QT_INSTALL_DIR}/elasticsearch/elasticsearch" ]; then
        info_log "bigdata-es installed already"
        return 1
    fi
    return 0
}


## --------------------Tar Packets Install------------------------ ##

install_es(){
    #is_es_installed
    #if [ $? -eq 1 ]; then
    #    return
    #fi

    info_log "Install bigdata-es...."
    yum clean all
    yum -y install jdk1.8.0_144 qingteng-jdk
    yum -y install bigdata-es qingteng-ik
    yum -y update bigdata-es qingteng-ik
    check "Install bigdata-es"
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
    if [  ${node_ip} ];then
	    if [ ${node_status} == "master" ];then
            node_name="node-`echo ${node_ip}|awk -F "." '{print $4}'`-1"
            if [ -f /usr/local/qingteng/elasticsearch/elasticsearch_ins1/etc/node-1.p12 ];then sudo  mv /usr/local/qingteng/elasticsearch/elasticsearch_ins1/etc/node-1.p12 /usr/local/qingteng/elasticsearch/elasticsearch_ins1/etc/${node_name}.p12;fi
            sudo  sed -i "s#node.name:.*#node.name: ${node_name}#g" /usr/local/qingteng/elasticsearch/elasticsearch_ins1/etc/elasticsearch.yml
	    else
	        node_name="node-`echo ${node_ip}|awk -F "." '{print $4}'`-2"
            if [ -f /usr/local/qingteng/elasticsearch/elasticsearch_ins2/etc/node-2.p12 ];then sudo  mv /usr/local/qingteng/elasticsearch/elasticsearch_ins2/etc/node-2.p12 /usr/local/qingteng/elasticsearch/elasticsearch_ins2/etc/${node_name}.p12;fi
            sudo  sed -i "s#node.name:.*#node.name: ${node_name}#g" /usr/local/qingteng/elasticsearch/elasticsearch_ins2/etc/elasticsearch.yml
        fi
    fi
    if [ ! ${node_status} ];then
        /sbin/chkconfig --add elasticsearch_ins1
        /sbin/chkconfig --add elasticsearch_ins2
        /sbin/chkconfig --add elasticsearch_ins4
        /sbin/chkconfig  elasticsearch_ins1  on
        /sbin/chkconfig  elasticsearch_ins2  on
        /sbin/chkconfig  elasticsearch_ins4  on
        /sbin/chkconfig  elasticsearch_ins3  off
        /sbin/chkconfig --del elasticsearch_ins3
        
        cpu_number=$(cat /proc/cpuinfo | grep processor | wc -l)
        if [ $cpu_number -lt 16 ];then
            thread_pool=3
        elif [ $cpu_number -ge 32 ];then
            thread_pool=12
        else
            thread_pool=6
        fi
        for m in {1..4};do
	        #if [ $m == 4 -a -z "`cat /usr/local/qingteng/elasticsearch/elasticsearch_ins$m/etc/elasticsearch.yml |grep -w "node.voting_only"`" ];then echo "node.voting_only: true " >>/usr/local/qingteng/elasticsearch/elasticsearch_ins$m/etc/elasticsearch.yml;else sed -i 's#node.voting_only:.*#node.voting_only: true#g' /usr/local/qingteng/elasticsearch/elasticsearch_ins$m/etc/elasticsearch.yml;fi
	        #if [ $m == 3 ];then sudo sed -i "s#node.master:.*#node.master: true#g" /usr/local/qingteng/elasticsearch/elasticsearch_ins$m/etc/elasticsearch.yml;sudo sed -i "s#node.data:.*#node.data: false#g" /usr/local/qingteng/elasticsearch/elasticsearch_ins$m/etc/elasticsearch.yml;fi
            if [ $m == 3 ];then continue;fi
            if [ -z "`cat /usr/local/qingteng/elasticsearch/elasticsearch_ins$m/etc/elasticsearch.yml |grep -w "indices.breaker.total.use_real_memory"`" ];then echo "indices.breaker.total.use_real_memory: true " >>/usr/local/qingteng/elasticsearch/elasticsearch_ins$m/etc/elasticsearch.yml;else sed -i 's#indices.breaker.total.use_real_memory:.*#indices.breaker.total.use_real_memory: true#g' /usr/local/qingteng/elasticsearch/elasticsearch_ins$m/etc/elasticsearch.yml;fi
            if [ -z "`cat /usr/local/qingteng/elasticsearch/elasticsearch_ins$m/etc/elasticsearch.yml |grep -w "indices.breaker.total.limit"`" ];then echo "indices.breaker.total.limit: 90%" >>/usr/local/qingteng/elasticsearch/elasticsearch_ins$m/etc/elasticsearch.yml;else sed -i 's#indices.breaker.total.limit:.*#indices.breaker.total.limit: 90%#g' /usr/local/qingteng/elasticsearch/elasticsearch_ins$m/etc/elasticsearch.yml;fi
            if [ -z "`cat /usr/local/qingteng/elasticsearch/elasticsearch_ins$m/etc/elasticsearch.yml |grep -w "indices.breaker.request.limit"`" ];then echo "indices.breaker.request.limit: 60%" >>/usr/local/qingteng/elasticsearch/elasticsearch_ins$m/etc/elasticsearch.yml;else sed -i 's#indices.breaker.request.limit:.*#indices.breaker.request.limit: 60%#g' /usr/local/qingteng/elasticsearch/elasticsearch_ins$m/etc/elasticsearch.yml;fi
            if [ -z "`cat /usr/local/qingteng/elasticsearch/elasticsearch_ins$m/etc/elasticsearch.yml |grep -w "indices.breaker.fielddata.limit"`" ];then echo "indices.breaker.fielddata.limit: 40%" >>/usr/local/qingteng/elasticsearch/elasticsearch_ins$m/etc/elasticsearch.yml;else sed -i 's#indices.breaker.fielddata.limit:.*#indices.breaker.fielddata.limit: 40%#g' /usr/local/qingteng/elasticsearch/elasticsearch_ins$m/etc/elasticsearch.yml;fi
            if [ -z "`cat /usr/local/qingteng/elasticsearch/elasticsearch_ins$m/etc/elasticsearch.yml |grep -w "network.breaker.inflight_requests.limit"`" ];then echo "network.breaker.inflight_requests.limit: 80%" >>/usr/local/qingteng/elasticsearch/elasticsearch_ins$m/etc/elasticsearch.yml;else sed -i 's#network.breaker.inflight_requests.limit:.*#network.breaker.inflight_requests.limit: 80%#g' /usr/local/qingteng/elasticsearch/elasticsearch_ins$m/etc/elasticsearch.yml;fi
            if [ -z "`cat /usr/local/qingteng/elasticsearch/elasticsearch_ins$m/etc/elasticsearch.yml |grep -w "indices.breaker.accounting.limit"`" ];then echo "indices.breaker.accounting.limit: 80%" >>/usr/local/qingteng/elasticsearch/elasticsearch_ins$m/etc/elasticsearch.yml;else sed -i 's#indices.breaker.accounting.limit:.*#indices.breaker.accounting.limit: 80%#g' /usr/local/qingteng/elasticsearch/elasticsearch_ins$m/etc/elasticsearch.yml;fi
            if [ -z "`cat /usr/local/qingteng/elasticsearch/elasticsearch_ins$m/etc/elasticsearch.yml |grep -w "search.default_search_timeout"`" ];then echo "search.default_search_timeout: 120s" >>/usr/local/qingteng/elasticsearch/elasticsearch_ins$m/etc/elasticsearch.yml;else sed -i 's#search.default_search_timeout:.*#search.default_search_timeout: 120s#g' /usr/local/qingteng/elasticsearch/elasticsearch_ins$m/etc/elasticsearch.yml;fi
            if [ $m != 1 ];then
                if [ -z "`cat /usr/local/qingteng/elasticsearch/elasticsearch_ins$m/etc/elasticsearch.yml |grep -w "indices.fielddata.cache.size"`" ];then echo "indices.fielddata.cache.size: 30%" >>/usr/local/qingteng/elasticsearch/elasticsearch_ins$m/etc/elasticsearch.yml;else sed -i 's#indices.fielddata.cache.size:.*#indices.fielddata.cache.size: 30%#g' /usr/local/qingteng/elasticsearch/elasticsearch_ins$m/etc/elasticsearch.yml;fi
                if [ -z "`cat /usr/local/qingteng/elasticsearch/elasticsearch_ins$m/etc/elasticsearch.yml |grep -w "thread_pool.write.size"`" ];then echo "thread_pool.write.size: $thread_pool" >>/usr/local/qingteng/elasticsearch/elasticsearch_ins$m/etc/elasticsearch.yml;else sed -i "s#thread_pool.write.size:.*#thread_pool.write.size: $thread_pool#g" /usr/local/qingteng/elasticsearch/elasticsearch_ins$m/etc/elasticsearch.yml;fi
	        fi
            sudo sed -i "s#node.ingest:.*#node.ingest: false#g" /usr/local/qingteng/elasticsearch/elasticsearch_ins$m/etc/elasticsearch.yml
            sudo sed -i 's#discovery.seed_hosts:.*#discovery.seed_hosts: ["127.0.0.1:9301"]#g' /usr/local/qingteng/elasticsearch/elasticsearch_ins$m/etc/elasticsearch.yml
            sudo sed -i 's#cluster.initial_master_nodes:.*#cluster.initial_master_nodes: ["node-2"]#g' /usr/local/qingteng/elasticsearch/elasticsearch_ins$m/etc/elasticsearch.yml
	        service elasticsearch_ins$m restart
        done
    elif [ ${node_status} == "master" ];then
        /sbin/chkconfig --del elasticsearch_ins1
        /sbin/chkconfig --del elasticsearch_ins2
        /sbin/chkconfig --del elasticsearch_ins3
        /sbin/chkconfig --del elasticsearch_ins4
        /sbin/chkconfig  elasticsearch_ins1  off
        /sbin/chkconfig  elasticsearch_ins2  off
        /sbin/chkconfig  elasticsearch_ins3  off
        /sbin/chkconfig  elasticsearch_ins4  off
	    if [ -z "`cat /usr/local/qingteng/elasticsearch/elasticsearch_ins1/etc/elasticsearch.yml |grep -w "indices.breaker.total.use_real_memory"`" ];then echo "indices.breaker.total.use_real_memory: true " >>/usr/local/qingteng/elasticsearch/elasticsearch_ins1/etc/elasticsearch.yml;else sed -i 's#indices.breaker.total.use_real_memory:.*#indices.breaker.total.use_real_memory: true#g' /usr/local/qingteng/elasticsearch/elasticsearch_ins1/etc/elasticsearch.yml;fi
        if [ -z "`cat /usr/local/qingteng/elasticsearch/elasticsearch_ins1/etc/elasticsearch.yml |grep -w "indices.breaker.total.limit"`" ];then echo "indices.breaker.total.limit: 90%" >>/usr/local/qingteng/elasticsearch/elasticsearch_ins1/etc/elasticsearch.yml;else sed -i 's#indices.breaker.total.limit:.*#indices.breaker.total.limit: 90%#g' /usr/local/qingteng/elasticsearch/elasticsearch_ins1/etc/elasticsearch.yml;fi
        if [ -z "`cat /usr/local/qingteng/elasticsearch/elasticsearch_ins1/etc/elasticsearch.yml |grep -w "indices.breaker.request.limit"`" ];then echo "indices.breaker.request.limit: 60%" >>/usr/local/qingteng/elasticsearch/elasticsearch_ins1/etc/elasticsearch.yml;else sed -i 's#indices.breaker.request.limit:.*#indices.breaker.request.limit: 60%#g' /usr/local/qingteng/elasticsearch/elasticsearch_ins1/etc/elasticsearch.yml;fi
        if [ -z "`cat /usr/local/qingteng/elasticsearch/elasticsearch_ins1/etc/elasticsearch.yml |grep -w "indices.breaker.fielddata.limit"`" ];then echo "indices.breaker.fielddata.limit: 40%" >>/usr/local/qingteng/elasticsearch/elasticsearch_ins1/etc/elasticsearch.yml;else sed -i 's#indices.breaker.fielddata.limit:.*#indices.breaker.fielddata.limit: 40%#g' /usr/local/qingteng/elasticsearch/elasticsearch_ins1/etc/elasticsearch.yml;fi
        if [ -z "`cat /usr/local/qingteng/elasticsearch/elasticsearch_ins1/etc/elasticsearch.yml |grep -w "network.breaker.inflight_requests.limit"`" ];then echo "network.breaker.inflight_requests.limit: 80%" >>/usr/local/qingteng/elasticsearch/elasticsearch_ins1/etc/elasticsearch.yml;else sed -i 's#network.breaker.inflight_requests.limit:.*#network.breaker.inflight_requests.limit: 80%#g' /usr/local/qingteng/elasticsearch/elasticsearch_ins1/etc/elasticsearch.yml;fi
        if [ -z "`cat /usr/local/qingteng/elasticsearch/elasticsearch_ins1/etc/elasticsearch.yml |grep -w "indices.breaker.accounting.limit"`" ];then echo "indices.breaker.accounting.limit: 80%" >>/usr/local/qingteng/elasticsearch/elasticsearch_ins1/etc/elasticsearch.yml;else sed -i 's#indices.breaker.accounting.limit:.*#indices.breaker.accounting.limit: 80%#g' /usr/local/qingteng/elasticsearch/elasticsearch_ins1/etc/elasticsearch.yml;fi
        if [ -z "`cat /usr/local/qingteng/elasticsearch/elasticsearch_ins1/etc/elasticsearch.yml |grep -w "search.default_search_timeout"`" ];then echo "search.default_search_timeout: 120s" >>/usr/local/qingteng/elasticsearch/elasticsearch_ins1/etc/elasticsearch.yml;else sed -i 's#search.default_search_timeout:.*#search.default_search_timeout: 120s#g' /usr/local/qingteng/elasticsearch/elasticsearch_ins1/etc/elasticsearch.yml;fi
    elif [ ${node_status} == "data" ];then
	    /sbin/chkconfig --del elasticsearch_ins1
        /sbin/chkconfig --del elasticsearch_ins2
        /sbin/chkconfig --del elasticsearch_ins3
        /sbin/chkconfig --del elasticsearch_ins4
        /sbin/chkconfig  elasticsearch_ins1  off
        /sbin/chkconfig  elasticsearch_ins2  off
        /sbin/chkconfig  elasticsearch_ins3  off
        /sbin/chkconfig  elasticsearch_ins4  off
        if [ -z "`cat /usr/local/qingteng/elasticsearch/elasticsearch_ins2/etc/elasticsearch.yml |grep -w "indices.breaker.total.use_real_memory"`" ];then echo "indices.breaker.total.use_real_memory: true " >>/usr/local/qingteng/elasticsearch/elasticsearch_ins2/etc/elasticsearch.yml;else sed -i 's#indices.breaker.total.use_real_memory:.*#indices.breaker.total.use_real_memory: true#g' /usr/local/qingteng/elasticsearch/elasticsearch_ins2/etc/elasticsearch.yml;fi
        if [ -z "`cat /usr/local/qingteng/elasticsearch/elasticsearch_ins2/etc/elasticsearch.yml |grep -w "indices.breaker.total.limit"`" ];then echo "indices.breaker.total.limit: 90%" >>/usr/local/qingteng/elasticsearch/elasticsearch_ins2/etc/elasticsearch.yml;else sed -i 's#indices.breaker.total.limit:.*#indices.breaker.total.limit: 90%#g' /usr/local/qingteng/elasticsearch/elasticsearch_ins2/etc/elasticsearch.yml;fi
        if [ -z "`cat /usr/local/qingteng/elasticsearch/elasticsearch_ins2/etc/elasticsearch.yml |grep -w "indices.breaker.request.limit"`" ];then echo "indices.breaker.request.limit: 60%" >>/usr/local/qingteng/elasticsearch/elasticsearch_ins2/etc/elasticsearch.yml;else sed -i 's#indices.breaker.request.limit:.*#indices.breaker.request.limit: 60%#g' /usr/local/qingteng/elasticsearch/elasticsearch_ins2/etc/elasticsearch.yml;fi
        if [ -z "`cat /usr/local/qingteng/elasticsearch/elasticsearch_ins2/etc/elasticsearch.yml |grep -w "indices.breaker.fielddata.limit"`" ];then echo "indices.breaker.fielddata.limit: 40%" >>/usr/local/qingteng/elasticsearch/elasticsearch_ins2/etc/elasticsearch.yml;else sed -i 's#indices.breaker.fielddata.limit:.*#indices.breaker.fielddata.limit: 40%#g' /usr/local/qingteng/elasticsearch/elasticsearch_ins2/etc/elasticsearch.yml;fi
        if [ -z "`cat /usr/local/qingteng/elasticsearch/elasticsearch_ins2/etc/elasticsearch.yml |grep -w "network.breaker.inflight_requests.limit"`" ];then echo "network.breaker.inflight_requests.limit: 80%" >>/usr/local/qingteng/elasticsearch/elasticsearch_ins2/etc/elasticsearch.yml;else sed -i 's#network.breaker.inflight_requests.limit:.*#network.breaker.inflight_requests.limit: 80%#g' /usr/local/qingteng/elasticsearch/elasticsearch_ins2/etc/elasticsearch.yml;fi
        if [ -z "`cat /usr/local/qingteng/elasticsearch/elasticsearch_ins2/etc/elasticsearch.yml |grep -w "indices.breaker.accounting.limit"`" ];then echo "indices.breaker.accounting.limit: 80%" >>/usr/local/qingteng/elasticsearch/elasticsearch_ins2/etc/elasticsearch.yml;else sed -i 's#indices.breaker.accounting.limit:.*#indices.breaker.accounting.limit: 80%#g' /usr/local/qingteng/elasticsearch/elasticsearch_ins2/etc/elasticsearch.yml;fi
        if [ -z "`cat /usr/local/qingteng/elasticsearch/elasticsearch_ins2/etc/elasticsearch.yml |grep -w "search.default_search_timeout"`" ];then echo "search.default_search_timeout: 120s" >>/usr/local/qingteng/elasticsearch/elasticsearch_ins2/etc/elasticsearch.yml;else sed -i 's#search.default_search_timeout:.*#search.default_search_timeout: 120s#g' /usr/local/qingteng/elasticsearch/elasticsearch_ins2/etc/elasticsearch.yml;fi
    fi

}

init_sys(){
    # sys config
    config_conf ${QT_SYS_CONF}
    sed -i '/^*/d' /etc/security/limits.d/*.conf
    modprobe bridge && sysctl -p || true
    swapoff -a
    sed -ri 's/.*swap.*/#&/' /etc/fstab
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
node_ip=$2
node_status=$3
if [ "$1" == "upconfig" ];then
    config_conf ${QT_CONF}
    service elasticsearch_ins1 restart
    service elasticsearch_ins2 restart
    service elasticsearch_ins3 restart
    service elasticsearch_ins4 restart
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


install_es

init_sys

# app config
config_conf ${QT_CONF}

# change mem
MemTotal=`sudo awk '($1 == "MemTotal:"){print int($2/1048576)}'  /proc/meminfo`

if [ ${node_status} ];then
    if [ ${node_status} == "master" ];then
        sudo sed -i 's#-Xms.*#-Xms2g#g' /usr/local/qingteng/elasticsearch/elasticsearch_ins1/etc/jvm.options
        sudo sed -i 's#-Xmx.*#-Xmx2g#g' /usr/local/qingteng/elasticsearch/elasticsearch_ins1/etc/jvm.options
        sudo sed -i "s#node.master:.*#node.master: true#g" /usr/local/qingteng/elasticsearch/elasticsearch_ins1/etc/elasticsearch.yml
        sudo sed -i "s#node.data:.*#node.data: false#g" /usr/local/qingteng/elasticsearch/elasticsearch_ins1/etc/elasticsearch.yml
    
    elif [ ${node_status} == "data" ];then
	    if [ $MemTotal -lt 8 ];then
		    info_log "Memory is too low (小于8G),performace may not meet expectations"
		    exit 1
        elif [ $(($MemTotal/2)) -lt 30 ];then
		    memtotal_tmp=$(($MemTotal/2))
        else
		    memtotal_tmp=30
        fi
        sudo sed -i "s#-Xms.*#-Xms${memtotal_tmp}g#g" /usr/local/qingteng/elasticsearch/elasticsearch_ins2/etc/jvm.options
        sudo sed -i "s#-Xmx.*#-Xmx${memtotal_tmp}g#g" /usr/local/qingteng/elasticsearch/elasticsearch_ins2/etc/jvm.options
        sudo sed -i "s#node.master:.*#node.master: false#g" /usr/local/qingteng/elasticsearch/elasticsearch_ins2/etc/elasticsearch.yml
        sudo sed -i "s#node.data:.*#node.data: true#g" /usr/local/qingteng/elasticsearch/elasticsearch_ins2/etc/elasticsearch.yml
    fi
elif [ $MemTotal -lt 30 ];then
    info_log "Memory is too low, performance may not meet expectations"
    exit 1
else
    if [ $(($MemTotal/2/2)) -gt 30 ];then
	    memototal_tmp=30
    else
	    memototal_tmp=$(($MemTotal/2/2))
    fi
    sudo sed -i "s/-Xmx[0-9]*g/-Xmx${memototal_tmp}g/g"  /usr/local/qingteng/elasticsearch/elasticsearch_ins1/etc/jvm.options
    sudo sed -i "s/-Xms[0-9]*g/-Xms${memototal_tmp}g/g"  /usr/local/qingteng/elasticsearch/elasticsearch_ins1/etc/jvm.options
    sudo sed -i "s/-Xmx[0-9]*g/-Xmx4g/g"  /usr/local/qingteng/elasticsearch/elasticsearch_ins2/etc/jvm.options
    sudo sed -i "s/-Xms[0-9]*g/-Xms4g/g"  /usr/local/qingteng/elasticsearch/elasticsearch_ins2/etc/jvm.options
    sudo sed -i "s/-Xmx[0-9]*g/-Xmx${memototal_tmp}g/g"  /usr/local/qingteng/elasticsearch/elasticsearch_ins4/etc/jvm.options
    sudo sed -i "s/-Xms[0-9]*g/-Xms${memototal_tmp}g/g"  /usr/local/qingteng/elasticsearch/elasticsearch_ins4/etc/jvm.options
fi
chmod 755 /data
chmod 755 -R /usr/local/qingteng/elasticsearch/
launch_service

info_log "Done"
