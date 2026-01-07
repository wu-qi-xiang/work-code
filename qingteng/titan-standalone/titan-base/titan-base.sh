#!/bin/bash
## ------------------------Marco Define--------------------------- ##

# error hint
COLOR_G="\x1b[0;32m"  # green
COLOR_R="\x1b[1;31m"  # red
RESET="\x1b[0m"
UPCONFIG=false
UPLOCALCONFIG=false
USE_KEY_LOGIN=false
Set_Error=true

## ssh login
DEFAULT_PORT=22
DEFAULT_USER=root

ROOT=`cd \`dirname $0\` && pwd`
## Local
QT_DEPS_ROOT=${ROOT}

## config file: server_name  ip
ROLE_IP_TEMPLATE=${ROOT}/.role_template
SERVER_IP_CONF=${ROOT}/service_ip.conf
BASE_VERSION_JSON=${ROOT}/version.json

## The dir that need to be sent to remote server
QT_CONNECT_DEPS=("${QT_DEPS_ROOT}/base" "${QT_DEPS_ROOT}/connect")
QT_JAVA_DEPS=("${QT_DEPS_ROOT}/base" "${QT_DEPS_ROOT}/java")
QT_PHP_DEPS=("${QT_DEPS_ROOT}/base" "${QT_DEPS_ROOT}/php")
QT_KEEPALIVED_DEPS=("${QT_DEPS_ROOT}/base" "${QT_DEPS_ROOT}/keepalived")
QT_MYSQL_DEPS=("${QT_DEPS_ROOT}/base" "${QT_DEPS_ROOT}/mysql")
QT_REDIS_DEPS=("${QT_DEPS_ROOT}/base" "${QT_DEPS_ROOT}/redis")
QT_MONGO_DEPS=("${QT_DEPS_ROOT}/base" "${QT_DEPS_ROOT}/mongo")
QT_ES_DEPS=("${QT_DEPS_ROOT}/base" "${QT_DEPS_ROOT}/es")
QT_BIGDATA_DEPS=("${QT_DEPS_ROOT}/base" "${QT_DEPS_ROOT}/bigdata")
QT_HAPROXY_DEPS=("${QT_DEPS_ROOT}/base" "${QT_DEPS_ROOT}/erproxy")
QT_SCAN_DEPS=("${QT_DEPS_ROOT}/base" "${QT_DEPS_ROOT}/scan")
QT_RABBITMQ_DEPS=("${QT_DEPS_ROOT}/base" "${QT_DEPS_ROOT}/rabbitmq")
QT_GLUSTERFS_DEPS=("${QT_DEPS_ROOT}/base" "${QT_DEPS_ROOT}/glusterfs")
QT_ES_PWD="RskWkp0WeliKl"

## Remote
## The remote dir that receive related deps
REMOTE_SERVER_DIR=("/data/qt_base")

##cluster_status


## -----------------------Utils Functions------------------------- ##
help() {
    echo "-------------------------------------------------------------------------------"
    echo "                        Usage information"
    echo "-------------------------------------------------------------------------------"
    echo ""
    echo "./titan-base.sh [<all | erlang | php | java | mysql | redis| mongo>] [upconfig | upconfig-local]"
    echo "Options:"
    echo "  all           set up environments for all server                             "
    echo "  connect     set up environments for connect server                           "
    echo "  rabbitmq      set up environments for rabbitmq server                        "
    echo "  glusterfs      set up environments for glusterfs server                      "
    echo "  php           set up environments for php server                             "
    echo "  es            set up environments for es server                              "
    echo "  bigdata       set up environments for bigdata server                         "
    echo "  erproxy       set up environments for erproxy server                         "
    echo "  docker_scan   set up environments for scan server                            "
    echo "  java          set up environments for java server                            "
    echo "  mysql         set up environments for mysql server(master&slave)             "
    echo "  redis_php     set up environments for redis server                           "
    echo "  redis_java    set up environments for redis server                           "
    echo "  redis_erlang  set up environments for redis server                           "
    echo "  mongo_java    set up environments for mongo server                           "
    echo "  mongo_erlang  set up environments for mongo server                           "
    echo "  pre_check     check ports before installation                                "
    echo "  ping_server   check the connectivity of QT servers                           "
    echo "  stop_python   stop dummy python server                                       "
    echo "  reset_es_pwd                reset es cluster passwd                          "
    echo "  es_cluster_check            check es cluster status                          "
    echo "  after_check                 check ports after installation finished          "
    echo "  titan_manager_server        manager all server                               "
    echo "  update_zookeeper_cluster	set zookeeper_cluster                            "
    echo "  update_kafka_cluster        set kafka_cluster                                "
    echo "  auto_set_nopwd        Automatically set no password                          "
    echo ""
    echo "  One-key install:"
    echo "    ./titan-base.sh all"
    echo "  Install for specific server:"
    echo "    ./titan-base.sh erlang"
    echo "-------------------------------------------------------------------"
    exit 1
}

info_log(){
    echo -e "${COLOR_G}$(date +"%Y-%m-%d %T")[Info] ${1}${RESET}"
}

error_log(){
    echo -e "${COLOR_R}$(date +"%Y-%m-%d %T")[Error] ${1}${RESET}"
    exit 1
}

check(){
    if [ $? -eq 0 ];then
        info_log "$* Successfully"
        info_content Success
    else
        error_log "$* Failed"
        info_content Failed
        exit 1
    fi
}

is_dir_existed(){
    local dirs=$*
    for d in ${dirs}
    do
        if [ ! -d ${d} ]
        then
            error_log "Dir not exists: ${QT_DEPS_ROOT}/${d}"
            exit 1
        fi
    done
}

sq() { # single quote for Bourne shell evaluation
    # Change ' to '\'' and wrap in single quotes.
    # If original starts/ends with a single quote, creates useless
    # (but harmless) '' at beginning/end of result.
    printf '%s\n' "$*" | sed -e "s/'/'\\\\''/g" -e 1s/^/\'/ -e \$s/\$/\'/
}

version_ge(){
    #test "$(echo "$@" | tr " " "\n" | sort -rV | head -n 1)" == "$1";
    version_base=$(echo $1|cut -d "_" -f1|sed 's#\.##g;s#v##g')
    version_install_base=$(echo $2 |cut -d"_" -f1|sed 's#\.##g;s#v##g')
    time_base=$(echo $1|cut -d "_" -f2)
    time_install_base=$(echo $2|cut -d "_" -f2|sed 's#\r##g')
    if [ $(expr $version_base \= $version_install_base) == "1" ];then
        if [ $(expr $time_base \>= $time_install_base) == "1" ];then
                return 1
        else
                return 0
        fi
    elif [ $(expr $version_base \> $version_install_base) == "1" ];then
        return 1
    else
        return 0
    fi
}

check_version(){
    local ip=`get_role_host php`
    VERSION_INSTALLED=`ssh_t ${ip} "[ -f /data/install/base-version.json ] && sudo sed -n 's/.*\"version\":\"\([^\"]*\)\".*/\1/p' /data/install/base-version.json"`
    BASE_VERSION=`sed -n 's/.*"version":"\([^"]*\)".*/\1/p' ${BASE_VERSION_JSON}`
    if [[ -z $VERSION_INSTALLED ]]; then
        info_log "installed base version is less than 330, no base-version.json, continue upgrade"
        return
    else
        version_ge $BASE_VERSION $VERSION_INSTALLED
        if [ $? == "1" ]; then
            info_log "base version:$BASE_VERSION is greater than or equal to $VERSION_INSTALLED,continue upgrade"
        else
            error_log "base version:$BASE_VERSION is less than installed version:$VERSION_INSTALLED"
        fi
    fi
}

ssh_t(){
    # 当用户不是root或者没有加sudo，才使用 sudo -n bash -c 'cmd', 主要处理web安装时 check hostname和path时的多个命令一起执行时的问题
    if [ -x /usr/bin/ssh ] ; then
      if [[ $DEFAULT_USER != "root" && !("$2" =~ .*sudo.*) ]]; then
          sudocmd="sudo -n bash -c $(sq "$2")"
          #echo "$sudocmd"
          ssh -t -p ${DEFAULT_PORT} -oStrictHostKeyChecking=no -o ConnectionAttempts=5 -o ConnectTimeout=3 ${DEFAULT_USER}@$1 "$sudocmd"
      else
          ssh -t -p ${DEFAULT_PORT} -oStrictHostKeyChecking=no -o ConnectionAttempts=5 -o ConnectTimeout=3 ${DEFAULT_USER}@$1 $2
      fi
    else 
      Ssh_Dir=`whereis ssh-keygen|awk '{print $2}'|awk -F 'ssh-keygen' '{print $1}'`
      if [[ $Ssh_Dir != " "  ]]; then      
         \cp -rf $Ssh_Dir/ssh*  /usr/bin/
         chmod +x /usr/bin/ssh*
        if [[ $DEFAULT_USER != "root" && !("$2" =~ .*sudo.*) ]]; then
          sudocmd="sudo -n bash -c $(sq "$2")"
          #echo "$sudocmd"
          ssh -t -p ${DEFAULT_PORT} -oStrictHostKeyChecking=no -o ConnectionAttempts=5 -o ConnectTimeout=3 ${DEFAULT_USER}@$1 "$sudocmd"
        else
          ssh -t -p ${DEFAULT_PORT} -oStrictHostKeyChecking=no -o ConnectionAttempts=5 -o ConnectTimeout=3 ${DEFAULT_USER}@$1 $2
        fi       
      fi 
    fi     
}

ssh_tt(){
    if [ -x /usr/bin/ssh ] ; then
      if [[ $DEFAULT_USER != "root" && !("$2" =~ .*sudo.*)  ]]; then
        sudocmd="sudo -n bash -c $(sq "$2")"
        #echo "$sudocmd"
        ssh -tt -p ${DEFAULT_PORT} -oStrictHostKeyChecking=no -o ConnectionAttempts=5 -o ConnectTimeout=3 ${DEFAULT_USER}@$1 "$sudocmd"
      else
        ssh -tt -p ${DEFAULT_PORT} -oStrictHostKeyChecking=no -o ConnectionAttempts=5 -o ConnectTimeout=3 ${DEFAULT_USER}@$1 $2
      fi
    else 
      Ssh_Dir=`whereis ssh-keygen|awk '{print $2}'|awk -F 'ssh-keygen' '{print $1}'`
      if [[ $Ssh_Dir != " " ]]; then      
         \cp -rf $Ssh_Dir/ssh* /usr/bin/
         chmod +x /usr/bin/ssh* 
        if [[ $DEFAULT_USER != "root" && !("$2" =~ .*sudo.*) ]]; then
          sudocmd="sudo -n bash -c $(sq "$2")"
          #echo "$sudocmd"
          ssh -t -p ${DEFAULT_PORT} -oStrictHostKeyChecking=no -o ConnectionAttempts=5 -o ConnectTimeout=3 ${DEFAULT_USER}@$1 "$sudocmd"
        else
          ssh -t -p ${DEFAULT_PORT} -oStrictHostKeyChecking=no -o ConnectionAttempts=5 -o ConnectTimeout=3 ${DEFAULT_USER}@$1 $2
        fi       
      fi 
    fi
}

