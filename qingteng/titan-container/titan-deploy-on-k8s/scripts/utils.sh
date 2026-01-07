#!/bin/bash

NS=qtsa
TITAN_DEPLOY_POD=titan-deploy-0

## error hint
COLOR_PR="\x1b[0;35m"  # purplish red
COLOR_G="\x1b[0;32m"  # green
COLOR_R="\x1b[1;31m"  # red
RESET="\x1b[0m"

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

try_to_titandeploy(){
    local cmd=$*
    #echo ${cmd:="bash"}
    deploy=`kubectl -n $NS get po $TITAN_DEPLOY_POD 2>&1 `
    if [[ "$deploy" == *"titan-deploy-0"*"Running"* ]]; then 
        info_log "titan-deploy-0 is running,now go to it to execute command"
        kubectl -n $NS exec -ti $TITAN_DEPLOY_POD -- ${cmd:="bash"}
    else
        if [[ -f titan-deploy.yml ]]; then
            kubectl replace --force -f titan-deploy.yml

            echo "wait titan-deploy start, at most wait 2 minutes ..."
            for i in {1..25}; do
                [ $i -eq 25 ] && echo "wait titan-deploy timeout after 2 minutes." && exit 1;
                sleep 5;
                ret=`kubectl -n $NS get po $TITAN_DEPLOY_POD 2>&1 `
                if [[ "$ret" == *"titan-deploy-0"*"Running"* ]]; then 
                    break
                else
                    continue
                fi
            done
            kubectl -n $NS exec -ti $TITAN_DEPLOY_POD -- ${cmd:="bash"}
        else
            error_log "Can not go to titan-deploy-0, and can't start it automatically"
        fi
    fi

}

#检查是否在titan-deploy内，不在的话尝试进入titan-deploy内执行
check_env(){
    if [[ "$HOSTNAME" != "titan-deploy-0" ]] && [[ ! -f /data/utils.yml ]]; then
        warn_log "The command must execute in titan-deploy-0,checked that now is not in titan-deploy-0, will try to titan-deploy"
        try_to_titandeploy $*
        info_log "try to titan-deploy-0 execute command end, now at $HOSTNAME"
        exit 0
    fi
}