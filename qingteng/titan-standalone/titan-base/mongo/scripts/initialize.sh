#!/bin/bash

host1=172.16.5.152
host2=172.16.5.148
host3=172.16.5.146


remove_old_base(){
    # set support MongoDB-CR authentication
    /usr/local/qingteng/mongodb/bin/mongo admin --eval "db.system.version.remove({_id: \"authSchema\"});\
    db.system.version.insert({_id:\"authSchema\",currentVersion:3});"
    /usr/local/qingteng/mongodb/bin/mongo admin --eval "db.system.users.remove({user:\"qingteng\"})"
}

remove_old_erlang(){
    remove_old_base
    /usr/local/qingteng/mongodb/bin/mongo admin --eval "db.system.users.remove({user:\"rwuser\"})"
}

init_database_erlang(){
    remove_old_erlang
    /usr/local/qingteng/mongodb/bin/mongo admin --eval "db.createUser({user:\"qingteng\", pwd:\"9pbsoq6hoNhhTzl\", roles:[\"root\"]})"
    /usr/local/qingteng/mongodb/bin/mongo cvelib --eval "db.createUser({user:\"rwuser\", pwd:\"titan7vc65x\", roles:[{role:\"readWrite\", db:\"cvelib\"}]})"
    /usr/local/qingteng/mongodb/bin/mongo assets --eval "db.createUser({user:\"rwuser\", pwd:\"titan7vc65x\", roles:[{role:\"readWrite\", db:\"assets\"}]})"
    /usr/local/qingteng/mongodb/bin/mongo core --eval "db.createUser({user:\"rwuser\", pwd:\"titan7vc65x\", roles:[{role:\"readWrite\", db:\"core\"}]})"
    /usr/local/qingteng/mongodb/bin/mongo vine_dev --eval "db.createUser({user:\"rwuser\", pwd:\"titan7vc65x\", roles:[{role:\"readWrite\", db:\"vine_dev\"}]})"
    # For V3.0
    /usr/local/qingteng/mongodb/bin/mongo job --eval "db.createUser({user:\"rwuser\", pwd:\"titan7vc65x\", roles:[{role:\"readWrite\", db:\"job\"}]})"
    /usr/local/qingteng/mongodb/bin/mongo job_error --eval "db.createUser({user:\"rwuser\", pwd:\"titan7vc65x\", roles:[{role:\"readWrite\", db:\"job_error\"}]})"
}

init_database_java(){
    remove_old_base
    /usr/local/qingteng/mongodb/bin/mongo admin --eval "db.system.version.remove({_id: \"authSchema\"})"
    /usr/local/qingteng/mongodb/bin/mongo admin --eval "db.createUser({user:\"qingteng\", pwd:\"9pbsoq6hoNhhTzl\", roles:[\"root\"]})"
    #add qingteng user for shard2 and shard3
    /usr/local/qingteng/mongodb/bin/mongo --host ${host2} --port 27020 admin --eval "db.createUser({user:\"qingteng\", pwd:\"9pbsoq6hoNhhTzl\", roles:[\"root\"]})"
    /usr/local/qingteng/mongodb/bin/mongo --host ${host3} --port 27021 admin --eval "db.createUser({user:\"qingteng\", pwd:\"9pbsoq6hoNhhTzl\", roles:[\"root\"]})"
}


disable_auth(){
    sed -i "s/^OPTIONS/#OPTIONS/"  /etc/sysconfig/mongod
}

enable_auth(){
    sed -i "s/^#OPTIONS/OPTIONS/"  /etc/sysconfig/mongod
}