set_np_authorized(){
    local ip=$1
    local ip_alias=${ip//\./_}
    if [ "${USE_KEY_LOGIN}" == "true" ]; then
        if  [ ! `grep "${ip_alias}" ${ROOT}/IDENTITY_FILE.txt` ]; then
			read -ep "Pls input the identity_file path for ${ip}: " IDENTITY_FILE_PATH
			if [ -f ${IDENTITY_FILE_PATH} ];then
				sudo chmod 400 ${IDENTITY_FILE_PATH}
				${ROOT}/scripts/setup_np_ssh.sh ${DEFAULT_USER}@${ip} ${DEFAULT_PORT} $IDENTITY_FILE_PATH
				[ $? -eq 0 ] && echo "IDENTITY_FILE_PATH_${ip_alias}=${IDENTITY_FILE_PATH}" >> ${ROOT}/IDENTITY_FILE.txt
			else
				error_log "identity file does not exist! pls upload identity file first."
				exit 1
			fi
		fi
    else
        ${ROOT}/scripts/setup_np_ssh.sh ${DEFAULT_USER}@${ip} ${DEFAULT_PORT}
    fi
}

execute_rsync(){
    local host=$1
    local pkg=$2
    local remote_dir=$3

    rsync -rz --rsync-path="sudo rsync" -e "ssh -p $DEFAULT_PORT"  --delete ${pkg} ${DEFAULT_USER}@${host}:${remote_dir}/
    check "rsync ${pkg} to ${host} "
}

ensure_remote_dir_exists(){
    local host=$1
    local cmd="cd ${REMOTE_SERVER_DIR} 2> /dev/null"
    ssh_t ${host} ${cmd}
    if [ $? -ne 0 ]; then
        info_log "Creating ${REMOTE_SERVER_DIR}!"
        ssh_t ${host} "sudo mkdir -p ${REMOTE_SERVER_DIR}"
        check "${REMOTE_SERVER_DIR} created on ${host}."
    fi
}

clean_yum_complete_transaction(){
    local host=$1
    ssh_t ${host} "! which yum-complete-transaction || yum-complete-transaction --cleanup-only"
    ssh_t ${host} "sudo yum clean all"
}

get_role_host(){
    local role=$1
    if [ ! -f ${SERVER_IP_CONF} ]; then
        error_log "Not found service_ip.conf file."
        exit 1
    fi
    cat ${SERVER_IP_CONF}|grep $role|awk -F" " '{print $2}'|head -1
}
get_role_number(){
    local role=$1
    if [ ! -f ${SERVER_IP_CONF} ]; then
        error_log "Not found service_ip.conf file."
        exit 1
    fi
    cat ${SERVER_IP_CONF}|grep -w $role|awk -F" " '{print $2}'|wc -l
}
## -----------------------Install--------------------------------- ##
install_rpm(){
    local host=$1
    local rpms=$2

    info_log "Install ${rpms}...."

    # comment the next line when offline
    local cmd="sudo yum -y --skip-broken localinstall ${rpms} >> /root/qingteng.log"

    # uncomment the next line when offline
    # local cmd="yum -y --skip-broken --disablerepo=* localinstall ${rpms} >> /root/qingteng.log"

    ssh_t ${host} ${cmd}

    check "Install ${rpms}"
}

execute_remote_shell(){
    local host=$1
    local name=$2
    local args=$2

    case ${name} in
        es|es_master|es_data)
            args=es
            if [ ${name} == "es_master" ];then
                args="${args} ${host} master"
            elif [ ${name} == "es_data" ];then
                args="${args} ${host} data"
            fi
            name=es
            ;;
        bigdata|logstash|viewer)
            name=bigdata
            args="${args} ${host}"
            ;;
        scan)
            name=scan
            ;;
        connect)
            name=connect
            ;;
        rabbitmq)
			if [ `get_role_number ${name}` == "1" ];then
				name=rabbitmq
			else
				rabbitmq_master_ip=`cat ${SERVER_IP_CONF} | grep -w "rabbitmq" | awk -F " " '{print $2}'|sed -n "1p"`
				if [ "${host}" == "${rabbitmq_master_ip}" ];then
					rabbit_master_status="master"
				else
					rabbit_master_status="nodes"
				fi
				rabbitmq_status="cluster"
				name=rabbitmq
				args="${args} ${rabbitmq_status} ${rabbitmq_master_ip} ${rabbit_master_status}"
			fi
            ;;
        erproxy)
            name=erproxy
            local java_ip=`get_role_host java`
            args="${java_ip}"
            ;;
        redis_erlang|redis_php|redis_java)
			if [ `get_role_number ${name}` == "1" ];then
				name=redis
			else
				name=redis_cluster5
			fi
            ;;
        mongo_erlang|mongo_java|mongo_ms_srv|enable_auth)
            if [ "${mongo_bigcache}" == "enable" -a "${name}" == "mongo_java" ];then
                args="${args} ${mongo_bigcache}"
            fi
            name=mongo
            ;;
        mysql|mysql_erlang|mysql_php|mysql_master|mysql_slave)
			if [ `get_role_number ${name}` == "1" ];then
				name=mysql
			else
                local mysql_conect="`cat ${SERVER_IP_CONF} | grep -w "mysql" | awk -F " " '{print $2}'| xargs | sed "s/"\ "/\,/g"`"
				local mysql_master_ip=`cat ${SERVER_IP_CONF} | grep -w "${role}" | awk -F " " '{print $2}'|sed -n "1p"`
				if [ ${host} == ${mysql_master_ip} ];then
					mysql_master_status="master"
				else
					mysql_master_status="nodes"
				fi
				name=mysql_cluster
				args="${args} ${host} ${mysql_conect} ${mysql_master_status}"

			fi
            ;;
        php)
            if [ "$name" == "php" ];then
                local java_ip=`get_role_host java`
                args="${java_ip}"
            fi
            ;;
        keepalived)
            name=keepalived
            local vip=`get_role_host vip`
            args="${host} ${vip}"
            ;;
        glusterfs)
            name=glusterfs
            args="${host}"
            ;;
        java)
            # pass zookeeper'ip to kafka
            args="${args}"
            ;;
        zookeeper)
            name=java
            args="${args} ${host}"
            ;;
        kafka)
            name=java
            args="${args} ${host}"
            ;;
        event_srv|ms_srv)
            name=java
            args="${args}"
            ;;
        *)
            exit 1
            ;;
    esac

    info_log "======== Execute shell on remote server $host($2) ========"
    if [ "$UPCONFIG" == "true" ];then
        ssh_t ${host} "[ ! -f ${REMOTE_SERVER_DIR}/${name}/install_${name}.sh ] \
        || sudo bash ${REMOTE_SERVER_DIR}/${name}/install_${name}.sh upconfig ${args}"
        check "upconfig ${name}"
        check "execute shell on $host($2)"
    elif [ "$UPLOCALCONFIG" == "true" ];then
        if [[ $name == mysql* ]] || [[ $name == redis* ]] || [[ $name == mongo* ]] || [[ $name == java ]];then
            ssh_t ${host} "[ ! -f ${REMOTE_SERVER_DIR}/${name}/install_${name}.sh ] \
            || sudo bash ${REMOTE_SERVER_DIR}/${name}/install_${name}.sh upconfig-local ${args}"
            check "upconfig-local ${name}"
            check "execute shell on $host($2)"
        fi
    elif [ $name == "redis_cluster5" ];then
        ssh_t ${host} "[ ! -f ${REMOTE_SERVER_DIR}/redis/install_${name}.sh ] \
        || sudo bash ${REMOTE_SERVER_DIR}/redis/install_${name}.sh ${args}"
        check "Install ${name}"
        check "execute shell on $host($2)"
    elif [ $name == "mysql_cluster" ];then
	    ssh_t ${host} "[ ! -f ${REMOTE_SERVER_DIR}/mysql/install_${name}.sh ] \
        || sudo bash ${REMOTE_SERVER_DIR}/mysql/install_${name}.sh ${args}"
        check "Install ${name}"
        check "execute shell on $host($2)"
    else
	ssh_t ${host} "[ ! -f ${REMOTE_SERVER_DIR}/${name}/install_${name}.sh ] \
        || sudo bash ${REMOTE_SERVER_DIR}/${name}/install_${name}.sh ${args}"
        check "Install ${name}"
        check "execute shell on $host($2)"
    fi

}

install_rabbitmq(){
    local host=$1
    clean_yum_complete_transaction ${host}

    execute_remote_shell ${host} rabbitmq
}

install_glusterfs(){
    local host=$1
    clean_yum_complete_transaction ${host}

    execute_remote_shell ${host} glusterfs
}
install_connect(){
    local host=$1
    clean_yum_complete_transaction ${host}

    execute_remote_shell ${host} connect
}


install_es(){
    local host=$1
    local name=$2
    clean_yum_complete_transaction ${host}

    execute_remote_shell ${host} ${name}
}

install_bigdata(){
    local host=$1
    local name=$2
    clean_yum_complete_transaction ${host}

    execute_remote_shell ${host} ${name}
}


install_erproxy(){
    local host=$1
    clean_yum_complete_transaction ${host}

    execute_remote_shell ${host} erproxy
}

install_scan(){
    local host=$1
    clean_yum_complete_transaction ${host}

    execute_remote_shell ${host} scan
}

install_php(){
    local host=$1
    clean_yum_complete_transaction ${host}
    #create_install_json ${host}
    execute_remote_shell ${host} php
}

install_keepalived(){
    local host=$1
    clean_yum_complete_transaction ${host}
    #create_install_json ${host}
    execute_remote_shell ${host} keepalived
}


webinstall_php(){
    local host=$1
    clean_yum_complete_transaction ${host}
    execute_remote_shell ${host} php
}
install_java(){
    local host=$1
    clean_yum_complete_transaction ${host}


    execute_remote_shell ${host} java
}

install_event(){
    local host=$1
    clean_yum_complete_transaction ${host}


    execute_remote_shell ${host} event_srv
}

install_ms(){
    local host=$1
    clean_yum_complete_transaction ${host}


    execute_remote_shell ${host} ms_srv
}

install_mysql(){
    local host=$1
    local role=$2 # mysql | mysql_php | mysql_erlang
    clean_yum_complete_transaction ${host}


    execute_remote_shell ${host} ${role}
}

install_redis(){
    local host=$1
    local role=$2 # redis_erlang | redis_php | redis_java
    clean_yum_complete_transaction ${host}

    execute_remote_shell ${host} ${role}
}

install_mongo(){
    local host=$1
    local role=$2 # mongo_erlang | mongo_java | mongo_ms_srv
    clean_yum_complete_transaction ${host}
    # Determine if it is a single mongo with a multi-node deployment
    if [ ${role} == "mongo_java" -a `grep ${host} service_ip.conf |wc -l` -eq 1 -a `grep ${role} service_ip.conf | wc -l ` -eq 1 ];then
        mongo_bigcache="enable"
    fi
    execute_remote_shell ${host} ${role}
}

install_zookeeper(){
	local host=$1
    clean_yum_complete_transaction ${host}
	execute_remote_shell ${host} zookeeper
	# ssh_t ${host} "sudo yum -y install qingteng-zookeeper; \
	# sudo yum -y update qingteng-zookeeper; \
	# if[ -f /etc/init.d/zookeeperd ];then sudo chmod +x /etc/init.d/zookeeperd;sudo chkconfig --add zookeeperd;sudo chkconfig --add zookeeperd;sudo chkconfig zookeeperd on;fi;"
}

install_kafka(){
    local host=$1
    clean_yum_complete_transaction ${host}
	execute_remote_shell ${host} kafka
}

install_by_role(){
    local name=$1
    local ip=$2

    if [[ -z ${ip} || ${ip} = "127.0.0.1" ]]; then
        error_log "Invalid IP ${ip} for ${name} server"
        return
    fi

    case ${name} in
        rabbitmq)
            install_rabbitmq ${ip}
            ;;
        glusterfs)
            install_glusterfs ${ip}
            ;;
        connect)
            install_connect ${ip}
            ;;
        es|es_master|es_data)
            install_es ${ip} ${name}
            ;;
        bigdata|logstash|viewer)
            install_bigdata ${ip} ${name}
            ;;
        erproxy)
            install_erproxy ${ip}
            ;;
        docker_scan)
            install_scan ${ip}
            ;;
        php)
            install_php ${ip}
            sleep 60
            ;;
        keepalived)
            install_keepalived ${ip}
            sleep 10
            ;;
        java)
            install_java ${ip}
            ;;
        mysql|mysql_php|mysql_erlang|mysql_master|mysql_slave)
            install_mysql ${ip} ${name}
            ;;
        redis_java|redis_erlang|redis_php)
            install_redis ${ip} ${name}
            ;;
        mongo_java|mongo_erlang|mongo_ms_srv)
            install_mongo ${ip} ${name}
            ;;
        zookeeper|kafka)
			if [ ${name} == "zookeeper" ];then
            info_log "开始安装 zookeeper install"
				install_zookeeper ${ip}
			elif [ ${name} == "kafka" ];then
				info_log "开始安装 kafka install"
				install_kafka ${ip}
			fi
            ;;
        ms_srv|event_srv)
            if [ ${name} == "ms_srv" ];then
                info_log "开始安装ms_srv"
                install_ms ${ip}
            elif [ ${name} == "event_srv" ];then
                info_log "开始安装event_srv"
                install_event ${ip}
            fi
            ;;
		vip)
            info_log "vip:$ip"
            ;;
          *)
            help
            ;;
    esac

}

set_zookeeper_cluster(){
	local zookeeper_conect=`cat ${SERVER_IP_CONF} | grep -w "zookeeper" | awk -F" " '{print $2}'`
	local n=1
	for line in $zookeeper_conect;do
        local m=1
		for line2 in $zookeeper_conect;do
		ssh_t ${line} "echo "server.${m}=${line2}:2888:3888"|sudo tee -a /usr/local/qingteng/zookeeper/conf/zoo.cfg"
		let "m=$m+1"
		done
		ssh_t $line "\
		if [ ! -f /data/zk-data/myid ];then echo "${n}"|sudo tee -a /data/zk-data/myid;sudo chown zookeeper:zookeeper /data/zk-data/myid;fi; \
		sudo /etc/init.d/zookeeperd restart; \
		sudo chkconfig zookeeperd on; \
		sudo /etc/init.d/zookeeperd status  "
#		check "set_zookeeper_cluster"
		let "n=$n+1"
	done
}

