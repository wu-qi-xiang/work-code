#!/bin/bash

patrol=$(ps -ef|grep patrol-srv.jar|grep -v grep|wc -l)
echo "$patrol"
if [ "${patrol}" = "0" ]; then
    /data/app/titan-patrol-srv/init.d/patrol-srv restart
fi

counter=$(service nginx status | grep running | wc -l)
echo "$counter"
if [ "${counter}" = "0" ]; then
    service nginx restart
    sleep 5
    counter=$(service nginx status | grep running | wc -l)
    if [ "${counter}" = "0" ]; then
        /etc/init.d/keepalived stop
    fi
fi