#!/bin/bash
# error hint
COLOR_G="\x1b[1;32m"  # green
COLOR_R="\x1b[1;31m"  # red
COLOR_L="\x1b[1;33m"  # yellow
RESET="\x1b[0m"
UPCONFIG=false
UPLOCALCONFIG=false
USE_KEY_LOGIN=false

## ssh login
DEFAULT_PORT=22
DEFAULT_USER=root

ROOT=`cd \`dirname $0\` && pwd`
SERVER_IP_CONF=${ROOT}/service_ip.conf
#SERVER_IP_CONF=${ROOT}/service_ip.conf

echo "##########################################################################"
echo "#                                                                        #"
echo "#                        Qingteng uninstall service script               #"
echo "#                                                                        #"
echo "#警告:本脚本会卸载相关服务，可能导致Titan相关服务不可用，请谨慎执行      #"
echo "##########################################################################"
echo " "



## -----------------------Utils Functions------------------------- ##
help() {
    echo "-------------------------------------------------------------------------------"
    echo "                        Usage information"
    echo "-------------------------------------------------------------------------------"
    echo ""
    echo "./uninstall.sh [<all | erlang | php | java | mysql | redis| mongo>]"
    echo "Options:"
    echo "  all           uninstall for all server                             "
    echo "  connect     uninstall for connect server                           "
    echo "  rabbitmq      uninstall for rabbitmq server                        "
    echo "  glusterfs      uninstall for glusterfs server                      "
    echo "  php           uninstall for php server                             "
    echo "  es            uninstall for es server                              "
    echo "  bigdata       uninstall for bigdata server                         "
    echo "  docker_scan   uninstall for scan server                            "
    echo "  java          uninstall for java server                            "
    echo "  ms_srv        uninstall for java server                            "
    echo "  ms_event      uninstall for java server                            "
    echo "  mysql         uninstall for mysql server(master&slave)             "
    echo "  redis_php     uninstall for redis server                           "
    echo "  redis_java    uninstall for redis server                           "
    echo "  redis_erlang  uninstall for redis server                           "
    echo "  mongo_java    uninstall for mongo server                           "
    echo "  mongo_ms_srv    uninstall for mongo_ms_srv server                  "
    echo ""
    echo "  One-key Uninstall:"
    echo "    ./uninstall.sh all"
    echo "  Uninstall for specific server:"
    echo "    ./uninstall.sh php"
    echo "-------------------------------------------------------------------"
    exit 1
}

info_log(){
    echo -e "${COLOR_G}[Info] ${1}${RESET}"
}

error_log(){
    echo -e "${COLOR_R}[Error] ${1}${RESET}"
    exit 1
}

info_log2(){
    echo -e "${COLOR_L}[Info] ${1}${RESET}"
}

check(){
    if [ $? -eq 0 ];then
        info_log "$* Successfully"
    else
        error_log "$* Failed"
        exit 1
    fi
}

sq() { # single quote for Bourne shell evaluation
    # Change ' to '\'' and wrap in single quotes.
    # If original starts/ends with a single quote, creates useless
    # (but harmless) '' at beginning/end of result.
    printf '%s\n' "$*" | sed -e "s/'/'\\\\''/g" -e 1s/^/\'/ -e \$s/\$/\'/
}

ssh_t(){
    # 当用户不是root或者没有加sudo，才使用 sudo -n bash -c 'cmd', 主要处理web安装时 check hostname和path时的多个命令一起执行时的问题
    if [[ $DEFAULT_USER != "root" && !("$2" =~ .*sudo.*) ]]; then
        sudocmd="sudo -n bash -c $(sq "$2")"
        #echo "$sudocmd"
        ssh -t -p ${DEFAULT_PORT} -oStrictHostKeyChecking=no -o ConnectionAttempts=5 -o ConnectTimeout=3 ${DEFAULT_USER}@$1 "$sudocmd"
    else
        ssh -t -p ${DEFAULT_PORT} -oStrictHostKeyChecking=no -o ConnectionAttempts=5 -o ConnectTimeout=3 ${DEFAULT_USER}@$1 $2
    fi
}

ssh_tt(){
    # 当用户不是root或者没有加sudo，才使用 sudo -n bash -c 'cmd', 主要处理web安装时 check hostname和path时的多个命令一起执行时的问题
    if [[ $DEFAULT_USER != "root" && !("$2" =~ .*sudo.*) ]]; then
        sudocmd="sudo -n bash -c $(sq "$2")"
        #echo "$sudocmd"
        ssh -p ${DEFAULT_PORT} -oStrictHostKeyChecking=no -o ConnectionAttempts=5 -o ConnectTimeout=3 ${DEFAULT_USER}@$1 "$sudocmd"
    else
        ssh -p ${DEFAULT_PORT} -oStrictHostKeyChecking=no -o ConnectionAttempts=5 -o ConnectTimeout=3 ${DEFAULT_USER}@$1 $2
    fi
}