set_kafka_cluster(){
    local zookeeper_conect="`cat ${SERVER_IP_CONF} | grep -w "zookeeper" | awk -F " " '{print $2}'| xargs | sed "s/"\ "/\:2181,/g"`:2181"
    local kafka_connect_num=`cat ${SERVER_IP_CONF} | grep -w "kafka" | awk -F" " '{print $2}'|wc -l`

    one_zk_server=$(cat ${SERVER_IP_CONF} | grep -w "zookeeper" | awk -F " " '{print $2}'| sed -n "1p")
    kafka_cluster_id=$(ssh_t $one_zk_server "sudo /usr/local/qingteng/zookeeper/bin/zkCli.sh get /cluster/id" | grep '\"version\":\"')
    [ ${kafka_cluster_id} ] && $(ssh_t $one_zk_server "sudo /usr/local/qingteng/zookeeper/bin/zkCli.sh set /cluster/id '${kafka_cluster_id}'")

    for num in `seq 0 \`expr $kafka_connect_num - 1\``;do
		let "kafka_cluster_num=$num+1"
		local host=`cat ${SERVER_IP_CONF} | grep -w "kafka" | awk -F " " '{print $2}'| sed -n "${kafka_cluster_num}p"`
		ssh_t $host "sudo sed -i "s#broker.id=.*#broker.id=${num}#g" /usr/local/qingteng/kafka/config/server.properties; \
		sudo sed -i "s#offsets.topic.replication.factor=.*#offsets.topic.replication.factor=3#g" /usr/local/qingteng/kafka/config/server.properties; \
		sudo sed -i "s#default.replication.factor=.*#default.replication.factor=3#g" /usr/local/qingteng/kafka/config/server.properties; \
		sudo sed -i "s#zookeeper.connect=.*#zookeeper.connect=${zookeeper_conect}#g" /usr/local/qingteng/kafka/config/server.properties; \
		echo "host.name=\`hostname\`"|sudo tee -a /usr/local/qingteng/kafka/config/server.properties; \
                sudo sed -i "s#broker.id=.*#broker.id=${num}#g" /data/kafka-data/meta.properties; \
        sudo sed -i '/^cluster.id.*/d' /data/kafka-data/meta.properties; \
		sudo service kafkad stop; \
		sleep 20; \
		sudo service kafkad start;"
		check "set_kafka_cluster"
	done
}

set_redis_cluster(){
	local role=$1
	case $role in
		redis_erlang)
			port1=6379
			port2=6479
			port3=6579
			master_number=1
			create_redis_cluster $role $master_number $port1 $port2 $port3
			;;
		redis_php)
			port1=6380
			port2=6480
			port3=6580
			master_number=2
			create_redis_cluster $role $master_number $port1 $port2 $port3
			;;
		redis_java)
			port1=6381
			port2=6481
			port3=6581
			master_number=3
			create_redis_cluster $role $master_number $port1 $port2 $port3
			;;
		*)
			error_log "Error,Not ${role} exists "
			;;
	esac
	info_log "install redis_cluster ok"
}

create_redis_cluster(){
    role=$1
	local master_redis_ip=`cat ${SERVER_IP_CONF} | grep -w "${role}" | awk -F " " '{print $2}'|sed -n "$2p"`
	local slave_redis_ip1=`cat ${SERVER_IP_CONF} | grep -w "${role}" | awk -F " " '{print $2}'|sed -n "1p"`
	local slave_redis_ip2=`cat ${SERVER_IP_CONF} | grep -w "${role}" | awk -F " " '{print $2}'|sed -n "2p"`
	local slave_redis_ip3=`cat ${SERVER_IP_CONF} | grep -w "${role}" | awk -F " " '{print $2}'|sed -n "3p"`
	local redis_cluster_status=`ssh_t ${master_redis_ip} "echo CLUSTER nodes  | /usr/local/qingteng/redis/bin/redis-cli -c -p $3 | cut -d ' ' -f 1"`
	if [ `echo ${redis_cluster_status}|sed 's/\r//g'` != "NOAUTH" ];then
        ssh_t ${master_redis_ip} "sudo /usr/local/qingteng/redis/bin/redis-cli --cluster create \
	${slave_redis_ip1}:$3 ${slave_redis_ip2}:$3 ${slave_redis_ip3}:$3 \
	${slave_redis_ip1}:$4 ${slave_redis_ip2}:$4 ${slave_redis_ip3}:$4 \
	${slave_redis_ip1}:$5 ${slave_redis_ip2}:$5 ${slave_redis_ip3}:$5 --cluster-replicas 2"
	check "create_redis_cluster"
	##设置授权
		for i in $slave_redis_ip1 $slave_redis_ip2 $slave_redis_ip3;do
			ssh_t $i "sudo chown  -R redis:redis /etc/redis/; \
		for node_port in $3 $4 $5 ;do echo \"config set masterauth  9pbsoq6hoNhhTzl\"  | /usr/local/qingteng/redis/bin/redis-cli -c -p \${node_port} && echo \"config set requirepass  9pbsoq6hoNhhTzl\" | /usr/local/qingteng/redis/bin/redis-cli -c -p \${node_port} && echo \"config rewrite\" |/usr/local/qingteng/redis/bin/redis-cli -c -p \${node_port} -a 9pbsoq6hoNhhTzl  ;done; \
		sudo chown  -R root:root /etc/redis/"
		done
	fi
	check "redis_cluster auth "
}

set_mysql_cluster(){
##初始化集群
	local role="mysql"
	local slave_mysql_ip1=`cat ${SERVER_IP_CONF} | grep -w "${role}" | awk -F " " '{print $2}'|sed -n "1p"`
		ssh_t ${slave_mysql_ip1} '/usr/bin/mysql -uroot -p9pbsoq6hoNhhTzl -e "flush privileges"'
		ssh_t ${slave_mysql_ip1} '/usr/bin/mysql -uroot -p9pbsoq6hoNhhTzl -e "grant all privileges on "*.*" to \"root\"@\"%\" identified by \"9pbsoq6hoNhhTzl\" with grant option"'
		ssh_t ${slave_mysql_ip1} '/usr/bin/mysql -uroot -p9pbsoq6hoNhhTzl -e "grant all privileges on "*.*" to \"root\"@\"localhost\" identified by \"9pbsoq6hoNhhTzl\" with grant option"'
		ssh_t ${slave_mysql_ip1} '/usr/bin/mysql -uroot -p9pbsoq6hoNhhTzl -e "grant all privileges on "*.*" to \"root\"@\"127.0.0.1\" identified by \"9pbsoq6hoNhhTzl\" with grant option"'
		ssh_t ${slave_mysql_ip1} '/usr/bin/mysql -uroot -p9pbsoq6hoNhhTzl -e "flush privileges"'
		ssh_t ${slave_mysql_ip1} '/usr/bin/mysql -uroot -p9pbsoq6hoNhhTzl -e "create database base"'
		ssh_t ${slave_mysql_ip1} '/usr/bin/mysql -uroot -p9pbsoq6hoNhhTzl -e "create database core"'
}

set_rabbit_cluster(){
	local rabbit_connect=`cat ${SERVER_IP_CONF} | grep -w "rabbitmq" | awk -F " " '{print $2}'`
	local rabbit_master=`cat ${SERVER_IP_CONF} | grep -w "rabbitmq" | awk -F " " '{print $2}'|sed -n "1p"`
	local hostname_master=`ssh_t ${rabbit_master} "hostname -s"`
	local m=1
	for i in ${rabbit_connect}
	do
		#写入hostsname
		hostname=`ssh_t $i "hostname -s"`
		for l in ${rabbit_connect}
		do
			ssh_t $l "echo \"$i `echo $hostname |sed 's/\r//g'` \" | sudo tee -a /etc/hosts "
		done
		if [ $m == '1' ];then
            ssh_t $i "if [ -f /data/app/titan-rabbitmq/.erlang.cookie ];then sudo rm -rf /root/.erlang.cookie;fi;sudo service rabbitmq-server restart"
            rsync -rz --rsync-path="sudo rsync" -e "ssh -p ${DEFAULT_PORT}"  --delete ${DEFAULT_USER}@${i}:/data/app/titan-rabbitmq/.erlang.cookie /tmp/.erlang.cookie
			check "rsync rabbitmq_master .erlang.cookie "
			ssh_t $i "sudo /etc/init.d/rabbitmq-server stop"
			rsync -rz --rsync-path="sudo rsync" -e "ssh -p ${DEFAULT_PORT}"  --delete /tmp/.erlang.cookie ${DEFAULT_USER}@${i}:/data/app/titan-rabbitmq/.erlang.cookie
			ssh_t $i "sudo chown rabbitmq:rabbitmq /data/app/titan-rabbitmq/.erlang.cookie"
			rsync -rz --rsync-path="sudo rsync" -e "ssh -p ${DEFAULT_PORT}"  --delete /tmp/.erlang.cookie ${DEFAULT_USER}@${i}:/root/.erlang.cookie
			ssh_t $i "if [ ! -d /data/servers/rabbitmq_root/etc ];then sudo chown rabbitmq:rabbitmq /data/servers; sudo chmod 755 /data/servers; sudo service rabbitmq-server restart ;fi;\
			sudo cp /data/qt_base/rabbitmq/config/rabbitmq.config /data/servers/rabbitmq_root/etc/rabbitmq/;\
			sudo chown rabbitmq:rabbitmq /data/servers/rabbitmq_root/etc/rabbitmq/rabbitmq.config;\
			sudo chmod 755 /data/servers/rabbitmq_root/etc/rabbitmq/rabbitmq.config"
			ssh_t $i "sudo service rabbitmq-server start;sleep 10;"
		else
			ssh_t $i "if [ ! -d /data/servers/rabbitmq_root/etc ];then sudo service rabbitmq-server restart ;sudo service rabbitmq-server stop ;fi"
			rsync -rz --rsync-path="sudo rsync" -e "ssh -p ${DEFAULT_PORT}"  --delete /tmp/.erlang.cookie ${DEFAULT_USER}@${i}:/data/app/titan-rabbitmq/.erlang.cookie
			rsync -rz --rsync-path="sudo rsync" -e "ssh -p ${DEFAULT_PORT}"  --delete /tmp/.erlang.cookie ${DEFAULT_USER}@${i}:/root/.erlang.cookie
			ssh_t $i " \
			sudo chown rabbitmq:rabbitmq /data/app/titan-rabbitmq/.erlang.cookie; \
			sudo cp /data/qt_base/rabbitmq/config/rabbitmq.config /data/servers/rabbitmq_root/etc/rabbitmq/; \
			sudo chown -R rabbitmq:rabbitmq /data/servers; \
            sudo chmod 755 /data/servers/rabbitmq_root/etc/rabbitmq/rabbitmq.config; \
			sudo service  rabbitmq-server start;sleep 20; \
			if [ \"\`sudo /etc/init.d/rabbitmq-server status|grep Error|wc -l\`\" != 0 ];then ps -ef | grep rabbitmq | grep -v grep | awk '{print \$2}' | xargs  sudo kill -9  ;sudo service rabbitmq-server start;sleep 10;fi; \
			sudo /data/app/titan-rabbitmq/bin/rabbitmqctl  stop_app;sleep 3; \
			sudo /data/app/titan-rabbitmq/bin/rabbitmqctl  join_cluster rabbit@`echo ${hostname_master}|sed 's/\r//g'`; sleep 3;\
			sudo /data/app/titan-rabbitmq/bin/rabbitmqctl  start_app;"
		fi
		let "m=$m+1"
	done
	ssh_t $rabbit_master "sudo /data/app/titan-rabbitmq/bin/rabbitmqctl set_policy ha-all "^" \"{\\\"ha-mode\\\":\\\"all\\\"}\" ;\
	sudo /data/app/titan-rabbitmq/bin/rabbitmqctl  cluster_status"

}

