#!/bin/bash

set -o pipefail

FILE_ROOT=`cd \`dirname $0\` && pwd`
source ${FILE_ROOT}/utils.sh

load_image(){
    echo "begin load base image to localhost, please wait"
    test -f titan-compose-*base-*.tar && docker load -i titan-compose-*base-*.tar
    test -f titan-rules-*.tar && docker load -i titan-rules-*.tar
    echo "begin load app images to localhost, please wait"
    docker load -i titan-compose-*app-*.tar
}

##### -------------------  for install start ----------------- ####
init_mysql_db(){
  presetRule=`grep presetrule .env | cut -d '=' -f 2`
  if [[ $presetRule == 'Y' ]]; then
    echo "install preset rules"
    rulesImage=`grep rules_image .env | cut -d '=' -f 2`
    docker run -ti --rm -v /data/titan-container/:/data/ $rulesImage sh -c 'test -d /data/mysql/qt_titan || pv -L 20m /mysql.tar.gz | tar -kzxvf - -C /data/ ; chown -R 1001:1001 /data/mysql'
  else
    #如果没有预置规则包 则需要复制php容器里的数据库初始化文件并执行
    phpImage=`grep ^php_image .env | cut -d '=' -f 2`
    docker-compose up -d mysql
    docker run -d --name="prepare-for-db" --rm $phpImage tail -f /dev/null
    docker cp prepare-for-db:/data/app/www/titan-web/db db
    docker cp db mysql:/tmp
    rm -rf db
    docker container stop prepare-for-db
    info_log "wait mysql start and init mysqldb"
    wait_for "docker-compose ps mysql | grep '(healthy)'" 30 10
    docker exec mysql bash -x -c 'mysqlpasswd=`cat /run/secrets/mysql_password`; for sqlfile in /tmp/db/*.sql; do mysql -uroot -p$mysqlpasswd < $sqlfile; done' 
  fi
}

#复制cdc和小红伞到指定目录
copy_cdc_and_ave(){
  cdcImage=`grep uploadsrv_cdc_image .env | cut -d '=' -f 2`
  docker run -ti --rm -v /data:/data $cdcImage sh -c '\
  rm -rf /data/titan-container/java/upload-srv/qingteng-openjdk \
  && cp -r /usr/local/qingteng/qingteng-openjdk /data/titan-container/java/upload-srv/ \
  && rm -rf /data/titan-container/java/upload-srv/cdc \
  && cp -r /titan-upload-srv/cdc /data/titan-container/java/upload-srv/ \
  && chown -R 2020:2020 /data/titan-container/java/upload-srv/qingteng-openjdk \
  && chown -R 2020:2020 /data/titan-container/java/upload-srv/cdc '

  aveImage=`grep uploadsrv_ave_image .env | cut -d '=' -f 2`
  docker run -ti --rm -v /data:/data $aveImage sh -c '\
  rm -rf /data/titan-container/java/upload-srv/titan_ave \
  && cp -r /titan-upload-srv/titan_ave /data/titan-container/java/upload-srv/ \
  && chown -R 2020:2020 /data/titan-container/java/upload-srv/titan_ave'
  echo "install cdc and ave done"
}

#复制agent安装包到指定目录
copy_agent_pkg(){
  agentImage=`grep titanagent_image .env | cut -d '=' -f 2`
  docker run -ti --rm -v /data:/data $agentImage sh -c 'cp -rf /rpm /data/titan-container/agent-pkg/ ; cp -rf /newshellaudit /data/titan-container/agent-pkg/ ; cp -rf /agent-update /data/titan-container/agent-pkg/ && chown -R 100:101 /data/titan-container/agent-pkg '
  echo "copy_agent_pkg done"
}

pre_install(){
  cp -fu env_template .env
  
  echo "create dir and ensure permission"
  deployImage=`grep deploy_image .env | cut -d '=' -f 2`
  docker run -ti --rm -v /data:/data -v "$FILE_ROOT"/titan.env_template:/root/titan.env_template $deployImage sh /prepare.sh

  init_mysql_db

  copy_cdc_and_ave
  copy_agent_pkg

  echo "create subnet titan_net if not exists"
  docker network ls | grep titan_net || docker network create -d bridge --subnet 10.172.16.0/24 -o "com.docker.network.bridge.name"="br-titancompose" titan_net
  
  # check_port
  cmd="ss -tuln | grep -E ':(80|81|8001|8002|8443|6677|7788|6220) '"
  result=`eval $cmd`
  if [ -n "$result" ]; then 
    eval $cmd
    error_log "some ports had been used. Please check and stop that process and then rerun this script"
  fi
}

