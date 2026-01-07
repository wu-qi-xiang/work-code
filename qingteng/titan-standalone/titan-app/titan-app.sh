#!/bin/bash


FILE_ROOT=`cd \`dirname $0\` && pwd`

source ${FILE_ROOT}/utils.sh

IS_UPGRADE=false

REMOTE_QT_PACKAGE_DIR=/data/qt_rpms

PHP_EXEC=/usr/local/php/bin/php
WEB_PATH=/data/app/www/titan-web
SERVER_EXEC=/data/app/titan-servers/bin/titan-server
Thunderfire_Engine_Path="/data/app/titan-upload-srv/cdc/webshell_engine"
INSTALL_PRE_PATH=/data
[ ! -f ${FILE_ROOT}/ip_template.json ] && error_log " Cannot found ${FILE_ROOT}/ip_template.json"

APP_VERSION_JSON=${FILE_ROOT}/version.json
IP_TEMPLATE=${FILE_ROOT}/ip_template.json
CUSTOMIZE_FILE=${FILE_ROOT}/CUSTOMIZE.json
REMOTE_DIR_IP_TEMPLATE=/data/app/www/titan-web/config_scripts

PACKAGE_TITAN_SERVER=(java_connect-dh java_connect-agent java_connect-sh)
PACKAGE_TITAN_WEB=(php_frontend_private
                    php_backend_private
                    php_agent_private
                    php_download_private
                    php_api_private
                    php_inner_api)

LOCAL_CERT_PATH=${FILE_ROOT}/cert
REMOTE_CERT_PATH=/data/app/conf/cert
LOCAL_CLUSTER_NGINX_PATH=${FILE_ROOT}/cluster
REMOTE_CLUSTER_NGINX_PATH=/data/app/conf/cluster

LOACL_ERL_MIGRATE_PATH=${FILE_ROOT}/erlang_migrate
REMOTE_ERL_MIGRATE_PATH=/data/servers/erlang_migrate

## --------------------------------------- Utils --------------------------------- ##

help() {
    echo "--------------------------------------------------------------------------"
    echo "                             Usage information                            "
    echo "--------------------------------------------------------------------------"
    echo ""
    echo "./titan-app.sh [Options]                                                  "
    echo "                                                                          "
    echo "Options:                                                                  "
    echo "  install (v3|v2)               installation and initialization           "
    echo "  upgrade (v3|v2)               upgrade application                       "
    echo "  upgrade_v2_to_v3              cross-version upgrade                     "
    echo "  distribute (v3|v2)            distribute rpm, then install              "
    echo "  config                        build config files                        "
    echo "  init_db                       create mysql database                     "
    echo "  launch (v3|v2)                start application                         "
    echo "  init_data                     sync rules & agent & bash                 "
    echo "  register (v3|v2)              register default account                  "
    echo "  update_rules                  sync rules                                "
    echo "  update_agent_url              update agent & bash url                   "
    echo "  restart_php                   restart php server                        "
    echo "  start_erlang                  restart all erlang services               "
    echo "  stop_erlang                   stop all erlang services                  "
    echo "  start_server                  restart titan-server                      "
    echo "  stop_server                   stop titan-server                         "
    echo "  start_java                    start java server                         "
    echo "  stop_java                     stop java server                          "
    echo "  start_bigdata                 start bigdata server                      "
    echo "  stop_bigdata                  stop bigdata server                       "
    echo "  start_docker_scan             start docker scan server                  "
    echo "  stop_docker_scan              stop docker scan server                   "
    echo "  start_anti_virus              start anti_virus server                   "
    echo "  stop_anti_virus               stop anti_virus server                    "
    echo "  dump                          backup mysql database                     "
    echo "  db_merge                      merge db while upgrade from v2 to v3      "
    echo "  jdb_flush                     flush java mongodb                        "
    echo "  cleancache                    clean cache for java                      "
    echo "  switchcompany mainID subID    switch company when upgrade from v2 to v3 "
    echo "  update_rules                  upgrade rules                             "
    echo "  update_license                update license info                       "
    echo "  change_wisteria_memory        change java memory                        "
    echo "  backup_config                 backup all config file                    "
    echo "  java_v320_update              update java                               "
    echo "  init_headquarters             init headquarters env                     "
    echo "  init_datasync                 init datasync env                         "
    echo "  alter_thp_config              change kafka  topic config                "
    echo "  update_thunderfire            update thunderfire files                  "
    echo "  uninstall_ms                  only uninstall ms_srv                     " 
    echo "                                                                          "
    echo "  Example:                                                                "
    echo "    ./titan-app.sh install v3                                             "
    echo "    ./titan-app.sh upgrade v3                                             "
    echo "    ./titan-app.sh upgrade_v2_to_v3                                       "
    echo "--------------------------------------------------------------------------"
    exit 1
}

setup_np_ssh_erlang(){
    local np_done=""
    for node in ${PACKAGE_TITAN_SERVER[*]};
    do
        local ip=`get_ip ${node}`
        if [ -z `echo ${np_done} |grep ${ip}` ]; then
            set_np_authorized ${ip}
            np_done="${np_done}**${ip}"
        fi
    done
}

## --------------- Backup ----------------##
backup_config(){
    role_mongo=(db_mongo_java)
    role_redis=(db_redis_erlang db_redis_java db_redis_php)
    role_mysql=(db_mysql_php)
    role_java=(java java_job-srv java_gateway java_user-srv java_detect-srv java_scan-srv java_anti-virus-srv java_upload-srv java_kafka java_zookeeper)
    role_connect=(java_connect-sh java_connect-agent java_connect-selector java_connect-dh)
    role_php=(php_frontend_private php_api_private)
    role_bigdata=(bigdata_logstash bigdata_viewer)
    role_java_src=(java_ms-srv java_event-srv)

    bak_dir=`date +%Y%m%d-%H%M%S`
    for role in ${role_mongo[*]} ${role_redis[*]} ${role_mysql[*]} ${role_java[*]} ${role_java_src[*]} ${role_connect[*]} ${role_php[*]} ${role_bigdata[*]};do
        ips=`get_ips $role`
        for ip in ${ips[@]} ; do
            if [ "$ip" == "" ];then 
                continue
            fi

            [ -f "/data/backup/system/$bak_dir/$ip" ] || mkdir -p /data/backup/system/$bak_dir/$ip
            case $role in
                db_mongo_erlang|db_mongo_java)
                    remote_scp_to_file $ip /usr/local/qingteng/mongodb/conf/mongod.conf /data/backup/system/$bak_dir/$ip
                ;;
                db_redis_erlang)
                    remote_scp_to_file $ip /etc/redis/6379.conf /data/backup/system/$bak_dir/$ip
                ;;
                db_redis_php)
                    remote_scp_to_file $ip /etc/redis/6380.conf /data/backup/system/$bak_dir/$ip
                ;;
                db_redis_java)
                    remote_scp_to_file $ip /etc/redis/6381.conf /data/backup/system/$bak_dir/$ip
                ;;
                db_mysql_php)
                    remote_scp_to_file $ip /etc/my.cnf /data/backup/system/$bak_dir/$ip
                ;;
                java)
                    remote_scp_to_file $ip /data/app/titan-config/java.json /data/backup/system/$bak_dir/$ip
                    remote_scp_to_file $ip /data/app/titan-wisteria/wisteria.conf /data/backup/system/$bak_dir/$ip
                ;;
                java_job-srv)
                    remote_scp_to_file $ip /data/app/titan-config/job.json /data/backup/system/$bak_dir/$ip
                    remote_scp_to_file $ip /data/app/titan-job-srv/job-srv.conf /data/backup/system/$bak_dir/$ip
                ;;
                java_user-srv)
                    remote_scp_to_file $ip /data/app/titan-user-srv/user-srv.conf /data/backup/system/$bak_dir/$ip
                ;;
                java_upload-srv)
                    remote_scp_to_file $ip /data/app/titan-upload-srv/upload-srv.conf /data/backup/system/$bak_dir/$ip
                ;;
                java_detect-srv)
                    remote_scp_to_file $ip /data/app/titan-detect-srv/detect-srv.conf /data/backup/system/$bak_dir/$ip
                ;;
                java_scan-srv)
                    remote_scp_to_file $ip /data/app/titan-config/java.json /data/backup/system/$bak_dir/$ip 
                    remote_scp_to_file $ip /data/app/titan-scan-srv/scan-srv.conf /data/backup/system/$bak_dir/$ip
                ;;
                java_anti-virus-srv)
                    remote_scp_to_file $ip /data/app/titan-config/java.json /data/backup/system/$bak_dir/$ip 
                    remote_scp_to_file $ip /data/app/titan-anti-virus-srv/anti-virus-srv.conf /data/backup/system/$bak_dir/$ip
                ;;
                java_ms-srv)
                    remote_scp_to_file $ip /data/app/titan-config/java.json /data/backup/system/$bak_dir/$ip
                    remote_scp_to_file $ip /data/app/titan-ms-srv/ms-srv.conf /data/backup/system/$bak_dir/$ip
                    remote_scp_to_file $ip /data/app/titan-ms-srv/custom.yml /data/backup/system/$bak_dir/$ip
                    remote_scp_to_file $ip /data/app/titan-ms-srv/application.yml /data/backup/system/$bak_dir/$ip
                ;;
                java_event-srv)
                    remote_scp_to_file $ip /data/app/titan-event-srv/event-srv.conf /data/backup/system/$bak_dir/$ip
                ;;
                java_gateway)
                    remote_scp_to_file $ip /data/app/titan-gateway/gateway.conf /data/backup/system/$bak_dir/$ip
                ;;
                java_kafka)
                    remote_scp_to_file $ip /usr/local/qingteng/kafka/config/server.properties  /data/backup/system/$bak_dir/$ip
                    remote_scp_to_file $ip /usr/local/qingteng/kafka/config/kafka.env  /data/backup/system/$bak_dir/$ip
                ;;
                java_zookeeper)
                    remote_scp_to_file $ip /usr/local/qingteng/zookeeper/conf/zoo.cfg  /data/backup/system/$bak_dir/$ip
                    remote_scp_to_file $ip /usr/local/qingteng/zookeeper/conf/java.env  /data/backup/system/$bak_dir/$ip
                    remote_scp_to_file $ip /usr/local/qingteng/zookeeper/conf/jaas_zk.conf  /data/backup/system/$bak_dir/$ip
                ;;
                java_connect-sh)
                    remote_scp_to_file $ip /data/app/titan-config/sh.json /data/backup/system/$bak_dir/$ip
                    remote_scp_to_file $ip /data/app/titan-connect-sh/connect-sh.conf /data/backup/system/$bak_dir/$ip
                ;;
                java_connect-agent)
                    remote_scp_to_file $ip /data/app/titan-connect-agent/connect-agent.conf /data/backup/system/$bak_dir/$ip
                ;;
                java_connect-selector)
                    remote_scp_to_file $ip /data/app/titan-connect-selector/connect-selector.conf /data/backup/system/$bak_dir/$ip
                    remote_scp_to_file $ip /data/app/titan-config/selector.json /data/backup/system/$bak_dir/$ip
                ;;
                java_connect-dh)
                    remote_scp_to_file $ip /data/app/titan-connect-dh/connect-dh.conf /data/backup/system/$bak_dir/$ip
                ;;
                php_frontend_private|php_api_private)
                    remote_scp_to_file $ip /data/app/conf/nginx.location.conf /data/backup/system/$bak_dir/$ip
                    remote_scp_to_file $ip /data/app/conf/nginx.servers.conf /data/backup/system/$bak_dir/$ip
                    remote_scp_to_file $ip /data/app/conf/cert/using.key /data/backup/system/$bak_dir/$ip
                    remote_scp_to_file $ip /data/app/conf/cert/using.pem /data/backup/system/$bak_dir/$ip
                    remote_scp_to_file $ip /data/app/conf/proxy/nginx.proxy.conf /data/backup/system/$bak_dir/$ip
                    remote_scp_to_file $ip /data/app/www/titan-web/conf/build.json /data/backup/system/$bak_dir/$ip
                    remote_scp_to_file $ip /data/app/www/titan-web/conf/product/application.ini /data/backup/system/$bak_dir/$ip
                    remote_scp_to_file $ip /data/app/www/titan-web/config_scripts/ip.json /data/backup/system/$bak_dir/$ip
                    remote_scp_to_file $ip /data/app/www/titan-web/config_scripts/ip_template.json /data/backup/system/$bak_dir/$ip
                    remote_scp_to_file $ip /data/app/titan-patrol-srv/patrol-srv.conf /data/backup/system/$bak_dir/$ip
                    remote_scp_to_file $ip /data/app/titan-patrol-srv/patrol_backup_json.conf /data/backup/system/$bak_dir/$ip
                    remote_scp_to_file $ip /data/app/titan-patrol-srv/patrol_json.conf /data/backup/system/$bak_dir/$ip
                ;;
                bigdata_logstash)
                    remote_scp_to_file $ip /usr/local/qingteng/bigdata/qt_consumer/conf/consumer.yml /data/backup/system/$bak_dir/$ip
                    remote_scp_to_file $ip /usr/local/qingteng/logstash/logstash.keystore /data/backup/system/$bak_dir/$ip
                ;;
                bigdata_viewer)
                    remote_scp_to_file $ip /usr/local/qingteng/bigdata/qt_viewer/config.yml /data/backup/system/$bak_dir/$ip
                ;;
                *)
                ;;
            esac
        done
    done

    local php_hosts=`get_ips php_inner_api`
    for php_host in ${php_hosts[@]} ; do
        execute_rsync ${php_host} /data/backup/system/ /data/backup/system/
    done
}

java_v320_update(){
    java_host=`get_ip java`
    if [ "$1" != "" ];then
    ssh_t ${java_host}  "\
    cd /data/app/upgradeTool && \
    /usr/local/qingteng/python2.7/bin/python upgrade.py  --type standalone byVersion --fromVer $1 --toVer 3.2.0"
    check "java v$1 update v3.2.0"
    else
    ssh_t ${java_host}  "\
    cd /data/app/upgradeTool && \
    /usr/local/qingteng/python2.7/bin/python upgrade.py  --type standalone byVersion --fromVer 3.0.6 --toVer 3.2.0"
    check "java v306 update v3.2.0"
    fi
}

create_install_json(){
    local host=$1
    if [ ! -f ${APP_VERSION_JSON} ]; then
        error_log "Not found version.json file."
        exit 1
    fi
    ssh_t ${host} "[ -f /data/install/installing.json ] && echo -e '  \"app\":' >> /data/install/installing.json"
    ssh_t ${host} "cat \"$APP_VERSION_JSON\" >> /data/install/installing.json"

    check "create install json"
}


## --------------- Distribution & Installation ------------------- ##

distribute_connect_agent(){

        distribute_webinstall_connect_agent
	
	if [ $deploy_status == "install" -o $deploy_status == "webinstall" ];then
		##----------java license-------------##
                update_titan_license
	fi
}