get_role_number(){
    local role=$1
    if [ ! -f ${SERVER_IP_CONF} ]; then
        error_log "Not found service_ip.conf file."
        exit 1
    fi
    cat ${SERVER_IP_CONF}|grep -w $role|awk -F" " '{print $2}'|wc -l
}

get_role_host(){
    local role=$1
    if [ ! -f ${SERVER_IP_CONF} ]; then
        error_log "Not found service_ip.conf file."
        exit 1
    fi
    cat ${SERVER_IP_CONF}|grep $role|awk -F" " '{print $2}'|head -1
}

get_role_host_list(){
    local role=$1
    if [ ! -f ${SERVER_IP_CONF} ]; then
        error_log "Not found service_ip.conf file."
        exit 1
    fi
    cat ${SERVER_IP_CONF}|grep -w $role|awk -F" " '{print $2}'
}

get_role_hosts(){
    local role=$1
    if [ ! -f ${SERVER_IP_CONF} ]; then
        error_log "Not found service_ip.conf file."
        exit 1
    fi
    cat ${SERVER_IP_CONF}|grep -w $role|awk -F" " '{print $2}'|xargs |head -1
}

delete_batch_file(){
    local file_dir=$2
    local host=$1
    [  -z $file_dir ] &&  error_log "$file_dir is null "
    info_log "Start cleaning up $file_dir file"
    # ssh_t $host " if [ \$(ls $2|wc -l) != "0" ];then rm -rf ${file_dir};fi"
    ssh_t $host "rm -rf ${file_dir}"
}



delete_file(){
    local file_dir=$2
    local host=$1
    [  -z $file_dir ] &&  error_log "$file_dir is null "
    info_log "Start cleaning up $file_dir files"
    ssh_t $host "[ -f "${file_dir}" ] && rm -rf ${file_dir}"
}

delete_dir(){
    local dir_name=$2
    local host=$1
    [  -z $dir_name ] &&  error_log "$dir_name is null "
    info_log "Start cleaning up $dir_name directory"
    if [[ $dir_name =~ "rabbitmq_" ]];then
        ssh_t $host "[ -L "${dir_name}" ] && rm -rf ${dir_name}"
    else
        ssh_t $host "[ -d "${dir_name}" ] && rm -rf ${dir_name}"
    fi
}

kill_process(){
    local host=$1
    local server_name=$2
    [  -z $server_name ] &&  error_log "$server_name is null "
    info_log "Start cleaning shutdown $server_name service process"
    # local ps_status=$(ssh_tt $host "ps -ef | grep $server_name | egrep -v 'grep' | awk '{print \$2}'")
    local ps_status_list=$(ssh_t $host "ps -ef|egrep \"$server_name\"")
    local ps_status=$(echo "$ps_status_list"|egrep -v 'grep'|egrep -v 'uninstall'|egrep -v 'bash' |awk '{print $2}')
    if [ -z "$ps_status" ];then return;fi
    for ps_statu in $ps_status;do
        ps_statu=$(echo $ps_statu|sed 's/\r//g')
        ssh_t $host "kill -9 $ps_statu"
    done
    # ssh_t $host "if [ ! -z $(echo $ps_status | sed 's/\r//g') ];then kill $ps_status;fi" > /dev/null 2>&1
}

rpm_e(){
    local host=$1
    local server_name=$2
    [  -z $server_name ] &&  error_log "$server_name is null "
    info_log "Start uninstalling $server_name service rpm"
    if [ $server_name == 'mongo' ];then
        ssh_t $host "rpm -aq|egrep '$server_name' | xargs -i rpm -e {} --nodeps --noscripts > /dev/null 2>&1 "
    else
        ssh_t $host "rpm -aq|egrep '$server_name' |egrep -v 'glusterfs-cli|glusterfs-api'| xargs -i rpm -e {} --nodeps  > /dev/null 2>&1 "
    fi
}

stop_server(){
    local host=$1
    local server_name=$2
    [  -z $server_name ] &&  error_log "$server_name is null "
    info_log "Start stop $server_name service"
    ssh_t $host "service $server_name stop > /dev/null 2>&1"
}

back_dir_file(){
    local host=$1
    local dir_name=$2
    local back_time=$(date "+%Y%m%d%H%M%S")
    [  -z $dir_name ] &&  error_log "$dir_name is null "
    info_log "Start Start backup $dir_name to $dir_name-$back_time-bak"
    ssh_t $host "[ -d "$dir_name" ] && mv $dir_name $dir_name-$back_time-bak"
    ssh_t $host "[ -f "$dir_name" ] && mv $dir_name $dir_name-$back_time-bak"

}

