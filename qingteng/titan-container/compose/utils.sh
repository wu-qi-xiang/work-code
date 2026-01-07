#!/bin/bash

## error hint
COLOR_PR="\x1b[0;35m"  # purplish red
COLOR_G="\x1b[0;32m"  # green
COLOR_R="\x1b[1;31m"  # red
RESET="\x1b[0m"

info_log(){
    echo -e "${COLOR_G}[Info] ${1}${RESET}"
}

error_log(){
    set -eo pipefail
    echo -e "${COLOR_R}[Error] ${1}${RESET}"
    exit 1
}

warn_log(){
    echo -e "${COLOR_PR}[Warn] ${1}${RESET}"
}

wait_for(){
  condition_cmd=$1
  wait_s=$2
  interval=$3

  for i in $(seq 1 $wait_s); do
    echo -e ".\c"
    sleep ${interval:=3};
    ret=`eval ${condition_cmd}`
    if [ -n "$ret" ]; then
        return
    fi
  done
  error_log "wait timeout after `expr $[$wait_s * $interval]` seconds."
}

start_compose_and_wait(){
    # restart and wait restart ok
    docker-compose up -d
    echo "now wait service start, at most wait about 10 minutes ..."
    condition_cmd="docker-compose ps | grep -v -E '(Name.*Command|-------)'"
    if [[ "$1" == "install" ]]; then
      condition_cmd="docker-compose ps | grep -v -E '(Name.*Command|-------)' | grep -v titan-connect-agent"
    fi

    for i in $(seq 1 60); do
        echo -e ".\c"
        if [[ $i -ne 1 ]]; then 
          sleep 10 
        fi
        ret=`eval ${condition_cmd}`
        if [[ -z "$ret" ]]; then
            error_log "container not found after docker-compose up -d, exit"
        elif [[ "$ret" =~ "Exit" || "$ret" =~ "Paused" ]]; then
            docker-compose ps
            error_log "some service start failed, exit"
        elif [[ "$ret" =~ "starting" ]]; then
            continue
        elif [[ "$ret" =~ "Restarting" ]]; then
            continue
        else
            echo "all services start success now"
            return
        fi
    done
    error_log "wait service start timeout"
}

get_common_tag(){
  common_tag=`ls -t *-compose-app*.tar | head -1 | awk -F 'app-|.tar' '{print $2}'`
  [ -z "${common_tag}" ] && error_log "image tag not found!" && exit 1
  echo ${common_tag}
}

random_passwd(){
  head /dev/urandom | tr -dc A-Za-z0-9_ | head -c 16
}

restart_app(){
  docker-compose up -d --force-recreate titan-web titan-connect-agent titan-connect-dh titan-connect-selector titan-connect-sh titan-dbbackup titan-detect-srv titan-gateway titan-job-srv titan-upload-srv titan-user-srv titan-web titan-wisteria
}

get_port(){
  type="$1"
  port=`cat /data/titan-container/titan.env | grep ${type}_port | awk -F "=" '{print $2}'`
  if [[ "$port"x == ""x ]]; then
    error_log "can't find port rom env"
  fi
  echo "$port"
}

get_port_line(){
  web_ports_line=`cat -n docker-compose.yml | grep -E "(hostname: titan-web|ports:)" | grep -A1 "hostname: titan-web" | sed -n 2p | awk '{print $1}'`
  type="$1"
  case $type in
    console)
        expr $web_ports_line + 1
        ;;
    backend)
        expr $web_ports_line + 2
        ;;
    api)
        expr $web_ports_line + 3
        ;;
    agent)
        expr $web_ports_line + 4
        ;;
    *)
        error_log "not support type"
        ;;
  esac
}

update_access(){
  types=("console" "backend" "api" "agent")
  for type in ${types[@]}
  do
    port=`get_port $type`
    line=`get_port_line $type`
    sed "${line}s/-.*$/- \"$port:$port\"/" docker-compose.yml | cat -n |grep -E "(^[ ]+)$line"
    sed -i "${line}s/-.*$/- \"$port:$port\"/" docker-compose.yml
  done
}