distribute_webinstall_connect_agent(){
        local connect_agent_ips=`get_ips java_connect-agent`
        [ -z "${connect_agent_ips}" ] && error_log "connect_agent_ip's ip is empty"
        for connect_agent_ip in ${connect_agent_ips[@]} ; do
            uninstall_rpm ${connect_agent_ip} titan-java-lib
            local rpm_connect_agent=`echo ${FILE_ROOT}/*/titan-connect-agent*.rpm`
            if [ "$connect_agent_ip" != "127.0.0.1" ];then
                # distribute
                execute_rsync ${connect_agent_ip} ${rpm_connect_agent} ${REMOTE_QT_PACKAGE_DIR}
                # install
                install_rpm ${connect_agent_ip} ${rpm_connect_agent##*/}
            fi
        done
}

distribute_connect_dh(){
        local connect_dh_ips=`get_ips java_connect-dh`
        [ -z "${connect_dh_ips}" ] && error_log "connect_dh_ip's ip is empty"
        for connect_dh_ip in ${connect_dh_ips[@]} ; do
            uninstall_rpm ${connect_dh_ip} titan-java-lib
            local rpm_connect_dh=`echo ${FILE_ROOT}/*/titan-connect-dh*.rpm`
            if [ "$connect_dh_ip" != "127.0.0.1" ];then
                # distribute
                execute_rsync ${connect_dh_ip} ${rpm_connect_dh} ${REMOTE_QT_PACKAGE_DIR}
                # install
                install_rpm ${connect_dh_ip} ${rpm_connect_dh##*/}
            fi
        done
}
distribute_connect_sh(){
        local connect_sh_ips=`get_ips java_connect-sh`
        [ -z "${connect_sh_ips}" ] && error_log "connect_sh_ip's ip is empty"
        for connect_sh_ip in ${connect_sh_ips[@]} ; do
            uninstall_rpm ${connect_sh_ip} titan-java-lib
            local rpm_connect_sh=`echo ${FILE_ROOT}/*/titan-connect-sh*.rpm`
            if [ "$connect_sh_ip" != "127.0.0.1" ];then
                # distribute
                execute_rsync ${connect_sh_ip} ${rpm_connect_sh} ${REMOTE_QT_PACKAGE_DIR}
                # install
                install_rpm ${connect_sh_ip} ${rpm_connect_sh##*/}
            fi
        done
}
distribute_connect_selector(){
        local connect_selector_ips=`get_ips java_connect-selector`
        [ -z "${connect_selector_ips}" ] && error_log "connect_selector_ip's ip is empty"
        for connect_selector_ip in ${connect_selector_ips[@]} ; do
            uninstall_rpm ${connect_selector_ip} titan-java-lib
            local rpm_connect_selector=`echo ${FILE_ROOT}/*/titan-connect-selector*.rpm`
            if [ "$connect_selector_ip" != "127.0.0.1" ];then
                # distribute
                execute_rsync ${connect_selector_ip} ${rpm_connect_selector} ${REMOTE_QT_PACKAGE_DIR}
                # install
                install_rpm ${connect_selector_ip} ${rpm_connect_selector##*/}
            fi
        done
}


distribute_titan_web(){

    local package_sent=""
    for node in ${PACKAGE_TITAN_WEB[*]};
    do
        local ips=`get_ips ${node}`

        [ -z "${ips}" ] && error_log "${node}'s ip is empty"

        for ip in ${ips[@]} ; do
            if [ -z "`echo ${package_sent} |grep ${ip}`" ]; then
                local rpm_web=`echo ${FILE_ROOT}/*/titan-web-*.rpm`
                local rpm_agent=`echo ${FILE_ROOT}/*/titan-agent-*.rpm`
                local rpm_patrol=`echo ${FILE_ROOT}/*/titan-patrol-srv-*.rpm`
                # distribute
                execute_rsync ${ip} ${rpm_web} ${REMOTE_QT_PACKAGE_DIR}
                uninstall_rpm  ${ip} titan-web
                execute_rsync ${ip} ${rpm_agent} ${REMOTE_QT_PACKAGE_DIR}
                execute_rsync ${ip} ${rpm_patrol} ${REMOTE_QT_PACKAGE_DIR}
                # install
                if [ -f ${APP_VERSION_JSON} ]; then
                    ssh_t ${ip} "sudo mkdir -p /data/install/"
                    #scp ${APP_VERSION_JSON}  ${ip}:/data/install/app-version.json
                    rsync -rz --rsync-path="sudo rsync" -e "ssh -p $DEFAULT_PORT"  --delete ${APP_VERSION_JSON} ${DEFAULT_USER}@${ip}:/data/install/app-version.json
                fi

                # get the value of product_name,
                # keep it, then restore after upgrade
                local customer=`get_ip product_name`
                install_rpm ${ip} ${rpm_web##*/}
                install_rpm ${ip} ${rpm_agent##*/}
                install_rpm ${ip} ${rpm_patrol##*/}
                #if docker is disable then delete Docker Plugin
                if [ "${IS_DOCKER}" = "false" ]; then
                    ssh_t ${ip} "sudo sed -i \"/Docker/d\"  /data/app/www/agent-update/*/ver.txt"
                fi
                # restore
                [ -n "${customer}" ] && ssh_t ${ip} "\
                sudo sed -i \"s/\"product_name\":.*/\"product_name\": \"${customer}\",/\" /data/app/www/titan-web/conf/build.json"

                package_sent="${package_sent}@${ip}"
            fi
        done
    done
}

distribute_webinstall_titan_web(){

    local package_sent=""
    for node in ${PACKAGE_TITAN_WEB[*]};
    do
        local ip=`get_ip ${node}`

        [ -z "${ip}" ] && error_log "${node}'s ip is empty"

        if [ -z "`echo ${package_sent} |grep ${ip}`" ]; then
            local rpm_web=`echo ${FILE_ROOT}/*/titan-web-*.rpm`
            # distribute
            execute_rsync ${ip} ${rpm_web} ${REMOTE_QT_PACKAGE_DIR}
            uninstall_rpm  ${ip} titan-web

            # get the value of product_name,
            # keep it, then restore after upgrade
            local customer=`get_ip product_name`
            install_rpm ${ip} ${rpm_web##*/}
            # restore
            [ -n "${customer}" ] && ssh_t ${ip} "\
            sudo sed -i \"s/\"product_name\":.*/\"product_name\": \"${customer}\",/\" /data/app/www/titan-web/conf/build.json"

            package_sent="${package_sent}@${ip}"
        fi
    done
}

distribute_titan_agent(){

    local package_sent=""
    for node in ${PACKAGE_TITAN_WEB[*]};
    do
        local ips=`get_ips ${node}`

        [ -z "${ips}" ] && error_log "${node}'s ip is empty"

        for ip in ${ips[@]} ; do
            if [ -z "`echo ${package_sent} |grep ${ip}`" ]; then
                local rpm_agent=`echo ${FILE_ROOT}/*/titan-agent-*.rpm`
                # distribute
                execute_rsync ${ip} ${rpm_agent} ${REMOTE_QT_PACKAGE_DIR}
                # install
                install_rpm ${ip} ${rpm_agent##*/}
                package_sent="${package_sent}@${ip}"
            fi
        done
    done
}

distribute_bigdata_logstash(){

    local bigdata_logstash_ips=`get_ips bigdata_logstash`

    for bigdata_logstash_ip in ${bigdata_logstash_ips[@]} ; do
        if [ "$bigdata_logstash_ip" != "127.0.0.1" ];then
            # distribute
            ssh_t $bigdata_logstash_ip "sudo chkconfig qingteng-consumer off && sudo chkconfig --del qingteng-consumer"
            # uninstall consumer 
            uninstall_rpm  ${bigdata_logstash_ip} qingteng-consumer
            ssh_t $bigdata_logstash_ip "sudo chkconfig --add logstash  && sudo chkconfig logstash on"
            ssh_t ${bigdata_logstash_ip} "[ -d /var/log/bigdata ] || sudo mkdir /var/log/bigdata && sudo chown bigdata:bigdata -R /var/log/bigdata"
        fi
    done
}

distribute_bigdata_viewer(){

    local bigdata_viewer_ips=`get_ips bigdata_viewer`

    for bigdata_viewer_ip in ${bigdata_viewer_ips[@]} ; do
        if [ "$bigdata_viewer_ip" != "127.0.0.1" ];then
            # install
            ssh_t ${bigdata_viewer_ip} "[ -d /var/log/bigdata ] || sudo mkdir /var/log/bigdata && sudo chown bigdata:bigdata -R /var/log/bigdata"
        fi
    done
}


distribute_bigdata(){

    distribute_bigdata_logstash
    distribute_bigdata_viewer
}


distribute_scan(){

    local scan_ips=`get_ips java_scan-srv`

    [ -z "${scan_ips}" ] && info_log "java_scan-srv's ip is empty,will not install"

    for scan_ip in ${scan_ips[@]} ; do
        uninstall_rpm ${scan_ip} titan-java-lib

        local rpm_scan=`echo ${FILE_ROOT}/*/titan-scan-srv-*.rpm`

        if [ "$scan_ip" != "127.0.0.1" ];then
            # distribute
            execute_rsync ${scan_ip} ${rpm_scan} ${REMOTE_QT_PACKAGE_DIR}
            # install
            install_rpm ${scan_ip} ${rpm_scan##*/}
        fi
    done
}

distribute_anti_virus(){

    local anti_virus_ips=`get_ips java_anti-virus-srv`

    [ -z "${anti_virus_ips}" ] && info_log "java_anti-virus-srv's ip is empty,will not install"

    for anti_virus_ip in ${anti_virus_ips[@]} ; do
        uninstall_rpm ${anti_virus_ip} titan-java-lib

        local rpm_anti_virus=`echo ${FILE_ROOT}/*/titan-anti-virus-srv-*.rpm`

        if [ "$anti_virus_ip" != "127.0.0.1" ];then
            # distribute
            execute_rsync ${anti_virus_ip} ${rpm_anti_virus} ${REMOTE_QT_PACKAGE_DIR}
            # install
            install_rpm ${anti_virus_ip} ${rpm_anti_virus##*/}
        fi
    done
}

distribute_ms(){

    local ms_ips=`get_ips java_ms-srv`

    [ -z "${ms_ips}" ] && info_log "java_ms-srv's ip is empty,will not install"

    for ms_ip in ${ms_ips[@]} ; do
        uninstall_rpm ${ms_ip} titan-java-lib

        local rpm_ms=`echo ${FILE_ROOT}/*/titan-ms-srv-*.rpm`

        if [ "$ms_ip" != "127.0.0.1" ];then
            # distribute
            execute_rsync ${ms_ip} ${rpm_ms} ${REMOTE_QT_PACKAGE_DIR}
            # install
            install_rpm ${ms_ip} ${rpm_ms##*/}
        fi
    done
}

distribute_event(){

    local event_ips=`get_ips java_event-srv`

    [ -z "${event_ips}" ] && info_log "java_event-srv's ip is empty,will not install"

    for event_ip in ${event_ips[@]} ; do
        uninstall_rpm ${event_ip} titan-java-lib

        local rpm_event=`echo ${FILE_ROOT}/*/titan-event-srv-*.rpm`

        if [ "$event_ip" != "127.0.0.1" ];then
            # distribute
            execute_rsync ${event_ip} ${rpm_event} ${REMOTE_QT_PACKAGE_DIR}
            # install
            install_rpm ${event_ip} ${rpm_event##*/}
        fi
    done
}


distribute_titan_wisteria(){
    local java_ips=`get_ips java`
    local php_ip=`get_ip php_inner_api`

    [ -z "${java_ips}" ] && error_log "java's ip is empty"

    for java_ip in ${java_ips[@]} ; do
        #delete java-lib
        uninstall_rpm  ${java_ip} titan-java-lib
        #execute_rsync ${java_ip}  ${FILE_ROOT}/setup_np_ssh.sh /tmp
        #ssh_t ${java_ip} "sudo bash /tmp/setup_np_ssh.sh ${DEFAULT_USER}@${php_ip} ${DEFAULT_PORT}"

        local rpm_java=`echo ${FILE_ROOT}/*/titan-wisteria-*.rpm`
        execute_rsync ${java_ip} ${rpm_java} ${REMOTE_QT_PACKAGE_DIR}
        install_rpm ${java_ip} ${rpm_java##*/}
    done

}

distribute_webinstall_titan_wisteria(){
    local java_ip=`get_ip java`
    local php_ip=`get_ip php_inner_api`

    [ -z "${java_ip}" ] && error_log "java's ip is empty"
    uninstall_rpm ${java_ip} titan-java-lib

    local rpm_java=`echo ${FILE_ROOT}/*/titan-wisteria-*.rpm`
    execute_rsync ${java_ip} ${rpm_java} ${REMOTE_QT_PACKAGE_DIR}
    install_rpm ${java_ip} ${rpm_java##*/}
}


distribute_config_thp(){
    local config_sent=""
    for node in ${PACKAGE_TITAN_WEB[*]};
    do
        local ips=`get_ips ${node}`

        [ -z "${ips}" ] && error_log "${node}'s ip is empty"

        for ip in ${ips[@]} ; do
            if [ -z "`echo ${config_sent} |grep ${ip}`" ]; then

                # ip_template.json
                ssh_t ${ip} "cd /data/app/www/titan-web/config_scripts && \
                [ -f ip.json ] && sudo mv ip.json ip.json_bak"
                execute_rsync ${ip}  ${IP_TEMPLATE} ${REMOTE_DIR_IP_TEMPLATE}
                ssh_t ${ip} "cd /data/app/www/titan-web/config_scripts && \
                [ ! -f ip.json ] && sudo cp -rf ip_template.json ip.json"
                execute_rsync ${ip}  ${CUSTOMIZE_FILE} ${REMOTE_DIR_IP_TEMPLATE}
                config_sent="${config_sent}@${ip}"
            fi
        done
    done
}




distribute_config(){
    local config_sent=""
    local channal_change_status="false"
    local channal_ip="`grep -rlE 'erl_channel_private' /data/backup/system* | grep ip_template.json$ | xargs ls -t |head -n 1 | grep ip_template.json$ | xargs cat |grep erl_channel_private | cut -d: -f 2 | tr -d '", '`"
    for node in ${PACKAGE_TITAN_WEB[*]};
    do
        local ips=`get_ips ${node}`        
        [ -z "${ips}" ] && error_log "${node}'s ip is empty"

        for ip in ${ips[@]} ; do
        if [ ! -z "${channal_ip}" -a "${channal_ip}" != "${ip}" -a "${channal_change_status}" == "false" ]; then
            execute_rsync ${channal_ip} ${LOCAL_CERT_PATH}/ ${REMOTE_CERT_PATH}
            ssh_t  ${channal_ip} "sudo service nginx restart"
            channal_change_status="true"
        fi 
            if [ -z "`echo ${config_sent} |grep ${ip}`" ]; then
                # ssl certifications
                execute_rsync ${ip} ${LOCAL_CERT_PATH}/ ${REMOTE_CERT_PATH}
                execute_rsync ${ip} ${LOCAL_CLUSTER_NGINX_PATH}/ ${REMOTE_CLUSTER_NGINX_PATH}

                # ip_template.json
                ssh_t ${ip} "cd /data/app/www/titan-web/config_scripts && \
                [ -f ip.json ] && sudo mv ip.json ip.json_bak"
                execute_rsync ${ip}  ${IP_TEMPLATE} ${REMOTE_DIR_IP_TEMPLATE}
                execute_rsync ${ip}  ${CUSTOMIZE_FILE} ${REMOTE_DIR_IP_TEMPLATE}
                config_sent="${config_sent}@${ip}"
            fi
        done
    done
}



install_rpm(){
    local host=$1
    local rpm=$2
    ssh_t ${host} "cd $REMOTE_QT_PACKAGE_DIR && sudo rpm -ivh --force ${rpm}"
    check "Install ${rpm} on ${host} "
}

uninstall_rpm(){
    local host=$1
    local rpm=$2
    ssh_t ${host} "rpm -aq|grep "${rpm}"|xargs -i sudo rpm -e {} >/dev/null 2>&1"
    if [ "${rpm}" == "qingteng-consumer" ];then
            if [ ! -z "`ssh_t ${host} 'rpm -aq|grep qingteng-bigdata'`" ];then
                ssh_t ${host} "rpm -aq|grep \"qingteng-bigdata\"|xargs -i sudo rpm -e {} >/dev/null 2>&1"
            fi
        ssh_t ${host} "sudo rm -rf /usr/local/qingteng/bigdata/qt_consumer"
    fi
    check "Uninstall ${rpm} on ${host} "

}

## -------------------------- Launch ----------------------------- ##

launch_erlang_node(){
    local host=$1
    local app=$2
    local req_async=false

    local cmd=""

    if [ -z $3 ]; then
        cmd="sudo ${app} stop &> /dev/null && sudo ${app} hp"
    else
        case $3 in
            om_node|dh_node|sh_node)
                local id=$4
                local num=$5
                if [ -z "${id}" ];then
                    cmd="sudo ${app} stop &> /dev/null && sudo ${app} -r $3 hp"
                else
                    cmd="sudo ${app} stop &> /dev/null && sudo ${app} -r $3 -id $4 -n $5"
                    req_async=true
                fi
                ;;
            [1-9]*)
                # $3 is number
                local num=$4
                cmd="sudo ${app} stop &> /dev/null && sudo ${app} -id $3 -n $4"
                req_async=true
                ;;
            *)
                error_log "launch_erlang_node($*)"
                exit 1
                ;;
        esac
    fi

    if [ ${req_async} = "false" ]; then
        ssh_tt ${host} "\
        sudo grep -q \"alias to_erl\" /root/.bashrc || \
        echo \"alias to_erl='erl_call() { TO_ERL=\\\`ls -d /root/*_root/*_server/titan_otp/otp-*/priv/pkg/bin/to_erl|head -1\\\`; \\\$TO_ERL \\\$1; }; erl_call'\" |sudo tee -a /root/.bashrc; \
        ${cmd} || exit 1"
    else
        ssh_tt ${host} "\
        sudo grep -q \"alias to_erl\" /root/.bashrc || \
        echo \"alias to_erl='erl_call() { TO_ERL=\\\`ls -d /root/*_root/*_server/titan_otp/otp-*/priv/pkg/bin/to_erl|head -1\\\`; \\\$TO_ERL \\\$1; }; erl_call'\" |sudo tee -a /root/.bashrc; \
        ${cmd} || exit 1" &
    fi

}

start_server_role(){
    local app=$1
    local node=$2

    case ${node} in
        sh_node)
            local ip_1=`get_ip erl_sh_1_private`
            local ip_2=`get_ip erl_sh_2_private`
            ;;
        dh_node)
            local ip_1=`get_ip erl_dh_1`
            local ip_2=`get_ip erl_dh_2`
            ;;
        om_node)
            local ip_1=`get_ip erl_om_1`
            local ip_2=`get_ip erl_om_2`
            ;;
        *)
            error_log "start_server_node($*)"
            exit 1
            ;;
    esac

    if [ ${ip_1} = ${ip_2}  ]; then
        launch_erlang_node ${ip_1} ${app} ${node}
    else
        launch_erlang_node ${ip_1} ${app} ${node} 1 1
        sleep 5
        launch_erlang_node ${ip_2} ${app} ${node} 2 2
    fi
    wait
}

### TODO:
start_titan_server() {

    local ips=""
    local num=0
    for node in ${PACKAGE_TITAN_SERVER[*]};
    do
        local ip=`get_ip ${node}`
        if [ -z `echo ${ips} |grep ${ip}` ]; then
            ips="${ips}*${ip}"
            let num++
        fi
    done

    ## num=1: om dh sh installed on one machine
    if [ ${num} -eq 1 ]; then
        launch_erlang_node `echo ${ips} |awk -F "*" '{print $2}'` ${SERVER_EXEC}
    else
        start_server_role ${SERVER_EXEC} om_node
        start_server_role ${SERVER_EXEC} dh_node
        start_server_role ${SERVER_EXEC} sh_node
    fi

}

start_titan_selector(){
    local sl_ip=`get_ip erl_selector_private`
    local selector=/data/app/titan-selector/bin/selector

    launch_erlang_node ${sl_ip} ${selector}
    wait
}


start_connect_agent(){
    local connect_agent_ips=`get_ips java_connect-agent`
    for connect_agent_ip in ${connect_agent_ips[@]} ; do
        if [ "$connect_agent_ip" != "127.0.0.1" ];then
            ssh_t ${connect_agent_ip} "sudo chmod 755 -R /data/app/titan-config && sudo service connect-agent restart"
        fi
    done
}

stop_connect_agent(){
    local connect_agent_ips=`get_ips java_connect-agent`
    for connect_agent_ip in ${connect_agent_ips[@]} ; do
        if [ "$connect_agent_ip" != "127.0.0.1" ];then
            ssh_t ${connect_agent_ip} "sudo service connect-agent stop"
        fi
    done
}

start_connect_sh(){
    local connect_sh_ips=`get_ips java_connect-sh`
    for connect_sh_ip in ${connect_sh_ips[@]} ; do
        if [ "$connect_sh_ip" != "127.0.0.1" ];then
            ssh_t ${connect_sh_ip} "sudo chmod 755 -R /data/app/titan-config && sudo service connect-sh restart"
        fi
    done
}

stop_connect_sh(){
    local connect_sh_ips=`get_ips java_connect-sh`
    for connect_sh_ip in ${connect_sh_ips[@]} ; do
        if [ "$connect_sh_ip" != "127.0.0.1" ];then
            ssh_t ${connect_sh_ip} "sudo service connect-sh stop"
        fi
    done
}
start_connect_dh(){
    local connect_dh_ips=`get_ips java_connect-dh`
    for connect_dh_ip in ${connect_dh_ips[@]} ; do
        if [ "$connect_dh_ip" != "127.0.0.1" ];then
            ssh_t ${connect_dh_ip} "sudo chmod 755 -R /data/app/titan-config && sudo service connect-dh restart"
        fi
    done
}

stop_connect_dh(){
    local connect_dh_ips=`get_ips java_connect-dh`
    for connect_dh_ip in ${connect_dh_ips[@]} ; do
        if [ "$connect_dh_ip" != "127.0.0.1" ];then
            ssh_t ${connect_dh_ip} "sudo service connect-dh stop"
        fi
    done
}
start_connect_selector(){
    local connect_selector_ips=`get_ips java_connect-selector`
    for connect_selector_ip in ${connect_selector_ips[@]} ; do
        if [ "$connect_selector_ip" != "127.0.0.1" ];then
            ssh_t ${connect_selector_ip} "sudo chmod 755 -R /data/app/titan-config && sudo service connect-selector restart"
        fi
    done
}
stop_connect_selector(){
    local connect_selector_ips=`get_ips java_connect-selector`
    for connect_selector_ip in ${connect_selector_ips[@]} ; do
        if [ "$connect_selector_ip" != "127.0.0.1" ];then
            ssh_t ${connect_selector_ip} "sudo service connect-selector stop"
        fi
    done
}
start_docker_scan(){
    local scan_ips=`get_ips java_scan-srv`
    for scan_ip in ${scan_ips[@]} ; do
        if [ "$scan_ip" != "127.0.0.1" ];then
            ssh_t ${scan_ip} "sudo chmod 755 -R /data/app/titan-config && sudo service scan-srv restart"
        fi
    done
}

stop_docker_scan(){
    local scan_ips=`get_ips java_scan-srv`
    for scan_ip in ${scan_ips[@]} ; do
        if [ "$scan_ip" != "127.0.0.1" ];then
            ssh_t ${scan_ip} "sudo service scan-srv stop"
        fi
    done
}

start_anti_virus(){
    local anti_virus_ips=`get_ips java_anti-virus-srv`
    for anti_virus_ip in ${anti_virus_ips[@]} ; do
        if [ "$anti_virus_ip" != "127.0.0.1" ];then
            ssh_t ${anti_virus_ip} "sudo chmod 755 -R /data/app/titan-config && sudo service anti-virus-srv restart"
        fi
    done
}

stop_anti_virus(){
    local anti_virus_ips=`get_ips java_anti-virus-srv`
    for anti_virus_ip in ${anti_virus_ips[@]} ; do
        if [ "$anti_virus_ip" != "127.0.0.1" ];then
            ssh_t ${anti_virus_ip} "sudo service anti-virus-srv stop"
        fi
    done
}

start_ms_srv(){
    local ms_ips=`get_ips java_ms-srv`
    for ms_ip in ${ms_ips[@]} ; do
        if [ "$ms_ip" != "127.0.0.1" ];then
            ssh_t ${ms_ip} "sudo chmod 755 -R /data/app/titan-config && sudo service ms-srv restart"
        fi
    done
}
stop_ms_srv(){
    local ms_ips=`get_ips java_ms-srv`
    for ms_ip in ${ms_ips[@]} ; do
        if [ "$ms_ip" != "127.0.0.1" ];then
            ssh_t ${ms_ip} "sudo service ms-srv stop"
        fi
    done
}

ms_srv_config(){
    local ms_ips=(`get_ips java_ms-srv`)
    local status=$1
    #if [ ! -f $FILE_ROOT ];then
    if [ ${#ms_ips[@]} -lt 1 ];then
        return
    fi
    if $(ssh_t  ${ms_ips[0]} "test ! -e /data/app/titan-ms-srv/custom.yml") ; then return ;fi
    if [ $status == "back" ];then
        if [ ! -f $FILE_ROOT/custom.yml ];then
            remote_scp ${ms_ips[0]} /data/app/titan-ms-srv/custom.yml $FILE_ROOT/custom.yml
        fi
    fi

    if [ $status == "recover" ]; then
        if [ -f $FILE_ROOT/custom.yml ];then
            if [ ${#ms_ips[@]} -ge 3 ];then
                execute_rsync_file ${ms_ips[0]} $FILE_ROOT/custom.yml /data/app/titan-dfs/ms-srv/config
                for ms_ip in ${ms_ips[@]} ; do
                ssh_t $ms_ip "sudo chown titan:titan /data/app/titan-dfs/ms-srv/config/custom.yml && sudo chmod 755 /data/app/titan-dfs/ms-srv/config/custom.yml"
                sudo rm -rf $FILE_ROOT/custom.yml
                done
            else
                execute_rsync_file ${ms_ips[0]} $FILE_ROOT/custom.yml /data/app/titan-ms-srv
                for ms_ip in ${ms_ips[@]} ; do
                    ssh_t $ms_ip "sudo chown titan:titan /data/app/titan-ms-srv/custom.yml && sudo chmod 755 /data/app/titan-ms-srv/custom.yml"
                done
            fi
            sudo rm -rf $FILE_ROOT/custom.yml
        fi
    fi


}

start_event_srv(){
    local event_ips=`get_ips java_event-srv`
    for event_ip in ${event_ips[@]} ; do
        if [ "$event_ip" != "127.0.0.1" ];then
            ssh_t ${event_ip} "sudo chmod 755 -R /data/app/titan-config && sudo service event-srv restart"
        fi
    done
}

stop_event_srv(){
    local event_ips=`get_ips java_event-srv`
    for event_ip in ${event_ips[@]} ; do
        if [ "$event_ip" != "127.0.0.1" ];then
            ssh_t ${event_ip} "sudo service event-srv stop"
        fi
    done
}

start_patrol(){
    local patrol_ips=`get_ips patrol-srv`
    for patrol_ip in ${patrol_ips[@]} ; do
        if [ "${patrol_ip}" != "127.0.0.1" ];then
            ssh_t ${patrol_ip} "sudo chmod 755 -R /data/app/titan-config && sudo service patrol-srv restart"
        fi
    done
}

stop_patrol(){
    local patrol_ips=`get_ips patrol-srv`
    for patrol_ip in ${patrol_ips[@]};
    do
        if [ "${patrol_ip}" != "127.0.0.1" ];then
            ssh_t ${patrol_ip} "sudo service patrol-srv stop"
        fi
    done
}

start_bigdata_logstash(){
    local logstash_ips=`get_ips bigdata_logstash`
    for logstash_ip in ${logstash_ips[@]} ; do
        if [ "$logstash_ip" != "127.0.0.1" ];then
            ssh_t ${logstash_ip} "if [ -d /usr/local/qingteng/bigdata/qt_consumer ];then \
            sudo service qingteng-consumer restart;\
            else \
            sudo service logstash stop && sudo service logstash start;fi"
        fi
    done
}

stop_bigdata_logstash(){
    local logstash_ips=`get_ips bigdata_logstash`
    for logstash_ip in ${logstash_ips[@]} ; do
        if [ "$logstash_ip" != "127.0.0.1" ];then
            ssh_t ${logstash_ip} "sudo service qingteng-consumer stop && sudo service logstash stop "
        fi
    done
}

start_bigdata_viewer(){
    local viewer_ips=`get_ips bigdata_viewer`
    for viewer_ip in ${viewer_ips[@]} ; do
        if [ "$viewer_ip" != "127.0.0.1" ];then
            ssh_t ${viewer_ip} "sudo service qingteng-viewer restart; sudo service nginx restart"
        fi
    done
}

stop_bigdata_viewer(){
    local viewer_ips=`get_ips bigdata_viewer`
    for viewer_ip in ${viewer_ips[@]} ; do
        if [ "$viewer_ip" != "127.0.0.1" ];then
            ssh_t ${viewer_ip} "sudo service qingteng-viewer stop"
        fi
    done
}

start_erlang_services(){
    #info_log "================ Launching Channel ==================="
    #start_titan_channel
    info_log "================ Launching Server ===================="
    start_titan_server
    info_log "================ Launching Selector =================="
    start_titan_selector
}

stop_erlang_node(){
    local host=$1
    local app=$2
    ssh_t ${host} "sudo ${app} stop || exit 1"
}

stop_titan_server(){

    local titan_server=/data/app/titan-servers/bin/titan-server
    local services_down=""
    local i=`expr ${#PACKAGE_TITAN_SERVER[*]} - 1`
    while [ $i -ge 0 ]
    do
        local ip=`get_ip ${PACKAGE_TITAN_SERVER[$i]}`
        if [ -z `echo ${services_down} |grep ${ip}` ]; then
            stop_erlang_node ${ip} ${titan_server}
            services_down="${services_down}**${ip}"
        fi
        let i--
    done
}

stop_titan_channel(){
    local ch_ip=`get_ip erl_channel_private`
    local channel=/data/app/titan-channel/bin/channel

    stop_erlang_node ${ch_ip} ${channel}

}

stop_titan_selector(){
    local sl_ip=`get_ip java_connect-selector`
    local selector=/data/app/titan-selector/bin/selector

    stop_erlang_node ${sl_ip} ${selector}
}


stop_erlang_services(){
    info_log "================= Stopping Selector =================="
    stop_titan_selector
    info_log "================= Stopping Server ===================="
    stop_titan_server
    #info_log "================= Stopping Channel ==================="
    #stop_titan_channel
}

start_titan_wisteria(){
    local java_ips=(`get_ips java`)
    for java_ip in ${java_ips[@]} ; do
        if [ "$java_ip" != "127.0.0.1" ];then
            ssh_t ${java_ip} "sudo chmod 755 -R /data/app/titan-config && sudo /etc/init.d/wisteria restart"
        fi
    done

    local java_ip=${java_ips[0]}
    ssh_t ${java_ip} "echo \"==================== Check Server Status ===================\"; \
    for i in {1..60}; do \
    sleep 10; \
    echo -e \".\c\"; \
    ret=\`curl -Ss ${java_ip}:6100/v1/assets/selfcheck/checkall\`; \
    [ \$i -eq 60 ] && echo \"Java start check all timeout after 10 min. \$ret\" && exit 1; \
    [ -z \"\$ret\" ] && continue; \
    [ ! -z \"\$(echo \$ret|grep false)\" ] && echo \$ret; \
    [ -z \"\$(echo \$ret|grep false)\" ] && echo \$ret && exit 0; \
    done"
    check "Start java"
}

change_wisteria_memory(){
    local java_ip=`get_ip java`
    [ -z "${java_ip}" ] && error_log "java ip is empty"

    info_log "change java memory"
    read -p "change wisteria memory default [8192]:" MEM
    echo "$MEM"|[ -n "`sed -n '/^[0-9][0-9]*$/p'`" ] || MEM=8192
    ssh_t ${java_ip} "sudo sed -i \"s/-Xmx[0-9]*M/-Xmx${MEM}M/\" /data/app/titan-wisteria/wisteria.conf"
    read -p "change gateway memory default [512]:" MEM
    echo "$MEM"|[ -n "`sed -n '/^[0-9][0-9]*$/p'`" ] || MEM=512
    ssh_t ${java_ip} "sudo sed -i \"s/-Xmx[0-9]*M/-Xmx${MEM}M/\" /data/app/titan-gateway/gateway.conf"
    read -p "change user-srv memory default [1024]:" MEM
    echo "$MEM"|[ -n "`sed -n '/^[0-9][0-9]*$/p'`" ] || MEM=1024
    ssh_t ${java_ip} "sudo sed -i \"s/-Xmx[0-9]*M/-Xmx${MEM}M/\" /data/app/titan-user-srv/user-srv.conf"
    read -p "change upload-srv memory default [512]:" MEM
    echo "$MEM"|[ -n "`sed -n '/^[0-9][0-9]*$/p'`" ] || MEM=512
    ssh_t ${java_ip} "sudo sed -i \"s/-Xmx[0-9]*M/-Xmx${MEM}M/\" /data/app/titan-upload-srv/upload-srv.conf"
    read -p "change detect-srv memory default [2048]:" MEM
    echo "$MEM"|[ -n "`sed -n '/^[0-9][0-9]*$/p'`" ] || MEM=2048
    ssh_t ${java_ip} "sudo sed -i \"s/-Xmx[0-9]*M/-Xmx${MEM}M/\" /data/app/titan-detect-srv/detect-srv.conf"
}

stop_titan_wisteria(){
    local java_ips=`get_ips java`
    for java_ip in ${java_ips[@]} ; do
        if [ "$java_ip" != "127.0.0.1" ];then
            ssh_t ${java_ip} "sudo /etc/init.d/wisteria stop || exit 1"
        fi
    done
}

execute_config_py() {
    local version=$1
    local usage=$2   # 0: install, 1:upgrade 2:other 3:upgrade to cluster
    
    local php_host=`get_ip php_inner_api`
    local config=/data/app/www/titan-web/config_scripts/config.py
    local config_helper=/data/app/www/titan-web/config_scripts/config_helper.py
    local system_check_config=/data/app/www/titan-web/config_scripts/titan_system_check.py

    local php_ips=`get_ips php_inner_api`
    for php_ip in ${php_ips[@]} ; do
        if [ "$php_ip" != "127.0.0.1" ];then
            ssh_t ${php_ip} "sudo sed -i \"s#\(DEFAULT_SSH_PORT =\).*#\1 $DEFAULT_PORT#\" $config_helper; \
                sudo sed -i \"s#\(DEFAULT_SSH_USER =\).*#\1 \\\"$DEFAULT_USER\\\"#\" $config_helper; \
                sudo sed -i \"s#\(DEFAULT_SSH_USER =\).*#\1 \\\"$DEFAULT_USER\\\"#\" $system_check_config; \
                sudo sed -i \"s#\(DEFAULT_SSH_PORT =\).*#\1 $DEFAULT_PORT#\" $system_check_config; "
        fi
    done

    ssh_t ${php_host} "\
    echo \"Automatically run the second step: $config, finish all services configure.\"; \
    sudo sed -i \"s#\(DEFAULT_SSH_PORT =\).*#\1 $DEFAULT_PORT#\" $config_helper; \
    sudo sed -i \"s#\(DEFAULT_SSH_USER =\).*#\1 \\\"$DEFAULT_USER\\\"#\" $config_helper; \
    sudo sed -i \"s#\(DEFAULT_SSH_USER =\).*#\1 \\\"$DEFAULT_USER\\\"#\" $system_check_config; \
    sudo sed -i \"s#\(DEFAULT_SSH_PORT =\).*#\1 $DEFAULT_PORT#\" $system_check_config; \
    sudo /usr/bin/python $config -v ${version:="v3"} --install_or_up=${usage:="2"} || exit 1"
    check "Config.py executed "
}
execute_config_py_thp() {
    local version=$1
    local php_host=`get_ip php_inner_api`
    local config=/data/app/www/titan-web/config_scripts/config.py
    local config_helper=/data/app/www/titan-web/config_scripts/config_helper.py
    local system_check_config=/data/app/www/titan-web/config_scripts/titan_system_check.py

    local php_ips=`get_ips php_inner_api`
    for php_ip in ${php_ips[@]} ; do
        if [ "$php_ip" != "127.0.0.1" ];then
            ssh_t ${php_ip} "sudo sed -i \"s#\(DEFAULT_SSH_PORT =\).*#\1 $DEFAULT_PORT#\" $config_helper; \
                sudo sed -i \"s#\(DEFAULT_SSH_USER =\).*#\1 \\\"$DEFAULT_USER\\\"#\" $config_helper; \
                sudo sed -i \"s#\(DEFAULT_SSH_USER =\).*#\1 \\\"$DEFAULT_USER\\\"#\" $system_check_config; \
                sudo sed -i \"s#\(DEFAULT_SSH_PORT =\).*#\1 $DEFAULT_PORT#\" $system_check_config; "
        fi
    done

    ssh_t ${php_host} "\
    echo \"Automatically run the second step: $config, finish all services configure.\"; \
    sudo sed -i \"s#\(DEFAULT_SSH_PORT =\).*#\1 $DEFAULT_PORT#\" $config_helper; \
    sudo sed -i \"s#\(DEFAULT_SSH_USER =\).*#\1 \\\"$DEFAULT_USER\\\"#\" $config_helper; \
    sudo sed -i \"s#\(DEFAULT_SSH_USER =\).*#\1 \\\"$DEFAULT_USER\\\"#\" $system_check_config; \
    sudo sed -i \"s#\(DEFAULT_SSH_PORT =\).*#\1 $DEFAULT_PORT#\" $system_check_config; \
    sudo /usr/bin/python $config --join_thp_config || exit 1"
    check "Config.py executed "
}

init_mysql_php(){
    local mysql_host=`get_ip db_mysql_php`
    local php_host=`get_ip php_inner_api`
    local mysql_port=`grep -A 3 "mysql" ${CUSTOMIZE_FILE} |grep "port" | awk -F ":*" '{print $2}' |awk -F ",*" '{print $1}'|awk -F " *" '{print $2}'`
    local mysql_user=`grep -A 3 "mysql" ${CUSTOMIZE_FILE} |grep "user" | awk -F ":*" '{print $2}' |awk -F ",*" '{print $1}'|awk -F "\"*" '{print $2}'`
    local mysql_pass=`grep -A 3 "mysql" ${CUSTOMIZE_FILE} |grep "password" | awk -F ":*" '{print $2}' |awk -F ",*" '{print $1}'|awk -F "\"*" '{print $2}'`

    if [ ! ${mysql_pass} ]; then
        ssh_t ${php_host}  "\
        echo \"MySQL Inititaion....\"; \
        mysql --default-character-set=utf8 -h ${mysql_host} -P ${mysql_port} -u${mysql_user} -p9pbsoq6hoNhhTzl < /data/app/www/titan-web/db/titan.sql; \
        mysql --default-character-set=utf8 -h ${mysql_host} -P ${mysql_port} -u${mysql_user} -p9pbsoq6hoNhhTzl < /data/app/www/titan-web/db/titan-monitor.sql; \
        mysql --default-character-set=utf8 -h ${mysql_host} -P ${mysql_port} -u${mysql_user} -p9pbsoq6hoNhhTzl < /data/app/www/titan-web/db/titan-user.sql; \
        mysql --default-character-set=utf8 -h ${mysql_host} -P ${mysql_port} -u${mysql_user} -p9pbsoq6hoNhhTzl < /data/app/www/titan-web/db/titan-back.sql; \
        mysql --default-character-set=utf8 -h ${mysql_host} -P ${mysql_port} -u${mysql_user} -p9pbsoq6hoNhhTzl < /data/app/www/titan-web/db/agent-monitor-db.sql; \
        mysql --default-character-set=utf8 -h ${mysql_host} -P ${mysql_port} -u${mysql_user} -p9pbsoq6hoNhhTzl < /data/app/www/titan-web/db/titan-connect.sql"
        check "init mysql "
    else
        ssh_t ${php_host}  "\
        echo \"MySQL Inititaion....\"; \
        mysql --default-character-set=utf8 -h ${mysql_host} -P ${mysql_port} -u${mysql_user} -p${mysql_pass} < /data/app/www/titan-web/db/titan.sql; \
        mysql --default-character-set=utf8 -h ${mysql_host} -P ${mysql_port} -u${mysql_user} -p${mysql_pass} < /data/app/www/titan-web/db/titan-monitor.sql; \
        mysql --default-character-set=utf8 -h ${mysql_host} -P ${mysql_port} -u${mysql_user} -p${mysql_pass} < /data/app/www/titan-web/db/titan-user.sql; \
        mysql --default-character-set=utf8 -h ${mysql_host} -P ${mysql_port} -u${mysql_user} -p${mysql_pass} < /data/app/www/titan-web/db/titan-back.sql; \
        mysql --default-character-set=utf8 -h ${mysql_host} -P ${mysql_port} -u${mysql_user} -p${mysql_pass} < /data/app/www/titan-web/db/agent-monitor-db.sql; \
        mysql --default-character-set=utf8 -h ${mysql_host} -P ${mysql_port} -u${mysql_user} -p${mysql_pass} < /data/app/www/titan-web/db/titan-connect.sql"
        check "init mysql "
    fi
    # 1 means init_mysql_php have done
    echo 1 > ${INIT_MYSQL_PHP_STATAUS}
}

start_php_worker(){
    local args_worker=install
    [ "$1" = "v3" ] && args_worker=install_v3
    local service_done=""
    for node in ${PACKAGE_TITAN_WEB[*]};
    do
        local ips=`get_ips ${node}`
        for ip in ${ips[@]} ; do
            if [ ! -z "`echo ${service_done} |grep ${ip}`" ]; then
                continue
            fi
            ssh_t ${ip} "\
            [ -d /data/titan-logs/nginx ] || sudo mkdir -p  /data/titan-logs/nginx && sudo chown -R nginx:nginx /data/titan-logs/nginx;\
            [ -d /data/titan-logs/php/dump ] || sudo mkdir -p  /data/titan-logs/php/dump && sudo chown -R nginx:nginx /data/titan-logs/php/dump;\
            sudo chmod 755 -R /data/app/www /data/app/conf && sudo chown nginx:nginx -R /data/app/www && sudo chown root:root -R /data/app/www/titan-web; \
            sudo chmod 600 -f /data/app/titan-rabbitmq/.erlang.cookie; \
            sudo /data/app/www/titan-web/script/update.sh && sudo service nginx restart"
            check "build application.ini & Restart nginx "
            service_done="${service_done}@${ip}"
        done
    done

    # worker running on php_inner_api site by defaults
    local worker_ips=`get_ips php_inner_api`
    for worker_ip in ${worker_ips[@]} ; do
        ssh_t ${worker_ip} "\
        sudo /data/app/www/titan-web/script/update.sh install && sudo service nginx restart && sudo service patrol-srv restart"
        check "Launching worker at $worker_ip"
    done
}


sync_rules(){
    local php_host=$1
    execute_rsync ${php_host} ${FILE_ROOT}/rules/ ${WEB_PATH}/rules
    ssh_t ${php_host}  "\
    echo \"================= 同步后台规则 =================\"; \
    [ -d ${WEB_PATH}/rules ] || (echo \"rules pack not found\" && exit 1); \
    sudo ${PHP_EXEC} ${WEB_PATH}/update/cli/pack.php -d ${WEB_PATH}/rules -no-sync || echo -e \"\\033[4;31m 导入部分规则有错误，请检查之后重新导入 \\033[0m\" && exit 1"
    ssh_t ${php_host} "\
    echo \"================= 刷新后台规则 =================\"; \
    sudo ${PHP_EXEC} ${WEB_PATH}/update/cli/pack.php -s || exit 1 && sudo chown -R root:root /data/app/www/titan-web"
}
update_agent_config(){

    local php_host=$1
    local upgrade=$2

if [ "${upgrade}" == "upgrade" ];then
#upgrade
    ssh_t ${php_host}  "\
    echo \"============== 加载Linux Agent 版本 ============\"; \
    ver_linux=\`ls /data/app/www/agent-update |grep '^v' |egrep -v '(v*-win*|v*-aix*|v*-aarch64*|v*-solaris.*|virus_engine|v*-sw_64*|v*-ppc64*|v*-ppcle64*)'|sort -Vr |head -1\`; \
    [ -n \"\${ver_linux}\" ] && \
    sudo ${PHP_EXEC} ${WEB_PATH}/script/update_agent.php linux \${ver_linux} && \
    echo linux agent version: \${ver_linux}; \
    [ \$? -ne 0 -a -n \"\${ver_linux}\" ] && echo failed && exit 1; \
    [ -z \"\${ver_linux}\" ] && echo [Warning]linux_agent_not_found; \

    echo \"============== 加载 Windows Agent 版本 ==========\"; \
    ver_win=\`ls /data/app/www/agent-update |grep '^v' |grep 'v*-win*' |sort -Vr |head -1\`; \
    [ -n \"\${ver_win}\" ] && sleep 12 && \
    sudo ${PHP_EXEC} ${WEB_PATH}/script/update_agent.php windows \${ver_win} && \
    echo windows agent version: \${ver_win}; \
    [ \$? -ne 0 -a -n \"\$ver_win\" ] && echo failed && exit 1; \
    [ -z \"\${ver_win}\" ] && echo [Warning]windows_agent_not_found; \

    echo \"============== 加载 ARM Linux Agent 版本 ==========\"; \
    ver_arm_linux=\`ls /data/app/www/agent-update |grep '^v' |grep 'v*-aarch64*' |sort -Vr |head -1\`; \
    [ -n \"\${ver_arm_linux}\" ] && sleep 12 && \
    sudo ${PHP_EXEC} ${WEB_PATH}/script/update_agent.php aarch64 \${ver_arm_linux} && \
    echo ARM Linux agent version: \${ver_arm_linux}; \
    [ \$? -ne 0 -a -n \"\$ver_arm_linux\" ] && echo failed && exit 1; \
    [ -z \"\${ver_arm_linux}\" ] && echo [Warning]ARM_Linux_agent_not_found; \

    echo \"============== 加载 AIX Agent 版本 ==========\"; \
    ver_aix=\`ls /data/app/www/agent-update |grep '^v' |grep 'v*-aix*' |sort -Vr |head -1\`; \
    [ -n \"\${ver_aix}\" ] && sleep 12 && \
    sudo ${PHP_EXEC} ${WEB_PATH}/script/update_agent.php aix \${ver_aix} && \
    echo aix agent version: \${ver_aix}; \
    [ \$? -ne 0 -a -n \"\$ver_aix\" ] && echo failed && exit 1; \
    [ -z \"\${ver_aix}\" ] && echo [Warning]aix_agent_not_found; \


    echo \"============== 加载 Solaris Agent 版本 ==========\"; \
    ver_solaris=\`ls /data/app/www/agent-update |grep '^v' |grep 'v*-solaris' |sort -Vr |head -1\`; \
    [ -n \"\${ver_solaris}\" ] && sleep 12 && \
    sudo ${PHP_EXEC} ${WEB_PATH}/script/update_agent.php solaris \${ver_solaris} && \
    echo solaris agent version: \${ver_solaris}; \
    [ \$? -ne 0 -a -n \"\$ver_solaris\" ] && echo failed && exit 1; \
    [ -z \"\${ver_solaris}\" ] && echo [Warning]solaris_agent_not_found; \
    
    
    echo \"============== 加载 SW 64 Agent 版本 ==========\"; \
    ver_sw64=\`ls /data/app/www/agent-update |grep '^v' |grep 'v*-sw_64' |sort -Vr |head -1\`; \
    [ -n \"\${ver_sw64}\" ] && sleep 12 && \
    ${PHP_EXEC} ${WEB_PATH}/script/update_agent.php linux \${ver_sw64} && \
    echo sw64 agent version: \${ver_sw64}; \
    [ \$? -ne 0 -a -n \"\$ver_sw64\" ] && echo failed && exit 1; \
    [ -z \"\${ver_sw64}\" ] && echo [Warning]sw64_agent_not_found;\

    echo \"============== 加载 Power Linux Agent 版本 ==========\"; \
    ver_ppc64=\`ls /data/app/www/agent-update |grep '^v' |grep 'v*-ppc64' |sort -Vr |head -1\`; \
    [ -n \"\${ver_ppc64}\" ] && sleep 12 && \
    ${PHP_EXEC} ${WEB_PATH}/script/update_agent.php linux \${ver_ppc64} && \
    echo ppc64 agent version: \${ver_ppc64}; \
    [ \$? -ne 0 -a -n \"\$ver_ppc64\" ] && echo failed && exit 1; \
    [ -z \"\${ver_ppc64}\" ] && echo [Warning]ppc64_agent_not_found;\

    echo \"============ 加载 Power Linux Agent 版本 LE ==========\"; \
    ver_ppcle64=\`ls /data/app/www/agent-update |grep '^v' |grep 'v*-ppc64le' |sort -Vr |head -1\`; \
    [ -n \"\${ver_ppcle64}\" ] && sleep 12 && \
    ${PHP_EXEC} ${WEB_PATH}/script/update_agent.php linux \${ver_ppcle64} && \
    echo ppc64le agent version: \${ver_ppcle64}; \
    [ \$? -ne 0 -a -n \"\$ver_ppcle64\" ] && echo failed && exit 1; \
    [ -z \"\${ver_ppcle64}\" ] && echo [Warning]ppc64le_agent_not_found;"

else
	#new install
    ssh_t ${php_host}  "\
    echo \"============== 加载Linux Agent 版本 ============\"; \
    ver_linux=\`ls /data/app/www/agent-update |grep '^v' |egrep -v '(v*-win*|v*-aix*|v*-aarch64*|v*-solaris.*|virus_engine|v*-sw_64*|v*-ppc64*|v*-ppcle64*)'|sort -Vr |head -1\`; \
    [ -n \"\${ver_linux}\" ] && \
    sudo ${PHP_EXEC} ${WEB_PATH}/script/update_agent.php linux \${ver_linux} publish && \
    echo linux agent version: \${ver_linux}; \
    [ \$? -ne 0 -a -n \"\${ver_linux}\" ] && echo failed && exit 1; \
    [ -z \"\${ver_linux}\" ] && echo [Warning]linux_agent_not_found; \

    echo \"============== 加载 Windows Agent 版本 ==========\"; \
    ver_win=\`ls /data/app/www/agent-update |grep '^v' |grep 'v*-win*' |sort -Vr |head -1\`; \
    [ -n \"\${ver_win}\" ] && sleep 12 && \
    sudo ${PHP_EXEC} ${WEB_PATH}/script/update_agent.php windows \${ver_win} publish && \
    echo windows agent version: \${ver_win}; \
    [ \$? -ne 0 -a -n \"\$ver_win\" ] && echo failed && exit 1; \
    [ -z \"\${ver_win}\" ] && echo [Warning]windows_agent_not_found; \

    echo \"============== 加载 ARM Linux Agent 版本 ==========\"; \
    ver_arm_linux=\`ls /data/app/www/agent-update |grep '^v' |grep 'v*-aarch64*' |sort -Vr |head -1\`; \
    [ -n \"\${ver_arm_linux}\" ] && sleep 12 && \
    sudo ${PHP_EXEC} ${WEB_PATH}/script/update_agent.php aarch64 \${ver_arm_linux} publish && \
    echo ARM Linux agent version: \${ver_arm_linux}; \
    [ \$? -ne 0 -a -n \"\$ver_arm_linux\" ] && echo failed && exit 1; \
    [ -z \"\${ver_arm_linux}\" ] && echo [Warning]ARM_Linux_agent_not_found; \

    echo \"============== 加载 AIX Agent 版本 ==========\"; \
    ver_aix=\`ls /data/app/www/agent-update |grep '^v' |grep 'v*-aix*' |sort -Vr |head -1\`; \
    [ -n \"\${ver_aix}\" ] && sleep 12 && \
    sudo ${PHP_EXEC} ${WEB_PATH}/script/update_agent.php aix \${ver_aix} publish && \
    echo aix agent version: \${ver_aix}; \
    [ \$? -ne 0 -a -n \"\$ver_aix\" ] && echo failed && exit 1; \
    [ -z \"\${ver_aix}\" ] && echo [Warning]aix_agent_not_found; \


    echo \"============== 加载 Solaris Agent 版本 ==========\"; \
    ver_solaris=\`ls /data/app/www/agent-update |grep '^v' |grep 'v*-solaris' |sort -Vr |head -1\`; \
    [ -n \"\${ver_solaris}\" ] && sleep 12 && \
    sudo ${PHP_EXEC} ${WEB_PATH}/script/update_agent.php solaris \${ver_solaris} publish && \
    echo solaris agent version: \${ver_solaris}; \
    [ \$? -ne 0 -a -n \"\$ver_solaris\" ] && echo failed && exit 1; \
    [ -z \"\${ver_solaris}\" ] && echo [Warning]solaris_agent_not_found; \
    
    echo \"============== 加载 SW 64 Agent 版本 ==========\"; \
    ver_sw64=\`ls /data/app/www/agent-update |grep '^v' |grep 'v*-sw_64' |sort -Vr |head -1\`; \
    [ -n \"\${ver_sw64}\" ] && sleep 12 && \
    ${PHP_EXEC} ${WEB_PATH}/script/update_agent.php linux \${ver_sw64} publish && \
    echo sw64 agent version: \${ver_sw64}; \
    [ \$? -ne 0 -a -n \"\$ver_sw64\" ] && echo failed && exit 1; \
    [ -z \"\${ver_sw64}\" ] && echo [Warning]sw64_agent_not_found;\

    echo \"============== 加载 Power Linux Agent 版本 ==========\"; \
    ver_ppc64=\`ls /data/app/www/agent-update |grep '^v' |grep 'v*-ppc64' |sort -Vr |head -1\`; \
    [ -n \"\${ver_ppc64}\" ] && sleep 12 && \
    ${PHP_EXEC} ${WEB_PATH}/script/update_agent.php linux \${ver_ppc64} publish && \
    echo ppc64 agent version: \${ver_ppc64}; \
    [ \$? -ne 0 -a -n \"\$ver_ppc64\" ] && echo failed && exit 1; \
    [ -z \"\${ver_ppc64}\" ] && echo [Warning]ppc64_agent_not_found;\

    echo \"============ 加载 Power Linux Agent LE版本 ==========\"; \
    ver_ppcle64=\`ls /data/app/www/agent-update |grep '^v' |grep 'v*-ppc64le' |sort -Vr |head -1\`; \
    [ -n \"\${ver_ppcle64}\" ] && sleep 12 && \
    ${PHP_EXEC} ${WEB_PATH}/script/update_agent.php linux \${ver_ppcle64} publish && \
    echo ppc64le agent version: \${ver_ppcle64}; \
    [ \$? -ne 0 -a -n \"\$ver_ppcle64\" ] && echo failed && exit 1; \
    [ -z \"\${ver_ppcle64}\" ] && echo [Warning]ppc64le_agent_not_found;"

fi
    ssh_t ${php_host}  "\
    echo \"============== Touch titanagent.md5sum ========\"; \
    cd /data/app/www/agent-update && sudo touch titanagent.md5sum && \
    sudo chmod 655 titanagent.md5sum && echo titanagent.md5sum created || exit 1; \

    echo \"================= 配置curl安装 =================\"; \
    sudo ${PHP_EXEC} ${WEB_PATH}/script/update_curl.php || exit 1; \

    sudo service patrol-srv restart && sudo service patrol-srv status; \
    sudo service supervisord restart && sudo supervisorctl status"

    local php_host_2s=`get_ips php_download_private`
    for php_host_2 in ${php_host_2s[@]} ; do
        ssh_t ${php_host_2}  "\
        echo \"============== Touch titanagent.md5sum ========\"; \
        cd /data/app/www/agent-update && sudo touch titanagent.md5sum && \
        sudo chmod 655 titanagent.md5sum && echo titanagent.md5sum created || exit 1; \
        sudo service patrol-srv restart && sudo service patrol-srv status"
    done

}

init_data() {
    ## worker running on php_inner_api site by defaults
    local php_host=`get_ip php_inner_api`
    local mysql_host=`get_ip db_mysql_php`
    local upgrade=$1
    info_log "Execute: crontab ${WEB_PATH}/config_scripts/titan.cron"
    ssh_t ${php_host} "sudo crontab ${WEB_PATH}/config_scripts/titan.cron && sudo crontab -l"
    update_php_license
    sync_rules ${php_host}
    if [ "${upgrade}" = "upgrade" ];then
        update_agent_config ${php_host} upgrade
    elif [ "${upgrade}" = "upgrade_thp" ];then
        info_log "updata join_thp_config,don\'t updata agent"
    else
        update_agent_config ${php_host}
    fi
}
# 更新安装雷火引擎离线文件,手动完毕需要删除目录，自动完毕需要删除安装包。
update_thunderfire(){
    local upload_hosts=`get_ips java_upload-srv`
    local update_type=$1
    if [ "$update_type" == "auto" ];then
        if [ -d ${FILE_ROOT}/thunderfire ]; then
            info_log "The thunderfire file already exists. Skip upgrade"
            return
        fi
        sudo cp -r ${FILE_ROOT}/common/thunderfire*.tar.gz ${FILE_ROOT}/
    else
        if [ ! -e ${FILE_ROOT}/thunderfire*.tar.gz  ];then
            error_log "no found thunderfire file !"
        fi
    fi
    
    cd ${FILE_ROOT} && sudo rm -rf thunderfire && sudo tar -zxf thunderfire*.tar.gz
    cd ${FILE_ROOT}/thunderfire && sudo tar -zxf php_cdc.tar.gz && rm -rf php_cdc.tar.gz

    for upload_host in ${upload_hosts[@]}; do
        ssh_t $upload_host "sudo mv $Thunderfire_Engine_Path $Thunderfire_Engine_Path-bak-$(date +%Y%m%d%H%M%S) && sudo mkdir -p $Thunderfire_Engine_Path "
        rsync -rz --rsync-path="sudo rsync" -e "ssh -p $DEFAULT_PORT"  --delete ${FILE_ROOT}/thunderfire/* ${DEFAULT_USER}@${upload_host}:$Thunderfire_Engine_Path
        ssh_t $upload_host "sudo chown -R titan:titan $Thunderfire_Engine_Path && \
        sudo chmod 500 $Thunderfire_Engine_Path/jsp_cdc/cdc_jsp.sh $Thunderfire_Engine_Path/php_cdc/cdc_php.sh "
    done
    check "update Thunderfire package"
    info_log "Update Thunderfire completed, delete the  Thunderfire backup"
    for upload_host in ${upload_hosts[@]}; do
        ssh_t $upload_host "sudo rm -rf $Thunderfire_Engine_Path-bak-*"
    done
    check "delete the Thunderfire backup"
    if [ "$update_type" == "auto" ];then
        sudo rm -rf ${FILE_ROOT}/thunderfire*.tar.gz
    fi
}

#解压pre.tar.gz包
pre_tar(){
    local mysql_host=$1
    local targz_rules=$2
    ssh_t $mysql_host "sudo service  mysqld stop &>/dev/null &&  if [ -d "/data/mysql" ];then sudo mv /data/mysql /data/mysql-bak-$(date +%Y%m%d%H%M%S) &>/dev/null;fi"
    ssh_t $mysql_host "sudo cp -r ${REMOTE_QT_PACKAGE_DIR}/$targz_rules $INSTALL_PRE_PATH/ &&  cd $INSTALL_PRE_PATH && sudo tar -zxf $INSTALL_PRE_PATH/$targz_rules && sudo chown -R mysql:mysql $INSTALL_PRE_PATH/mysql &>/dev/null && sudo chmod -R 755 $INSTALL_PRE_PATH/mysql &>/dev/null"
}
preset_rules(){
    local mysql_host=`get_ip db_mysql_php`
    local php_host=`get_ip php_inner_api`
    local mysql_port=`grep -A 3 "mysql" ${CUSTOMIZE_FILE} |grep "port" | awk -F ":*" '{print $2}' |awk -F ",*" '{print $1}'|awk -F " *" '{print $2}'`
    local mysql_user=`grep -A 3 "mysql" ${CUSTOMIZE_FILE} |grep "user" | awk -F ":*" '{print $2}' |awk -F ",*" '{print $1}'|awk -F "\"*" '{print $2}'`
    local mysql_pass=`grep -A 3 "mysql" ${CUSTOMIZE_FILE} |grep "password" | awk -F ":*" '{print $2}' |awk -F ",*" '{print $1}'|awk -F "\"*" '{print $2}'`
    local rules_status=`ssh_t ${mysql_host} "ls $INSTALL_PRE_PATH |grep qingteng-rules|wc -l"`
    
    if [ `echo ${rules_status}|sed 's/\r//g'` == "0" ];then
	info_log "Prepare to install preset rules"
        [ -z "${mysql_host}" ] && error_log "db_mysql_php's ip is empty"

        local os_version=`cat /etc/redhat-release | tr -cd '[0-9,\.]'| cut -d '.' -f 1`
        local mysql_ips=(`get_ips db_mysql_php`)
        local mysql_num=${#mysql_ips[@]}
        # if mysql cluster, stop other node, then stop ${mysql_host}
        if test $mysql_num -gt 1; then
            for mysql_ip in ${mysql_ips[@]} ; do
                if [ ${mysql_ip} != ${mysql_host} ]; then
                    ssh_t ${mysql_ip} "sudo service mysql stop; sudo service mysql@bootstrap stop"
                fi
            done
            ssh_t ${mysql_host} "sudo service mysql stop; sudo service mysql@bootstrap stop"
        fi

        local targz_rules=`echo ${FILE_ROOT}/*/qingteng-rules-*.tar.gz`
        execute_rsync ${mysql_host} ${targz_rules} ${REMOTE_QT_PACKAGE_DIR}
        pre_tar ${mysql_host} ${targz_rules##*/}
        check "install MySQL data"
        
        # if mysql cluster, start this node which install qingteng-rules, then start others
        if test $mysql_num -gt 1; then
            ssh_t ${mysql_host} "test -f /data/mysql/grastate.dat && sudo sed -i 's/safe_to_bootstrap:.*/safe_to_bootstrap: 1/' /data/mysql/grastate.dat"
            ssh_t ${mysql_host} "sudo sed -i 's/^wsrep_sst_method.*$/wsrep_sst_method=rsync/' /etc/my.cnf"
            if [ ${os_version} == "7" ]; then
                ssh_t ${mysql_host} "sudo service mysql@bootstrap start"
            else
                ssh_t ${mysql_host} "sudo /etc/init.d/mysql bootstrap-pxc"
            fi
        else
            ssh_t ${mysql_host} "sudo service mysqld start"
        fi
        # if mysql cluster, start other node.
        # after base mysql cluster install, wsrep_sst_method is rsync,after start, need change to xtrabackup-v2, and restrat again
        if test $mysql_num -gt 1; then
            for mysql_ip in ${mysql_ips[@]} ; do
                if [ ${mysql_ip} != ${mysql_host} ]; then
                    ssh_t ${mysql_ip} "sudo sed -i 's/^wsrep_sst_method.*$/wsrep_sst_method=rsync/' /etc/my.cnf"
                    ssh_t ${mysql_ip} "sudo service mysql restart"
                fi
            done

            for mysql_ip in ${mysql_ips[@]} ; do
                ssh_t ${mysql_ip} "sudo sed -i 's/^wsrep_sst_method.*$/wsrep_sst_method=xtrabackup-v2/' /etc/my.cnf"
                if [ ${mysql_ip} != ${mysql_host} ]; then
                    ssh_t ${mysql_ip} "sudo service mysql restart"
                else
                    if [ ${os_version} == "7" ]; then
                        ssh_t ${mysql_ip} "sudo service mysql@bootstrap stop"
                    else
                        ssh_t ${mysql_ip} "sudo service mysql stop"
                    fi
                    ssh_t ${mysql_ip} "sudo service mysql start"
                fi
                
            done
        fi

        check "MySQL start"
    else
	info_log "preset rules Already exist"
    fi
    if [ ! -d /data/mysql/qt_titan_connect ];then
        #3.3.9 init titan-connect.sql
        if [ ! ${mysql_pass} ]; then
            ssh_t ${php_host}  "\
            echo \"MySQL Inititaion....\"; \
            mysql --default-character-set=utf8 -h ${mysql_host} -uroot -p9pbsoq6hoNhhTzl < /data/app/www/titan-web/db/titan-connect.sql"
            check "init mysql "
        else
            ssh_t ${php_host}  "\
            echo \"MySQL Inititaion....\"; \
            mysql --default-character-set=utf8 -h ${mysql_host} -P ${mysql_port} -u${mysql_user} -p${mysql_pass} < /data/app/www/titan-web/db/titan-connect.sql"
            check "init mysql "
        fi
    fi
}

webpreset_rules(){
    local mysql_host=`get_ip db_mysql_php`
    local php_host=`get_ip php_inner_api`
    local mysql_port=`grep -A 3 "mysql" ${CUSTOMIZE_FILE} |grep "port" | awk -F ":*" '{print $2}' |awk -F ",*" '{print $1}'|awk -F " *" '{print $2}'`
    local mysql_user=`grep -A 3 "mysql" ${CUSTOMIZE_FILE} |grep "user" | awk -F ":*" '{print $2}' |awk -F ",*" '{print $1}'|awk -F "\"*" '{print $2}'`
    local mysql_pass=`grep -A 3 "mysql" ${CUSTOMIZE_FILE} |grep "password" | awk -F ":*" '{print $2}' |awk -F ",*" '{print $1}'|awk -F "\"*" '{print $2}'`
    local rules_status=`ssh_t ${mysql_host} "ls $INSTALL_PRE_PATH |grep qingteng-rules|wc -l"`

    if [ `echo ${rules_status}|sed 's/\r//g'` == "0" ];then
        info_log "Prepare to install preset rules"
    
        [ -z "${mysql_host}" ] && error_log "db_mysql_php's ip is empty"
        local targz_rules=`echo ${FILE_ROOT}/*/qingteng-rules-*.tar.gz`
        execute_rsync ${mysql_host} ${targz_rules} ${REMOTE_QT_PACKAGE_DIR}
	pre_tar ${mysql_host} ${targz_rules##*/}
        check "install MySQL data"
        ssh_t ${mysql_host} "sudo service mysqld start"
        check "MySQL start"
    else
        info_log "preset rules Already exist"
    fi
    if [ ! -d /data/mysql/qt_titan_connect ];then
        #3.3.9 init titan-connect.sql
        if [ ! ${mysql_pass} ]; then
            ssh_t ${php_host}  "\
            echo \"MySQL Inititaion....\"; \
            mysql --default-character-set=utf8 -h ${mysql_host} -uroot -p9pbsoq6hoNhhTzl < /data/app/www/titan-web/db/titan-connect.sql"
            check "init mysql "
        else
            ssh_t ${php_host}  "\
            echo \"MySQL Inititaion....\"; \
            mysql --default-character-set=utf8 -h ${mysql_host} -P ${mysql_port} -u${mysql_user} -p${mysql_pass} < /data/app/www/titan-web/db/titan-connect.sql"
            check "init mysql "
        fi
    fi
}

start_init_data(){
    local upgrade=$1
    info_log "Do you want to sync rules now [Y/N] ? default is Y"
    read -p "Enter [Y/N]: " Enter
    case $Enter in
        Y | y)
            if [ "${upgrade}" = "upgrade" ];then
                init_data upgrade
            elif [ "${upgrade}" = "upgrade_thp" ];then
                init_data upgrade_thp
            else
                init_data
            fi
            ;;
        N | n)
            exit 0
            ;;
        *)
            if [ "${upgrade}" = "upgrade" ];then
                init_data upgrade
            elif [ "${upgrade}" = "upgrade_thp" ];then
                init_data upgrade_thp
            else
                init_data
            fi
            ;;
    esac
}


check_backend_account() {
    local php_host=`get_ip php_inner_api`

    local register_back_v3_dir=${WEB_PATH}/user-backend/cli/

    local check_back_v3_script=check-back-register.php

    ssh_t ${php_host}  "\
    cd ${register_back_v3_dir} && \
    ${PHP_EXEC} ${check_back_v3_script}"

    check "Check backend account "
}

# if failed at register account, prompt use not rerun install
check_register_acct(){
    if [ $? -eq 0 ];then
        info_log "$* Successfully"
    else
        warn_log "$* Failed, this is the last step of install, Please resolve manually, not rerun ./titan-app.sh install again"
        exit 1
    fi
}

register_default_account() {
    ## php script executed on php_worker_site
    local php_host=`get_ip php_inner_api`

    local register_v2_dir=${WEB_PATH}/user-backend/cli/
    local register_back_v3_dir=${WEB_PATH}/user-backend/cli/
    local register_v3_dir=${WEB_PATH}/update/cli/

    local register_v2_script=back-default-register.php
    local register_back_v3_script=back-register.php
    local check_back_v3_script=check-back-register.php
    local register_v3_script=v3-tool-front-register.php

    local register_default_dir=${register_v3_dir}
    local register_default_script=${register_v3_script}

    [ "$1" = "v2" ] && register_default_dir=${register_v2_dir} && register_default_script=${register_v2_script}

    info_log "=================== 注册前台账号 ==================="
    randompwd=`head /dev/urandom | tr -dc A-Za-z0-9@%_ | head -c 13`
    read -ep "Input username (default: admin@sec.com): " username
    read -ep "Input password (default: $randompwd): " password

    echo ${username:="admin@sec.com"}  ${password:="$randompwd"}

    ssh_t ${php_host}  "\
    cd ${register_default_dir} && \
    sudo ${PHP_EXEC} ${register_default_script} ${username:=\"admin@sec.com\"} ${password:=\"sec.com@qt2020\"};"

    check_register_acct "Register console default account "

    #if not multi_user version, set this account to java.json's default_uname,then sub account can login without main account
    local MULTI_USER=`sed -r -n 's/.*"multi_user":"([01]).*/\1/p' ${FILE_ROOT}/license/license.key`
    if [ $MULTI_USER == "0" ]; then
        local java_ips=`get_ips java_user-srv`
        for java_ip in ${java_ips[@]} ; do
            ssh_t ${java_ip} "sudo sed -i -r '/default_uname/s/:[^,]+/: \"$username\"/' /data/app/titan-config/java.json"
            ssh_t ${java_ip} "sudo /data/app/titan-user-srv/init.d/user-srv restart"
        done
    fi

    info_log "=================== 注册后台账号 ==================="
    randompwd=`head /dev/urandom | tr -dc A-Za-z0-9@%_ | head -c 13`
    read -ep "Input username (default: admin@sec.com): " username
    read -ep "Input password (default: $randompwd): " password

    echo ${username:="admin@sec.com"}  ${password:="$randompwd"}

    ssh_t ${php_host}  "\
    cd ${register_back_v3_dir} && \
    sudo ${PHP_EXEC} ${register_back_v3_script} ${username:=\"admin@sec.com\"} ${password:=\"sec.com@qt2020\"};"

    check_register_acct "Register backend default account "

    info_log "=================== 注册Patrol账号 ==================="
    randompwd=`head /dev/urandom | tr -dc A-Za-z0-9@%_ | head -c 13`
    read -ep "Input username (default: admin): " username
    read -ep "Input password (default: $randompwd): " password
    echo ${username:="admin"}  ${password:="$randompwd"} 
    
    md5passwd=`echo -n $password|md5sum|cut -d ' ' -f1`
    local php_ips=`get_ips php_frontend_private`
    for php_ip in ${php_ips[@]} ; do
        ssh_t ${php_ip} "sudo sqlite3 /data/app/titan-patrol-srv/db.sqlite \"update patrol_user set password='$md5passwd', username='$username';\" "
    done

    check_register_acct "Register patrol default account "

    read -p "Please remeber user info, Enter to continue "
}


distribute(){

    local version=$1
    distribute_connect_agent
    distribute_connect_sh
    distribute_connect_dh
    distribute_connect_selector

    #bigdata
    distribute_bigdata
    #scan
    distribute_scan
    #anti-virus
    distribute_anti_virus

    #java
    [ "${version}" = "v3" ] && distribute_titan_wisteria

    #srv
    distribute_event
    distribute_ms
    #php
    distribute_titan_web
}

configuration(){
    local version=$1
    local usage=$2
    # upload ip_template.json to php server
    distribute_config
    # take effect
    execute_config_py ${version} ${usage:="2"}
}

launch_services(){

    local version=$1

    start_php_worker ${version}

    start_connect_agent
    start_connect_dh

    start_connect_selector
    start_connect_sh

    start_bigdata_logstash
    start_bigdata_viewer
    start_docker_scan

    start_anti_virus

    #java
    if [ "${version}" = "v3" ]; then
        info_log "Restart java [Y/N] ? default is Y"
        read -p "Enter [Y/N]: " Enter
        [ -z "${Enter}" -o "${Enter}" = "Y" -o "${Enter}" = "y" ] && start_titan_wisteria
    fi
    start_ms_srv
    start_event_srv

}

initialization(){
    local version=$1
    # sync rules
    start_init_data

    # register default account
    register_default_account ${version:="v2"}
}

webinstall(){
    local name=$1
    case ${name} in 
        logstash)
            distribute_bigdata_logstash
            ;;
        viewer)
            distribute_bigdata_viewer
            ;;
        docker_scan)
            distribute_scan
            ;;
        anti_virus)
            distribute_anti_virus
            ;;
        ms_srv)
            distribute_ms
            ;;
        event_srv)
            distribute_event
            ;;
        wisteria)
            distribute_webinstall_titan_wisteria
            ;;
        web)
            distribute_webinstall_titan_web
            ;;
        agent)
            distribute_titan_agent
            ;;  
        connect_agent)
            distribute_webinstall_connect_agent
            ;;
        connect_dh)
            distribute_connect_dh
            ;;
        connect_sh)
            distribute_connect_sh
            ;;
        connect_selector)
            distribute_connect_selector
            ;;
        *)
            help
            ;;
    esac
}