clean_chkconfig(){
    local host=$1
    local server_name=$2
    local centos_version=$3
    [  -z $server_name ] &&  error_log "$server_name is null "
    info_log "Start stop $server_name auto start"
    if [ $centos_version == "7" ];then
        if [ $server_name == "nginx" ];then
            if [[ "$(ssh_t $host "systemctl disable $server_name ")" =~ "chkconfig" ]];then
                ssh_t $host "chkconfig $server_name off > /dev/null 2>&1 ;chkconfig --del $server_name > /dev/null 2>&1 " 
            else
                ssh_t $host " if [ ! -z \"\$(systemctl list-unit-files|grep nginx)\" ];then systemctl disable $server_name;fi "
            fi
        else
            ssh_t $host "chkconfig $server_name off > /dev/null 2>&1 ;chkconfig --del $server_name > /dev/null 2>&1 "
        fi
    fi
}


uninstall_rabbitmq(){
    local host=$1
    local name=$2
    local file_list="/root/.erlang.cookie"
    local srv_hosts=$(get_role_host_list event_srv)
    local dir_list=("/data/app/titan-rabbitmq" "/data/servers" "/root/rabbitmq_data" "/root/rabbitmq_root")
    local centos_version=$(ssh_tt $host "awk '{print \$(NF-1)}' /etc/redhat-release| cut -d\".\" -f1" )
    local rabbitmq_host_lists=$(cat ${SERVER_IP_CONF}|grep $name|awk '{print $2}')
    stop_server $host "${name}-server"
    clean_chkconfig $host "${name}-server" ${centos_version}
    kill_process $host $name    
    rpm_e $host "${name}"
    
    ##clern hosts
    for rabbitmq_host_list in ${rabbitmq_host_lists[@]};do
        local host_name=$(ssh_t $rabbitmq_host_list "hostname -s"|sed 's/\r//g')
        ssh_t $host "sed -i '/^$rabbitmq_host_list \?$host_name \$/d' /etc/hosts"
    done

    for file in ${file_list[@]};do
        delete_file $host $file
    done

    for dir in ${dir_list[@]};do
        delete_dir $host $dir
    done
}

uninstall_php(){
    local host=$1
    local name=$2
    local rpm_list=("qingteng-php" "qingteng-nginx" "qingteng-jdk" "nginx" "supervisor")
    local server_list=("php-fpm" "nginx" "supervisord")
    local process_list="nginx|supervisord|php-fpm"
    local centos_version=$(ssh_tt $host "awk '{print \$(NF-1)}' /etc/redhat-release| cut -d\".\" -f1" )
    local dir_list=("/var/lib/nginx"
    "/var/lib/nginx/tmp"
    "/data/app/conf"
    "/data/titan-logs/php"
    "/var/log/nginx"
    "/data/titan-logs/supervisor"
    "/data/titan-logs/php-fpm"
    "/data/titan-logs/nginx")
    
    #stop server
    for server_name in ${server_list[@]};do
        stop_server $host "${server_name}"
        clean_chkconfig $host "${server_name}" ${centos_version}
    done

    kill_process $host $process_list

    for rpm_name in ${rpm_list[@]};do
        rpm_e $host "${rpm_name}"
    done
    ! [[ $(get_role_hosts mysql) =~ $host ]] && rpm_e $host "qingteng-percona"

    for dir in ${dir_list[@]};do 
        delete_dir $host $dir
    done
}

