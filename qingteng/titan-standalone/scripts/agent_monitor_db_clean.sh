#!/bin/bash

OLDDATE=`date  -d'30 day ago' +%Y%m%d`
MYSQL_PASSWD=9pbsoq6hoNhhTzl

IP_TEMPLATE=/data/app/www/titan-web/config_scripts/ip_template.json

get_ip(){
    grep \"$1\" ${IP_TEMPLATE} |awk -F ":*" '{print $2}' |awk -F ",*" '{print $1}' | awk -F "\"*" '{print $2}'
}

MIP=`get_ip db_mysql_php`
if [ "$MIP" == "" ];then
	exit 1
fi

DATAS=`/usr/local/qingteng/mysql/bin/mysql -h$MIP -uroot -p$MYSQL_PASSWD -D agent_monitor_db -N -e "show tables"`

for i in $DATAS
do 
      NUM=`echo $i |awk -F'_' '{ print NF }'`
      if [ $NUM -ge 5 ];then
      	YYYY=`echo $i |awk -F'_' '{ print $(NF - 2) }'`
        if [ `echo ${#YYYY}` -eq 1 ];then
		YYYY="0"$YYYY
        fi
      	MM=`echo $i |awk -F'_' '{ print $(NF - 1) }'`
        if [ `echo ${#MM}` -eq 1 ];then
		MM="0"$MM
        fi
      	DD=`echo $i |awk -F'_' '{ print $NF }'`
        if [ `echo ${#DD}` -eq 1 ];then
		DD="0"$DD
        fi
        NOWDATE=$YYYY$MM$DD
	if [ $NOWDATE -lt $OLDDATE ];then
	    /usr/local/qingteng/mysql/bin/mysql -h$MIP -uroot -p$MYSQL_PASSWD -D agent_monitor_db  -e "drop table $i"
        fi
      fi
done
