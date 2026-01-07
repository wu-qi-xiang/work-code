#!/bin/bash

TYPE=$1
NAME=$2
STATE=$3

date_str=`date "+%F %T"`
case $STATE in
        "MASTER") echo $date_str" MASTER" >> /data/app/www/titan-web/config_scripts/keepalived_state_change
                  ;;
        "BACKUP") echo $date_str" BACKUP" >> /data/app/www/titan-web/config_scripts/keepalived_state_change
                  ;;
        "FAULT")  echo $date_str" FAULT" >> /data/app/www/titan-web/config_scripts/keepalived_state_change
                  exit 0
                  ;;
        *)        echo $date_str" UNKONW" >> /data/app/www/titan-web/config_scripts/keepalived_state_change
                  exit 1
                  ;;
esac