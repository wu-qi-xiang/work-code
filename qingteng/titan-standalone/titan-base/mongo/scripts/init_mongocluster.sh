#!/bin/bash

QT_MONGO_PATH="/usr/local/qingteng/mongodb/bin/mongo"
IPS=($1)
roles=$2
arbiter_port_init=37019
sharding_port_init=27019
config_port=27018
sharding_nums=$((${#IPS[@]}/2))

for ((i=0;i<${sharding_nums};i++))
do
    if [ $i == $((sharding_nums-1)) ];then
        arbiter_ips[$i]=${IPS[1]}
    else
        arbiter_ips[$i]=${IPS[$((((2*$i))+3))]}
    fi
done

remove_old_base(){
    # set support MongoDB-CR authentication
    ${QT_MONGO_PATH} admin --eval "db.system.version.remove({_id: \"authSchema\"});\
    db.system.version.insert({_id:\"authSchema\",currentVersion:3});"
    ${QT_MONGO_PATH} admin --eval "db.system.users.remove({user:\"qingteng\"})"
}

remove_old_erlang(){
    remove_old_base
    ${QT_MONGO_PATH} admin --eval "db.system.users.remove({user:\"rwuser\"})"
}

init_database_erlang(){
    remove_old_erlang
    ${QT_MONGO_PATH} admin --eval "db.createUser({user:\"qingteng\", pwd:\"9pbsoq6hoNhhTzl\", roles:[\"root\"]})"
    ${QT_MONGO_PATH} cvelib --eval "db.createUser({user:\"rwuser\", pwd:\"titan7vc65x\", roles:[{role:\"readWrite\", db:\"cvelib\"}]})"
    ${QT_MONGO_PATH} assets --eval "db.createUser({user:\"rwuser\", pwd:\"titan7vc65x\", roles:[{role:\"readWrite\", db:\"assets\"}]})"
    ${QT_MONGO_PATH} core --eval "db.createUser({user:\"rwuser\", pwd:\"titan7vc65x\", roles:[{role:\"readWrite\", db:\"core\"}]})"
    ${QT_MONGO_PATH} vine_dev --eval "db.createUser({user:\"rwuser\", pwd:\"titan7vc65x\", roles:[{role:\"readWrite\", db:\"vine_dev\"}]})"
    # For V3.0
    ${QT_MONGO_PATH} job --eval "db.createUser({user:\"rwuser\", pwd:\"titan7vc65x\", roles:[{role:\"readWrite\", db:\"job\"}]})"
    ${QT_MONGO_PATH} job_error --eval "db.createUser({user:\"rwuser\", pwd:\"titan7vc65x\", roles:[{role:\"readWrite\", db:\"job_error\"}]})"
}

init_database_java(){
    remove_old_base
    ${QT_MONGO_PATH} admin --eval "db.system.version.remove({_id: \"authSchema\"})"
    ${QT_MONGO_PATH} admin --eval "db.createUser({user:\"qingteng\", pwd:\"9pbsoq6hoNhhTzl\", roles:[\"root\"]})"
    #add qingteng user for shard2 and shard3
	for ((i=0,sharding_port=${sharding_port_init};i<${sharding_nums};i++,sharding_port++))
	do
        $QT_MONGO_PATH --host ${IPS[$((2*i))]} --port ${sharding_port} admin --eval "db.createUser({user:\"qingteng\", pwd:\"9pbsoq6hoNhhTzl\", roles:[\"root\"]})"

	done
}


disable_auth(){
    sed -i "s/^OPTIONS/#OPTIONS/"  /etc/sysconfig/mongod
}

enable_auth(){
    sed -i "s/^#OPTIONS/OPTIONS/"  /etc/sysconfig/mongod
}

shard(){
if [ $roles == 'mongo_java' ];then
    ${QT_MONGO_PATH} --eval "sh.enableSharding(\"wisteria_assets\")"
    ${QT_MONGO_PATH} --eval "sh.enableSharding(\"basic_data\")"
    ${QT_MONGO_PATH} --eval "sh.enableSharding(\"wisteria_detect\")"
    
    ${QT_MONGO_PATH} --eval "sh.shardCollection(\"wisteria_assets.baseline2_check_result\", {_id:1})"
    
    ${QT_MONGO_PATH} --eval "db.detect_abnormallogin.createIndex({\"agentId\": 1}, {\"name\": \"agentId\"})" wisteria_assets
    ${QT_MONGO_PATH} --eval "sh.shardCollection(\"wisteria_assets.detect_abnormallogin\", {agentId:1})"
    
    ${QT_MONGO_PATH} --eval "db.detect_shellaudit_log.createIndex({\"agentId\": 1}, {\"name\": \"agentId\"})" wisteria_assets
    ${QT_MONGO_PATH} --eval "sh.shardCollection(\"wisteria_assets.detect_shellaudit_log\", {agentId:1})"
    
    ${QT_MONGO_PATH} --eval "db.linux_account.createIndex({\"agentId\": 1}, {\"name\": \"agentId\"})" wisteria_assets
    ${QT_MONGO_PATH} --eval "sh.shardCollection(\"wisteria_assets.linux_account\", {agentId:1})"
    
    ${QT_MONGO_PATH} --eval "db.linux_account_group.createIndex({\"agentId\": 1}, {\"name\": \"agentId\"})" wisteria_assets
    ${QT_MONGO_PATH} --eval "sh.shardCollection(\"wisteria_assets.linux_account_group\", {agentId:1})"
    
    ${QT_MONGO_PATH} --eval "db.linux_env.createIndex({\"agentId\": 1}, {\"name\": \"agentId\"})" wisteria_assets
    ${QT_MONGO_PATH} --eval "sh.shardCollection(\"wisteria_assets.linux_env\", {agentId:1})"
    
    ${QT_MONGO_PATH} --eval "db.linux_kernelmodule.createIndex({\"agentId\": 1}, {\"name\": \"agentId\"})" wisteria_assets
    ${QT_MONGO_PATH} --eval "sh.shardCollection(\"wisteria_assets.linux_kernelmodule\", {agentId:1})"
    
    ${QT_MONGO_PATH} --eval "db.linux_pkg.createIndex({\"agentId\": 1}, {\"name\": \"agentId\"})" wisteria_assets
    ${QT_MONGO_PATH} --eval "sh.shardCollection(\"wisteria_assets.linux_pkg\", {agentId:1})"
    
    ${QT_MONGO_PATH} --eval "db.linux_port.createIndex({\"agentId\": 1}, {\"name\": \"agentId\"})" wisteria_assets
    ${QT_MONGO_PATH} --eval "sh.shardCollection(\"wisteria_assets.linux_port\", {agentId:1})"
    
    ${QT_MONGO_PATH} --eval "db.linux_process.createIndex({\"agentId\": 1}, {\"name\": \"agentId\"})" wisteria_assets
    ${QT_MONGO_PATH} --eval "sh.shardCollection(\"wisteria_assets.linux_process\", {agentId:1})"
    
    ${QT_MONGO_PATH} --eval "db.vul2_patch_result.createIndex({\"agentId\": 1}, {\"name\": \"agentId\"})" wisteria_assets
    ${QT_MONGO_PATH} --eval "sh.shardCollection(\"wisteria_assets.vul2_patch_result\", {agentId:1})"
    
    ${QT_MONGO_PATH} --eval "db.ready_event_log.createIndex({\"agentId\": 1}, {\"name\": \"agentId\"})" basic_data
    ${QT_MONGO_PATH} --eval "sh.shardCollection(\"basic_data.ready_event_log\", {agentId:1})"
    
    ${QT_MONGO_PATH} --eval "db.collect_log.createIndex({\"agentId\": 1}, {\"name\": \"agentId\"})" basic_data
    ${QT_MONGO_PATH} --eval "sh.shardCollection(\"basic_data.collect_log\", {agentId:1})"
    
    ${QT_MONGO_PATH} --eval "db.refresh_log.createIndex({\"agentId\": 1}, {\"name\": \"agentId\"})" basic_data
    ${QT_MONGO_PATH} --eval "sh.shardCollection(\"basic_data.refresh_log\", {agentId:1})"
    
    ${QT_MONGO_PATH} --eval "sh.shardCollection(\"wisteria_detect.detect_virus_check_sub_task\", {_id:1})"
    
    ${QT_MONGO_PATH} --eval "sh.shardCollection(\"wisteria_detect.detect_virus_check_task_info\", {_id:1})"
else
    ${QT_MONGO_PATH} --eval "sh.enableSharding(\"wisteria_ms\")"
    ${QT_MONGO_PATH} --eval "sh.shardCollection(\"wisteria_ms.access_relation\", {uuid:1},true )"
    ${QT_MONGO_PATH} --eval "sh.shardCollection(\"wisteria_ms.net_connect_record\", { _id : \"hashed\" } )"
    ${QT_MONGO_PATH} --eval "sh.shardCollection(\"wisteria_ms.strategy_dst_host\", { _id : \"hashed\" } )"
    ${QT_MONGO_PATH} --eval "sh.shardCollection(\"wisteria_ms.strategy_dst_host_history\", { _id : \"hashed\" } )"
    ${QT_MONGO_PATH} --eval "sh.shardCollection(\"wisteria_ms.strategy_issue_status\", { _id : \"hashed\" } )"
    ${QT_MONGO_PATH} --eval "sh.shardCollection(\"wisteria_ms.strategy_src_host\", { _id : \"hashed\" } )"
    ${QT_MONGO_PATH} --eval "sh.shardCollection(\"wisteria_ms.strategy_src_host_history\", { _id : \"hashed\" } )"
fi
}

rs_status_check(){
    if [ "$1" != "" ];then
        SECONDARY_NUM=`$QT_MONGO_PATH --host $1 --port $2 --eval "rs.status()" |grep stateStr |grep SECONDARY |wc -l`
        PRIMARY_NUM=`$QT_MONGO_PATH --host $1 --port $2 --eval "rs.status()" |grep stateStr |grep PRIMARY |wc -l`
        if [ "$2" == "27018" ] ;then
            if [ "$SECONDARY_NUM" == "2" ] && [ "$PRIMARY_NUM" == "1" ];then
                echo 0
            else 
                echo 2
            fi
        else
            if [ "$SECONDARY_NUM" == "1" ] && [ "$PRIMARY_NUM" == "1" ];then
                echo 0
            else
                echo 2
            fi
        fi
    else
        echo 3
    fi
}


config_cluster(){
num=0
while true
do
    if [ $num -le 3 ] ;then
        $QT_MONGO_PATH --port ${config_port} --eval "rs.initiate({_id : \"cs\",members : [{_id : 0, host :\"${IPS[0]}:${config_port}\",priority:100},{_id : 1, host : \"${IPS[1]}:${config_port}\"},{_id : 2, host : \"${IPS[2]}:${config_port}\"}]})"|grep "\"ok\" : 1" && break || let num+=1
        sleep 1
    else
        break
    fi
done
$QT_MONGO_PATH --port ${config_port} --eval "rs.status()"

}

initcluster(){
for ((i=0,sharding_port=${sharding_port_init},arbiter_port=${arbiter_port_init};i<${sharding_nums};i++,sharding_port++,arbiter_port++))
do
    num=0
    while true
	do
		if [ $num -le 3 ] ;then
            echo ${IPS[$i]}
            $QT_MONGO_PATH --host ${IPS[$((2*i))]} --port ${sharding_port} -eval "rs.initiate({_id : \"shard$((i+1))\",members : [{_id : 0, host :\"${IPS[$((2*i))]}:$sharding_port\",priority:100},{_id : 1, host : \"${IPS[$((((2*i))+1))]}:${sharding_port}\"},{_id : 2, host : \"${arbiter_ips[$i]}:${arbiter_port}\", arbiterOnly: true}]})"|grep "\"ok\" : 1" && break || let num+=1
            sleep 1
        else
            break
        fi
    done
done

#check the rs status 
while true
do
    cs=`rs_status_check ${IPS[0]} 27018`
    [ "$cs" == "0" ] && break
    sleep 1
done

for ((i=0,x=0,sharding_port=${sharding_port_init};i<${sharding_nums};i++,x=x+2,sharding_port++))
do

	while true
        do
            shard_status=`rs_status_check ${IPS[$x]} $sharding_port`
            [ "$shard_status" == "0" ] && break
            sleep 1
        done
done

#change the mongos.conf and restart mongos
sed -i "s#\(configdb.*=\).*#\1 cs/${IPS[0]}:27018,${IPS[1]}:27018,${IPS[2]}:27018#" /usr/local/qingteng/mongocluster/etc/mongos.conf
/etc/init.d/mongos  restart

#add sharding
for ((i=0,sharding_port=${sharding_port_init},arbiter_port=${arbiter_port_init};i<${sharding_nums};i++,sharding_port++,arbiter_port++))
do

	$QT_MONGO_PATH --eval "sh.addShard(\"shard$((i+1))/${IPS[$((2*i))]}:$sharding_port,${IPS[$((((2*i))+1))]}:$sharding_port,${arbiter_ips[${i}]}:$arbiter_port\")"
done

#check sharding status
while true
do
    shs=`$QT_MONGO_PATH --eval "sh.status()" |grep "\"state\" : 1" |wc -l`
    if [ "$shs" == "$sharding_nums" ];then
        break
    else
        sleep 1
    fi
done
#${QT_MONGO_PATH} --eval "sh.status()"
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

config_cluster
initcluster
init_database_java
shard