install(){

    local version=$1

    info_log "================== RPM Installation =================="
    # distribution && install rpm
    distribute ${version:="v2"}

    local mysql_pass=`grep -A 3 "mysql" ${CUSTOMIZE_FILE} |grep "password" | awk -F ":*" '{print $2}' |awk -F ",*" '{print $1}'|awk -F "\"*" '{print $2}'`
    if [ -e $FILE_ROOT/common/qingteng-rules*.tar.gz ] && [ ! ${mysql_pass} ];then
        preset_rules
    else
        # create databases
        [ -d /data/mysql/qt_titan_connect ] || init_mysql_php
    fi

    info_log "================== Configuration ====================="
    configuration ${version:="v2"} "0"

    info_log "================== Update thunderfire ================"
    update_thunderfire auto

    info_log "================== Launching Services ================"
    # launching services
    launch_services ${version:="v2"}

    info_log "================== Initialization ===================="
    # init data && sync rules
    initialization ${version:="v2"}
}

app_upgrade(){

    IS_UPGRADE=true

    local version=$1
    local ver_1=${version}
    local ver_2=${version}

    [ ${version} = "v2tov3" ] && ver_1="v2" && ver_2="v3"

    info_log "Stopping services [Y/N] ? default is Y"
    read -p "Enter [Y/N]: " Enter
    [ -z "${Enter}" -o  "${Enter}" = "Y" -o "${Enter}" = "y" ] && setup_np_ssh_erlang && stop_erlang_services

    # basic lib config changed, then use upgrade-conf.sh to update config files
    info_log "upgrade config hotfix [Y/N] ? default is N"
    read -p "Enter [Y/N]: " Enter
    [ "${Enter}" = "Y" -o "${Enter}" = "y" ] && bash ${FILE_ROOT}/upgrade-conf.sh

    info_log "Distributing installation packages [Y/N] ? default is Y"
    read -p "Enter [Y/N]: " Enter
    [ -z "${Enter}" -o  "${Enter}" = "Y" -o "${Enter}" = "y" ] && distribute ${ver_1}

    info_log "Distribute config files [Y/N] ? default is Y"
    read -p "Enter [Y/N]: " Enter
    [ -z "${Enter}" -o  "${Enter}" = "Y" -o "${Enter}" = "y" ] && distribute_config && execute_config_py ${ver_2} "1"


    ##----------java license-------------##
    update_titan_license


    info_log "Restart php [Y/N] ? default is Y"
    read -p "Enter [Y/N]: " Enter
    [ -z "${Enter}" -o  "${Enter}" = "Y" -o "${Enter}" = "y" ] && start_php_worker ${ver_2}

    info_log "Restart connect [Y/N] ? default is Y"
    read -p "Enter [Y/N]: " Enter
    [ -z "${Enter}" -o "${Enter}" = "Y" -o "${Enter}" = "y" ] && start_connect_agent && start_connect_dh && start_connect_selector && start_connect_sh

    info_log "Restart Bigdata [Y/N] ? default is Y"
    read -p "Enter [Y/N]: " Enter
    if [ -z "${Enter}" -o "${Enter}" = "Y" -o "${Enter}" = "y" ] ;then
        stop_bigdata_logstash
        start_bigdata_logstash
        stop_bigdata_viewer
        start_bigdata_viewer
    fi

    # info_log "Restart Docker Scan [Y/N] ? default is Y"
    # read -p "Enter [Y/N]: " Enter
    local scan_ips=`get_ips java_scan-srv`
    local scan_ip_len=${#scan_ips[@]}
    if [ $scan_ip_len -gt 0 ] ;then
        stop_docker_scan
        start_docker_scan
    fi

    local anti_virus_ips=`get_ips java_anti-virus-srv`
    local anti_virus_ip_len=${#anti_virus_ips[@]}
    if [ $anti_virus_ip_len -gt 0 ] ;then
        stop_anti_virus
        start_anti_virus
    fi

    local ms_ips=`get_ips java_ms-srv`
    local ms_ip_len=${#ms_ips[@]}
    if [ $ms_ip_len -gt 0 ] ;then
        ms_srv_config recover
        stop_ms_srv
        start_ms_srv
    fi
    # 启动event-srv
    stop_event_srv
    start_event_srv
}

app_upgrade_to_cluster(){

    IS_UPGRADE=true

    local version=$1
    local ver_1=${version}
    local ver_2=${version}

    info_log "Distributing installation packages [Y/N] ? default is Y"
    read -p "Enter [Y/N]: " Enter
    [ -z "${Enter}" -o  "${Enter}" = "Y" -o "${Enter}" = "y" ] && distribute ${ver_1}

    info_log "Distribute config files [Y/N] ? default is Y"
    read -p "Enter [Y/N]: " Enter
    [ -z "${Enter}" -o  "${Enter}" = "Y" -o "${Enter}" = "y" ] && distribute_config && execute_config_py ${ver_2} "3"

    ##----------java license-------------##
    update_titan_license

    info_log "Restart php [Y/N] ? default is Y"
    read -p "Enter [Y/N]: " Enter
    [ -z "${Enter}" -o  "${Enter}" = "Y" -o "${Enter}" = "y" ] && start_php_worker ${ver_2}

    info_log "Restart connect [Y/N] ? default is Y"
    read -p "Enter [Y/N]: " Enter
    [ -z "${Enter}" -o "${Enter}" = "Y" -o "${Enter}" = "y" ] && start_connect_agent && start_connect_dh && start_connect_selector && start_connect_sh

    info_log "Restart Bigdata [Y/N] ? default is Y"
    read -p "Enter [Y/N]: " Enter
    if [ -z "${Enter}" -o "${Enter}" = "Y" -o "${Enter}" = "y" ] ;then
        stop_bigdata_logstash
        start_bigdata_logstash
        stop_bigdata_viewer
        start_bigdata_viewer
    fi

    # info_log "Restart Docker Scan [Y/N] ? default is Y"
    # read -p "Enter [Y/N]: " Enter
    local scan_ips=`get_ips java_scan-srv`
    local scan_ip_len=${#scan_ips[@]}
    if [ $scan_ip_len -gt 0 ] ;then
        stop_docker_scan
        start_docker_scan
    fi

    local anti_virus_ips=`get_ips java_anti-virus-srv`
    local anti_virus_ip_len=${#anti_virus_ips[@]}
    if [ $anti_virus_ip_len -gt 0 ] ;then
        stop_anti_virus
        start_anti_virus
    fi

    local ms_ips=`get_ips java_ms-srv`
    local ms_ip_len=${#ms_ips[@]}
    if [ $ms_ip_len -gt 0 ] ;then
        stop_ms_srv
	ms_srv_config recover
        start_ms_srv
    fi
    # 启动event-srv
    stop_event_srv
    start_event_srv
}
#updata thp

app_upgrade_thp(){

    IS_UPGRADE=true

    local version=$1
    local ver_1=${version}
    local ver_2=${version}

    [ ${version} = "v2tov3" ] && ver_1="v2" && ver_2="v3"
    info_log "upgrade config hotfix [Y/N] ? default is N"
    read -p "Enter [Y/N]: " Enter
    [ "${Enter}" = "Y" -o "${Enter}" = "y" ] && bash ${FILE_ROOT}/upgrade-conf.sh
    
    info_log "Distributing installation packages [Y/N] ? default is Y"
    read -p "Enter [Y/N]: " Enter
    [ -z "${Enter}" -o  "${Enter}" = "Y" -o "${Enter}" = "y" ] && distribute_bigdata
    
    info_log "Distribute config files [Y/N] ? default is Y"
    read -p "Enter [Y/N]: " Enter
    [ -z "${Enter}" -o  "${Enter}" = "Y" -o "${Enter}" = "y" ] && distribute_config_thp && execute_config_py_thp ${ver_2}
    
    ##----------java license-------------##
    update_titan_license

#    info_log "Restart php [Y/N] ? default is Y"
#    read -p "Enter [Y/N]: " Enter
#    [ -z "${Enter}" -o  "${Enter}" = "Y" -o "${Enter}" = "y" ] && start_php_worker ${ver_2}
    
    info_log "Restart connect [Y/N] ? default is Y"
    read -p "Enter [Y/N]: " Enter
    [ -z "${Enter}" -o "${Enter}" = "Y" -o "${Enter}" = "y" ] && start_connect_agent && start_connect_dh && start_connect_selector && start_connect_sh
    
    info_log "Restart Bigdata [Y/N] ? default is Y"
    read -p "Enter [Y/N]: " Enter
    if [ -z "${Enter}" -o "${Enter}" = "Y" -o "${Enter}" = "y" ] ;then
        stop_bigdata_logstash
        start_bigdata_logstash
        stop_bigdata_viewer
        start_bigdata_viewer
    fi   
    
    # info_log "Restart Docker Scan [Y/N] ? default is Y"
    # read -p "Enter [Y/N]: " Enter
    # local scan_ips=`get_ips java_scan-srv`
    # local scan_ip_len=${#scan_ips[@]}
    # if [ $scan_ip_len -gt 0 ] ;then
    #      stop_docker_scan 
    #      start_docker_scan
    # fi                                       
}       
# upgrade from 2.x to 2.x (include v3-lite)
upgrade_v2(){
    # application upgrade
    app_upgrade v2
    # rules update
    start_init_data
}
#backup erlang data
backup_erlang_data(){

	info_log "begin to backup erlang data..."
	local old_om_ip=`get_ip java_connect-agent`
	local php_host=`get_ip php_inner_api`
        [ -z "${old_om_ip}" ] && error_log "java_connect-agent_ip's ip is empty"
        if [ "$old_om_ip" != "127.0.0.1" ];then
            local connectagent_status=`ssh_t ${old_om_ip} "test -f /data/app/titan-connect-agent/connect-agent.jar && echo connectagent_exist"`
            local result=$(echo $connectagent_status | grep "connectagent_exist")
            if [[ "$result" != "" ]]; then
                info_log "connect already install, no need backup erlang data"
                return 
            fi
            # distribute erlang_migrate to OM node
            execute_rsync ${old_om_ip} ${LOACL_ERL_MIGRATE_PATH} /data/servers
            # backup scripts 
            ssh_t ${old_om_ip} "cd ${REMOTE_ERL_MIGRATE_PATH} && sudo /data/servers/titan_root/titan_server/titan_otp/otp-1.0.0/priv/pkg/bin/escript ${REMOTE_ERL_MIGRATE_PATH}/export-scripts.escript"
            check "Check backup scripts"
            # backup ras key
            ssh_t ${old_om_ip} "cd ${REMOTE_ERL_MIGRATE_PATH} && sudo /data/servers/titan_root/titan_server/titan_otp/otp-1.0.0/priv/pkg/bin/escript ${REMOTE_ERL_MIGRATE_PATH}/keys-backup.escript"
            check "Check backup ras key "

            #rsync erlang data to PHP server /data/erlang_migrate
            [ ! -d /data/erlang_migrate ] && sudo mkdir -p /data/erlang_migrate/
            remote_scp ${old_om_ip} ${REMOTE_ERL_MIGRATE_PATH}/scripts /data/erlang_migrate/
            remote_scp ${old_om_ip} ${REMOTE_ERL_MIGRATE_PATH}/company.backup /data/erlang_migrate/

            #backup erlang release 
            execute_rsync ${php_host} ${LOACL_ERL_MIGRATE_PATH}/export-erlang-release.php /data/app/www/titan-web/script/
            ssh_t ${php_host} "sudo /usr/local/php/bin/php /data/app/www/titan-web/script/export-erlang-release.php /data/erlang_migrate"
            check "Check backup erlang release "           
        fi	
}

erlang_migrate(){
    local selector_ip=`get_ip java_connect-selector`        
    local php_host=`get_ip php_inner_api`
    local selector_status=`ssh_nt ${selector_ip} "test ! -d /data/app/titan-selector/ && echo selector_not_exist"`
    local result=$(echo $selector_status | grep "selector_not_exist")
    if [[ "$result" == "selector_not_exist" ]]; then
        info_log "erlang already remove, no need erlang migrate"
        return 
    fi
    
    info_log "Merging erlang data [Y/N] ? default is Y"
    read -p "Enter [Y/N]: " Enter
    if [ -z "${Enter}" -o "${Enter}" = "Y" -o "${Enter}" = "y" ];then
        ssh_t ${php_host} "\
        sudo /usr/local/php/bin/php /data/app/www/titan-web/script/migration.php -c import_erlang_release -dir /data/erlang_migrate;\
        sudo /usr/local/php/bin/php /data/app/www/titan-web/script/migration.php -c user -rsa_key_file /data/erlang_migrate/company.backup" 
        check "Check Merging erlang data "

        # change php logs permission
        ssh_t ${php_host} "sudo chown -R nginx:nginx /data/titan-logs/php/cli_log/update"
        #mv erlang data dir
        ssh_t ${selector_ip} "sudo mv -f /data/app/titan-selector/ /data/app/titan-selector-bak"
        local mv_erlang_done=""
        for node in ${PACKAGE_TITAN_SERVER[*]};
        do
            local ip=`get_ip ${node}`
            if [ -z `echo ${mv_erlang_done} |grep ${ip}` ]; then
                    ssh_t ${ip} "sudo mv -f /data/app/titan-servers/ /data/app/titan-servers-bak"
                    mv_erlang_done="${mv_erlang_done}**${ip}"
            fi
        done
    fi

}

# upgrade from 3.x to 3.x
upgrade_v3(){
    info_log "Stopping Java Server [Y/N] ? default is Y"
    read -p "Enter [Y/N]: " Enter
    [ -z "${Enter}" -o "${Enter}" = "Y" -o "${Enter}" = "y" ] && stop_titan_wisteria
    
    stop_bigdata_logstash
    stop_bigdata_viewer
    stop_ms_srv
    ##back application
    ms_srv_config back
    stop_event_srv
    stop_patrol
    app_upgrade v3
    
    info_log "================== Update thunderfire ================"
    update_thunderfire auto

    info_log "Restart java [Y/N] ? default is Y"
    read -p "Enter [Y/N]: " Enter
    [ -z "${Enter}" -o "${Enter}" = "Y" -o "${Enter}" = "y" ] && start_titan_wisteria

    start_init_data upgrade
}

upgrade_thp(){
    info_log "Stopping Java Server [Y/N] ? default is Y"
    read -p "Enter [Y/N]: " Enter
    [ -z "${Enter}" -o "${Enter}" = "Y" -o "${Enter}" = "y" ] && stop_titan_wisteria
    #stop_bigdata_logstash
    #stop_bigdata_viewer
    app_upgrade_thp v3
    
    info_log "================== Update thunderfire ================"
    update_thunderfire auto

    info_log "Restart java [Y/N] ? default is Y"
    read -p "Enter [Y/N]: " Enter
    [ -z "${Enter}" -o "${Enter}" = "Y" -o "${Enter}" = "y" ] && start_titan_wisteria

    start_init_data upgrade_thp
}

# upgrade from 3.4.0 normal to 3.4.0 cluster
upgrade_v3_to_cluster(){
    info_log "Stopping Java Server [Y/N] ? default is Y"
    read -p "Enter [Y/N]: " Enter
    [ -z "${Enter}" -o "${Enter}" = "Y" -o "${Enter}" = "y" ] && stop_titan_wisteria
    stop_ms_srv
    ##back application
    ms_srv_config back
    stop_event_srv
    app_upgrade_to_cluster v3

    info_log "================== Update thunderfire ================"
    update_thunderfire auto

    info_log "Restart java [Y/N] ? default is Y"
    read -p "Enter [Y/N]: " Enter
    [ -z "${Enter}" -o "${Enter}" = "Y" -o "${Enter}" = "y" ] && start_titan_wisteria
    
    start_init_data upgrade
}


titan_mysql_dump(){
    local java_ip=`get_ip java`
    local mysql_ip=`get_ip db_mysql_php`
    ssh_t ${java_ip} "[ -f /data/app/titan-wisteria/config/java.json ] || (echo \"java.json not found\" && exit 1); \
    sudo sed -i \"s/127.0.0.1/${mysql_ip}/g\" /data/app/titan-wisteria/config/java.json && \
    cd /data/app/titan-wisteria/v3-upgrade-script && \
    python2.7 upgrade.py backup"
}

titan_mysql_rollback(){
    local java_ip=`get_ip java`
    ssh_t ${java_ip} "cd /data/app/titan-wisteria/v3-upgrade-script && \
    python2.7 upgrade.py restore"
}

titan_db_merge(){
    local java_ip=`get_ip java`
    local comId=$1
    ssh_t ${java_ip} "cd /data/app/titan-wisteria/v3-upgrade-script && \
    python2.7 upgrade.py merge --main ${comId}"
}

java_db_flush(){
    local java_ip=`get_ip java`
    local comId=$1
    ssh_t ${java_ip} "cd /data/app/titan-wisteria/v3-upgrade-script && \
    python2.7 upgrade.py flushv3"
}

java_clean_cache(){
    local java_ip=`get_ip java`
    local comId=$1
    ssh_t ${java_ip} "cd /data/app/titan-wisteria/v3-upgrade-script && \
    python2.7 upgrade.py clearcache"
}

switch_company(){
    local java_ip=`get_ip java`
    local comId=$1
    local subId=$2
    ssh_t ${java_ip} "cd /data/app/titan-wisteria/v3-upgrade-script && \
    python2.7 upgrade.py switchcom --main ${comId} --sub ${subId}"
}


db_migrate(){

    info_log "Merging database [Y/N] ? default is Y"
    read -p "Enter [Y/N]: " Enter
    [ -z "${Enter}" -o "${Enter}" = "Y" -o "${Enter}" = "y" ] && \
    read -p "Input main comId: " Enter
    [ -z "${Enter}" ] && error_log "CompanyID is empty"
    [ ${#Enter} -eq 20 ] && java_db_flush && titan_db_merge ${Enter} || error_log "unexpected: ${Enter}"
}

customized_rules_migrate(){

    local php_host=`get_ip php_inner_api`

    info_log "Import customized baseline [Y/N]? default is N"
    read -p "Enter [Y/N]: " Enter
    [ "${Enter}" = "Y" -o "${Enter}" = "y" ] && \
    read -p "Input comId: " Enter && \
    ([ -z "${Enter}" ] && error_log "CompanyID is empty";

    [ ${#Enter} -eq 20 ] && ssh_t ${php_host} "\
    ${PHP_EXEC} ${WEB_PATH}/worker/tools/pa-baseline-rule-import-tool.php comid ${Enter};" || error_log "unexpected: ${Enter}")

    info_log "Import customized rules (webfile & shell-white)"
    ssh_t ${php_host}  "\
    cd ${WEB_PATH}/update/cli && ${PHP_EXEC} tool-webfile-sync.php;\
    cd ${WEB_PATH}/update/cli && ${PHP_EXEC} tool-import-shell-white.php"
}

upgrade_v2_to_v3(){

    info_log "Distribute Java application ? default is Y"
    read -p "Enter [Y/N]: " Enter
    [ -z "${Enter}" -o "${Enter}" = "Y" -o "${Enter}" = "y" ] && distribute_titan_wisteria

    info_log "Dumping database...."
    titan_mysql_dump

    # upgrade Erlang and PHP application
    app_upgrade v2tov3

    start_init_data

    # db from v2 to v3
    db_migrate

    info_log "================== Update thunderfire ================"
    update_thunderfire auto

    info_log "Restart java [Y/N] ? default is Y"
    read -p "Enter [Y/N]: " Enter
    [ -z "${Enter}" -o "${Enter}" = "Y" -o "${Enter}" = "y" ] && start_titan_wisteria && java_clean_cache


    #info_log "Migrate customized rules"
    #customized_rules_migrate

}

## -------------------------- Start ------------------------------ ##
version_ge(){
    #test "$(echo "$@" | tr " " "\n" | sort -rV | head -n 1)" == "$1";
    version_app=$(echo $1|cut -d "_" -f1|sed 's#\.##g')
    version_install_app=$(echo $2 |cut -d"_" -f1|sed 's#\.##g')
    time_app=$(echo $1|cut -d "_" -f2)
    time_install_app=$(echo $2|cut -d "_" -f2)
    if [ $(expr $version_app \= $version_install_app) == "1" ];then
        if [ $(expr $time_app \>= $time_install_app) == "1" ];then
                return 1
        else
                return 0
        fi
    elif [ $(expr $version_app \> $version_install_app) == "1" ];then
        return 1
    else
        return 0
    fi
}


check_version(){
    for node in ${PACKAGE_TITAN_WEB[*]};do
    local ips=(`get_ips ${node}`)
            [ -z "${ips}" ] && error_log "${node}'s ip is empty"
            VERSION_INSTALLED=`ssh -p ${DEFAULT_PORT} -oStrictHostKeyChecking=no -o ConnectionAttempts=5 ${DEFAULT_USER}@${ips[0]} "[ -f /data/install/app-version.json ] && sudo sed -n 's/.*\"version\":\"\([^\"]*\)\".*/\1/p' /data/install/app-version.json" |sudo sed 's/v//g'`
    done

    APP_VERSION=`sudo sed -n 's/.*"version":"\([^"]*\)".*/\1/p' ${APP_VERSION_JSON} | sed 's/v//g'`
    if [[ -z $VERSION_INSTALLED ]]; then
        info_log "installed app version is less than 330, no app-version.json, continue upgrade"
        return
    else
        version_ge $APP_VERSION $VERSION_INSTALLED
        if [ $? == "1" ]; then
            info_log "app version:$APP_VERSION is greater than or equal to $VERSION_INSTALLED,continue upgrade"
        else
            error_log "app version:$APP_VERSION is less than installed version:$VERSION_INSTALLED"
        fi
    fi
}


unzip_rules(){
    zipfile=`ls -t ${FILE_ROOT}/*-v*-*.zip | head -1`
    [ -z "${zipfile}" ] && exit 1

    [ -d ${FILE_ROOT}/rules ] && rm -rf ${FILE_ROOT}/rules
    mkdir -p ${FILE_ROOT}/rules
    unzip ${zipfile} -d ${FILE_ROOT}/rules
}

unzip_license(){
    license_zipfile=`ls -t ${FILE_ROOT}/*-license*.zip | head -1`
    [ -z "${license_zipfile}" ] && exit 1

    [ -d ${FILE_ROOT}/license ] && rm -rf ${FILE_ROOT}/license
    mkdir -p ${FILE_ROOT}/license
    unzip ${license_zipfile} -d ${FILE_ROOT}/license
    
    license_version=`sed -n 's/.*"version":"\([^"]*\)".*/\1/p' ${FILE_ROOT}/license/license.key`
    app_version=`sed -n 's/.*"version":"\([^"]*\)".*/\1/p' ${APP_VERSION_JSON}`
    IS_DOCKER=`sed -n 's/.*"docker":*\([a-zA-Z]\+\).*/\1/p' ${FILE_ROOT}/license/license.key`
    #IS_BIGDATA=`sed -n 's/.*"bigdata":*\([a-zA-Z]\+\).*/\1/p' ${FILE_ROOT}/license/license.key`
    #IS_THP=`sed -n 's/.*"thp":*\([a-zA-Z]\+\).*/\1/p' ${FILE_ROOT}/license/license.key`
    IS_MS=`sed -n 's/.*"ms_srv":*\([a-zA-Z]\+\).*/\1/p' ${FILE_ROOT}/license/license.key`
    IS_EVENT=`sed -n 's/.*"event_srv":*\([a-zA-Z]\+\).*/\1/p' ${FILE_ROOT}/license/license.key`
    IS_ANTI_VIRUS=`sed -n 's/.*"antivirus-srv":*\([a-zA-Z]\+\).*/\1/p' ${FILE_ROOT}/license/license.key`
    #if [ $? != "0" ];then
    #    IS_THP="false"
    #fi
    
    #checking the status between license file and ip_template.json
    local ms_srv_ip=`get_ip java_ms-srv`
    local event_srv_ip=`get_ip java_event-srv`
    if [[ "$event_srv_ip" = "127.0.0.1" && "$IS_EVENT" = "true" ]];then
        error_log "event-srv status is mismatch between license file and ip_template.json"
    elif [[ "$event_srv_ip" != "127.0.0.1" && "$IS_EVENT" = "false" ]];then
        error_log "event-srv status is mismatch between license file and ip_template.json"
    fi
    #check license thp status
    if [[ "$ms_srv_ip" = "127.0.0.1" && "$IS_MS" = "true" ]];then
        error_log "ms-srv status is mismatch between license file and ip_template.json"
    elif [[ "$ms_srv_ip" != "127.0.0.1" && "$IS_MS" = "false" ]]; then
        error_log "ms-srv status is mismatch between license file and ip_template.json"
    elif [[ "$ms_srv_ip" != "127.0.0.1" && "$IS_EVENT" = "false" ]]; then
        error_log "event-srv status and ms-srv status is mismatch between license file and ip_template.json"
    fi


    local scan_ip=`get_ip java_scan-srv`
    if [[ "$scan_ip" = "127.0.0.1" && "$IS_DOCKER" = "true" ]];then
        error_log "docker status is mismatch between license file and ip_template.json"
    elif [[ "$scan_ip" != "127.0.0.1" && "$IS_DOCKER" = "false" ]]; then
        error_log "docker status is mismatch between license file and ip_template.json"
    fi

    local anti_virus_ip=`get_ip java_anti-virus-srv`
    if [[ "$anti_virus_ip" = "127.0.0.1" && "$IS_ANTI_VIRUS" = "true" ]];then
        error_log "anti_virus status is mismatch between license file and ip_template.json"
    elif [[ "$anti_virus_ip" != "127.0.0.1" && "$IS_ANTI_VIRUS" = "false" ]]; then
        error_log "anti_virus status is mismatch between license file and ip_template.json"
    fi
    
    local ms_ip=`get_ip java_ms-srv`
    if [[ "$ms_ip" = "127.0.0.1" && "$IS_MS" = "true" ]];then
        error_log "ms_srv status is mismatch between license file and ip_template.json"
    elif [[ "$ms_ip" != "127.0.0.1" && "$IS_MS" = "false" ]]; then
        error_log "ms_srv status is mismatch between license file and ip_template.json"
    fi
    ## checking version in license.key equals to the version in version.json
    if [[ $license_version == "" || ! $app_version =~ $license_version.* ]]; then
        error_log " license file version not equals to app version"
    fi
    ## bak license.zip to /data/install
    for node in ${PACKAGE_TITAN_WEB[*]};
    do
        local ip=`get_ip ${node}`
        ssh_t ${ip} "sudo mkdir -p /data/install/do-not-manually-copy-files-to-this-dir/"
        ssh_t ${ip} "sudo rm -fr /data/install/do-not-manually-copy-files-to-this-dir/titan-license-*.zip"
        rsync -rz --rsync-path="sudo rsync" -e "ssh -p $DEFAULT_PORT"  --delete ${license_zipfile} ${DEFAULT_USER}@${ip}:/data/install/do-not-manually-copy-files-to-this-dir/
    done
}
update_titan_license(){

    ##----------java license-------------##
    info_log "begin to write java license to zookeeper..."
    local zookeeper=(java_zookeeper java_zookeeper_cluster)
    local java_lic=`ls -t ${FILE_ROOT}/*/license.key |head -1`
    local java_package_sent=""
    for node in ${zookeeper[*]};
    do
        local zk_ip=`get_ip ${node}`
        if [ $zk_ip == "127.0.0.1" ]; then
            continue
        fi
        local license_content="`cat $java_lic`"
        local first_ip_port=${zk_ip%%,*}
        zk_ip=${first_ip_port%%:*}
        ssh_t $zk_ip "/usr/local/qingteng/zookeeper/bin/zkCli.sh -server 127.0.0.1:2181 create /license null"
        ssh_t $zk_ip <<EOF
/usr/local/qingteng/zookeeper/bin/zkCli.sh -server 127.0.0.1:2181 create /license/license.key '${license_content}'
EOF
        ssh_t $zk_ip <<EOF 
/usr/local/qingteng/zookeeper/bin/zkCli.sh -server 127.0.0.1:2181 set /license/license.key '${license_content}'
EOF
        ssh_t $zk_ip "/usr/local/qingteng/zookeeper/bin/zkCli.sh -server 127.0.0.1:2181 setAcl /license/license.key sasl:qingteng:cdrwa"
        break;
    done
}

update_php_license(){
    local php_host=`get_ip php_inner_api`
    execute_rsync ${php_host} ${FILE_ROOT}/license/ ${WEB_PATH}/license
    sudo ${PHP_EXEC} ${WEB_PATH}/update/cli/license.php ${WEB_PATH}/license || exit 1
}

init_headquarters(){
    local php_host=`get_ip php_inner_api`
    ssh_t ${php_host} "sudo /usr/bin/python /data/app/www/titan-web/config_scripts/config_hq.py"
}

init_datasync(){
    local php_host=`get_ip php_inner_api`
    ssh_t ${php_host} "sudo /usr/bin/python /data/app/www/titan-web/config_scripts/config_datasync.py"
}

#kafka新增大数据的topic
alter_thp_kafka(){
    local php_host=`get_ip php_inner_api`
    ssh_t ${php_host} "sudo /usr/bin/python /data/app/www/titan-web/config_scripts/config_thp.py alter_topic_config"
}

#单独卸载微隔离
uninstall_ms(){
    #更新去掉微隔离的授权和规则
    start_init_data upgrade

    echo "开始卸载微隔离相关信息"
    #停止ms_srv的进程
    local ms_hosts=`get_ips java_ms-srv`
    for host in ${ms_hosts}; do
        ssh_t ${host} "sudo service ms-srv stop"
        ssh_t ${host} "sudo rpm -e \`rpm -qa|grep titan-ms-srv|tail -1\`"
    done
 
    #卸载ms_mongo
    local ms_mongo_hosts=`get_ips db_mongo_ms_srv`
    time=`date +%Y%m%d%H%M%S`
    for mongo_host in ${ms_mongo_hosts}; do
        ssh_t ${mongo_host} "sudo service mongod stop"
        ssh_t ${mongo_host} "sudo mv /data/mongodb /data/mongodb-bak-${time} && sudo rpm -e qingteng-mongodb"
        ssh_t ${mongo_host} "[ -d /data/mongocluster ]"
        if [ $? -eq 0 ]; then
            ssh_t ${mongo_host} "sudo service mongocluster stop"
            ssh_t ${mongo_host} "sudo mv /data/mongocluster /data/mongocluster-bak-${time} && sudo rpm -e qingteng-mongocluster"
        fi
    done

    #kafka清理
    local php_host=`get_ip php_inner_api`
    ssh_t ${php_host} "sudo /usr/bin/python /data/app/www/titan-web/config_scripts/uninstall_ms.py del_kafka_topic"

    #修改mysql表
    local php_host=`get_ip php_inner_api`
    ssh_t ${php_host} "sudo /usr/bin/python /data/app/www/titan-web/config_scripts/uninstall_ms.py alter_mysql_table"

    #替换ip_template.json的ms_srv和ms_mongo的ip为127.0.0.1,更新ip.json
    sudo /usr/bin/python ./ip-config.py --del_ms_ip

    #删除service_ip.conf的ms_srv和ms_mongo配置
    [ -f ../titan-base/service_ip.conf ] && sudo sed -i '/ms_srv/d' ../titan-base/service_ip.conf
    [ -f ../titan-base/service_ip.conf ] && sudo sed -i '/mongo_ms_srv/d' ../titan-base/service_ip.conf
}

deploy_status=$1
while [ $# -gt 0 ]; do
    case $1 in
        distribute)
            # distribute packages & install rpm
            [ $# -ne 2 ] && echo "bash ./titan-app.sh distribute (v2 | v3)" && exit 1
            [ "$2" != "v2" -a "$2" != "v3" ] && echo "bash ./titan-app.sh distribute (v2 | v3)" && exit 1
            unzip_rules
            unzip_license
            distribute $2
            exit 0
            ;;
        config)
            # scp ip_template.json to php server, execute config.py on php server
            [[ $# -ne 2 && $# -ne 3 ]] && echo "bash ./titan-app.sh config (v2 | v3)" && exit 1
            [ "$2" != "v2" -a "$2" != "v3" ] && echo "bash ./titan-app.sh config (v2 | v3)" && exit 1
            configuration $2 $3
            exit 0
            ;;
        init_db)
            # create databases & init data
            init_mysql_php
            exit 0
            ;;
        launch)
            # start application
            [ $# -ne 2 ] && echo "bash ./titan-app.sh launch (v2 | v3)" && exit 1
            [ "$2" != "v2" -a "$2" != "v3" ] && echo "bash ./titan-app.sh launch (v2 | v3)" && exit 1
            launch_services $2
            exit 0
            ;;
        init_data)
            # sync rules, agent, bash
            unzip_rules
            unzip_license
            start_init_data
            exit 0
            ;;
        init_data_upgrade)
            # sync rules, agent, bash for upgarde
            unzip_rules
            unzip_license
            start_init_data upgrade
            exit 0
            ;;
        webpreset_rules)
            # web preset rules
            webpreset_rules
            exit 0
            ;;
        preset_rules)
            #preset rules
            unzip_rules
            unzip_license
            preset_rules
            exit 0
            ;;
        register)
            # register default account
            [ $# -ne 2 ] && echo "bash ./titan-app.sh register (v2 | v3)" && exit 1
            [ "$2" != "v2" -a "$2" != "v3" ] && echo "bash ./titan-app.sh install (v2 | v3)" && exit 1
            register_default_account $2
            exit 0
            ;;
        install)
            [ $# -ne 2 ] && echo "bash ./titan-app.sh install (v2 | v3)" && exit 1
            [ "$2" != "v2" -a "$2" != "v3" ] && echo "bash ./titan-app.sh install (v2 | v3)" && exit 1
            unzip_rules
            unzip_license
            install $2
            check_backend_account
            backup_config
            exit 0
            ;;
        webinstall)
            webinstall $2
            exit 0
            ;;
        upgrade)
            [ $# -ne 2 ] && echo "bash ./titan-app.sh upgrade (v2 | v3)" && exit 1
            [ "$2" != "v2" -a "$2" != "v3" ] && echo "bash ./titan-app.sh upgrade (v2 | v3)" && exit 1
            check_version
            unzip_rules
            unzip_license
            backup_config
            backup_erlang_data
            [ "$2" = "v2" ] && upgrade_v2
            [ "$2" = "v3" ] && upgrade_v3 && check_backend_account
            erlang_migrate
            exit 0
            ;;
        upgrade_to_cluster)
            unzip_rules
            unzip_license
            backup_config
            upgrade_v3_to_cluster && check_backend_account
            exit 0
            ;;
        backup_erlang_data)
            backup_erlang_data
            exit 0
            ;;
        erlang_migrate)
            erlang_migrate
            exit 0
            ;;
        upgrade_v2_to_v3)
            unzip_rules
            unzip_license
            upgrade_v2_to_v3
            check_backend_account
            exit 0
            ;;
        check_backend_account)
            check_backend_account
            exit 0
            ;;
        update_rules)
            # update rules
            unzip_rules
            php_host=`get_ip php_inner_api`
            sync_rules ${php_host}
            exit 0
            ;;
        update_agent_url)
            php_host=`get_ip php_inner_api`
            update_agent_config ${php_host}
            exit 0
            ;;
        update_agent_url_upgrade)
            php_host=`get_ip php_inner_api`
            update_agent_config ${php_host} upgrade
            exit 0
            ;;
        update_license)
            unzip_license
            update_titan_license
            update_php_license
            exit 0
            ;;
        restart_php)
            [ $# -ne 2 ] && echo "bash ./titan-app.sh restart_php (v2 | v3)" && exit 1
            [ "$2" != "v2" -a "$2" != "v3" ] && echo "bash ./titan-app.sh restart_php (v2 | v3)" && exit 1
            start_php_worker $2
            exit 0
            ;;
        stop_erlang)
            setup_np_ssh_erlang
            #stop all erlang services (titan-server, channel, selector)
            stop_erlang_services
            exit 0
            ;;
        start_erlang)
            setup_np_ssh_erlang
            # all erlang services
            start_erlang_services
            exit 0
            ;;
        start_server)
            # titan-server
            start_titan_server
            exit 0
            ;;
        stop_server)
            stop_titan_server
            exit 0
            ;;
        restart_om)
            # titan-server: om (distribution)
            start_server_role ${SERVER_EXEC} om_node
            exit 0
            ;;
        restart_dh)
            # titan-server: dh (distribution)
            start_server_role ${SERVER_EXEC} dh_node
            exit 0
            ;;
        restart_sh)
            # titan-server: sh l
            start_server_role ${SERVER_EXEC} sh_node
            exit 0
            ;;
        stop_java)
            stop_titan_wisteria
            exit 0
            ;;
        start_java)
            start_titan_wisteria
            exit 0
            ;;
        stop_bigdata)
            stop_bigdata_logstash
            stop_bigdata_viewer
            exit 0
            ;;
        stop_docker_scan)
            stop_docker_scan
            exit 0
            ;;
        start_docker_scan)
            start_docker_scan
            exit 0
            ;;
        stop_anti_virus)
            stop_anti_virus
            exit 0
            ;;
        start_anti_virus)
            start_anti_virus
            exit 0
            ;;
        start_bigdata)
            start_bigdata_logstash
            start_bigdata_viewer
            exit 0
            ;;
        dump)
            titan_mysql_dump
            exit 0
            ;;
        rollback)
            titan_mysql_rollback
            exit 0
            ;;
        db_merge)
            # $2=comId
            java_db_flush
            titan_db_merge $2;
            exit 0
            ;;
        jdb_flush)
            java_db_flush
            exit 0
            ;;
        customized_rules)
            customized_rules_migrate
            exit 0
            ;;
        cleancache)
            java_clean_cache
            exit 0
            ;;
        upgrade_conf)
            bash ${FILE_ROOT}/upgrade-conf.sh
            exit 0
            ;;
        switchcompany)
            # $2=mainID, $3=subID
            switch_company $2 $3
            exit 0
            ;;
        change_wisteria_memory)
            change_wisteria_memory
            stop_titan_wisteria
            start_titan_wisteria
            exit 0
            ;;
        backup_config)
            backup_config
            exit 0
            ;;
        java_v320_update)
            java_v320_update $2
            exit 0
            ;;
        init_headquarters)
            init_headquarters
            exit 0
            ;;
        init_datasync)
            init_datasync
            exit 0 
            ;;
        alter_thp_config)
            alter_thp_kafka
            exit 0 
            ;;
        check_version)
            check_version
            exit 0
            ;;
        join_thp_config)
            unzip_rules
            unzip_license
            backup_config
            upgrade_thp && check_backend_account 
            exit 0
            ;;
        auto_update_thunderfire)
            info_log "================== Auto Update thunderfire ================"
            update_thunderfire auto
            exit 0
            ;;
        update_thunderfire)
            info_log "================== Update thunderfire ================"
            update_thunderfire notauto
            exit 0
            ;;
        uninstall_ms)
            unzip_license
            uninstall_ms
            exit 0
            ;;    
        *)
            help $*
            exit 0
            ;;
    esac
done
exit 0