uninstall_mysql(){
    local host=$1
    local name=$2
    local mysql_cluster
    local centos_version=$(ssh_tt $host "awk '{print \$(NF-1)}' /etc/redhat-release| cut -d\".\" -f1" )
    local back_dir_lists=("/etc/my.cnf" "/data/mysql")
    local dir_lists=("/data/titan-logs/mysql")
    local file_lists=("/run/lock/subsys/mysql"
                    "/run/systemd/generator.late/mysqld.service"
                    "/run/systemd/generator.late/mysql.service"
                    "/tmp/mysql.tmp")
    local batch_files=("/usr/local/bin/mysql*" "/usr/local/sbin/*") 
    [ $(get_role_number ${name}) -gt "1" ] && mysql_cluster="0" || mysql_cluster="1"
    
    if [ "$mysql_cluster" == "0" ];then
        stop_server $host "mysql@bootstrap"
        stop_server $host "mysql"
        clean_chkconfig $host "mysql@bootstrap" ${centos_version}
        clean_chkconfig $host "mysql" ${centos_version}
    else
        stop_server $host "mysqld"
        
    fi
    
    clean_chkconfig $host "mysqld" ${centos_version}
    kill_process $host $name
    for back_dir in ${back_dir_lists[@]};do
        back_dir_file $host $back_dir
    done

    if [ "$mysql_cluster" == "0" ];then
        rpm_e $host "Percona-XtraDB-Cluster"
        rpm_e $host "qingteng-percona"
    else
        rpm_e $host "qingteng-percona"
    fi
    
    for batch_file in ${batch_files[@]};do
        delete_batch_file $host $batch_file
    done

    for dir_list in ${dir_lists[@]};do
        delete_dir $host $dir_list
    done
    
    for file_list in ${file_lists[@]};do
        delete_file $host $file_list
    done

    rm -f /data/qingteng-rules-*.tar.gz
}
uninstall_glusterfs_client(){
    local php_hosts=$(get_role_host_list php)
    local event_srv_hosts=$(get_role_host_list event_srv)
    local ms_srv_hosts=$(get_role_host_list ms_srv)
    local glusterfs_hosts=$(get_role_host_list glusterfs)
    local n=0
    for glusterfs_host in ${glusterfs_hosts[@]};do
        if [[ "$(echo ${php_hosts[@]})" =~ "$glusterfs_host" ]];then
            let "n = $n + 1"
        fi
    done           
    if [ $n -ge $(echo ${glusterfs_host}|awk -F " " '{print NF}') ];then
        info_log "nothing to doing"
    else
        for php_host in ${php_hosts[@]};do
            local php_host_name=$(ssh_t ${php_host} "hostname -s"|sed 's/\r//g')
            rpm_e $php_host "gluster"
            ssh_t $php_host "sed -i '/titan-dfs/d' /etc/fstab"
            ssh_t $php_host "sed -i '/^${php_host}.* ${php_host_name} \?\r\$/d' /etc/hosts"
            ssh_t $php_host "umount /data/app/titan-dfs >/dev/null 2>&1"
            ssh_t $php_host "rm -rf /data/app/titan-dfs"
        done
    fi

    for event_srv_host in ${event_srv_hosts[@]};do
            local event_host_name=$(ssh_t ${event_srv_host} "hostname -s"|sed 's/\r//g')
            rpm_e $event_srv_host "gluster"
            ssh_t $event_srv_host "sed -i '/titan-dfs/d' /etc/fstab"
            ssh_t $event_srv_host "sed -i '/^${event_srv_host}.* ${event_host_name} \?\r\$/d' /etc/hosts"
            ssh_t $event_srv_host "umount /data/app/titan-dfs >/dev/null 2>&1"
            ssh_t $event_srv_host "rm -rf /data/app/titan-dfs"
    done
    for ms_srv_host in ${ms_srv_hosts[@]};do
            local ms_host_name=$(ssh_t ${ms_srv_host} "hostname -s"|sed 's/\r//g')
            rpm_e $ms_srv_host "gluster"
            ssh_t $ms_srv_host "sed -i '/titan-dfs/d' /etc/fstab"
            ssh_t $ms_srv_host "sed -i '/^${ms_srv_host}.* ${ms_host_name} \?\r\$/d' /etc/hosts"
            ssh_t $ms_srv_host "umount /data/app/titan-dfs >/dev/null 2>&1"
            ssh_t $ms_srv_host "rm -rf /data/app/titan-dfs"
    done
}
uninstall_glusterfs(){
    local host=$1
    local name=$2
    local php_hosts=$(get_role_host_list php)
    local srv_hosts=$(get_role_host_list event_srv)
    local glusterfs_host_lists=$(get_role_host_list $name)
    local dir_lists=("/var/lib/glusterd"
                    "/data/app/titan-dfs"
                    "/data/storage"
                    "/run/gluster"
                    "/var/log/glusterfs")
    local file_lists=("/etc/selinux/targeted/active/modules/100/glusterd" "/run/glusterd.socket")
    local centos_version=$(ssh_tt $host "awk '{print \$(NF-1)}' /etc/redhat-release| cut -d\".\" -f1" )
    ssh_t $host "umount /data/app/titan-dfs"
    stop_server $host "glusterd"
    kill_process $host  "gluster"
    clean_chkconfig $host "glusterd" ${centos_version}
    rpm_e $host "gluster"


    for dir_list in ${dir_lists[@]};do
        delete_dir $host $dir_list
    done

    for file_list in ${file_lists[@]};do
        delete_file $host $file_list
    done
    
    for glusterfs_host_list in ${glusterfs_host_lists[@]};do
        local host_name=$(ssh_t ${glusterfs_host_list} "hostname -s"|sed 's/\r//g')
        if [ $glusterfs_host_list == $host ];then
            continue
        else
            ssh_t $host "sed -i '/^${glusterfs_host_list}.* ${host_name} \?\r\$/d' /etc/hosts"
        fi
    done   
    ssh_t $host "sed -i '/titan-dfs/d' /etc/fstab"
    ssh_t $host "umount /data/app/titan-dfs"

}

