#!/bin/bash


# error hint
COLOR_G="\x1b[0;32m"  # green
COLOR_R="\x1b[1;31m"  # red
RESET="\x1b[0m"
## ssh login
DEFAULT_PORT=22
DEFAULT_USER=root
ROOT=`cd \`dirname $0\`/.. && pwd`
FILE_DIR=${ROOT}/base/qingteng/other
SERVER_IP_CONF=${ROOT}/service_ip.conf
info_log(){
    echo -e "${COLOR_G}[Info] ${1}${RESET}"
}
error_log(){
    echo -e "${COLOR_R}[Error] ${1}${RESET}"
}
ssh_t(){
    ssh -t -p ${DEFAULT_PORT} -oStrictHostKeyChecking=no ${DEFAULT_USER}@$1 $2
}
hosts=`cat $SERVER_IP_CONF|awk -F " " '{print $2}' | sort | uniq `
chrony_base_addr=`cat $SERVER_IP_CONF |grep php| head -n 1| awk -F " " '{print $2}'`

for host in ${hosts}
  do 
    # 传rpm包并检测是否存在chrony配置文件，如果不存在则使用rpm安装
    ssh_t ${host} "mkdir -p /tmp/chrony"
    info_log "========Check and Install chrony at ${host}========"
    scp -rp ${FILE_DIR}/chrony* ${FILE_DIR}/libseccomp* $DEFAULT_USER@${host}:/tmp/chrony/.
    ssh_t ${host} " [[ -f /etc/chrony.conf ]] || rpm -ivh --force /tmp/chrony/* "
    if [[ $? != 0 ]]; then
        error_log "========Install chrony at ${host} Failed========" && exit 0
    else ssh_t ${host} " sed -i -e 's/^server/#server/g' -e 's/#local/local/' -e 's/#log/log/' -e 's/#allow.*/allow 0.0.0.0\/0/'  /etc/chrony.conf && sed -i \"/server 0/i server $chrony_base_addr iburst\" /etc/chrony.conf  && service chronyd restart"
    fi 
  done