set_keepalived_cluster(){
	local ips=$(cat ${SERVER_IP_CONF}|grep -w keepalived |awk '{print $2}')
	local virtual_router_id=$[$[$RANDOM%$[254-1]]+1]
	local conf_dir="/etc/keepalived/keepalived.conf"

	for ip in $ips;do
		ssh_t $ip "sudo sed -i \"s#virtual_router_id.*#virtual_router_id $virtual_router_id#g\" ${conf_dir}&& sudo service keepalived restart"
	done

}
install_mongodb_cluster(){
    local roles=$1
    #if 3 node ha-cluster mongodb only use Replica Set.
    if [ "`cat service_ip.conf | egrep -v "vip|ms_srv|event_srv|es|es_master|es_data|bigdata|logstash|viewer|^$" | awk -F" " '{print $2}'| sort  | uniq |wc -l`" == "3" -a "`cat service_ip.conf | grep "vip" |wc -l`" == "1" -a $roles == "mongo_java" ]; then
        if [ "`cat ${SERVER_IP_CONF}|grep $roles |wc -l`" == "3" ];then
            local mongodb_node01=`cat ${SERVER_IP_CONF}|grep $roles|awk -F" " '{print $2}' | head -1`
            local mongodb_node02=`cat ${SERVER_IP_CONF}|grep $roles|awk -F" " '{print $2}' | sed -n "2p"`
            local mongodb_node03=`cat ${SERVER_IP_CONF}|grep $roles|awk -F" " '{print $2}' | sed -n "3p"`
            for mongodb_ips in `cat ${SERVER_IP_CONF}|grep $roles|awk -F" " '{print $2}'`
            do
                ssh_t ${mongodb_ips} "sudo yum -y install qingteng-mongocluster && \
                sudo /etc/init.d/mongod_cs start && \
                sudo /etc/init.d/mongod_27019 start "
                ssh_t ${mongodb_ips} "sudo cp -rfp /data/qt_base/mongo/scripts/*.sh /usr/local/qingteng/mongocluster/bin/"
            done

            #modifid the node ip.
            ssh_t $mongodb_node01 "sudo sed -i "s#host1=.*#host1=${mongodb_node01}#g" /usr/local/qingteng/mongocluster/bin/init_one_shard.sh && \
                                    sudo sed -i "s#host2=.*#host2=${mongodb_node02}#g" /usr/local/qingteng/mongocluster/bin/init_one_shard.sh && \
                                    sudo sed -i "s#host3=.*#host3=${mongodb_node03}#g" /usr/local/qingteng/mongocluster/bin/init_one_shard.sh && \
                                    sudo bash /usr/local/qingteng/mongocluster/bin/init_one_shard.sh"

            #enable auth and start mongo_cs first
            for mongodb_ips in `cat ${SERVER_IP_CONF}|grep $roles|awk -F" " '{print $2}'`
            do
                ssh_t ${mongodb_ips} "sudo /etc/init.d/mongocluster stop && \
                sudo /etc/init.d/mongocluster enable_auth && \
                sudo /etc/init.d/mongod_cs start"
            done
            #enable auth and start all service
            for mongodb_ips in `cat ${SERVER_IP_CONF}|grep $roles|awk -F" " '{print $2}'`
            do

                ssh_t ${mongodb_ips} "sudo /etc/init.d/mongod_27019 restart && \
                sudo sed -i \"s#\(configdb.*=\).*#\1\ cs/${mongodb_node01}:27018,${mongodb_node02}:27018,${mongodb_node03}:27018#\" /usr/local/qingteng/mongocluster/etc/mongos.conf && \
                sudo /etc/init.d/mongos start"
            done
        fi
    else
        if [ "`cat ${SERVER_IP_CONF}|grep $roles |wc -l`" == "3" ];then
            local mongodb_node01=`cat ${SERVER_IP_CONF}|grep $roles|awk -F" " '{print $2}' | head -1`
            local mongodb_node02=`cat ${SERVER_IP_CONF}|grep $roles|awk -F" " '{print $2}' | sed -n "2p"`
            local mongodb_node03=`cat ${SERVER_IP_CONF}|grep $roles|awk -F" " '{print $2}' | sed -n "3p"`
            for mongodb_ips in `cat ${SERVER_IP_CONF}|grep $roles|awk -F" " '{print $2}'`
            do
                ssh_t ${mongodb_ips} "sudo yum -y install qingteng-mongocluster && sudo /etc/init.d/mongocluster start"
                ssh_t ${mongodb_ips} "sudo cp -rfp /data/qt_base/mongo/scripts/*.sh /usr/local/qingteng/mongocluster/bin/"
                #set ms_mongo cachesize 4g
                if [ $roles == "mongo_ms_srv" ];then
                    ssh_t ${mongodb_ips} "\
                        sudo sed -i 's#cacheSizeGB:.*#cacheSizeGB: 4#g' /usr/local/qingteng/mongocluster/etc/mongod_27019.conf && \
                        sudo sed -i 's#cacheSizeGB:.*#cacheSizeGB: 4#g' /usr/local/qingteng/mongocluster/etc/mongod_27020.conf && \
                        sudo sed -i 's#cacheSizeGB:.*#cacheSizeGB: 4#g' /usr/local/qingteng/mongocluster/etc/mongod_27021.conf"
                fi
            done

            #set ms_mongo cachesize 4g
            #modifid the node ip.
            ssh_t $mongodb_node01 "sudo sed -i "s#host1=.*#host1=${mongodb_node01}#g" /usr/local/qingteng/mongocluster/bin/initialize.sh && \
                                sudo sed -i "s#host2=.*#host2=${mongodb_node02}#g" /usr/local/qingteng/mongocluster/bin/initialize.sh && \
                                sudo sed -i "s#host3=.*#host3=${mongodb_node03}#g" /usr/local/qingteng/mongocluster/bin/initialize.sh && \
                                sudo bash /usr/local/qingteng/mongocluster/bin/initialize.sh ${roles}"
            #add qingteng user
            #ssh_t $mongodb_node02 "sudo mongo --port 27020 admin --eval "db.createUser\(\{user:\"qingteng\",pwd:\"9pbsoq6hoNhhTzl\",roles:[\"root\"]\}\)""
            #ssh_t $mongodb_node03 "sudo mongo --port 27021 admin --eval "db.createUser\(\{user:\"qingteng\",pwd:\"9pbsoq6hoNhhTzl\",roles:[\"root\"]\}\)""

            #enable auth and start mongo_cs first
            for mongodb_ips in `cat ${SERVER_IP_CONF}|grep $roles|awk -F" " '{print $2}'`
            do
            ssh_t ${mongodb_ips} "sudo /etc/init.d/mongocluster stop && \
            sudo /etc/init.d/mongocluster enable_auth && \
            sudo /etc/init.d/mongod_cs start"
            done
            #enable auth and start all service
            for mongodb_ips in `cat ${SERVER_IP_CONF}|grep $roles|awk -F" " '{print $2}'`
            do

            ssh_t ${mongodb_ips} "sudo /etc/init.d/mongocluster restart && \
            sudo sed -i \"s#\(configdb.*=\).*#\1\ cs/${mongodb_node01}:27018,${mongodb_node02}:27018,${mongodb_node03}:27018#\" /usr/local/qingteng/mongocluster/etc/mongos.conf && \
            sudo /etc/init.d/mongos start"
            done
        else
            mongodb_cluster_ips=($(cat ${SERVER_IP_CONF}|grep $roles|awk '{print $2}'))
            sharding_port_init=27019
            arbiter_port_init=37019
            sharding_nums=$((${#mongodb_cluster_ips[@]}/2))
            max_arbiter_port=$(($arbiter_port_init+$((sharding_nums-1))))

            #arbiter_shard_names
            for ((i=0;i<${sharding_nums};i++))
            do
            if [ $i == 0 ];then
                arbiter_shard_names[$i]=shard${sharding_nums}
            else
                arbiter_shard_names[$i]=shard${i}
            fi
            done
            #sharding_ports
            for ((i=0,sharding_port=${sharding_port_init};i<${sharding_nums};i++,sharding_port++))
            do
            sharding_ports[$i]=$sharding_port
            done
            echo "sharding ports: ${sharding_ports[@]}"
            #arbiter_ports
            for ((i=0,arbiter_port=${arbiter_port_init};i<${sharding_nums};i++))
            do
            if [ $i == 0 ];then
                arbiter_ports[$i]=$(($arbiter_port+$((sharding_nums-1))))
            else
                arbiter_ports[$i]=$arbiter_port
                let arbiter_port+=1
            fi
            done
            echo "arbiter ports: ${arbiter_ports[@]}"
            #install mongocluster rpm in mongodb nodes

            for ((i=0;i<${#mongodb_cluster_ips[@]};i++))
            do
                ssh_t ${mongodb_cluster_ips[$i]} "sudo yum -y install qingteng-mongocluster"
                ssh_t ${mongodb_ips} "sudo cp -rfp /data/qt_base/mongo/scripts/*.sh /usr/local/qingteng/mongocluster/bin/"
                if [ $roles == "mongo_ms_srv" ];then
                    ssh_t ${mongodb_cluster_ips[$i]} "\
                        sudo sed -i 's#cacheSizeGB:.*#cacheSizeGB: 4#g' /usr/local/qingteng/mongocluster/etc/mongod_27019.conf && \
                        sudo sed -i 's#cacheSizeGB:.*#cacheSizeGB: 4#g' /usr/local/qingteng/mongocluster/etc/mongod_27020.conf && \
                        sudo sed -i 's#cacheSizeGB:.*#cacheSizeGB: 4#g' /usr/local/qingteng/mongocluster/etc/mongod_27021.conf"
                fi
                if [ $i -lt 3 ];then
                    ssh_t ${mongodb_cluster_ips[$i]} "sudo service mongod_cs restart"
                fi
            done

            # start sharding master nodes
            for ((i=0,x=0,y=1;i<${#mongodb_cluster_ips[@]};i=i+2,x++,y++))
            do
            ssh_t ${mongodb_cluster_ips[$i]} "\
            if [ ! -f /etc/init.d/mongod_${sharding_ports[${x}]} ];then \
                sudo cp -rfp /etc/init.d/mongod_27019 /etc/init.d/mongod_${sharding_ports[${x}]} && \
                sudo sed -i "s#27019#${sharding_ports[${x}]}#g" /etc/init.d/mongod_${sharding_ports[${x}]} && \
                sudo cp -rfp /usr/local/qingteng/mongocluster/etc/mongod_27019.conf /usr/local/qingteng/mongocluster/etc/mongod_${sharding_ports[${x}]}.conf && \
                sudo sed -i "s#27019#${sharding_ports[${x}]}#g" /usr/local/qingteng/mongocluster/etc/mongod_${sharding_ports[${x}]}.conf && \
                sudo sed -i "s#shard1#shard${y}#g" /usr/local/qingteng/mongocluster/etc/mongod_${sharding_ports[${x}]}.conf && \
                sudo mkdir -p /data/mongocluster/shard${y} && \
                sudo chown mongodb:mongodb -R /data/mongocluster; \
            fi; \
            service mongod_${sharding_ports[${x}]} start"
            done
            #start sharding secendary and arbiter
            for ((i=1,x=0,y=1;i<${#mongodb_cluster_ips[@]};i=i+2,x++,y++))
            do
            ssh_t ${mongodb_cluster_ips[$i]} "\
            if [ ! -f /etc/init.d/mongod_${sharding_ports[${x}]} ];then \
                sudo cp -rfp /etc/init.d/mongod_27019 /etc/init.d/mongod_${sharding_ports[${x}]} && \
                sudo sed -i "s#27019#${sharding_ports[${x}]}#g" /etc/init.d/mongod_${sharding_ports[${x}]} && \
                sudo cp -rf /usr/local/qingteng/mongocluster/etc/mongod_27019.conf  /usr/local/qingteng/mongocluster/etc/mongod_${sharding_ports[${x}]}.conf && \
                sudo sed -i "s#27019#${sharding_ports[${x}]}#g" /usr/local/qingteng/mongocluster/etc/mongod_${sharding_ports[${x}]}.conf && \
                sudo sed -i "s#shard1#shard${y}#g" /usr/local/qingteng/mongocluster/etc/mongod_${sharding_ports[${x}]}.conf && \
                sudo mkdir -p /data/mongocluster/shard${y} && \
                sudo chown mongodb:mongodb -R /data/mongocluster; \
            fi; \
            if [ ! -f /etc/init.d/mongod_${arbiter_ports[${x}]} ];then \
                sudo cp -rf /etc/init.d/mongod_27019 /etc/init.d/mongod_${arbiter_ports[${x}]} && \
                sudo sed -i "s#27019#${arbiter_ports[${x}]}#g" /etc/init.d/mongod_${arbiter_ports[${x}]} && \
                sudo cp -rf /usr/local/qingteng/mongocluster/etc/mongod_27019.conf  /usr/local/qingteng/mongocluster/etc/mongod_${arbiter_ports[${x}]}.conf && \
                sudo sed -i "s#27019#${arbiter_ports[${x}]}#g" /usr/local/qingteng/mongocluster/etc/mongod_${arbiter_ports[${x}]}.conf && \
                sudo sed -i "s#shard1#${arbiter_shard_names[${x}]}#g" /usr/local/qingteng/mongocluster/etc/mongod_${arbiter_ports[${x}]}.conf && \
                sudo sed -i "s#shard1#${arbiter_shard_names[${x}]}#g" /usr/local/qingteng/mongocluster/etc/mongod_${arbiter_ports[${x}]}.conf && \
                sudo sed -i \"s#dbPath:.*#dbPath:\ /data/mongocluster/arbiter/${arbiter_shard_names[${x}]}#g\" /usr/local/qingteng/mongocluster/etc/mongod_${arbiter_ports[${x}]}.conf && \
                sudo mkdir -p /data/mongocluster/arbiter/${arbiter_shard_names[${x}]} && \
                sudo chown mongodb:mongodb -R /data/mongocluster; \
            fi; \
            sudo service mongod_${sharding_ports[${x}]} start && sudo service mongod_${arbiter_ports[${x}]} start"
            done

            #exec initialize.sh on first node.

            ssh -t -p ${DEFAULT_PORT} -oStrictHostKeyChecking=no -o ConnectionAttempts=5 ${DEFAULT_USER}@${mongodb_cluster_ips[0]} "\
            sudo bash /usr/local/qingteng/mongocluster/bin/init_mongocluster.sh \"${mongodb_cluster_ips[@]}\" ${roles}"

            #stop all service ,enable auth and start mongo_cs first

            for ((i=0;i<${#mongodb_cluster_ips[@]};i++))
            do
            ssh_t ${mongodb_cluster_ips[$i]} "for z in /etc/init.d/mongod_*; do sudo \$z stop ;done && \
            sudo /etc/init.d/mongocluster enable_auth"
            if [ $i -lt 3 ];then
                ssh_t ${mongodb_cluster_ips[$i]} "sudo service mongod_cs restart"
            fi
            done

            #start sharding nodes
            for ((i=0,x=0;i<${#mongodb_cluster_ips[@]};i=i+2,x++))
            do
            ssh_t ${mongodb_cluster_ips[$i]} "service mongod_${sharding_ports[${x}]} start"
            done

            #start sharding secendary and arbiter
            for ((i=1,x=0;i<${#mongodb_cluster_ips[@]};i=i+2,x++))
            do
            ssh_t ${mongodb_cluster_ips[$i]} "sudo service mongod_${sharding_ports[${x}]} start && \
            sudo service mongod_${arbiter_ports[${x}]} start"
            done
            #start mongos
            for ((i=0;i<${#mongodb_cluster_ips[@]};i++))
            do
            ssh_t ${mongodb_cluster_ips[$i]} "sudo sed -i \"s#\(configdb.*=\).*#\1\ cs/${mongodb_cluster_ips[0]}:27018,${mongodb_cluster_ips[1]}:27018,${mongodb_cluster_ips[2]}:27018#\" /usr/local/qingteng/mongocluster/etc/mongos.conf && \
            sleep 5 && \
            sudo /etc/init.d/mongos restart"
            done
        fi
    fi
}


install_es_cluster(){
    local es_master_list="[\"`cat ${SERVER_IP_CONF}|grep -w es_master|awk -F " " '{print $2}'|xargs | sed "s/"\ "/\:9300\\\", \\\"/g"`:9300\"]"
    local es_name_list="[\"node-`cat ${SERVER_IP_CONF}|grep -w es_master|awk -F " " '{print $2}'|awk -F "." '{print $4}'|xargs | sed "s/"\ "/-1\\\", \\\"node-/g"`-1\"]"
    local es_master_connect=`cat ${SERVER_IP_CONF} | grep "es_master" | awk -F " " '{print $2}'`
    local es_data_connect=`cat ${SERVER_IP_CONF} | grep "es_data" | awk -F " " '{print $2}'`
    local m1=1
    for es_list_master in ${es_master_connect};do
        ssh_t ${es_list_master} "sed -i 's#discovery.seed_hosts:.*#discovery.seed_hosts:\ ${es_master_list}#g' /usr/local/qingteng/elasticsearch/elasticsearch_ins1/etc/elasticsearch.yml; \
        sed -i 's#cluster.initial_master_nodes:.*#cluster.initial_master_nodes:\ ${es_name_list}#g' /usr/local/qingteng/elasticsearch/elasticsearch_ins1/etc/elasticsearch.yml; \
        /etc/init.d/elasticsearch_ins1 restart;\
	/sbin/chkconfig --add elasticsearch_ins1;\
	/sbin/chkconfig  elasticsearch_ins1  on;"
    done
    for es_list_node in ${es_data_connect};do
	if [ $m1 == 1 ];then ssh_t ${es_list_node} "if [ \"\` cat /usr/local/qingteng/elasticsearch/elasticsearch_ins2/etc/elasticsearch.yml | grep -w \"node.voting_only\"|wc -l \`\" == 0 ];then echo \"node.voting_only: true\" >> /usr/local/qingteng/elasticsearch/elasticsearch_ins2/etc/elasticsearch.yml;fi; \
	sed -i 's#node.master.*#node.master:\ true#g' /usr/local/qingteng/elasticsearch/elasticsearch_ins2/etc/elasticsearch.yml;";fi
        let "m1=$m1+1"
        ssh_t ${es_list_node} "sed -i 's#discovery.seed_hosts:.*#discovery.seed_hosts:\ ${es_master_list}#g' /usr/local/qingteng/elasticsearch/elasticsearch_ins2/etc/elasticsearch.yml; \
        sed -i 's#cluster.initial_master_nodes:.*#cluster.initial_master_nodes:\ ${es_name_list}#g' /usr/local/qingteng/elasticsearch/elasticsearch_ins2/etc/elasticsearch.yml; \
        /etc/init.d/elasticsearch_ins2 restart;\
        /sbin/chkconfig --add elasticsearch_ins2;\
	/sbin/chkconfig  elasticsearch_ins2  on;"
    done

}

install_glusterfs_cluster(){

    glusterfs_ips=($(cat ${SERVER_IP_CONF}|grep -w glusterfs|awk '{print $2}'))
    php_ips=($(cat ${SERVER_IP_CONF}|grep -w php|awk '{print $2}'))
    event_ips=($(cat ${SERVER_IP_CONF}|grep -w event_srv|awk '{print $2}'))
    ms_ips=($(cat ${SERVER_IP_CONF}|grep -w ms_srv_srv|awk '{print $2}'))
    tmp_hosts_file="/tmp/tmp_hosts_file"

    #set hostname
    #generate glusterfs hosts tmp file
    for ((i=0;i<${#glusterfs_ips[@]};i++))
    do
        if [ $i == 0 ];then
            ssh_t ${glusterfs_ips[$i]} "uniq /etc/hosts |grep ${glusterfs_ips[$i]}" > $tmp_hosts_file
        else
            ssh_t ${glusterfs_ips[$i]} "uniq /etc/hosts |grep ${glusterfs_ips[$i]}" >> $tmp_hosts_file
        fi
    done

    for ((i=0;i<${#glusterfs_ips[@]};i++))
    do
        execute_rsync ${glusterfs_ips[$i]} $tmp_hosts_file /tmp
    done

    for ((i=0;i<${#glusterfs_ips[@]};i++))
    do
        ssh_t ${glusterfs_ips[$i]} "cat $tmp_hosts_file  | grep -v ${glusterfs_ips[$i]} >> /etc/hosts ;[ -f $tmp_hosts_file ] && rm -rf $tmp_hosts_file"
    done

    #clean glusterfs hosts tmp file
    [ -f $tmp_hosts_file ] && rm -rf $tmp_hosts_file

    for ((i=1;i<${#glusterfs_ips[@]};i++))
    do
        ssh_t ${glusterfs_ips[0]} "sudo gluster peer probe ${glusterfs_ips[$i]}"
    done
    #ssh_t ${glusterfs_node01} "sudo gluster peer probe ${glusterfs_node02};sudo gluster peer probe ${glusterfs_node03};"
    ssh_t ${glusterfs_ips[0]} "sudo gluster volume create java replica 3 ${glusterfs_ips[0]}:/data/storage/ ${glusterfs_ips[1]}:/data/storage/ ${glusterfs_ips[2]}:/data/storage/ force"
    #ssh_t ${glusterfs_node01} "sudo gluster volume create java replica 3 ${glusterfs_node01}:/data/storage/ ${glusterfs_node02}:/data/storage/ ${glusterfs_node03}:/data/storage/ force"
    ssh_t ${glusterfs_ips[0]} "sudo gluster volume start java"

    #mount glusterfs
    for ((i=0;i<${#glusterfs_ips[@]};i++))
    do
        ssh_t ${glusterfs_ips[$i]} "mount -a"
    done
    #install glusterfs client on php nodes
    for((i=0;i<${#php_ips[@]};i++))
    do
        ssh_t ${php_ips[$i]} "sudo yum -y install glusterfs glusterfs-fuse; \
        sudo mkdir -p /data/app/titan-dfs; \
        sudo mount -t glusterfs ${glusterfs_ips[0]}:/java /data/app/titan-dfs; \
        if [ -z \"\`grep -w \"glusterfs\" /etc/fstab\`\" ];then echo \"${glusterfs_ips[0]}:/java   /data/app/titan-dfs    glusterfs   defaults,_netdev 0 0\"|sudo tee -a /etc/fstab;fi"
    done
    #install glusterfs client on event-srv app nodes
    for((i=0;i<${#event_ips[@]};i++))
    do
        ssh_t ${event_ips[$i]} "sudo yum -y install glusterfs glusterfs-fuse; \
        sudo mkdir -p /data/app/titan-dfs; \
        sudo mount -t glusterfs ${glusterfs_ips[0]}:/java /data/app/titan-dfs; \
        if [ -z \"\`grep -w \"glusterfs\" /etc/fstab\`\" ];then echo \"${glusterfs_ips[0]}:/java   /data/app/titan-dfs    glusterfs   defaults,_netdev 0 0\"|sudo tee -a /etc/fstab;fi"
    done
    #install glusterfs client on ms-srv app nodes
    for((i=0;i<${#ms_ips[@]};i++))
    do
        ssh_t ${ms_ips[$i]} "if [ -d /data/app/titan-dfs ];then \
        sudo yum -y install glusterfs glusterfs-fuse; \
        sudo mkdir -p /data/app/titan-dfs; \
        sudo mount -t glusterfs ${glusterfs_ips[0]}:/java /data/app/titan-dfs; \
        if [ -z \"\`grep -w \"glusterfs\" /etc/fstab\`\" ];then echo \"${glusterfs_ips[0]}:/java   /data/app/titan-dfs    glusterfs   defaults,_netdev 0 0\"|sudo tee -a /etc/fstab;fi; \
        fi"
    done
}

webinstall_by_role(){
    local name=$1
    local ip=$2

    if [[ -z ${ip} || ${ip} = "127.0.0.1" ]]; then
        error_log "Invalid IP ${ip} for ${name} server"
        return
    fi

    case ${name} in
        rabbitmq)
            install_rabbitmq ${ip}
            ;;
        connect)
            install_connect ${ip}
            ;;
        es|es_master|es_data)
            install_es ${ip} ${name}
            ;;
        bigdata|logstash|viewer)
            install_bigdata ${ip} ${name}
            ;;
        erproxy)
            install_erproxy ${ip}
            ;;
        docker_scan)
            install_scan ${ip}
            ;;
        php)
            webinstall_php ${ip}
            ;;
        java)
            install_java ${ip}
            ;;
        mysql|mysql_php|mysql_erlang|mysql_master|mysql_slave)
            install_mysql ${ip} ${name}
            ;;
        redis_java|redis_erlang|redis_php)
            install_redis ${ip} ${name}
            ;;
        mongo_java|mongo_erlang|mongo_ms_srv)
            install_mongo ${ip} ${name}
            ;;
        zookeeper|kafka)
            if [ ${name} == "zookeeper" ];then
                info_log "开始安装 zookeeper install"
				install_zookeeper ${ip}
			elif [ ${name} == "kafka" ];then
				info_log "开始安装 kafka install"
				install_kafka ${ip}
			fi
			;;
        ms_srv|event_srv)
            if [ ${name} == "ms_srv" ];then
                info_log "开始安装ms_srv"
                install_ms ${ip}
            elif [ ${name} == "event_srv" ];then
                info_log "开始安装event_srv"
                install_event ${ip}
            fi
            ;;
          *)
            help
            ;;
    esac

}

upconfig_by_role(){
    local name=$1
    local ip=$2

    if [[ -z ${ip} || ${ip} = "127.0.0.1" ]]; then
        error_log "Invalid IP ${ip} for ${name} server"
        return
    fi

    execute_remote_shell ${ip} ${name}

}

## -----------------------Distribution---------------------------- ##
distribute_packets(){
    local dir=$1
    local host=$2

    info_log "Sending: ${dir[@]} to ${host}"

    execute_rsync ${host} "${dir}" "${REMOTE_SERVER_DIR}"
#    rsync -rz --delete ${dir} root@${host}:${REMOTE_SERVER_DIR}/
}

distribute_by_role(){
    local name=$1
    local ip=$2

    #set_np_authorized ${ip}

    if [[ -z ${ip} || ${ip} = "127.0.0.1" ]]; then
        return
    fi

    case ${name} in
        rabbitmq)
            is_dir_existed ${QT_RABBITMQ_DEPS[*]}
            ensure_remote_dir_exists ${ip}
            info_log "Sending package to rabbitmq Server"
            distribute_packets "${QT_RABBITMQ_DEPS[*]}" ${ip}
            ;;
        glusterfs)
            is_dir_existed ${QT_GLUSTERFS_DEPS[*]}
            ensure_remote_dir_exists ${ip}
            info_log "Sending package to glusterfs Server"
            distribute_packets "${QT_GLUSTERFS_DEPS[*]}" ${ip}
            ;;
        connect)
            is_dir_existed ${QT_CONNECT_DEPS[*]}
            ensure_remote_dir_exists ${ip}
            info_log "Sending package to Connect Server"
            distribute_packets "${QT_CONNECT_DEPS[*]}" ${ip}
            ;;
        php)
            #check version
            check_version
            if [ -f ${BASE_VERSION_JSON} ]; then
                ssh_t ${ip} "sudo mkdir -p /data/install/"
                #scp ${BASE_VERSION_JSON}  ${ip}:/data/install/base-version.json
                rsync -rz --rsync-path="sudo rsync" -e "ssh -p $DEFAULT_PORT"  --delete ${BASE_VERSION_JSON} ${DEFAULT_USER}@${ip}:/data/install/base-version.json
            fi

            is_dir_existed ${QT_PHP_DEPS[*]}
            ensure_remote_dir_exists ${ip}
            info_log "Sending package to PHP Server"
            distribute_packets "${QT_PHP_DEPS[*]}" ${ip}
            ;;
        keepalived)
            is_dir_existed ${QT_PHP_DEPS[*]}
            ensure_remote_dir_exists ${ip}
            info_log "Sending package to keepalived Server"
            distribute_packets "${QT_KEEPALIVED_DEPS[*]}" ${ip}
            ;;
        java)
            is_dir_existed ${QT_JAVA_DEPS[*]}
            ensure_remote_dir_exists ${ip}
            info_log "Sending package to Java Server"
            distribute_packets "${QT_JAVA_DEPS[*]}" ${ip}
            ;;
        mysql|mysql_php|mysql_erlang|mysql_master|mysql_slave)
            is_dir_existed ${QT_MYSQL_DEPS[*]}
            ensure_remote_dir_exists ${ip}
            info_log "Sending package to MySQL Server"
            distribute_packets "${QT_MYSQL_DEPS[*]}" ${ip}
            ;;
        redis_java|redis_erlang|redis_php)
            is_dir_existed ${QT_REDIS_DEPS[*]}
            ensure_remote_dir_exists ${ip}
            info_log "Sending package to Redis Server"
            distribute_packets "${QT_REDIS_DEPS[*]}" ${ip}
            ;;
        mongo_java|mongo_erlang|mongo_ms_srv)
            is_dir_existed ${QT_MONGO_DEPS[*]}
            ensure_remote_dir_exists ${ip}
            info_log "Sending package to MongoDB Server"
            distribute_packets "${QT_MONGO_DEPS[*]}" ${ip}
            ;;
        es|es_master|es_data)
            is_dir_existed ${QT_ES_DEPS[*]}
            ensure_remote_dir_exists ${ip}
            info_log "Sending package to Es Server"
            distribute_packets "${QT_ES_DEPS[*]}" ${ip}
            ;;
        bigdata|logstash|viewer)
            is_dir_existed ${QT_ES_DEPS[*]}
            ensure_remote_dir_exists ${ip}
            info_log "Sending package to Es Server"
            distribute_packets "${QT_BIGDATA_DEPS[*]}" ${ip}
            ;;
        erproxy)
            is_dir_existed ${QT_HAPROXY_DEPS[*]}
            ensure_remote_dir_exists ${ip}
            info_log "Sending package to ERproxy Server"
            distribute_packets "${QT_HAPROXY_DEPS[*]}" ${ip}
            ;;
        docker_scan)
            is_dir_existed ${QT_SCAN_DEPS[*]}
            ensure_remote_dir_exists ${ip}
            info_log "Sending package to Scan Server"
            distribute_packets "${QT_SCAN_DEPS[*]}" ${ip}
            ;;
        zookeeper|kafka)
			is_dir_existed ${QT_JAVA_DEPS[*]}
			ensure_remote_dir_exists ${ip}
			info_log "Sending package to zookeeper Server"
			distribute_packets "${QT_JAVA_DEPS[*]}" ${ip}
            ;;
        ms_srv|event_srv)
            is_dir_existed ${QT_JAVA_DEPS[*]}
            ensure_remote_dir_exists ${ip}
            info_log "Sending package to srv Server"
            distribute_packets "${QT_JAVA_DEPS[*]}" ${ip}
            ;;
		vip)
            #不做任何操作
			info "add vip infomation"
			;;
        *)
            help
            ;;
    esac
}

webdistribute_by_role(){
    local name=$1
    local ip=$2

    #set_np_authorized ${ip}

    if [[ -z ${ip} || ${ip} = "127.0.0.1" ]]; then
        return
    fi

    check_rsync ${ip}

    case ${name} in
        rabbitmq)
            is_dir_existed ${QT_RABBITMQ_DEPS[*]}
            ensure_remote_dir_exists ${ip}
            info_log "Sending package to rabbitmq Server"
            distribute_packets "${QT_RABBITMQ_DEPS[*]}" ${ip}
            ;;
        connect)
            is_dir_existed ${QT_CONNECT_DEPS[*]}
            ensure_remote_dir_exists ${ip}
            info_log "Sending package to Connect Server"
            distribute_packets "${QT_CONNECT_DEPS[*]}" ${ip}
            ;;
        php)
            is_dir_existed ${QT_PHP_DEPS[*]}
            ensure_remote_dir_exists ${ip}
            info_log "Sending package to PHP Server"
            distribute_packets "${QT_PHP_DEPS[*]}" ${ip}
            ;;
        java)
            is_dir_existed ${QT_JAVA_DEPS[*]}
            ensure_remote_dir_exists ${ip}
            info_log "Sending package to Java Server"
            distribute_packets "${QT_JAVA_DEPS[*]}" ${ip}
            ;;
        ms_srv|event_srv)
            is_dir_existed ${QT_JAVA_DEPS[*]}
            ensure_remote_dir_exists ${ip}
            info_log "Sending package to srv Server"
            distribute_packets "${QT_JAVA_DEPS[*]}" ${ip}
            ;;
        mysql|mysql_php|mysql_erlang|mysql_master|mysql_slave)
            is_dir_existed ${QT_MYSQL_DEPS[*]}
            ensure_remote_dir_exists ${ip}
            info_log "Sending package to MySQL Server"
            distribute_packets "${QT_MYSQL_DEPS[*]}" ${ip}
            ;;
        redis_java|redis_erlang|redis_php)
            is_dir_existed ${QT_REDIS_DEPS[*]}
            ensure_remote_dir_exists ${ip}
            info_log "Sending package to Redis Server"
            distribute_packets "${QT_REDIS_DEPS[*]}" ${ip}
            ;;
        mongo_java|mongo_erlang)
            is_dir_existed ${QT_MONGO_DEPS[*]}
            ensure_remote_dir_exists ${ip}
            info_log "Sending package to MongoDB Server"
            distribute_packets "${QT_MONGO_DEPS[*]}" ${ip}
            ;;
        es)
            is_dir_existed ${QT_ES_DEPS[*]}
            ensure_remote_dir_exists ${ip}
            info_log "Sending package to Es Server"
            distribute_packets "${QT_ES_DEPS[*]}" ${ip}
            ;;
        bigdata)
            is_dir_existed ${QT_ES_DEPS[*]}
            ensure_remote_dir_exists ${ip}
            info_log "Sending package to Es Server"
            distribute_packets "${QT_BIGDATA_DEPS[*]}" ${ip}
            ;;
        erproxy)
            is_dir_existed ${QT_HAPROXY_DEPS[*]}
            ensure_remote_dir_exists ${ip}
            info_log "Sending package to ERproxy Server"
            distribute_packets "${QT_HAPROXY_DEPS[*]}" ${ip}
            ;;
        docker_scan)
            is_dir_existed ${QT_SCAN_DEPS[*]}
            ensure_remote_dir_exists ${ip}
            info_log "Sending package to Scan Server"
            distribute_packets "${QT_SCAN_DEPS[*]}" ${ip}
            ;;
        zookeeper|kafka)
            is_dir_existed ${QT_JAVA_DEPS[*]}
			ensure_remote_dir_exists ${ip}
			info_log "Sending package to zookeeper Server"
			distribute_packets "${QT_JAVA_DEPS[*]}" ${ip}
            ;;
        *)
            help
            ;;
    esac
}

enable_mongo_auth(){
    local ips=$*
    for ip in ${ips[*]}; do
        info_log "================ Enable MongoDB Auth ($ip) ================"
        execute_remote_shell ${ip} enable_auth
    done
}

check_hostname(){
    local ip=$1
    info_log "Check hostname"
    ssh_t ${ip} "tag_short=\`hostname -s\`; tag=\`hostname\`; tag_long=\`hostname -f\`; [ -z \"\`grep 127.0.0.1 /etc/hosts | grep \$tag_short\`\" ] && echo \"127.0.0.1 \$tag_short \$tag \$tag_long\" >> /etc/hosts || echo \"127.0.0.1 hostname already exist.\""
    ssh_t ${ip} "tag_short=\`hostname -s\`; tag=\`hostname\`; tag_long=\`hostname -f\`; [ -z \"\`grep ${ip} /etc/hosts | grep \$tag_short\`\" ] && echo \"${ip} \$tag_short \$tag \$tag_long\" >> /etc/hosts || echo \"${ip} hostname already exist.\""
    check "Check hostname on ${ip}"
}

check_path(){
    local ip=$1
    local usrbin="/usr/local/bin"
    info_log "Check PATH"
    ssh_t ${ip} "[ -z \"\`echo \$PATH|grep ${usrbin}\`\" ] && echo \"export PATH=${usrbin}:\\\$PATH\" >> /etc/profile || echo \"PATH already exist.\" && source /etc/profile"
    check "Check PATH on ${ip}"
    info_log "Check PATH in /etc/bashrc"
    ssh_t ${ip} "[ -z \"\`echo \$PATH|grep ${usrbin}\`\" ] && echo \"export PATH=${usrbin}:\\\$PATH\" >> /etc/bashrc || echo \"PATH already exist.\""
    check "Check PATH /etc/bashrc on ${ip}"
}

# 如果/data目录为软连接，检查格式是否正确
check_symbolic_link(){
    local ip=$1
    info_log "Check symbolic link"
    ssh_t ${ip} "[[ ! -L /data ]] || (filename=`ls -al \/ | grep -w data | awk '{print \$11}'` && [[ ! \"\$filename\" =~ .*/$ ]]) || exit 1"
    check "The symbolic link format of ${ip}:/data dir is error please check"
}

check_rsync(){
    local ip=$1
    local rpmbin="/bin/rpm"
    info_log "Check Rsync"
    ssh_t ${ip} "sudo ${rpmbin} -q rsync"
    if [ $? -ne 0 ];then
        sudo scp -P ${DEFAULT_PORT} ${ROOT}/base/qingteng/rsync-* ${DEFAULT_USER}@${ip}:/tmp
        ssh_t ${ip} "sudo rpm -ivh /tmp/rsync-*"
    fi
}
start(){
    if [ -f ${SERVER_IP_CONF} ]; then
        # distribute or install
        local flag=$1
        # default: all components
        local content=`cat ${SERVER_IP_CONF}`
        # specific components according to $1
        if [ $2 != all ]; then
            # start with $2
            content=`cat ${SERVER_IP_CONF} |grep ^$2`
        fi

        (IFS=$'\n';for line in ${content}; do
            local name=`echo ${line} | awk -F " " '{print $1}'`
            local host=`echo ${line} | awk -F" " '{print $2}'`

            if [ -f $ROOT/${name}.tmp ];then
                if [ `cat $ROOT/service_ip.conf|grep -w ${name}|wc -l` -eq 1 ];then
                    continue
                fi
                #重复执行base时才会触发,此时表明name的安装过程已经完成,可以跳过。
                if [ $(cat $ROOT/${name}.tmp| sort | uniq |wc -l) == $(cat $ROOT/service_ip.conf|grep -w ${name}|wc -l) ];then
                    continue
                fi
            fi
            if [ ! -f $ROOT/${name}_ips.tmp  ];then 
                if [ "${flag}" == "distribute" ]; then
                    if [ $name != "vip" -a ! -z ${name} ];then
                        set_np_authorized ${host}
                        check_hostname ${host}
                        check_path ${host}
                        check_rsync ${host}
                        check_symbolic_link ${host}
                # send packages
                        distribute_by_role ${name} ${host}
                    fi
                elif [ "${flag}" == "install" ]; then
                    install_by_role ${name} ${host} 
                # store mongodb ip, to enable auth after mongodb initiation
                    if [ ! -z `echo ${name} |grep ^mongo_java` ]; then
                        echo "${host}" >> ${ROOT}/mongos_java_ips.tmp
                    fi
                    if [ ! -z `echo ${name} |grep ^mongo_ms_java` ]; then
                        echo "${host}" >> ${ROOT}/mongos_ms_srv_ips.tmp
                    fi
                    echo "${host}" >> ${ROOT}/${name}.tmp
                elif [ "${flag}" == "upconfig" ]; then
                    upconfig_by_role ${name} ${host}
                fi
            else 
                info_log "${name}cluster installed"
            fi
        done;)
        if [ $? -ne 0 ]; then
            exit 1
        fi
        # enable mongo auth
        if [ -f ${ROOT}/mongos_java_ips.tmp ]; then
            local mongo_java_ips=`cat ${ROOT}/mongos_java_ips.tmp |sort |uniq`
            rm -f ${ROOT}/mongos_java_ips.tmp
            enable_mongo_auth ${mongo_java_ips}
        fi
        if [ -f ${ROOT}/mongos_ms_srv_ips.tmp ]; then
            local mongo_ms_srv_ips=`cat ${ROOT}/mongos_ms_srv_ips.tmp |sort |uniq`
            rm -f ${ROOT}/mongos_ms_srv_ips.tmp
            enable_mongo_auth ${mongo_ms_srv_ips}
        fi

    fi
}

webstart(){
    if [ -f ${SERVER_IP_CONF} ]; then
        # distribute or install
        local flag=$1
        # default: all components
        local content=`cat ${SERVER_IP_CONF}`
        # specific components according to $1
        if [ $2 != all ]; then
            # start with $2
            content=`cat ${SERVER_IP_CONF} |grep ^$2`
        fi

        (IFS=$'\n';for line in ${content}; do
        local name=`echo ${line} | awk -F " " '{print $1}'`
        local host=`echo ${line} | awk -F" " '{print $2}'`
            if [ "${flag}" == "distribute" ]; then
                check_hostname ${host}
                check_path ${host}
                # send packages
                webdistribute_by_role ${name} ${host}
            elif [ "${flag}" == "install" ]; then
                webinstall_by_role ${name} ${host}
                # store mongodb ip, to enable auth after mongodb initiation
                if [ ! -z `echo ${name} |grep ^mongo` ]; then
                    echo "${host}" >> ${ROOT}/mongo_ips.tmp
                fi
            elif [ "${flag}" == "upconfig" ]; then
                upconfig_by_role ${name} ${host}
            fi
        done;)
        if [ $? -ne 0 ]; then
            exit 1
        fi
        # enable mongo auth
        if [ -f ${ROOT}/mongo_ips.tmp ]; then
            local mongo_ips=`cat ${ROOT}/mongo_ips.tmp |sort |uniq`
            rm -f ${ROOT}/mongo_ips.tmp
            enable_mongo_auth ${mongo_ips}
        fi

    fi
}
mysql_master_slave(){

    local slave_ip=`grep mysql_slave ${SERVER_IP_CONF}| awk -F " " '{print $2}'`

    [ -z "${slave_ip}" ] && exit 0

    local master_ip=`grep mysql_master ${SERVER_IP_CONF}| awk -F " " '{print $2}'`

    info_log "========== Show MySQL master status ==========="
    ssh_t ${master_ip} "\
    ret=\"\`mysql -uroot -p9pbsoq6hoNhhTzl -e \"show master status\"\`\"; \
    echo \${ret}" > /tmp/qingteng-mysql-master-status
    result="`cat /tmp/qingteng-mysql-master-status | grep Position`"
    local bin_file=`echo ${result}| awk -F " " '{print $6}'`
    local file_pos=`echo ${result}| awk -F " " '{print $7}'`

    [ -z "${bin_file}" ] && echo "Cannot found mysql file: mysql-bin.*" && exit 1
    [ -z "${file_pos}" ] && echo "Cannot found file position" && exit 1

    echo "File: ${bin_file}"
    echo "Position: ${file_pos}"

    info_log "========== Connect to Master Server ==========="

    info_log "Stop slave..."
    ssh_t ${slave_ip} "mysql -uroot -p9pbsoq6hoNhhTzl -e \"stop slave;\""

    sleep 1
    info_log "Change master to..."
    ssh_t ${slave_ip} "mysql -uroot -p9pbsoq6hoNhhTzl -e \"\
    change master to master_host=\\\"${master_ip}\\\", master_user=\\\"root\\\", master_password=\\\"9pbsoq6hoNhhTzl\\\", master_log_file=\\\"${bin_file}\\\", master_log_pos=${file_pos};
    start slave;\""

    sleep 2
    info_log "Show slave status"
    ssh_t ${slave_ip} "mysql -uroot -p9pbsoq6hoNhhTzl -e \"show slave status\\\G;\""
}
reset_es_pwd(){
    local es_host_ip=`get_role_host es_master`
    info_log "set es_cluster passwd : ${ES_PWD}"
    sudo sed -i "s#reset_elasticsearch_pwd.*#reset_elasticsearch_pwd(\"${es_host_ip}\",\"${QT_ES_PWD}\")#g" ${ROOT}/scripts/test.py
    sudo /usr/bin/python ${ROOT}/scripts/test.py
    check "set_cluster passwd"
    sleep 10
}

es_cluster_check(){
    local es_host_ip=`get_role_host es_master`
    local logstash_host_ip=""
    if [ ! -z $(get_role_host logstash) ];then logstash_host_ip=$(get_role_host logstash);fi
    ##兼容bigdata logstash的场景
    if [ ! -z $(get_role_host bigdata) ];then logstash_host_ip=$(get_role_host bigdata);fi
    if [ -z $logstash_host_ip ];then
	error_log "The ip address of logstash/bigdata is not found in service_ip.conf, please check and re-execute ./titan-base es_cluster_check"
	exit 1
    fi
    local es_node_number=$(cat ${SERVER_IP_CONF}|grep es|awk -F" " '{print $2}'|wc -l)
    local es_data_node_number=$(get_role_number es_node)
    local es_cluster_number=$(sudo ssh ${logstash_host_ip} curl  -X GET --user elastic:${QT_ES_PWD} http://${es_host_ip}:9200/_cat/health?v -s|awk -F " " '{print $5}'|tail -1)
    local es_cluster_data_nuber=$(sudo ssh ${logstash_host_ip} curl  -X GET --user elastic:${QT_ES_PWD} http://${es_host_ip}:9200/_cat/health?v -s|awk -F " " '{print $6}'|tail -1)
    local es_cluster_status=$(sudo ssh ${logstash_host_ip} curl  -X GET --user elastic:${QT_ES_PWD} http://${es_host_ip}:9200/_cat/health?v -s|awk -F " " '{print $4}'|tail -1)
    local es_check_cmd="检查集群详细信息可以在PHP服务器上使用：sudo ssh ${logstash_host_ip} curl -X GET --user elastic:${QT_ES_PWD} http://${es_host_ip}:9200/_cat/nodes?v -s"
    info_log "${es_check_cmd}"
    if [ ${es_cluster_status} == "green" -o  ${es_cluster_status} == "yellow" ];then
        info_log "集群健康检查正常：${es_cluster_status}！"
        if [ $es_cluster_number  -ge $es_node_number ];then
            info_log "正常！实际集群节点数与配置文件相符，数量为：$es_cluster_number"
        else
            echo -e "\\033[4;31m 集群实际node数量为：$es_cluster_number,与配置文件不符合，请安装完毕后检查  \\033[0m"
        fi
        if [ $es_cluster_data_nuber -ge $es_data_node_number ];then
            info_log "正常！集群数据节点与配置文件相符合，data_node数量为：$es_cluster_data_nuber"
        else
            echo -e "\\033[4;31m 集群实际data_node数量为：$es_cluster_data_nuber,与配置文件不符合，请安装完毕后检查  \\033[0m"
        fi
    else
        echo -e "\\033[4;31m 集群状态异常!!!! 请参考上面命令检查 !!! \\033[0m"
    fi
}

#版本升级时, 跳过mysql和mongo
update_ignore_db(){
    list='mysql mongo_java mongo_ms_srv' 
    for dbname in ${list}; do
        local host=`get_role_host ${dbname}`
        if [ -z ${host} ]; then 
            continue
        fi
        if [[ "${dbname}" == mysql* ]]; then
            # 判断mysql是否安装
            ssh_t ${host} "[ -d /data/mysql ]"
            if [ $? -eq 0 ]; then
                if [ $(cat $ROOT/service_ip.conf|grep -w ${dbname}|wc -l) -ge 3 ]; then
                    # 当tmp文件不存在，但是集群配置文件存在，表示集群已安装，可以生成mysql_ips.tmp
                    # 当tmp文件存在，表示mysql已安装，但还未设置mysql集群，不生成mysql_ips.tmp文件。
                    if [ ! -f ${ROOT}/${dbname}.tmp ]; then
                        ssh_t ${host} "[ -f /etc/percona-xtradb-cluster.cnf ]"
                        if [ $? -eq 0 ]; then
                            echo "ok" |sudo tee -a ${ROOT}/${dbname}_ips.tmp
                        fi
                    fi
                    # 集群安装mysql,安装到某个主机失败时，提示安装失败，退出重装。
                    if [ -f ${ROOT}/${dbname}.tmp -a $(cat ${ROOT}/${dbname}.tmp|wc -l) -ne $(cat $ROOT/service_ip.conf|grep -w ${dbname}|wc -l) ]; then
                       echo "${dbname}安装有问题, 脚本退出, 手动重装${dbname}"
                       exit 1
                    fi
                else
                    echo "ok" |sudo tee -a ${ROOT}/${dbname}.tmp
                fi
            fi
        elif [[ "${dbname}" == mongo* ]]; then
            ssh_t ${host} "[ -d /data/mongodb ]"
            if [ $? -eq 0 ]; then
                if [ $(cat $ROOT/service_ip.conf|grep -w ${dbname}|wc -l) -ge 3 ]; then
                    # 当mongo安装未设置集群时，跳过生成mongo_java_ips.tmp
                    if [ ! -f ${ROOT}/${dbname}.tmp ]; then
                        ssh_t ${host} "[ -d /data/mongocluster ]"
                        if [ $? -eq 0 ]; then
                            echo "ok" |sudo tee -a ${ROOT}/${dbname}_ips.tmp
                        fi
                    fi
                    if [ -f ${ROOT}/${dbname}.tmp -a $(cat ${ROOT}/${dbname}.tmp|wc -l) -ne $(cat $ROOT/service_ip.conf|grep -w ${dbname}|wc -l) ]; then
                       echo "${dbname}安装有问题, 脚本退出, 手动重装${dbname}"
                       exit 1
                    fi
                else
                    echo "ok" |sudo tee -a ${ROOT}/${dbname}.tmp
                fi
            fi
        fi
    done
}

info_content(){
    local info_status=$1
    if [ ${info_status} == "Success" ];then
        info_log "安装成功Installed success ."
    else
        error_log "To reinstall you need to use "./titan-bash all ""
    fi
}

main(){
    local name=$1
    #版本升级的时候跳过mongo和mysql
    update_ignore_db
    echo "--------------------Packet Distribution--------------------"
    start distribute ${name}

    if [ $? -ne 0 ]; then
        exit 1
    fi

    echo "--------------------RPM Packets Install--------------------"
    info_log "Start installing dependency lib"
    if [ "$UPCONFIG" == "true" ];then
        start upconfig ${name}
    else
        start install ${name}
		if [ ${name} == "mysql" ];then
			mysql_master_slave
		fi
    fi
	
    local server_name_lists=(docker_scan java connect php ms_srv event_srv)
    for server_name_list in ${server_name_lists[@]};do
        if [ `cat ${SERVER_IP_CONF}|grep -w ${server_name_list}|wc -l` -ge 3 -a ! -f ${ROOT}/${server_name_list}_ips.tmp ];then
        echo "ok" > ${ROOT}/${server_name_list}_ips.tmp
            rm -rf ${ROOT}/${server_name_list}.tmp
	fi
    done
	#确定keepablived 安装完成
    if [ `cat ${SERVER_IP_CONF}|grep -w "keepalived"|wc -l` -ge 3 -a ! -f ${ROOT}/keepalived_ips.tmp ];then
        set_keepalived_cluster
            check "install set_keepalived_cluster"
            rm -rf ${ROOT}/keepalived.tmp
        echo "ok" > ${ROOT}/keepalived_ips.tmp
    fi
	#配置zookeeperd集群
    if [ `cat ${SERVER_IP_CONF}|grep -w "zookeeper"|wc -l` -ge 3 -a ! -f ${ROOT}/zookeeper_ips.tmp ];then
        set_zookeeper_cluster
            rm -rf ${ROOT}/zookeeper.tmp
        echo "ok" > ${ROOT}/zookeeper_ips.tmp
    fi
    if [ `cat ${SERVER_IP_CONF}|grep -w "kafka"|wc -l` -ge 3 -a ! -f ${ROOT}/kafka_ips.tmp ];then
        set_kafka_cluster
            rm -rf ${ROOT}/kafka.tmp
        echo "ok" > ${ROOT}/kafka_ips.tmp
    fi
	#配置redis 集群
    for redis_roles in redis_erlang redis_php redis_java;do
        if [ `get_role_number ${redis_roles}` -ge 3 -a ! -f ${ROOT}/${redis_roles}_ips.tmp ];then
        set_redis_cluster ${redis_roles}
        check "install redis_cluster ${redis_roles}"
        rm -rf ${ROOT}/${redis_roles}.tmp
        echo "ok" > ${ROOT}/${redis_roles}_ips.tmp
	fi			
    done
	#配置mysql 集群
    if [ `cat ${SERVER_IP_CONF}|grep -w "mysql"|wc -l` -ge 3 -a ! -f ${ROOT}/mysql_ips.tmp ];then
        set_mysql_cluster 
        check "install mysql_cluster "
        rm -rf ${ROOT}/mysql.tmp
        echo "ok" > ${ROOT}/mysql_ips.tmp
		
    fi
    #配置rabbit集群
    if [ `cat ${SERVER_IP_CONF}|grep -w "rabbitmq"|wc -l` -ge 3 -a ! -f ${ROOT}/rabbitmq_ips.tmp ];then	
        set_rabbit_cluster 
        check "install rabbit_cluster"
            rm -rf ${ROOT}/rabbitmq.tmp
        echo "ok" > ${ROOT}/rabbitmq_ips.tmp
    fi
    #install mongodb cluster 
    if [ `cat ${SERVER_IP_CONF}|grep -w "mongo_java"|wc -l` -ge 3 -a ! -f ${ROOT}/mongo_java_ips.tmp ];then   
        install_mongodb_cluster mongo_java
        check "install mongodb_cluster"
        rm -rf ${ROOT}/mongo_java.tmp
        echo "ok" > ${ROOT}/mongo_java_ips.tmp
    fi
    #install mongodb_ms_srv cluster
    if [ `cat ${SERVER_IP_CONF}|grep -w "mongo_ms_srv"|wc -l` -ge 3 -a ! -f ${ROOT}/mongo_ms_srv_ips.tmp ];then   
        install_mongodb_cluster mongo_ms_srv
        check "install mongodb_srv_cluster"
        rm -rf ${ROOT}/mongo_ms_srv.tmp
        echo "ok" > ${ROOT}/mongo_ms_srv_ips.tmp
    fi
    #install glusterfs 
    if [ `cat ${SERVER_IP_CONF}|grep -w "glusterfs"|wc -l` -ge 3 -a ! -f ${ROOT}/glusterfs_ips.tmp ];then   
        install_glusterfs_cluster
        check "install glusterfs"
        rm -rf ${ROOT}/glusterfs.tmp
        echo "ok" > ${ROOT}/glusterfs_ips.tmp
    fi    
    #install es_cluster
    if [ `cat ${SERVER_IP_CONF}|grep -w "es_master"|wc -l` != 0 -a ! -f ${ROOT}/es_master_ips.tmp -a ! -f ${ROOT}/es_data_ips.tmp ];then
        install_es_cluster
        reset_es_pwd 
        es_cluster_check
        rm -rf ${ROOT}/es_master.tmp
        rm -rf ${ROOT}/es_data.tmp
        check " install es cluster"
        echo "ok" > ${ROOT}/es_master_ips.tmp
        echo "ok" > ${ROOT}/es_data_ips.tmp   
    fi
}
webmain(){
    local name=$1
    echo "--------------------Packet Distribution--------------------"
    sleep 60
    webstart distribute ${name}

    if [ $? -ne 0 ]; then
        exit 1
    fi

    echo "--------------------RPM Packets Install--------------------"
    info_log "Start installing dependency lib"
if [ "$UPCONFIG" == "true" ];then
        start upconfig ${name}
    else
        webstart install ${name}
        mysql_master_slave
    fi

}

manager_server(){
    if [[ -z $1 || $1 = "127.0.0.1" ]]; then
        return
    else
        info_log "Execute shell on remote server $1 $2 $3"
        ssh_t $1 "service $3 $2"
    fi
}

titan_manager_server(){
    if [ $# -ne 2 ];then 
        help $*
    else
        [ $2 != "start" ] &&  [ $2 != "stop" ] && [ $2 != "restart" ] &&  [ $2 != "status" ] && help $*
    fi
    
    if [ "$1" == "mysql" ] || [ "$1" == "all" ];then
        local mysql_ip=`get_role_host mysql`
        manager_server $mysql_ip $2 mysqld
    fi
    if [ "$1" == "redis_php" ] || [ "$1" == "all" ];then
        local redis_php_ip=`get_role_host redis_php`
        manager_server $redis_php_ip $2 redis6380d
    fi
    if [ "$1" == "redis_erlang" ] || [ "$1" == "all" ];then
        local redis_erlang_ip=`get_role_host redis_erlang`
        manager_server $redis_erlang_ip $2 redis6379d
    fi
    if [ "$1" == "redis_java" ] || [ "$1" == "all" ];then
        local redis_java_ip=`get_role_host redis_java`
        manager_server $redis_java_ip $2 redis6381d
    fi
    if [ "$1" == "mongo_java" ] || [ "$1" == "all" ];then
        local mongo_java_ip=`get_role_host mongo_java`
        manager_server $mongo_java_ip $2 mongod
    fi
    if [ "$1" == "zookeeper" ] || [ "$1" == "all" ];then
        local zookeeper_ip=`get_role_host zookeeper`
        manager_server $zookeeper_ip $2 zookeeperd
    fi
    if [ "$1" == "kafka" ] || [ "$1" == "all" ];then
        local kafka_ip=`get_role_host kafka`
        manager_server $kafka_ip $2 kafkad
    fi
    if [ "$1" == "java" ] || [ "$1" == "all" ];then
        local java_ip=`get_role_host java`
        manager_server $java_ip $2 wisteria
    fi
    if [ "$1" == "connect" ] || [ "$1" == "all" ];then
        local connect_ip=`get_role_host connect`
        manager_server $connect_ip $2 titan-dh
        manager_server $connect_ip $2 titan-sh
        manager_server $connect_ip $2 titan-selector
        manager_server $connect_ip $2 titan-agent
    fi
    if [ "$1" == "rabbitmq" ] || [ "$1" == "all" ];then
        local rabbitmq_ip=`get_role_host rabbitmq`
        manager_server $rabbitmq_ip $2 rabbitmq-server
    fi
    if [ "$1" == "php" ] || [ "$1" == "all" ];then
        local php_ip=`get_role_host php`
        manager_server $php_ip $2 php-fpm
        manager_server $php_ip $2 supervisord 
        manager_server $php_ip $2 nginx
    fi
}

copy_server_ip_to_data_install(){
    local php_ip=`get_role_host php`
    if [ ! -z ${php_ip} ];then rsync -rz --rsync-path="sudo rsync" -e "ssh -p $DEFAULT_PORT"  --delete ${SERVER_IP_CONF} ${DEFAULT_USER}@${php_ip}:/data/install/server_ip.conf;fi
}
auto_set_nopwd(){
	if [ $(cat $ROOT/host.conf|grep 127.0.0.1) ];then error "${ROOT}/host.conf has not been modified, please rerun after modification: ./titan-bash.sh auto_set_nopwd";fi
	sudo bash $ROOT/scripts/ssh_non_pwd_login.sh
	check "auto set password"
}

check_env(){
    local status=$1
    bash $ROOT/check_system.sh $status  2>&1 | sudo tee -a $ROOT/titan_check_env.log
}

uninstall(){
    local roles=$1
    bash $ROOT/uninstall.sh $roles 2>&1 | sudo tee -a $ROOT/titan_uninstall.log
}
## ----------------------------Starting--------------------------- ##

[ $# -gt 0 ] || help $*

if [ $DEFAULT_USER != "root" ];then 
    sudo sed  -i  "s/DEFAULT_USER=.*/DEFAULT_USER=${DEFAULT_USER}/g" $ROOT/scripts/portscan.sh
    sudo sed  -i  "s#DEFAULT_SSH_USER = .*#DEFAULT_SSH_USER = \"${DEFAULT_USER}\"#g" $ROOT/scripts/config_helper.py
fi

if [ $DEFAULT_PORT != "22" ];then
    sudo sed  -i  "s/DEFAULT_PORT=.*/DEFAULT_PORT=${DEFAULT_PORT}/g" $ROOT/scripts/portscan.sh
    sudo sed -i "s#DEFAULT_SSH_PORT = .*#DEFAULT_SSH_PORT = ${DEFAULT_PORT}#g" $ROOT/scripts/config_helper.py
fi

start_arg=$1
[ "$2" == "upconfig" ] && UPCONFIG=true
[ "$2" == "upconfig-local" ] && UPLOCALCONFIG=true
# [ "$2" == "+e" ] && Set_Error=false

while [ $# -gt 0 ]; do
    case $1 in
        all)
            # if [ ${Set_Error} == true ];then
            #      set -e
            # fi
            main all
            copy_server_ip_to_data_install
            info_content Success
            exit 0
            ;;
        webinstall)
            webmain $2
            exit 0
            ;;
        es)
            main es
            exit 0
            ;;
        bigdata)
            main bigdata
            exit 0
            ;;
        erproxy)
            main erproxy
            exit 0
            ;;
        docker_scan)
            main docker_scan
            exit 0
            ;;
        rabbitmq)
            main rabbitmq
            exit 0
            ;;
        connect)
            main connect
            exit 0
            ;;
        php)
            main php
            exit 0
            ;;
        keepalived)
            main keepalived
            exit 0
            ;;
        java)
            main java
            exit 0
            ;;
        ms_srv)
            main ms_srv
            exit 0
            ;;
        event_srv)
            main event_srv
            exit 0
            ;;
        mysql)
            main mysql
            mysql_master_slave
            exit 0
            ;;
        redis)
            main redis
            exit 0
            ;;
        redis_erlang)
            main redis_erlang
            exit 0
            ;;
        redis_php)
            main redis_php
            exit 0
            ;;
        redis_java)
            main redis_java
            exit 0
            ;;
        mongo)
            main mongo
            exit 0
            ;;
        mongo_erlang)
            main mongo_erlang
            exit 0
            ;;
        mongo_java)
            main mongo_java
            exit 0
            ;;
        mongo_ms_srv)
            main mongo_ms_srv
            exit 0
            ;;
        pre_check)
            ${ROOT}/scripts/portscan.sh start
            exit 0
            ;;
        ping_server)
            ${ROOT}/scripts/portscan.sh ping
            exit 0
            ;;
        stop_python)
            ${ROOT}/scripts/portscan.sh stop
            exit 0
            ;;
        after_check)
            ${ROOT}/scripts/portscan.sh qt_ports
            exit 0
            ;;
        reset_es_pwd)
            reset_es_pwd
            ;;
        es_cluster_check)
            es_cluster_check
            exit 0
            ;;
        titan_manager_server)
            titan_manager_server $2 $3
            exit 0
            ;;
        update_zookeeper_cluster)
            main zookeeper
            exit 0
            ;;
        update_kafka_cluster)
            main kafka
            exit 0
            ;;
        auto_set_nopwd)
            auto_set_nopwd
            exit 0
            ;;
        check_env)
            check_env $2
            exit 0
        ;;
        uninstall)
            if [ ! -z $2 ];then
                uninstall $2
            else
            uninstall all
            fi
            exit 0
            ;;
        *)
            help $*
            exit 0
            ;;
    esac
done
exit 0 