update_license(){
    echo "update license"
    license_zipfile=`ls -t *-license*.zip | head -1`
    [ -z "${license_zipfile}" ] && echo "can't find license file" && exit 1

    rm -rf license/ && mkdir license
    alpineImage=`grep alpine_image .env | cut -d '=' -f 2`
    docker run -ti --rm -v "$FILE_ROOT"/:/tmp/ $alpineImage sh -c "unzip /tmp/$license_zipfile -d /tmp/license"

    license_content=`cat license/license.key`
    docker exec -ti zookeeper bash -c "zkCli.sh -server 127.0.0.1:2181 create /license null"
    docker exec -ti zookeeper bash -c "zkCli.sh -server 127.0.0.1:2181 create /license/license.key '$license_content'"
    docker exec -ti zookeeper bash -c "zkCli.sh -server 127.0.0.1:2181 set /license/license.key '$license_content'"

    docker exec -ti titan-web bash -c 'rm -rf /data/app/www/titan-web/license/*'
    docker cp license/. titan-web:/data/app/www/titan-web/license
    docker exec -ti titan-web bash -c 'php /data/app/www/titan-web/update/cli/license.php /data/app/www/titan-web/license'
    sleep 5 && docker-compose up -d titan-connect-agent
    echo "wait connect-agent ok, at most wait 5 minutes ..."
    wait_for "docker-compose ps titan-connect-agent | grep '(healthy)'" 30 10
}

sync_rules(){
    echo "sync rules"
    rule_zipfile=`ls -t *-rule-*.zip | head -1`
    [ -z "${rule_zipfile}" ] && echo "can't find rule file" && exit 1

    rm -rf rules/ && mkdir rules
    alpineImage=`grep alpine_image .env | cut -d '=' -f 2`
    docker run -ti --rm -v "$FILE_ROOT"/:/tmp/ $alpineImage sh -c "unzip /tmp/$rule_zipfile -d /tmp/rules"

    docker exec -ti titan-web bash -c 'rm -rf /data/app/www/titan-web/rules/*'
    docker cp rules/. titan-web:/data/app/www/titan-web/rules

    docker exec -ti titan-web /docker-run.sh sync_rules
}

updatedb(){
    docker exec -ti titan-web php /data/app/www/titan-web/script/updatedb.php auto
}

update_agent_config(){
    echo "update agent config"
    docker exec -ti titan-web /docker-run.sh update_agent_config $1
}

init_data(){
    updatedb
    update_license
    sync_rules
    update_agent_config
}

register(){
    echo "begin register" | tee -a install.log
    echo "=================== 注册前台账号 ==================="
    randompwd=`head /dev/urandom | tr -dc A-Za-z0-9@%_ | head -c 13`
    read -ep "Input username (default: admin@sec.com): " username
    read -ep "Input password (default: $randompwd): " password
    echo ${username:="admin@sec.com"}  ${password:="$randompwd"}
    docker exec -ti titan-web /usr/local/php/bin/php /data/app/www/titan-web/update/cli/v3-tool-front-register.php $username $password

    echo "=================== 注册后台账号 ==================="
    randompwd=`head /dev/urandom | tr -dc A-Za-z0-9@%_ | head -c 13`
    read -ep "Input username (default: admin@sec.com): " username
    read -ep "Input password (default: $randompwd): " password
    echo ${username:="admin@sec.com"}  ${password:="$randompwd"}
    docker exec -ti titan-web /usr/local/php/bin/php /data/app/www/titan-web/user-backend/cli/back-register.php $username $password

    echo "=================== 注册go-patrol账号 ==================="
    docker exec -ti titan-go-patrol /data/app/titan-go-patrol/go-patrol register -c /data/app/titan-go-patrol/config/settings.yml
    echo "end register" | tee -a install.log
}

##### -------------------  for install end ----------------- ####

license_code(){
  test -f .env || cp -f env_template .env
  docker load -i titan-sysinfo-*.tar
  sysinfoImage=`grep sysinfo_image .env | cut -d '=' -f 2`
  docker run -ti --rm --net=host $sysinfoImage su -s /bin/sh -c "/sysinfo --split" titan
}

##### -------------------  for upgrade ----------------- ####
upgrade_config_and_pkg(){
    cp -f env_template .env

    echo "backup old config and cp new config and script"
    deployImage=`grep deploy_image .env | cut -d '=' -f 2`
    docker run -ti --rm -v /data:/data -v "$FILE_ROOT"/titan.env_template:/root/titan.env_template $deployImage sh -c "
    awk -F= '(FNR==NR && !\$1) || !a[\$1]++' /data/titan-container/titan.env /root/titan.env_template > /root/titan.env_merge; \
    awk -F= '(FNR==NR && !\$1) || !a[\$1]++' /data/titan-container/config/java/java.properties /root/config/java/java.properties > /root/java.properties_merge; \
    echo -n '' >> /data/titan-container/config/java/job.properties; \
    awk -F= '(FNR==NR && !\$1) || !a[\$1]++' /data/titan-container/config/java/job.properties /root/config/java/job.properties > /root/job.properties_merge; \
    awk -F= '(FNR==NR && !\$1) || !a[\$1]++' /data/titan-container/config/java/sh.properties /root/config/java/sh.properties > /root/sh.properties_merge; \
    awk -F= '(FNR==NR && !\$1) || !a[\$1]++' /data/titan-container/config/php/application.properties /root/config/php/application.properties > /root/application.properties_merge; \
    awk -F= '(FNR==NR && !\$1) || !a[\$1]++' /data/titan-container/config/php/build.properties /root/config/php/build.properties > /root/build.properties_merge; \
    cp -f /data/titan-container/config/mongod.conf /root/config/; \
    cp -rf /root/config /data/titan-container/; \
    cp -rf /data/titan-container/config /data/titan-container/config_bak`date +%s`; \
    cp -f /root/titan.env_merge /data/titan-container/titan.env; \
    cp -f /root/java.properties_merge /data/titan-container/config/java/java.properties; \
    cp -f /root/job.properties_merge /data/titan-container/config/java/job.properties; \
    cp -f /root/sh.properties_merge /data/titan-container/config/java/sh.properties; \
    cp -f /root/application.properties_merge /data/titan-container/config/php/application.properties; \
    cp -f /root/build.properties_merge /data/titan-container/config/php/build.properties; \
    cp -rf /root/script /data/titan-container/ "
    update_access

    copy_cdc_and_ave
    copy_agent_pkg
}

