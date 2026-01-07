#!/bin/bash
# ------------------------------------------------------------------------------
# @author:  jiang.wu
# @email:   jiang.wu@qingteng.cn
#-------------------------------------------------------------------------------

## error hint
COLOR_PR="\x1b[0;35m"  # purplish red
COLOR_G="\x1b[0;32m"  # green
COLOR_R="\x1b[1;31m"  # red
RESET="\x1b[0m"

## ssh login
DEFAULT_PORT=22
DEFAULT_USER=root

FILE_ROOT=`cd \`dirname $0\` && pwd`
IP_TEMPLATE=${FILE_ROOT}/ip_template.json

info_log(){
    echo -e "${COLOR_G}[Info] ${1}${RESET}"
}

error_log(){
    echo -e "${COLOR_R}[Error] ${1}${RESET}"
    exit 1
}

warn_log(){
    echo -e "${COLOR_PR}[Warn] ${1}${RESET}"
}

check(){
    if [ $? -eq 0 ];then
        info_log "$* Successfully"
    else
        error_log "$* Failed"
    fi
}

get_ip(){
    grep \"$1\" ${IP_TEMPLATE} |awk -F ":*" '{print $2}' |awk -F ",*" '{print $1}' | awk -F "\"*" '{print $2}'
}

get_ips(){
    local vip=`get_ip vip`
    arr=(`grep -E "\"$1\"|\"$1_cluster\"" ${IP_TEMPLATE} |awk -F'":' '{print $2}' | tr -d '[" \n]'| tr ',' ' '`)
    local ips=()
    # declare exists as a map
    declare -A exists
    if [ -n "$vip" ]; then
        exists[$vip]=1
    fi
    
    for s in ${arr[@]} ; do 
        tempip=${s%:*}
        [[ $tempip == '127.0.0.1' ]] && continue  # if 127.0.0.1, not add to ips
        [[ ${exists[$tempip]} ]] && continue  # if already in exists, not add to ips
        ips+=( "$tempip" )
        exists[$tempip]=1
    done
    echo ${ips[@]}
}

is_file_existed(){
    local file=$1
    if [ ! -e ${file} ]; then
        error_log "${file}: Not Found"
        exit 1
    fi
}

ssh_nt(){
    ssh -p ${DEFAULT_PORT} -oStrictHostKeyChecking=no -o ConnectionAttempts=5 -o ConnectTimeout=3 ${DEFAULT_USER}@$1 $2
}
ssh_t(){
    ssh -t -p ${DEFAULT_PORT} -oStrictHostKeyChecking=no -o ConnectionAttempts=5 -o ConnectTimeout=3 ${DEFAULT_USER}@$1 $2
}
ssh_tt(){
    ssh -tt -p ${DEFAULT_PORT} -oStrictHostKeyChecking=no -o ConnectionAttempts=5 -o ConnectTimeout=3 ${DEFAULT_USER}@$1 $2
}

set_np_authorized(){
    local ip=$1
    ${FILE_ROOT}/setup_np_ssh.sh ${DEFAULT_USER}@${ip} ${DEFAULT_PORT}
}

execute_rsync(){
    local host=$1
    local pkg=$2
    local remote_dir=$3

    [ -z "${pkg}" -o -z "${remote_dir}" ] && echo "execute rsync with wrong params" && exit 1

    set_np_authorized ${host}
    ssh_t ${host} "sudo mkdir -p ${remote_dir}" && rsync -rz --rsync-path="sudo rsync" -e "ssh -p ${DEFAULT_PORT}" --delete ${pkg} ${DEFAULT_USER}@${host}:${remote_dir}/
    check "rsync ${pkg} to ${host} "
}

execute_rsync_file(){
    local host=$1
    local pkg=$2
    local remote_dir=$3

    rsync -rz --rsync-path="sudo rsync" -e "ssh -p $DEFAULT_PORT"  --delete ${pkg} ${DEFAULT_USER}@${host}:${remote_dir}/
    check "rsync ${pkg} to ${host} "
}

execute_scp(){
    local host=$1
    local file=$2
    local remote_dir=$3

    set_np_authorized ${host}
    scp -P ${DEFAULT_PORT} ${file} ${DEFAULT_USER}@${host}:${remote_dir}/
    check "scp ${file} to ${host} "
}

remote_scp(){
    local remote_host=$1
    local remote_file=$2
    local local_dir=$3

    scp -rp -P ${DEFAULT_PORT} ${DEFAULT_USER}@${remote_host}:${remote_file} ${local_dir}
    if [ $? -eq 0 ];then
        echo "scp ${remote_host}:${remote_file} to ${local_dir} Successfully"
    else
        echo "scp ${remote_host}:${remote_file} to ${local_dir} Failed"
    fi
}

# call : remote_scp_to_file 1.1.1.1 /data/app/test.conf /usr/local/
# result : /usr/local/data/app/test.conf
# Generally used for backup config file
remote_scp_to_file(){
    local remote_host=$1
    local remote_file=$2
    local local_file=$3$2

    dir=${local_file%/*}
    [ ! -d $dir ] && mkdir -p $dir

    scp -rp -P ${DEFAULT_PORT} ${DEFAULT_USER}@${remote_host}:${remote_file} ${local_file}
    if [ $? -eq 0 ];then
        echo "scp ${remote_host}:${remote_file} to ${local_file} Successfully"
    else
        echo "scp ${remote_host}:${remote_file} to ${local_file} Failed"
    fi
}
