#!/bin/bash
# ------------------------------------------------------------------------------
# @author:  leilei.zhai
# @copyright leilei.zhai@qingteng.cn
# @doc:     Auto rsync_bash version
#-------------------------------------------------------------------------------

AGENT_BUILD_SSH_URL=qingteng@172.16.6.187
buildVariant=$1
shell_audit_path="bashaudit/$2"
dns_access_path="dns_access/$3"
cmdaudit_path="cmdaudit/$4"
psaudit_path="psaudit/$5"
sysmon_path="sysmon/$6"

#local
event_plugin_linux_localpath="/data/app/www/agent-update/event_plugin/$buildVariant/radar_event_collect_plugin2/linux"
event_plugin_windows_localpath="/data/app/www/agent-update/event_plugin/$buildVariant/radar_event_collect_plugin2/windows"
#remote
event_plugin_remotepath="agent_files/www/agent-update/radar_event_collect_plugin"


info_log(){
    echo -e "${COLOR_G}$(date +"%Y-%m-%d %T")[Info] ${1}${RESET}"
}

error_log(){
    echo -e "${COLOR_R}$(date +"%Y-%m-%d %T")[Error] ${1}${RESET}"
    exit 1
}

check(){
    if [ $? -eq 0 ];then
        info_log "found version: $1"
    else
        error_log "Not found  version: $1"
        exit 1
    fi
}


mkdir -p agent_files/www/agent-update
rm -rf agent_files/www/agent-update/*
mkdir -p $event_plugin_remotepath/windows/cmdaudit/
mkdir -p $event_plugin_remotepath/windows/psaudit/
mkdir -p $event_plugin_remotepath/windows/sysmon/
mkdir -p $event_plugin_remotepath/linux/bashaudit/


#curl
rsync -rv --delete $AGENT_BUILD_SSH_URL:/data/app/www/agent-update/curl agent_files/www/agent-update/
#linux
#newshellaudit
rsync -rv --delete $AGENT_BUILD_SSH_URL:$event_plugin_linux_localpath/bashaudit/common/* $event_plugin_remotepath/linux/bashaudit/
check "newshellaudit/common"
#shellaudit
rsync -rv --delete $AGENT_BUILD_SSH_URL:$event_plugin_linux_localpath/$shell_audit_path/latest/* $event_plugin_remotepath/linux/bashaudit/
check "$shell_audit_path "
#dns_access
rsync -rv --delete $AGENT_BUILD_SSH_URL:$event_plugin_linux_localpath/$dns_access_path/latest/* $event_plugin_remotepath/linux/dns_access/
check "$_path"
#window cmdaudit  psaudit  sysmon
rsync -rv --delete $AGENT_BUILD_SSH_URL:$event_plugin_windows_localpath/$cmdaudit_path/latest/* $event_plugin_remotepath/windows/cmdaudit/
check "$cmdaudit_path"
rsync -rv --delete $AGENT_BUILD_SSH_URL:$event_plugin_windows_localpath/$psaudit_path/latest/* $event_plugin_remotepath/windows/psaudit/
check "$psaudit_path"
rsync -rv --delete $AGENT_BUILD_SSH_URL:$event_plugin_windows_localpath/$sysmon_path/latest/* $event_plugin_remotepath/windows/sysmon/
check "$sysmon_path"