uninstall_redis(){
    local host=$1
    local name=$2
    local arg=$args
    local centos_version=$(ssh_tt $host "awk '{print \$(NF-1)}' /etc/redhat-release| cut -d\".\" -f1" )
    local batch_files=("/run/systemd/generator.late/runlevel5.target.wants/redis*" 
    "/etc/rc.d/init.d/redis*")
    local dir_lists=("/etc/redis" "/usr/local/qingteng/redis" "/data/redis" "/data/titan-logs/redis")
    [ $(get_role_number ${name}) -ge "3" ] && redis_cluster="0" || redis_cluster="1"

    case $name in
        redis_erlang)
            if [ $redis_cluster = 0 ] ;then
                redis_port_lists=("6379" "6479" "6579")
            else
                redis_port_lists=("6379")
            fi
            ;;
        redis_php)
            if [ $redis_cluster = 0 ] ;then
                redis_port_lists=("6380" "6480" "6580")
            else
                redis_port_lists=("6380")
            fi
            ;;
        redis_java)
            if [ $redis_cluster = 0 ] ;then
                redis_port_lists=("6381" "6481" "6581")
            else
                redis_port_lists=("6381")
            fi            
            ;;
        *)
            error_log "Parameter passing error"
            exit 1
    esac
    for redis_port_list in ${redis_port_lists[@]};do
        stop_server $host "redis${redis_port_list}d"
        kill_process $host "${redis_port_list}"
        clean_chkconfig $host "redis${redis_port_list}d" ${centos_version}      
        if [ $args == "all" -o -z "$(ssh_t $host "ss -lntp|awk '{print \$4}'|egrep '6379|6479|6579|6380|6480|6580|6381|6481|6581'")" ];then
            rpm_e $host "redis"
            for batch_file in ${batch_files[@]};do
                delete_batch_file $host ${batch_file} 
            done
            for dir_list in ${dir_lists[@]};do
                delete_dir $host ${dir_list}
            done
        else
            delete_batch_file $host "/data/redis/${redis_port_list}/*"
            delete_file $host "/data/titan-logs/redis/${redis_port_list}-redis.log"
        fi       
    done
    
}

uninstall_es(){
    local host=$1
    local name=$2
    local centos_version=$(ssh_tt $host "awk '{print \$(NF-1)}' /etc/redhat-release| cut -d\".\" -f1" )
    local es_service_lists=("elasticsearch_ins1" "elasticsearch_ins2" "elasticsearch_ins3" "elasticsearch_ins4")
    local rpm_lists=("jdk1.8.0_144" "qingteng-jdk" "bigdata-es" "qingteng-ik" "elasticsearch")
    local dir_lists=("/etc/elasticsearch"
        "/var/lib/elasticsearch"
        "/var/log/elasticsearch"
        "/usr/share/elasticsearch"
        "/usr/local/qingteng/elasticsearch"
        "/data/titan-logs/elasticsearch"
        "/data/elasticsearch"
        "/etc/elasticsearch")
    local batch_files=("/run/systemd/generator.late/elasticsearch*"
        "/run/systemd/generator.late/runlevel5.target.wants/elasticsearch_ins*"
        "/run/systemd/generator.late/runlevel4.target.wants/elasticsearch_ins*"
        "/run/systemd/generator.late/runlevel3.target.wants/elasticsearch_ins*"
        "/run/systemd/generator.late/runlevel2.target.wants/elasticsearch_ins*"
        "/etc/rc.d/init.d/elasticsearch*"
        "/etc/sysconfig/elasticsearch*"
        "/tmp/elasticsearch*"
        )
    local file_lists=("/usr/lib/firewalld/services/elasticsearch.xml"
        "/usr/lib/systemd/system/elasticsearch.service"
        "/usr/lib/tmpfiles.d/elasticsearch.conf"
        "/usr/lib/sysctl.d/elasticsearch.conf"
        "/run/lock/subsys/elasticsearch"
        "/run/elasticsearch"
        )
    case $name in
        es)
            for es_service_list in ${es_service_list[@]};do
                stop_server $host $es_service_list
                kill_process $host $es_service_list
                clean_chkconfig $host $es_service_list ${centos_version}
            done
            ;;
        es_master)
            local es_service_list="elasticsearch_ins1"
            stop_server $host $es_service_list
            kill_process $host $es_service_list
            clean_chkconfig $host $es_service_list ${centos_version}
            ;;
        es_data)
            local es_service_list="elasticsearch_ins2"
            stop_server $host $es_service_list
            kill_process $host $es_service_list
            clean_chkconfig $host $es_service_list ${centos_version}
            ;;
    esac
    for rpm_list in ${rpm_lists[@]};do
        rpm_e $host $rpm_list
    done

    for dir_list in ${dir_lists[@]};do
        delete_dir $host $dir_list 
    done

    for batch_file in ${batch_files[@]};do
        delete_batch_file $host ${batch_file}
    done

    for file_list in ${file_lists[@]};do
        delete_file $host ${file_list} 
    done  
}

