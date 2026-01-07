#!/bin/bash

set -o pipefail

FILE_ROOT=`cd \`dirname $0\` && pwd`
source ${FILE_ROOT}/utils.sh

all_srvs=("mongo" "redisjava" "redisphp" "rediserl" "mysql" "kafka" "zookeeper" "rabbitmq")

reset_mongo_passwd(){
  # stop mongo 
  docker-compose stop mongo
  # stop mongotmp noauth
  mongoImage=`grep mongo_image .env | cut -d '=' -f 2`
  docker run -di --rm --name="mongotmp" -v /data/titan-container/mongodb/:/data/mongodb -v /data/titan-container/config/mongod.conf:/etc/mongo/mongod.conf -v /data/titan-logs/mongodb:/data/titan-logs/mongodb/ $mongoImage mongod --config /etc/mongo/mongod.conf --noauth
  echo "will sleep 10 seconds to wait mongotmp start ok" && sleep 10
  # set new password
  deployImage=`grep deploy_image .env | cut -d '=' -f 2`
  create_new_secret mongo
  new_passwd=`get_plain_secret mongo | tr -s '\r\n'`
  echo -e "mongo: ${new_passwd}"
  docker exec -i mongotmp sh -c "mongo --quiet --port 27017 admin --eval 'db.system.users.remove({user:\"qingteng\"}); db.createUser({user:\"qingteng\",pwd:\"${new_passwd}\",roles:[\"root\"]})' "
  docker container stop mongotmp
}

reset_rabbitmq_passwd(){
  create_new_secret rabbitmq
  new_passwd=`get_plain_secret rabbitmq | tr -s '\r\n'`
  echo -e "rabbitmq: ${new_passwd}"
  docker exec -i rabbitmq sh -c "rabbitmqctl change_password guest ${new_passwd}"
}

create_new_secret(){
  srvname=$1
  deployImage=`grep deploy_image .env | cut -d '=' -f 2`
  docker run -i --rm -v /data/titan-container/secrets:/run/secrets $deployImage sh -c "/root/script/dockerize -createSecret /run/secrets/${srvname}_password && chmod 644 /run/secrets/${srvname}_password"
}

get_plain_secret(){
  deployImage=`grep deploy_image .env | cut -d '=' -f 2`
  docker run -i --rm -v /data/titan-container/secrets:/run/secrets $deployImage sh -c "/root/script/dockerize -getPlain $1"
}

reset_passwd(){
  services=${@}
  srv_array=(${services//,/ })
  for service in ${srv_array[@]}
  do
    [[ " ${all_srvs[@]} " =~ " ${service} " ]] || error_log "invalid services: ${service}"
  done

  deployImage=`grep deploy_image .env | cut -d '=' -f 2`
  for service in ${srv_array[@]}
  do
    case $service in
      mongo)
        reset_mongo_passwd
        ;;
      rabbitmq)
        reset_rabbitmq_passwd
        ;;
      zookeeper)
        create_new_secret zk
        ;;
      *)
        # 生成随机密码， 重启服务即可
        create_new_secret $service
        ;;
    esac
  done
  
  if [[ " ${srv_array[@]} " =~ " zookeeper " ]] && [[ ! " ${srv_array[@]} " =~ " kafka " ]]; then
    srv_array=("${srv_array[@]}" "kafka") 
  fi
  echo "${srv_array[@]}"
  docker-compose up -d --force-recreate "${srv_array[@]}"
  
  restart_app
}

get_plain(){
  services=${@}
  srv_array=(${services//,/ })
  for service in ${srv_array[@]}
  do
    [[ " ${all_srvs[@]} " =~ " ${service} " ]] || error_log "usage: config.sh get_plain zookeeper,kafka,mongo,mysql,redisjava,redisphp,rediserl,rabbitmq"
  done  
  
  deployImage=`grep deploy_image .env | cut -d '=' -f 2`
  for service in ${srv_array[@]}
  do
    plain_passwd=`get_plain_secret ${service}`
    echo "${service}: ${plain_passwd}"
  done
}

usage() {
    cat <<_EOF_
config.sh <options>
Options:
  reset_passwd    reset service password, mongo,redisjava,redisphp,rediserl,mysql,kafka,zookeeper,rabbitmq
  get_plain       get plain password, available service:mongo,redisjava,redisphp,rediserl,mysql,kafka,zookeeper,rabbitmq
  update_access   update access url after change in titan.env
  help            show this help
_EOF_
}

action=$1
#echo "Action is $action"
case $action in
    reset_passwd)
        reset_passwd ${@:2} | tee -a config.log
        exit 0
        ;;
    get_plain)
        get_plain ${@:2} 
        exit 0
        ;;
    update_access)
        update_access | tee -a config.log
        docker-compose up -d --force-recreate titan-gateway titan-wisteria titan-web titan-go-patrol
        exit 0
        ;;
    *)
        usage | tee -a install.log
        exit 1
        ;;
esac