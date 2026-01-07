#!/bin/bash

WEB_PATH="/data/app/www/titan-web"
PHP_EXEC="/usr/local/php/bin/php"

usage() {
    cat <<_EOF_
docker run [-it] <container name> <options>
Options:
  start                 start the container
  update_agent_config   register the default account
  sync_rules            sync rules
  help                  show this help
_EOF_
}

# 语法结构与 titan-app.sh 里保持一致，便于那边修改了，这边也做相同的修改即可。 相比 titan-app.sh 去掉了sudo，去掉了service重启命令
# 后面如果不维护titan-app.sh了，可以把这里改得简明一点，去掉bash -c ，去掉里面的各种转义符号，现在真难看
update_agent_config(){

    local upgrade=$1

if [ "${upgrade}" == "upgrade" ];then
#upgrade
    bash -c "\
    echo \"============== 加载Linux Agent 版本 ============\"; \
    ver_linux=\`ls /data/app/www/agent-update |grep '^v' |egrep -v '(v*-win*|v*-aix*|v*-aarch64*|v*-solaris.*|virus_engine)'|sort -Vr |head -1\`; \
    [ -n \"\${ver_linux}\" ] && \
     ${PHP_EXEC} ${WEB_PATH}/script/update_agent.php linux \${ver_linux} && \
    echo linux agent version: \${ver_linux}; \
    [ \$? -ne 0 -a -n \"\${ver_linux}\" ] && echo failed && exit 1; \
    [ -z \"\${ver_linux}\" ] && echo [Warning]linux_agent_not_found; \

    echo \"============== 加载 Windows Agent 版本 ==========\"; \
    ver_win=\`ls /data/app/www/agent-update |grep '^v' |grep 'v*-win*' |sort -Vr |head -1\`; \
    [ -n \"\${ver_win}\" ] && sleep 12 && \
     ${PHP_EXEC} ${WEB_PATH}/script/update_agent.php windows \${ver_win} && \
    echo windows agent version: \${ver_win}; \
    [ \$? -ne 0 -a -n \"\$ver_win\" ] && echo failed && exit 1; \
    [ -z \"\${ver_win}\" ] && echo [Warning]windows_agent_not_found; \

    echo \"============== 加载 ARM Linux Agent 版本 ==========\"; \
    ver_arm_linux=\`ls /data/app/www/agent-update |grep '^v' |grep 'v*-aarch64*' |sort -Vr |head -1\`; \
    [ -n \"\${ver_arm_linux}\" ] && sleep 12 && \
     ${PHP_EXEC} ${WEB_PATH}/script/update_agent.php aarch64 \${ver_arm_linux} && \
    echo ARM Linux agent version: \${ver_arm_linux}; \
    [ \$? -ne 0 -a -n \"\$ver_arm_linux\" ] && echo failed && exit 1; \
    [ -z \"\${ver_arm_linux}\" ] && echo [Warning]ARM_Linux_agent_not_found; \

    echo \"============== 加载 AIX Agent 版本 ==========\"; \
    ver_aix=\`ls /data/app/www/agent-update |grep '^v' |grep 'v*-aix*' |sort -Vr |head -1\`; \
    [ -n \"\${ver_aix}\" ] && sleep 12 && \
     ${PHP_EXEC} ${WEB_PATH}/script/update_agent.php aix \${ver_aix} && \
    echo aix agent version: \${ver_aix}; \
    [ \$? -ne 0 -a -n \"\$ver_aix\" ] && echo failed && exit 1; \
    [ -z \"\${ver_aix}\" ] && echo [Warning]aix_agent_not_found; \


    echo \"============== 加载 Solaris Agent 版本 ==========\"; \
    ver_solaris=\`ls /data/app/www/agent-update |grep '^v' |grep 'v*-solaris' |sort -Vr |head -1\`; \
    [ -n \"\${ver_solaris}\" ] && sleep 12 && \
     ${PHP_EXEC} ${WEB_PATH}/script/update_agent.php solaris \${ver_solaris} && \
    echo solaris agent version: \${ver_solaris}; \
    [ \$? -ne 0 -a -n \"\$ver_solaris\" ] && echo failed && exit 1; \
    [ -z \"\${ver_solaris}\" ] && echo [Warning]solaris_agent_not_found;"
else
	#new install
    bash -c "\
    echo \"============== 加载Linux Agent 版本 ============\"; \
    ver_linux=\`ls /data/app/www/agent-update |grep '^v' |egrep -v '(v*-win*|v*-aix*|v*-aarch64*|v*-solaris.*|virus_engine)'|sort -Vr |head -1\`; \
    [ -n \"\${ver_linux}\" ] && \
     ${PHP_EXEC} ${WEB_PATH}/script/update_agent.php linux \${ver_linux} publish && \
    echo linux agent version: \${ver_linux}; \
    [ \$? -ne 0 -a -n \"\${ver_linux}\" ] && echo failed && exit 1; \
    [ -z \"\${ver_linux}\" ] && echo [Warning]linux_agent_not_found; \

    echo \"============== 加载 Windows Agent 版本 ==========\"; \
    ver_win=\`ls /data/app/www/agent-update |grep '^v' |grep 'v*-win*' |sort -Vr |head -1\`; \
    [ -n \"\${ver_win}\" ] && sleep 12 && \
     ${PHP_EXEC} ${WEB_PATH}/script/update_agent.php windows \${ver_win} publish && \
    echo windows agent version: \${ver_win}; \
    [ \$? -ne 0 -a -n \"\$ver_win\" ] && echo failed && exit 1; \
    [ -z \"\${ver_win}\" ] && echo [Warning]windows_agent_not_found; \

    echo \"============== 加载 ARM Linux Agent 版本 ==========\"; \
    ver_arm_linux=\`ls /data/app/www/agent-update |grep '^v' |grep 'v*-aarch64*' |sort -Vr |head -1\`; \
    [ -n \"\${ver_arm_linux}\" ] && sleep 12 && \
     ${PHP_EXEC} ${WEB_PATH}/script/update_agent.php aarch64 \${ver_arm_linux} publish && \
    echo ARM Linux agent version: \${ver_arm_linux}; \
    [ \$? -ne 0 -a -n \"\$ver_arm_linux\" ] && echo failed && exit 1; \
    [ -z \"\${ver_arm_linux}\" ] && echo [Warning]ARM_Linux_agent_not_found; \

    echo \"============== 加载 AIX Agent 版本 ==========\"; \
    ver_aix=\`ls /data/app/www/agent-update |grep '^v' |grep 'v*-aix*' |sort -Vr |head -1\`; \
    [ -n \"\${ver_aix}\" ] && sleep 12 && \
     ${PHP_EXEC} ${WEB_PATH}/script/update_agent.php aix \${ver_aix} publish && \
    echo aix agent version: \${ver_aix}; \
    [ \$? -ne 0 -a -n \"\$ver_aix\" ] && echo failed && exit 1; \
    [ -z \"\${ver_aix}\" ] && echo [Warning]aix_agent_not_found; \


    echo \"============== 加载 Solaris Agent 版本 ==========\"; \
    ver_solaris=\`ls /data/app/www/agent-update |grep '^v' |grep 'v*-solaris' |sort -Vr |head -1\`; \
    [ -n \"\${ver_solaris}\" ] && sleep 12 && \
     ${PHP_EXEC} ${WEB_PATH}/script/update_agent.php solaris \${ver_solaris} publish && \
    echo solaris agent version: \${ver_solaris}; \
    [ \$? -ne 0 -a -n \"\$ver_solaris\" ] && echo failed && exit 1; \
    [ -z \"\${ver_solaris}\" ] && echo [Warning]solaris_agent_not_found;"

fi
    bash -c "\
    echo \"============== Touch titanagent.md5sum ========\"; \
    cd /data/app/www/agent-update &&  touch titanagent.md5sum && \
     chmod 655 titanagent.md5sum && echo titanagent.md5sum created || exit 1; \

    echo \"================= 配置curl安装 =================\"; \
     ${PHP_EXEC} ${WEB_PATH}/script/update_curl.php || exit 1;"


    bash -c "\
        echo \"============== Touch titanagent.md5sum ========\"; \
        cd /data/app/www/agent-update &&  touch titanagent.md5sum && \
         chmod 655 titanagent.md5sum && echo titanagent.md5sum created || exit 1"

}

