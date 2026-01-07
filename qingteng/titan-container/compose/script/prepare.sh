#!/bin/sh

mkdir -p /data/titan-container/ /data/titan-logs && chmod 755 /data/titan-container/ /data/titan-logs

cd /data/titan-container/ 
mkdir -p config && mkdir -p script 
mkdir -p redis/data && chown -R 999:1000 redis 
mkdir -p zk-data && chown -R 1000:1000 zk-data 
mkdir -p kafka-data && chown -R 1000:1000 kafka-data 
mkdir -p rabbitmq && chown -R 100:101 rabbitmq 
mkdir -p mysql && chown -R 1001:1001 mysql 
mkdir -p mongodb/data && chown -R 1001:1001 mongodb

mkdir -p titan-web/keys titan-web/rules titan-web/license 
chown -R 101:101 titan-web/
mkdir -p agent-pkg/agent-update && chown -R 101:101 agent-pkg/
mkdir -p java/wisteria/files java/upload-srv/titan_ave java/upload-srv/titan-upload java/upload-srv/yara/rules java/scan-srv/layer 
chown -R 2020:2020 java/ 
mkdir -p patrol/db config/patrol/cert
chown -R 2021:2021 patrol/db config/patrol/cert

cd /data/titan-logs 
mkdir -p redis && chown -R 999:1000 redis 
mkdir -p zookeeper && chown -R 1000:1000 zookeeper 
mkdir -p kafka && chown -R 1000:1000 kafka 
mkdir -p rabbitmq && chown -R 100:101 rabbitmq 
mkdir -p mysql && chown -R 1001:1001 mysql 
mkdir -p mongodb && chown -R 1001:1001 mongodb

mkdir -p php supervisor php-fpm nginx 
chown -R 100:101 php supervisor php-fpm nginx 
mkdir -p java && chown -R 2020:2020 java/
mkdir -p go/patrol && chown -R 2021:2021 go/patrol

# create random secrets
if [[ -f /data/titan-container/secrets/login_rsa_public_key ]]; then
	echo "secret already created"
else
	mkdir -p /data/titan-container/secrets
   	head /dev/urandom | tr -dc A-Za-z0-9@%_ | head -c 32 > /data/titan-container/secrets/pbeconfig
	echo "begin create secrets"
	/root/script/dockerize -pbePath /data/titan-container/secrets/pbeconfig -createSecret /data/titan-container/secrets/zk_password
	/root/script/dockerize -pbePath /data/titan-container/secrets/pbeconfig -createSecret /data/titan-container/secrets/kafka_password
	/root/script/dockerize -pbePath /data/titan-container/secrets/pbeconfig -createSecret /data/titan-container/secrets/mysql_password
	/root/script/dockerize -pbePath /data/titan-container/secrets/pbeconfig -createSecret /data/titan-container/secrets/mongo_password
	/root/script/dockerize -pbePath /data/titan-container/secrets/pbeconfig -createSecret /data/titan-container/secrets/rabbitmq_password
	/root/script/dockerize -pbePath /data/titan-container/secrets/pbeconfig -createSecret /data/titan-container/secrets/redisjava_password
	/root/script/dockerize -pbePath /data/titan-container/secrets/pbeconfig -createSecret /data/titan-container/secrets/redisphp_password
	/root/script/dockerize -pbePath /data/titan-container/secrets/pbeconfig -createSecret /data/titan-container/secrets/rediserl_password
	/root/script/dockerize -pbePath /data/titan-container/secrets/pbeconfig -createSecret /data/titan-container/secrets/thrift_token

	openssl genrsa -out pkcs1_prikey.pem 2048
	openssl pkcs8 -topk8 -inform PEM -in pkcs1_prikey.pem -outform pem -nocrypt -out pkcs8_prikey.pem
	openssl rsa -in pkcs1_prikey.pem -pubout -out tmp_pubkey.pem
	cat pkcs8_prikey.pem |grep -v KEY | tr -d "\n" > /data/titan-container/secrets/login_rsa_private_key
	cat tmp_pubkey.pem |grep -v KEY | tr -d "\n" > /data/titan-container/secrets/login_rsa_public_key
	rm -f pkcs1_prikey.pem pkcs8_prikey.pem tmp_pubkey.pem 
	chmod -R 755 /data/titan-container/secrets
fi

cp -ru /root/config /data/titan-container/ 
mkdir -p /data/titan-container/config/env
# 主要为了自定义服务的JVM内存配置，rabbitmq的暂无用。
touch /data/titan-container/config/env/zookeeper.env
touch /data/titan-container/config/env/kafka.env
touch /data/titan-container/config/env/rabbitmq.env
touch /data/titan-container/config/env/connect-agent.env
touch /data/titan-container/config/env/connect-dh.env
touch /data/titan-container/config/env/connect-selector.env
touch /data/titan-container/config/env/connect-sh.env
touch /data/titan-container/config/env/wisteria.env
touch /data/titan-container/config/env/gateway.env
touch /data/titan-container/config/env/user-srv.env
touch /data/titan-container/config/env/upload-srv.env
touch /data/titan-container/config/env/detect-srv.env
touch /data/titan-container/config/env/job-srv.env
touch /data/titan-container/config/env/scan-srv.env
touch /data/titan-container/config/env/clusterlink-srv.env
touch /data/titan-container/config/env/dbbackup.env
touch /data/titan-container/config/env/go-patrol.env

rm -rf /data/titan-container/config/nginx/cert/* && mkdir -p /data/titan-container/config/nginx/cert
/root/script/mkcert -cert-file /data/titan-container/config/nginx/cert/server.pem -key-file /data/titan-container/config/nginx/cert/server.key localhost 127.0.0.1 ${web_publicip} ${web_domain}

chmod -R 755 /data/titan-container/config


cp -ru /root/script /data/titan-container/ && chmod -R 755 /data/titan-container/script/
cp -fu /root/titan.env_template /data/titan-container/titan.env && chmod -R 755 /data/titan-container/titan.env
echo done