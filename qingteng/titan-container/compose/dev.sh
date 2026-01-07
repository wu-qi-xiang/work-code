#!/bin/bash

FILE_ROOT=`cd \`dirname $0\` && pwd`

host_mode(){
  compose_dev

  cp -f docker-compose.yml docker-compose.yml_bak`date +%s`
  sed -i '/network_mode:/d' docker-compose.yml
  sed -i -r '/extra_hosts:/, /(^[ ]+[a-z].*)/ s/^[ ]+(extra_hosts|- ).*$/__TO_DELETE__/g' docker-compose.yml
  sed -i '/__TO_DELETE__/d' docker-compose.yml
  sed -i '/hostname:/a \ \ \ \ network_mode: host' docker-compose.yml
  sed -i -r '/[ ]+networks:/,+2d' docker-compose.yml
  
  alpineImage=`grep alpine_image .env | cut -d '=' -f 2`
  docker run -ti --rm -v /data/titan-container/:/data/titan-container/ -v /etc/:/data/etc/  $alpineImage sh -x -c '
  public_ip=`cat /data/titan-container/titan.env | grep web_publicip | cut -d "=" -f 2`; \
  sed -i -r "/^${public_ip} /d" /data/etc/hosts; \
  sed -i -r "s/^10.172.16.[0-9]+ /${public_ip} /g" /data/etc/hosts; \

  sed -i "/EXT_JAVA_OPTS=/d" /data/titan-container/titan.env; \
  echo "EXT_JAVA_OPTS=-Dspring.cloud.inetutils.preferred-networks=${public_ip}" >> /data/titan-container/titan.env '
}

compose_dev(){
  rm -rf ./titan-config
  docker cp titan-gateway:/data/app/titan-config/ ./ 

  alpineImage=`grep alpine_image .env | cut -d '=' -f 2`
  docker run -ti --rm -v /data/:/data/ -v "$FILE_ROOT"/titan-config:/tmp/titan-config/ $alpineImage sh -c 'chmod -R 777 /data/titan-logs/java && mkdir -p /data/app/titan-config/ && cp -rf /tmp/titan-config/* /data/app/titan-config/'
  docker run -ti --rm -v /etc/:/data/etc/  $alpineImage sh -x -c '
  cp -f /data/etc/hosts /data/etc/hosts_bak`date +%s`; \
  sed -i -r "/^10.172.16.[0-9]+ /d" /data/etc/hosts; \
  cat>>/data/etc/hosts<<EOF
10.172.16.10 rediserl   
10.172.16.11 redisphp   
10.172.16.12 redisjava  
10.172.16.13 zookeeper  
10.172.16.14 kafka      
10.172.16.15 rabbitmq   
10.172.16.16 mysql      
10.172.16.17 mongo      
10.172.16.18 titan-web  
10.172.16.19 titan-connect-dh 
10.172.16.20 titan-connect-selector 
10.172.16.21 titan-wisteria   
10.172.16.22 titan-gateway    
10.172.16.23 titan-user-srv   
10.172.16.24 titan-upload-srv 
10.172.16.26 titan-detect-srv 
10.172.16.27 titan-job-srv  
10.172.16.28 titan-clusterlink-srv  
10.172.16.25 titan-scan-srv   
10.172.16.40 titan-dbbackup 
EOF'

}

usage() {
    cat <<_EOF_
pre_install.sh <options>
Options:
  compose_dev          copy java.json and config /etc/hosts for dev
  host_mode            change docker-compose network_mode: host     
  help                 show this help
_EOF_
}

action=$1
#echo "Action is $action"
case $action in
    compose_dev)
        compose_dev | tee -a dev.log
        exit 0
        ;;
    host_mode)
        host_mode | tee -a dev.log
        exit 0
        ;;
    help)
        usage | tee -a dev.log
        exit 0
        ;;
    *)
        usage | tee -a dev.log
        exit 0
        ;;
esac