uninstall_bigdata(){
    local host=$1
    local name=$2
    local rpm_lists=("bigdata-python" "nginx" "librdkafka-devel")
    local dir_lists=("/usr/local/qingteng/python2.7.9" "/etc/nginx" "/var/log/nginx")
    local centos_version=$(ssh_tt $host "awk '{print \$(NF-1)}' /etc/redhat-release| cut -d\".\" -f1" )

    if [ $name != "logstash" ];then
        stop_server $host "nginx"
        kill_process $host "nginx"
        clean_chkconfig $host "nginx" ${centos_version}
        for server_list in ${server_lists[@]};do
            rpm_e $host ${server_list}
        done
        for dir_list in ${dir_lists[@]};do
            delete_dir $host $dir_list
        done
    else
        for server_list in ${server_lists[@]};do
            if [ $sever_list == "nginx" ];then
                continue
            else
                rpm_e $host ${server_list}
            fi
        done
        delete_dir $host ${dir_lists[0]}
    fi
}

uninstall_zookeeper(){
    local host=$1
    local name=$2
    local centos_version=$(ssh_tt $host "awk '{print \$(NF-1)}' /etc/redhat-release| cut -d\".\" -f1" )
    local kafka_ips=$(get_role_hosts "kafka")
    local java_ips=$(get_role_hosts "java")
    local connect_ips=$(get_role_hosts "connect")
    local check_ip_list="${kafka_ips} ${java_ips} ${connect_ips}"
    local dir_lists=("/data/zk-data" "/data/titan-logs/zookeeper" "/usr/local/qingteng/zookeeper" )
    local file_lists=("/run/systemd/generator.late/zookeeperd.service" "/sys/fs/cgroup/systemd/system.slice/zookeeperd.service" )
    stop_server $host "${name}d"
    kill_process $host "zoo.cfg"
    clean_chkconfig $host "zookeeperd" ${centos_version}
    rpm_e $host "zookeeper"
    if [[ "$check_ip_list" =~ "$host" ]];then
        info_log "don't uninstall jdk" 
    else
        rpm_e $host "jdk"
    fi

    for dir_list in ${dir_lists[@]};do
        delete_dir $host "$dir_list"
    done

    for file_list in ${file_lists[@]};do
        delete_file $host "$file_list"
    done
    
}


uninstall_kafka(){
    local host=$1
    local name=$2
    local centos_version=$(ssh_tt $host "awk '{print \$(NF-1)}' /etc/redhat-release| cut -d\".\" -f1" )
    local zk_ips=$(get_role_hosts "zookeeper")
    local java_ips=$(get_role_hosts "java")
    local connect_ips=$(get_role_hosts "connect")
    local check_ip_list="${zk_ips} ${java_ips} ${connect_ips}"
    local dir_lists=("/data/kafka-data" "/data/titan-logs/kafka" "/usr/local/qingteng/kafka" )
    local file_lists=("/run/systemd/generator.late/kafkad.service")
    stop_server $host "${name}"
    kill_process $host "${name}"
    clean_chkconfig $host "${name}" ${centos_version}
    rpm_e $host "${name}"
    if [[ "$check_ip_list" =~ "$host" ]];then
        info_log "don't uninstall jdk" 
    else
        rpm_e $host "jdk"
    fi

    for dir_list in ${dir_lists[@]};do
        delete_dir $host "$dir_list"
    done

    for file_list in ${file_lists[@]};do
        delete_file $host "$file_list"
    done
    
}

uninstall_java(){
    local host=$1
    local name=$2
    local dir_lists=("/usr/local/qingteng/arthas" )
    local connect_ips=$(get_role_hosts "connect")
    rpm_e $host "qingteng-python"
    if [ "$args" == "all" ];then
        rpm_e $host "jdk"
    elif [ ! -z "$(ssh_tt $host "ss -lntp|awk '{print \$4}'|egrep '9092|2181'")" ];then
        rpm_e $host "qingteng-openjdk"
    else
        rpm_e $host "jdk"
    fi

    if [[ "$connect_ips" =~ "$host" ]];then
        for dir_list in ${dir_lists[@]};do
            delete_dir $host "$dir_list"
        done
    elif [ $args == "all" ];then
        for dir_list in ${dir_lists[@]};do
            delete_dir $host "$dir_list"
        done
    fi
}

