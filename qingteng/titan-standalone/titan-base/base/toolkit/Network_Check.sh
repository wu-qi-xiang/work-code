#!/usr/bin/env bash
## Aulthor: dlh
## desc: 脚本功能测试2个节点之间的网络的健康度，脚本采用mtr工具进行测试

source ~/.bashrc

##需要测试的目的ip，如果多个ip请用逗号隔开
remote_iplist="10.106.109.77"

count=0
sum=1
ip_num=`echo $remote_iplist|grep -o ','|wc -l`
echo "ip_num: $ip_num"
## 日志保留天数
log_save_time=30

if ! command -v mtr >/dev/null 2>&1;then
    yum install mtr -y
    if ! command -v mtr >/dev/null 2>&1;then
       echo "mtr: command not found !"
       exit 1
    fi
fi

## 获取本地的ip地址
local_ip=`ifconfig -a|grep inet|grep -v 127.0.0.1|grep -v inet6|awk '{print $2}'|tr -d "addr:"`
if [[ `echo $local_ip|grep -c ' '` -ge 1 ]];then
    local_ip="127.0.0.1"
fi

execute(){
      file_name="localhost_`echo $1|cut -d'.' -f4`.txt"
      current_time=`date +"%Y-%m-%d %H:%M:%S"`
      #time_H=`echo $current_time|awk -F' ' '{print $2}'|awk -F: '{print $1}'`
      time_H=`date +%_H`
      time_M=`echo $current_time|awk -F: '{print $2}'`
      if [ $time_M == "00" ];then
         echo -e "\t\t Current_period: $time_H~$(($time_H+1))" >>/data/network_test/$day_time/$file_name
         sleep 60
      fi
      result=`mtr -r -c 10 $1|tail -1|awk '{print $3"\t\t\t" $6"ms""\t\t\t" $8"ms"}'`
      if [ $ip_num -eq 0 ];then
          if [ $sum == 1 ];then
             sum=$(($sum+1))
             echo -e "\t\t Current_period: $time_H~$(($time_H+1))" >>/data/network_test/$day_time/$file_name
          fi
      else
          if [[ $count -le $ip_num ]];then
             count=$(($count+1))
             echo -e "\t\t Current_period: $time_H~$(($time_H+1))" >>/data/network_test/$day_time/$file_name
          fi
      fi
      echo -e "$local_ip >>>>>>>>>>>>>>>>>>>> $1 current_time: $current_time">>/data/network_test/$day_time/$file_name
      echo $result|tr ' ' '\t' >>/data/network_test/$day_time/$file_name
}

main(){
while :
do
day_time=`date +"%Y%m%d"`
time_hour=`date +%_H`
if [ ! -d "/data/network_test/$day_time" ];then
   mkdir -p /data/network_test/$day_time
   if [[ `echo $remote_iplist|grep -c ','` -ne 0 ]];then
      array=(${remote_iplist//,/ })
      for ip in ${array[@]}
      do
         file_name="localhost_`echo $ip|cut -d'.' -f4`.txt"
         echo -e "丢包率loss\t平均延时avg\t最长时间延时">>/data/network_test/$day_time/$file_name
      done
   else
       file_name="localhost_`echo $remote_iplist|cut -d'.' -f4`.txt"
       echo -e "丢包率loss\t平均延时avg\t最长时间延时">>/data/network_test/$day_time/$file_name
   fi
fi
if [[ `echo $remote_iplist|grep -c ','` -ne 0 ]];then
   array=(${remote_iplist//,/ })
   for ip in ${array[@]}
   do
      execute $ip
   done
else
   execute $remote_iplist
fi
done
if [ $time_hour == 2 ];then
   find /data/network_test/* -type d -ctime +${log_save_time} -exec rm -rf {} \;
fi
}

main