shard(){
if [ $roles == "mongo_java" ];then
    /usr/local/qingteng/mongodb/bin/mongo --eval "sh.enableSharding(\"wisteria_assets\")"
    /usr/local/qingteng/mongodb/bin/mongo --eval "sh.enableSharding(\"basic_data\")"
    /usr/local/qingteng/mongodb/bin/mongo --eval "sh.enableSharding(\"wisteria_detect\")"
    
    /usr/local/qingteng/mongodb/bin/mongo --eval "sh.shardCollection(\"wisteria_assets.baseline2_check_result\", {_id:1})"
    
    /usr/local/qingteng/mongodb/bin/mongo --eval "db.detect_abnormallogin.createIndex({\"agentId\": 1}, {\"name\": \"agentId\"})" wisteria_assets
    /usr/local/qingteng/mongodb/bin/mongo --eval "sh.shardCollection(\"wisteria_assets.detect_abnormallogin\", {agentId:1})"
    
    /usr/local/qingteng/mongodb/bin/mongo --eval "db.detect_shellaudit_log.createIndex({\"agentId\": 1}, {\"name\": \"agentId\"})" wisteria_assets
    /usr/local/qingteng/mongodb/bin/mongo --eval "sh.shardCollection(\"wisteria_assets.detect_shellaudit_log\", {agentId:1})"
    
    /usr/local/qingteng/mongodb/bin/mongo --eval "db.linux_account.createIndex({\"agentId\": 1}, {\"name\": \"agentId\"})" wisteria_assets
    /usr/local/qingteng/mongodb/bin/mongo --eval "sh.shardCollection(\"wisteria_assets.linux_account\", {agentId:1})"
    
    /usr/local/qingteng/mongodb/bin/mongo --eval "db.linux_account_group.createIndex({\"agentId\": 1}, {\"name\": \"agentId\"})" wisteria_assets
    /usr/local/qingteng/mongodb/bin/mongo --eval "sh.shardCollection(\"wisteria_assets.linux_account_group\", {agentId:1})"
    
    /usr/local/qingteng/mongodb/bin/mongo --eval "db.linux_env.createIndex({\"agentId\": 1}, {\"name\": \"agentId\"})" wisteria_assets
    /usr/local/qingteng/mongodb/bin/mongo --eval "sh.shardCollection(\"wisteria_assets.linux_env\", {agentId:1})"
    
    /usr/local/qingteng/mongodb/bin/mongo --eval "db.linux_kernelmodule.createIndex({\"agentId\": 1}, {\"name\": \"agentId\"})" wisteria_assets
    /usr/local/qingteng/mongodb/bin/mongo --eval "sh.shardCollection(\"wisteria_assets.linux_kernelmodule\", {agentId:1})"
    
    /usr/local/qingteng/mongodb/bin/mongo --eval "db.linux_pkg.createIndex({\"agentId\": 1}, {\"name\": \"agentId\"})" wisteria_assets
    /usr/local/qingteng/mongodb/bin/mongo --eval "sh.shardCollection(\"wisteria_assets.linux_pkg\", {agentId:1})"
    
    /usr/local/qingteng/mongodb/bin/mongo --eval "db.linux_port.createIndex({\"agentId\": 1}, {\"name\": \"agentId\"})" wisteria_assets
    /usr/local/qingteng/mongodb/bin/mongo --eval "sh.shardCollection(\"wisteria_assets.linux_port\", {agentId:1})"
    
    /usr/local/qingteng/mongodb/bin/mongo --eval "db.linux_process.createIndex({\"agentId\": 1}, {\"name\": \"agentId\"})" wisteria_assets
    /usr/local/qingteng/mongodb/bin/mongo --eval "sh.shardCollection(\"wisteria_assets.linux_process\", {agentId:1})"
    
    /usr/local/qingteng/mongodb/bin/mongo --eval "db.vul2_patch_result.createIndex({\"agentId\": 1}, {\"name\": \"agentId\"})" wisteria_assets
    /usr/local/qingteng/mongodb/bin/mongo --eval "sh.shardCollection(\"wisteria_assets.vul2_patch_result\", {agentId:1})"
    
    /usr/local/qingteng/mongodb/bin/mongo --eval "db.ready_event_log.createIndex({\"agentId\": 1}, {\"name\": \"agentId\"})" basic_data
    /usr/local/qingteng/mongodb/bin/mongo --eval "sh.shardCollection(\"basic_data.ready_event_log\", {agentId:1})"
    
    /usr/local/qingteng/mongodb/bin/mongo --eval "db.collect_log.createIndex({\"agentId\": 1}, {\"name\": \"agentId\"})" basic_data
    /usr/local/qingteng/mongodb/bin/mongo --eval "sh.shardCollection(\"basic_data.collect_log\", {agentId:1})"
    
    /usr/local/qingteng/mongodb/bin/mongo --eval "db.refresh_log.createIndex({\"agentId\": 1}, {\"name\": \"agentId\"})" basic_data
    /usr/local/qingteng/mongodb/bin/mongo --eval "sh.shardCollection(\"basic_data.refresh_log\", {agentId:1})"
    
    /usr/local/qingteng/mongodb/bin/mongo --eval "sh.shardCollection(\"wisteria_detect.detect_virus_check_sub_task\", {_id:1})"
    
    /usr/local/qingteng/mongodb/bin/mongo --eval "sh.shardCollection(\"wisteria_detect.detect_virus_check_task_info\", {_id:1})"
else
    /usr/local/qingteng/mongodb/bin/mongo --eval "sh.enableSharding(\"wisteria_ms\")"
    /usr/local/qingteng/mongodb/bin/mongo --eval "sh.shardCollection(\"wisteria_ms.access_relation\", {uuid:1},true )"
    /usr/local/qingteng/mongodb/bin/mongo --eval "sh.shardCollection(\"wisteria_ms.net_connect_record\", { _id : \"hashed\" } )"
    /usr/local/qingteng/mongodb/bin/mongo --eval "sh.shardCollection(\"wisteria_ms.strategy_dst_host\", { _id : \"hashed\" } )"
    /usr/local/qingteng/mongodb/bin/mongo --eval "sh.shardCollection(\"wisteria_ms.strategy_dst_host_history\", { _id : \"hashed\" } )"
    /usr/local/qingteng/mongodb/bin/mongo --eval "sh.shardCollection(\"wisteria_ms.strategy_issue_status\", { _id : \"hashed\" } )"
    /usr/local/qingteng/mongodb/bin/mongo --eval "sh.shardCollection(\"wisteria_ms.strategy_src_host\", { _id : \"hashed\" } )"
    /usr/local/qingteng/mongodb/bin/mongo --eval "sh.shardCollection(\"wisteria_ms.strategy_src_host_history\", { _id : \"hashed\" } )"
fi
}

