#! /usr/bin/env python
# -*- coding: utf-8 -*-
# auther xiang.wu

import os
import sys
import json
import re
import commands
from config_helper import *

reload(sys)
sys.setdefaultencoding('utf8')
kafka_ips = get_service_ips("java_kafka")
kafka_ip = kafka_ips[0]
zkconnect = "127.0.0.1:2181"
kafka_path = "/usr/local/qingteng/kafka/bin"


def alter_mysql_table():
    # 卸载微隔离时修改的mysql表。
    ENCRYPT_PASSWD_DICT = {}
    mysql_ips = get_service_ips("db_mysql_php")
    mysql_ip = mysql_ips[0]
    #ScriptPath = os.path.split(os.path.realpath(sys.argv[0]))[0]
    java_config = json.load(file("/data/app/titan-config/java.json"))
    pbeconfig = java_config["base"]["pbeconfig"]
    ENCRYPT_PASSWD_DICT["mysql"] = java_config["mysql"]["password"]
    mysql_pwd = decrypt_string(pbeconfig[:16],pbeconfig[16:],ENCRYPT_PASSWD_DICT["mysql"])
    _cmd = 'mysql' + ''' -uroot -p'{mysql_pwd}' -e "alter table qt_titan_connect.tc_micro_seg_rule  rename  as  qt_titan_connect.tc_micro_seg_rule_2022;" ''' 
    exec_ssh_cmd(mysql_ip, _cmd.format(mysql_pwd=mysql_pwd), _cmd)
    _cmd = 'mysql' + ''' -uroot -p'{mysql_pwd}' -e "alter table qt_titan_connect.tc_micro_seg_rule_ref  rename as  qt_titan_connect.tc_micro_seg_rule_ref_2022;" ''' 
    exec_ssh_cmd(mysql_ip, _cmd.format(mysql_pwd=mysql_pwd), _cmd)


# 卸载微隔离删除topic
def del_kafka_topic():
    zk_ips = get_service_ips("java_zookeeper")
    zk_ip = zk_ips[0]
    del_topic = ["MICRO-SEGMENTATION-EVENT","ms_access_relation","ms_strategy_sync","ms_strategy_accessRelation","ms_black_strategy_sync","tc_micro_segment_msg","ms_process_warn"]
    for topic in del_topic:
        # 删除kafka中的topic
        list_topic_cmd = '''{kafka_path}/kafka-topics.sh --delete --zookeeper {zkconnect} --topic {topic}'''
        _list_topic_cmd = list_topic_cmd.format(kafka_path=kafka_path, zkconnect=zkconnect, topic=topic)
        exec_ssh_cmd_withresult(kafka_ip, _list_topic_cmd)
        #删除zk中的topic配置
        exec_ssh_cmd_withresult(zk_ip, '''/usr/local/qingteng/zookeeper/bin/zkCli.sh -server {zkconnect} deleteall /brokers/topics/{topic} '''.format(zk_ip=zk_ip,zkconnect=zkconnect,topic=topic))
        

def main():
    func = sys.argv[1]
    if func == 'alter_mysql_table':
        alter_mysql_table()
    elif func == 'del_kafka_topic':
        del_kafka_topic()
    else:
        print('输入参数不对,请重新输入')
        sys.exit(1)


if __name__ == "__main__":
    main()