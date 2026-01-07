#!/bin/bash

nginx_log_dir=${NGINX_LOG_DIR:="/data/titan-logs/nginx/"}
logs=`find $nginx_log_dir -regex ".*[^0-9].log"`
echo " begin mv nginx log file"
for log_file in ${logs[*]}
do
  new_file_name=${log_file%.log}-$(date +%Y%m%d).log
  echo "mv $log_file $new_file_name"
  mv $log_file $new_file_name
done

nginx -s reopen