rs_status_check(){
    if [ "$1" != "" ];then
        SECONDARY_NUM=`/usr/local/qingteng/mongodb/bin/mongo --port $1 --eval "rs.status()" |grep stateStr |grep SECONDARY |wc -l`
        PRIMARY_NUM=`/usr/local/qingteng/mongodb/bin/mongo --port $1 --eval "rs.status()" |grep stateStr |grep PRIMARY |wc -l`
        if [ "$SECONDARY_NUM" == "2" ] && [ "$PRIMARY_NUM" == "1" ];then
            if [ "$1" == "27020" ];then
                PRIMARY_27020_HOST2_NUM=`/usr/local/qingteng/mongodb/bin/mongo --port $1 --eval "rs.status()" |grep -B 3 "PRIMARY"  |grep "$host2" |wc -l`
                [ $PRIMARY_27020_HOST2_NUM == "1" ] && echo 0 || echo 2
            elif [ "$1" == "27021" ];then
                PRIMARY_27021_HOST3_NUM=`/usr/local/qingteng/mongodb/bin/mongo --port $1 --eval "rs.status()" |grep -B 3 "PRIMARY"  |grep "$host3" |wc -l`
                [ $PRIMARY_27021_HOST3_NUM == "1" ] && echo 0 || echo 2
            else
                echo 0
            fi
        else
            echo 2
        fi
    else
        echo 3
    fi
}