## execute mongo upgrade script in upgradetool
exec_upgradetool(){
  fromver="$1"
  tover="$2"
  if [[ "$fromver" == "" ]] || [[ "$tover" == "" ]]; then
    error_log "exec_upgradetool version error" 
  fi
  if [[ "$fromver" == "$tover" ]]; then
    info_log "from verion equals to verion, will not execute upgrade script" && return 
  fi

  test -d upgradetool_log || mkdir upgradetool_log
  docker cp titan-wisteria:/data/app/titan-config/java.json ./upgradetool_log/
  upgradeToolImage=`grep upgradetool_image .env | cut -d '=' -f 2`
  docker run -dti --rm --name="upgradetool" --network titan_net -v "$FILE_ROOT"/upgradetool_log/:/upgradetool_log $upgradeToolImage sh -c "mkdir -p /data/app/titan-config/ && cp /upgradetool_log/java.json /data/app/titan-config/java.json && echo 'upgrade.py execute begin'; cd /data/app/upgradeTool && python upgrade.py --type standalone byVersion --fromVer $fromver --toVer $tover; cp /data/app/upgradeTool/*.log /upgradetool_log/; sleep 3"
  docker exec -ti upgradetool sh -c 'sleep 1; test -f /data/app/upgradeTool/info*.log && tail -f /data/app/upgradeTool/info*.log'
  rm -f upgradetool_log/java.json
}

usage() {
    cat <<_EOF_
compose.sh <options>
Options:
  load_image           load image to localhost
  license_code         get license auth code 
  pre_install          prepare for pre_install     
  install              install and start and init_data
  init_data            update license and sync rules and update agent config and register account      
  update_license       update license and wait connect-agent ok
  sync_rules           sync rules 
  update_agent_config  update agent url 
  register             register console and backend account
  start                start and wait start success     
  update_config        update config for new version
  help                 show this help
  upgrade              upgrade to new version
_EOF_
}

action=$1
#echo "Action is $action"
case $action in
	  license_code)
        license_code | tee -a install.log
        exit 0
        ;;
    update_license)
        update_license | tee -a install.log
        exit 0
        ;;
    sync_rules)
        sync_rules | tee -a install.log
        exit 0
        ;;
    load_image)
        load_image | tee -a install.log
        exit 0
        ;;
    pre_install)
        pre_install | tee -a install.log
        exit 0
        ;;
    install)
        load_image | tee -a install.log
        pre_install | tee -a install.log
        start_compose_and_wait install | tee -a install.log
        init_data | tee -a install.log
        register
        exit 0
        ;;
    start)
        start_compose_and_wait | tee -a install.log
        exit 0
        ;;
    init_data)
        init_data | tee -a install.log
        register
        exit 0
        ;;
    update_agent_config)
        update_agent_config | tee -a install.log
        exit 0
        ;;
    update_agent_config_upgrade)
        update_agent_config upgrade | tee -a install.log
        exit 0
        ;;
    register)
        register
        exit 0
        ;;
    updatedb)
        updatedb | tee -a install.log
        exit 0
        ;;
    upgrade)
        load_image | tee -a install.log
        upgrade_config_and_pkg | tee -a install.log
        fromver=`docker container ls -a --format "table {{.ID}}|{{.Image}}"| grep wisteria | head -n 1 | cut -d ":" -f 2 | cut -d "-" -f 1`
        start_compose_and_wait | tee -a install.log
        updatedb | tee -a install.log
        update_agent_config upgrade | tee -a install.log
        curver=`cat .env | grep wisteria | cut -d ":" -f 2 | cut -d "-" -f 1`
        exec_upgradetool "$fromver" "$curver" | tee -a install.log
        ;;
    exec_upgradetool)
        exec_upgradetool $2 $3 | tee -a install.log
        ;;
    help)
        usage && exit 0
        ;;
    *)
        printf "Wrong option or empty option...!" 1>&2
        usage && exit 1
        ;;
esac
