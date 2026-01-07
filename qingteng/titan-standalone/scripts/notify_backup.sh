#!/bin/bash

IP_JSON=/data/app/www/titan-web/config_scripts/ip.json

get_ip(){
    grep \"$1\" ${IP_JSON} |awk -F ":*" '{print $2}' |awk -F ",*" '{print $1}' | awk -F "\"*" '{print $2}'
}

# vip changed, ssh-keygen -R
VIP=`get_ip vip`
if [ "$VIP" != "" ];then
	ssh-keygen -R $VIP 
fi

# delete crontab
crontab -l | grep -v '/data/app/www/' | crontab -