initcluster(){
num=0
while true
do
    if [ $num -le 3 ] ;then
        /usr/local/qingteng/mongodb/bin/mongo --port 27019 --eval "rs.initiate({_id : \"shard1\",members : [{_id : 0, host :\"${host1}:27019\",priority:100},{_id : 1, host : \"${host2}:27019\"},{_id : 2, host : \"${host3}:27019\"}]})"|grep "\"ok\" : 1" && break || let num+=1
        sleep 1
    else
        break
    fi
done
/usr/local/qingteng/mongodb/bin/mongo --port 27019 --eval "rs.status()"


num=0
while true
do
    if [ $num -le 3 ] ;then
        /usr/local/qingteng/mongodb/bin/mongo --port 27020 --eval "rs.initiate({_id : \"shard2\",members : [{_id : 0, host :\"${host1}:27020\"},{_id : 1, host : \"${host2}:27020\",priority:100},{_id : 2, host : \"${host3}:27020\"}]})"|grep "\"ok\" : 1" && break || let num+=1
        sleep 1
    else
        break
    fi
done
/usr/local/qingteng/mongodb/bin/mongo --port 27020 --eval "rs.status()"


num=0
while true
do
    if [ $num -le 3 ] ;then
        /usr/local/qingteng/mongodb/bin/mongo --port 27021 --eval "rs.initiate({_id : \"shard3\",members : [{_id : 0, host :\"${host1}:27021\"},{_id : 1, host : \"${host2}:27021\"},{_id : 2, host : \"${host3}:27021\",priority:100}]})"|grep "\"ok\" : 1" && break || let num+=1
        sleep 1
    else
        break
    fi
done
/usr/local/qingteng/mongodb/bin/mongo --port 27021 --eval "rs.status()"

num=0
while true
do
    if [ $num -le 3 ] ;then
        /usr/local/qingteng/mongodb/bin/mongo --port 27018 --eval "rs.initiate({_id : \"cs\",members : [{_id : 0, host :\"${host1}:27018\",priority:100},{_id : 1, host : \"${host2}:27018\"},{_id : 2, host : \"${host3}:27018\"}]})"|grep "\"ok\" : 1" && break || let num+=1
        sleep 1
    else
        break
    fi
done
/usr/local/qingteng/mongodb/bin/mongo --port 27018 --eval "rs.status()"

while true
do
    cs=`rs_status_check 27018`
    sh1=`rs_status_check 27019`
    sh2=`rs_status_check 27020`
    sh3=`rs_status_check 27021`
    [ "$cs" == "0" ] &&  [ "$sh1" == "0" ] && [ "$sh2" == "0" ] && [ "$sh3" == "0" ] && break
    sleep 1
done

sed -i "s#\(configdb.*=\).*#\1 cs/${host1}:27018,${host2}:27018,${host3}:27018#" /usr/local/qingteng/mongocluster/etc/mongos.conf
/etc/init.d/mongos  restart

/usr/local/qingteng/mongodb/bin/mongo --eval "sh.addShard(\"shard1/${host1}:27019,${host2}:27019,${host3}:27019\")"
/usr/local/qingteng/mongodb/bin/mongo --eval "sh.addShard(\"shard2/${host1}:27020,${host2}:27020,${host3}:27020\")"
/usr/local/qingteng/mongodb/bin/mongo --eval "sh.addShard(\"shard3/${host1}:27021,${host2}:27021,${host3}:27021\")"
while true
do
    shs=`/usr/local/qingteng/mongodb/bin/mongo --eval "sh.status()" |grep "\"state\" : 1" |wc -l`
    [ "$shs" == "3" ] && break
done
/usr/local/qingteng/mongodb/bin/mongo --eval "sh.status()"
}

if [ -d "/data/mongodb/data" ] && [ -d "/data/mongocluster/shard1" ];then
    num=`ls /data/mongodb/data/ |wc -l`
    if [ "$num" != "0" ];then
        /etc/init.d/mongod_27019 stop
        rm -rf /data/mongocluster/shard1/*
        scp -rp /data/mongodb/data/* /data/mongocluster/shard1/
        chown -R mongodb:mongodb /data/mongocluster 
        /etc/init.d/mongod_27019 restart
    fi
fi

roles=$1
initcluster
init_database_java
shard