uninstall_connect(){
    local host=$1
    local name=$2
    local dir_lists=("/usr/local/qingteng/arthas")
    local java_ips=$(get_role_hosts "java")
    local zk_ips=$(get_role_hosts "zookeeper")
    local kafka_ips=$(get_role_hosts "kafka")
    local check_ip_list="${zk_ips} ${java_ips} ${kafka_ips}"
    if [ "$args" == "all"  ];then
        rpm_e $host "qingteng-jdk|jdk1.8"
        for dir_list in ${dir_lists[@]};do
            delete_dir $host "$dir_list"
        done
    elif [[ ${check_ip_list} =~ ${host} ]];then
        info_log "don't uninstall jdk" 
    else
        rpm_e $host "qingteng-jdk|jdk1.8"
        for dir_list in ${dir_lists[@]};do
            delete_dir $host "$dir_list"
        done
    fi
}

uninstall_mongo(){
    local host=$1
    local name=$2
    [ $(get_role_number ${name}) -ge "3" ] && mongo_cluster="0" || mongo_cluster="1"
    local centos_version=$(ssh_tt $host "awk '{print \$(NF-1)}' /etc/redhat-release| cut -d\".\" -f1" )
    local dir_lists=("/data/titan-logs/mongodb" "/usr/local/qingteng/mongodb" "/data/titan-logs/mongodb" )
    local batch_files=("/usr/local/bin/mongo*" "/usr/local/bin/mongo*" "/run/systemd/generator.late/mongo*")
    local mongoserver_lists=$(ssh_tt $host "ls /etc/init.d/mongo*|egrep -v 'bak'|awk -F '/' '{print \$4}'")
    local rpm_lists="mongo"
    local file_lists=("/run/systemd/generator.late/runlevel5.target.wants/mongocluster.service" "/run/systemd/generator.late/runlevel3.target.wants/mongocluster.service" "/sys/fs/cgroup/systemd/system.slice/mongocluster.service" "/etc/init.d/mongod-bak" "/tmp/mongodb-27017.sock" )
    if [ $mongo_cluster == "0" ];then
        local back_dir_lists=("/data/mongodb" "/data/mongocluster" "/data/mongobackup")
    else
        local back_dir_lists=("/data/mongodb" "/data/mongobackup")
    fi
    
    if [ ! -z "$mongoserver_lists" ];then
        for  mongoserver_list in ${mongoserver_lists[@]};do
            stop_server $host $mongoserver_list
            kill_process $host $mongoserver_list 
            clean_chkconfig $host $mongoserver_list ${centos_version}
        done
    fi

    rpm_e $host ${rpm_lists}
    for back_dir_list in ${back_dir_lists[@]};do
        back_dir_file $host $back_dir_list
    done
    
    for batch_file in ${batch_files[@]};do
        delete_batch_file $host $batch_file
    done

    for dir_list in ${dir_lists[@]};do
        delete_dir $host $dir_list
    done
    
    for file_list in ${file_lists[@]};do
        delete_file $host $file_list
    done
    
}


uninstall_keepalived(){
    local host=$1
    local name=$2
    local dir_lists=("/etc/keepalived" "/usr/share/doc/keepalived-1.3.5")
    local centos_version=$(ssh_tt $host "awk '{print \$(NF-1)}' /etc/redhat-release| cut -d\".\" -f1" )
    local file_lists=("/etc/systemd/system/multi-user.target.wants/keepalived.service"
        "/etc/sysconfig/keepalived"
        "/etc/selinux/targeted/active/modules/100/keepalived"
        "/usr/sbin/keepalived"
        "/usr/lib/systemd/system/keepalived.service"
        "/usr/libexec/keepalived")
    stop_server $host $name
    kill_process $host $name
    clean_chkconfig $host $name $centos_version
    rpm_e $host $name

    for dir_list in ${dir_lists[@]};do
        delete_dir $host $dir_list
    done

    for file_list in ${file_lists[@]};do
        delete_file $host $file_list
    done

}

uninstall_by_role(){
    local name=$1
    local ip=$2

    if [[ -z ${ip} || ${ip} = "127.0.0.1" ]]; then
        error_log "Invalid IP ${ip} for ${name} server"
        return
    fi

    case ${name} in
        rabbitmq)
            uninstall_rabbitmq ${ip} ${name}
            ;;
        glusterfs)
            uninstall_glusterfs ${ip} ${name}
            ;;
        connect)
            uninstall_connect ${ip} ${name}
            ;;
        es|es_master|es_data)
            uninstall_es ${ip} ${name}
            ;;
        bigdata|logstash|viewer)
            uninstall_bigdata ${ip} ${name}
            ;;
        erproxy)
            uninstall_erproxy ${ip} ${name}
            ;;
        docker_scan)
            uninstall_java ${ip} ${name}
            ;;
        php)
            uninstall_php ${ip} ${name}
            ;;
        keepalived)
            uninstall_keepalived ${ip} ${name}
            ;;
        java|ms_srv|event_srv)
            uninstall_java ${ip} ${name}
            ;;
        mysql|mysql_php|mysql_erlang|mysql_master|mysql_slave)
            uninstall_mysql ${ip} ${name}
            ;;
        redis_java|redis_erlang|redis_php)
            uninstall_redis ${ip} ${name}
            ;;
        mongo_java|mongo_erlang|mongo_ms_srv)
            uninstall_mongo ${ip} ${name}
            ;;
        zookeeper|kafka)
			if [ ${name} == "zookeeper" ];then
				uninstall_zookeeper ${ip} ${name}
			elif [ ${name} == "kafka" ];then
				uninstall_kafka ${ip} ${name}
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