sync_rules() {
    echo "================= 同步后台规则 ================="; 
    flag=0
    [ -d ${WEB_PATH}/rules ] || (echo "rules pack not found" && exit 1); 
    [ -d ${WEB_PATH}/license ] || (echo "license pack not found" && exit 1); 
    ${PHP_EXEC} ${WEB_PATH}/update/cli/license.php ${WEB_PATH}/license || exit 1;
    ${PHP_EXEC} ${WEB_PATH}/update/cli/pack.php -d ${WEB_PATH}/rules -no-sync || flag=1;
    ${PHP_EXEC} ${WEB_PATH}/update/cli/pack.php -s || flag=1 
    chown -Rf nginx:nginx /data/app/www/titan-web
    if [[ $flag == 1 ]]; then
        echo "部分规则导入有错误，请检查"
        exit 1
    fi
}

start() {
    # 启动前检查nginx server配置文件不存在则复制过去
    test -f /data/app/conf/nginx.servers.conf || /bin/cp -rf /data/app/conf-inner/*  /data/app/conf/

    mkdir -p /data/titan-logs/php /data/titan-logs/supervisor /data/titan-logs/php-fpm /data/titan-logs/nginx
    chown -R nginx:nginx /data/app/www/titan-web/conf /data/app/www/titan-web/license /data/app/www/titan-web/rules  /data/app/conf 
    chown nginx:nginx /data/titan-logs/php /data/titan-logs/supervisor /data/titan-logs/php-fpm /data/titan-logs/nginx /var/log/nginx

    su -s /bin/sh -c "supervisord" nginx
    su -s /bin/sh -c "php-fpm --fpm-config /usr/local/etc/php-fpm.conf --pid /data/titan-logs/php-fpm/php-fpm.pid" nginx
    crond -b -d 0 -L /var/log/crond.log
    nginx -g "daemon off;"
}

action=$1

echo "Action is $action"

case $action in
    start)
        start
        exit 0
        ;;
    sync_rules)
        sync_rules
        exit 0
        ;;
    update_agent_config)
        update_agent_config "$2"
        exit 0
        ;;
    help)
        usage
        exit 0
        ;;
    *)
        exec "$@"
        ;;
esac

