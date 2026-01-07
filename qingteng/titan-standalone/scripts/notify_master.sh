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

# delete crontab and install cron again
crontab -l | grep -v '/data/app/www/' | crontab -
python /data/app/www/titan-web/config_scripts/config.py --install_cron
# ensure it's still master
if [ -n "`ip addr|grep inet| awk -F '/' '{print $1}' | grep -v 127.0.0.1 |grep $VIP`" ]; then
	crontab /data/app/www/titan-web/config_scripts/titan.cron
fi
