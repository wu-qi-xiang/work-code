#!/bin/bash
# ------------------------------------------------------------------------------
# @author:  leilei.zhai
# @copyright leilei.zhai@qingteng.cn
# @doc:     Auto rsync_cdc version
# 弃用： 202206201605
#-------------------------------------------------------------------------------

FILE_ROOT=`cd \`dirname $0\` && pwd`
AGENT_BUILD_SSH_URL=qingteng@172.16.6.187
CDC_PATH="$FILE_ROOT/upload-srv/build_cdc/cdc/webshell_engine"
CDC_JSP_PATH="$CDC_PATH/jsp_cdc"
Update_type=$1

info_log(){
    echo -e "${COLOR_G}$(date +"%Y-%m-%d %T")[Info] ${1}${RESET}"
}

error_log(){
    echo -e "${COLOR_R}$(date +"%Y-%m-%d %T")[Error] ${1}${RESET}"
    exit 1
}

check(){
    if [ $? -eq 0 ];then
        info_log "Update $1 successfully"
    else
        error_log "Update $1 failed"
    fi
}
##更新cdc_php
if [ "$Update_type" == "all" ];then
    info_log "Update cdc_php"
    rm -rf $CDC_PHP_PATH/php_cdc
    rsync -rv --delete $AGENT_BUILD_SSH_URL:/data/thunderfire/php/php_cdc.tar.gz $CDC_PATH
    cd $CDC_PATH && tar -zxf php_cdc.tar.gz  && chmod +x php_cdc/cdc_php.sh && rm -rf php_cdc.tar.gz
    check "cdc_php"
fi

##更新cdc_jsp
info_log "Update cdc_jsp"
rsync -rv --delete $AGENT_BUILD_SSH_URL:/data/thunderfire/jsp/jspwebshell*.jar $CDC_JSP_PATH/
for files in {threat_func.json,cdc.properties,match.json};do
    rsync -rv --delete $AGENT_BUILD_SSH_URL:/data/thunderfire/jsp/$files $CDC_JSP_PATH/src/config/
done
rsync -rv --delete $AGENT_BUILD_SSH_URL:/data/thunderfire/jsp/lib $CDC_JSP_PATH/
rsync -rv --delete $AGENT_BUILD_SSH_URL:/data/thunderfire/jsp/cdc_jsp.sh $CDC_JSP_PATH/
check "cdc_jsp"