start(){
    if [ -f ${SERVER_IP_CONF} ]; then
        # distribute or install
        local flag=$1
        # local name=$2
        # default: all components
        local content=`cat ${SERVER_IP_CONF}`
        # specific components according to $1
        if [ $2 != all ]; then
            content=`cat ${SERVER_IP_CONF} |grep ^$2`
        fi
        if [ $2 == all -o $2 == glusterfs ]; then
            uninstall_glusterfs_client 
        fi
        [ ! -z "$(cat ${SERVER_IP_CONF}|grep 127.0.0.1)" ] && error_log "127.0.0.1 exists in service_ip.conf, please check"
        (IFS=$'\n';for line in ${content}; do
            local name=`echo ${line} | awk -F " " '{print $1}'`
            local host=`echo ${line} | awk -F" " '{print $2}'` 
            [ -f $ROOT/${name}_ips.tmp  ] && rm -rf $ROOT/${name}_ips.tmp
            [ -f $ROOT/${name}.tmp  ] && rm -rf $ROOT/${name}.tmp
            if [ $2 != all ];then clean_roles_hostname $host;fi		
            if [ "${flag}" == "uninstall" ]; then
                if [ $name == "vip" -o -z ${name} ];then
                    continue
                fi
                info_log2 "-------------------[${host}:]start uninstall $name------------------"
                uninstall_by_role ${name} ${host}                 
            fi 
            info_log "${name}  uninstalled"
        done;)
        if [ $? -ne 0 ]; then
            exit 1
        fi
    fi
}


main(){
    local name=$1
    local yes_cmd=(y Y yes Yes YES)
    local no_cmd=(n N no No NO)
    info_log "Do you want to uninstall ${name} [Y/N] ? default is N"
    until [[ "$flag" == "yes" || "$flag" == "no" ]]
    do
        read -p "Enter [Y/N]:" Enter
        if [ -z $Enter ];then Enter="N";fi
        if [[ "${yes_cmd[@]}" =~ "${Enter:N}" ]]; then
            flag="yes"
            break   
        elif [[ "${no_cmd[@]}" =~ "$Enter" ]];then
            flag="no"
            info_log "Cancel uninstall"
            exit 0
        else
            info_log "input error.Please enter [Y/N]"
            continue
        fi
    done
    echo "--------------------uninstall server --------------------"
    start uninstall ${name}

    if [ $? -ne 0 ]; then
        exit 1
    fi
}


clean_hostname(){
    if [ $1 == all ];then
        hosts=$(cat ${SERVER_IP_CONF}|egrep -v "^$|vip"|awk -F" " '{print $2}'|sort|uniq)
    else
        hosts=$(cat ${SERVER_IP_CONF}|egrep -w "$1"|awk -F" " '{print $2}'|sort|uniq)
    fi
    for host in ${hosts[@]};do
        local host_name=$(ssh_t $host "hostname -s"|sed 's/\r//g')
        ssh_t $host "sed -i '/^$host \?$host_name \+/d' /etc/hosts"
        ssh_t $host "sed -i '/^127.0.0.1 \?$host_name \+/d' /etc/hosts"
    done
}

clean_roles_hostname(){
    local host=$1
    local host_name=$(ssh_t $host "hostname -s"|sed 's/\r//g')
    ssh_t $host "sed -i '/^$host \?$host_name \+/d' /etc/hosts"
    ssh_t $host "sed -i '/^127.0.0.1 \?$host_name \+/d' /etc/hosts"
}

## ----------------------------Starting--------------------------- ##

[ $# -gt 0 ] || help $*
args=$1

while [ $# -gt 0 ]; do
    case $args in
        all)
            clean_hostname all
            main all
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
        event_srv)
            main event_srv
            exit 0
            ;;
        ms_srv)
            main ms_srv
            exit 0
            ;;
        zookeeper)
            main zookeeper
            exit 0
            ;;
        kafka)
            main kafka
            exit 0
            ;;
        mysql)
            main mysql
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
        mongo_java)
            main mongo_java
            exit 0
            ;;
        mongo_ms_srv)
            main mongo_ms_srv
            exit 0
            ;;
        glusterfs)
            main glusterfs
            exit 0
            ;;
        *)
            help $*
            exit 0
            ;;
    esac
done
exit 0 
