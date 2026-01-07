#! /usr/bin/python
# -*- coding: utf-8 -*-

import json
import os
import sys
import getopt
import re
import time
from config_helper import *

def log_error(msg):
    print('\033[31m' + "ERROR:" + str(msg) + '\033[0m')
    sys.exit(1)

def log_warn(msg):
    print('\033[35m' + "WARN:" + str(msg) + '\033[0m')

def log_info(msg):
    print('\033[32m' + "INFO:" +str(msg) + "\033[0m")

def check_rabbitmq_queues():
    rabbit_ips = get_service_ips("erl_rabbitmq")
    rabbit_ip = rabbit_ips[0]

    rabbit_count = len(rabbit_ips)

    queues_master = exec_ssh_cmd_withresult(rabbit_ip, '''/data/app/titan-rabbitmq/bin/rabbitmqctl -q list_queues name messages pid 2>&1 | sed -e 's/[><]//g' ''')

    big_queues = {}
    queues_master_count = {}
    queues_total = len(queues_master.splitlines())
    for name_count_master in queues_master.splitlines():
        tmp_strs = name_count_master.split()
        queue_name = tmp_strs[0]
        queue_count = tmp_strs[1]
        master_str = tmp_strs[2]

        master = master_str[:master_str.find(".")]
        print(master)
        queues_master_count.setdefault(master, 0)
        queues_master_count[master] = queues_master_count[master] + 1

        if int(queue_count) > 5000:
            big_queues[queue_name] = queue_count 

    print(queues_master_count)
    print(queues_total)

    cluster_nodes = exec_ssh_cmd_withresult(rabbit_ip, '''/data/servers/rabbitmq_root/bin/rabbitmqctl cluster_status|sed -n '/Running Nodes/,/Versions/p'|grep -c ^rabbit''') 
    if cluster_nodes == str(len(rabbit_ips)):
        print("all node OK")
    
    if len(queues_master_count) < rabbit_count:
        print("some node have no queue, not balance")

    max_count = max(queues_master_count.values())
    if max_count > (queues_total / rabbit_count) + 3:
        print("not balance, you can run script to reblance the queues")
    else:
        print("queues master balanced")

    if len(big_queues) > 0:
        print("some queues are build-up")
        for queue_name, queue_count in big_queues.items():
            print(queue_name + "    " + queue_count)

def rebalance_rabbitmq_queues():

    rabbit_ips = get_service_ips("erl_rabbitmq")
    rabbit_ip = rabbit_ips[0]

    scp_to_remote("/data/app/www/titan-web/config_scripts/rebalance-queue-masters", rabbit_ip, '/data/app/titan-rabbitmq/bin/')

    print("now begin run rebalance-queue-masters, it will take a long time, please wait")
    exec_ssh_cmd_withresult(rabbit_ip, "export PATH=/data/app/titan-rabbitmq/bin/:$PATH; chmod +x /data/app/titan-rabbitmq/bin/rebalance-queue-masters; /data/app/titan-rabbitmq/bin/rebalance-queue-masters")

def check_glusterfs_mount():
    glusterfs_error_node = set()

    php_ips = get_service_ips("php_frontend_private")
    all_java_ips = get_all_java_ips()
    all_java_ips.update(php_ips)
    for ip in all_java_ips:
        df_result = exec_ssh_cmd_withresult(ip, "df -Ph | grep :/java")
        if not df_result or '传输端点' in df_result or 'Transport endpoint' in df_result:
            glusterfs_error_node.add(ip)

    if len(glusterfs_error_node) > 0:
        log_warn("some host's glusterfs mount exception, please check:" + str(glusterfs_error_node))

def help():
    print "----------------------------------------------------------"
    print "                   Usage information"
    print "----------------------------------------------------------"
    print ""
    print "python titan_cluster_check.py [Args] "
    print "  --check_rabbitmq       check rabbitmq queues balanced or not               "
    print "  --rebalance_rabbitmq   rebalance rabbitmq queues                   "
    print "  --check_glusterfs   check_glusterfs mount                   "
    print "----------------------------------------------------------"
    sys.exit(2)


def main(argv):
    check_rabbitmq = False
    rebalance_rabbitmq = False
    check_glusterfs = False

    try:
        opts, args = getopt.getopt(argv, "", ["check_rabbitmq", "rebalance_rabbitmq", "check_glusterfs"])
    except getopt.GetoptError:
        help()
    for opt, arg in opts:
        if opt in ("--rebalance_rabbitmq"):
            rebalance_rabbitmq = True
        elif opt == "--check_rabbitmq":
            check_rabbitmq = True
        elif opt == "--check_glusterfs":
            check_glusterfs = True
        else:
            help()
            exit(1)

    if rebalance_rabbitmq:
        rebalance_rabbitmq_queues()
        exit(0)

    if check_rabbitmq:
        check_rabbitmq_queues()
        exit(0)

    if check_glusterfs:
        check_glusterfs_mount()
        exit(0)

    help()
    exit(1)    

if __name__ == '__main__':
    main(sys.argv[1:])
