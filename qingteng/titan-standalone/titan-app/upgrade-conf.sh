#!/bin/bash

# handle the config change when upgrade version


## -------------------------- Erlang ------------------------------ ##

FILE_ROOT=`cd \`dirname $0\` && pwd`

source ${FILE_ROOT}/utils.sh


## -------------------------- Erlang ------------------------------ ##

# v2.x, no databases: job & job_error
# v3.x, using databases: job & job_error
# Should create databases before upgrading from 2.x to 3.x
create_mongo_db(){
    local mongo_ip=`get_ip db_mongo_erlang`

    ssh_t ${mongo_ip} "\
    mongo job --eval \"db.createUser({user:\\\"rwuser\\\", pwd:\\\"titan7vc65x\\\", roles:[{role:\\\"readWrite\\\", db:\\\"job\\\"}]})\"; \
    mongo job_error --eval \"db.createUser({user:\\\"rwuser\\\", pwd:\\\"titan7vc65x\\\", roles:[{role:\\\"readWrite\\\", db:\\\"job_error\\\"}]})\""

    check "Creating mongodb for Erlang"
}


upgrade_erlang(){
    create_mongo_db
    info_log "upgrade erlang done"
}

## -------------------------- PHP --------------------------------- ##

check_remote_file(){
    local host=$1
    local file=$2

    ssh_t ${host} "[ -f ${file} ] && exit 0 || exit 1"

    [ $? -ne 0 ] && return 1
    return 0
}

# version < 2.3.7, auth was disabled in redis_php
# now, we make redis' auth enabled
enable_redis_auth(){
    local redis_ip=`get_ip db_redis_php`

    # abs path of redis_php configuration file
    local path1=/usr/local/redis/6380.conf
    local path2=/etc/redis/6380.conf
    # abs path of redis executable file
    local redis_exec=/usr/local/redis/bin/redis-server

    ssh_t ${redis_ip} "\
    [ -f ${path1} ] && exit 101; \
    [ -f ${path2} ] && exit 102; \
    exit 0"

    local ret_code=$?
    local conf_path=${path2}

    if [ ${ret_code} -eq 101 ]; then
        conf_path=${path1}
    elif [ ${ret_code} -eq 102 ]; then
        conf_path=${path2}
    else
        while true;
        do
            info_log "Cannot found the config file of redis_php!"
            read -p "Please input the abs path of redis_php's config file: " Enter
            if [ -z "${Enter}" ]; then
                continue
            else
                check_remote_file ${redis_ip} ${Enter}
                [ $? -eq 0 ] && conf_path=${Enter} && break
            fi
        done
    fi

    echo ${conf_path}

    ssh_t ${redis_ip} "\
    [ -f ${conf_path} ] && [ ! -z \"\`grep requirepass ${conf_path}\`\" ] && \
    sed -i \"s/\`grep requirepass ${conf_path}\`/requirepass 9pbsoq6hoNhhTzl/\" ${conf_path}; \
    [ -f ${conf_path} ] && [ -z \"\`grep requirepass ${conf_path}\`\" ] && \
    echo \"requirepass 9pbsoq6hoNhhTzl\" >> ${conf_path}; \
    [ -f ${conf_path} ] && [ -x ${redis_exec} ] && redis-cli -p 6380 shutdown && sleep 2 && ${redis_exec} ${conf_path}"
}

upgrade_php(){
    enable_redis_auth
    info_log "upgrade php configurations done"
}

## -------------------------- Java -------------------------------- ##


update_kafka_config(){
    local kafka_ip=`get_ip java_kafka`

    ssh_t ${kafka_ip} "\
    cd /usr/local/qingteng/kafka; \
    [ -n \"\`grep message.max.bytes config/server.properties\`\" ] && \
    sed -i \"s/message.max.bytes.*/message.max.bytes=8388608/\" config/server.properties; \
    [ -z \"\`grep message.max.bytes config/server.properties\`\" ] && \
    echo \"message.max.bytes=8388608\" >> config/server.properties; \
    [ -n \"\`grep replica.fetch.max.bytes config/server.properties\`\" ] && \
    sed -i \"s/replica.fetch.max.bytes.*/replica.fetch.max.bytes=10485760/\" config/server.properties; \
    [ -z \"\`grep replica.fetch.max.bytes config/server.properties\`\" ] && \
    echo \"replica.fetch.max.bytes=10485760\" >> config/server.properties; \
    "
}

upgrade_java(){

    update_kafka_config

    info_log "upgrade java configurations done"
}

## -------------------------- Start ------------------------------ ##

start_upgrade(){
    #upgrade_erlang
    upgrade_php
    upgrade_java
}

start_upgrade