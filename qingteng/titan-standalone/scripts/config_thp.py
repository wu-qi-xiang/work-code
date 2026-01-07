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

# 修改kafka中QTEVRNT的参数
def alter_topic_config(): 
    alter_topic=["QTEVENT"]
    retention_ms=24*60*60*1000
    retention_bytes=500*1000*1000*1000 
    list_topic_cmd = '''{kafka_path}/kafka-topics.sh --list --zookeeper {zkconnect}'''
    exists_topics = exec_ssh_cmd_withresult(kafka_ip, list_topic_cmd.format(kafka_path=kafka_path,zkconnect=zkconnect))
    if exists_topics is None:
        print ("查询kafka的topics失败")
        return

    for topic in alter_topic:
        if topic not in exists_topics:
            create_topic_cmd = '''{kafka_path}/kafka-topics.sh  --create --zookeeper {zkconnect} --replication-factor 1 --partitions 3 --topic QTEVENT'''
            _create_topic_cmd = create_topic_cmd.format(kafka_path=kafka_path, zkconnect=zkconnect)
            exec_ssh_cmd_withresult(kafka_ip, _create_topic_cmd)
        alter_topic_ms_bytes_cmd = '''{kafka_path}/kafka-configs.sh  --alter --zookeeper {zkconnect} --entity-type topics --entity-name {topic} --add-config retention.ms={retention_ms},retention.bytes={retention_bytes}'''
        _alter_topic_ms_bytes_cmd = alter_topic_ms_bytes_cmd.format(kafka_path=kafka_path, zkconnect=zkconnect, topic=topic, retention_ms=retention_ms, retention_bytes=retention_bytes)
        exec_ssh_cmd_withresult(kafka_ip, _alter_topic_ms_bytes_cmd)


def main():
    func = sys.argv[1]
    if func == 'alter_topic_config':
        alter_topic_config()
    else:
        print('输入参数不对,请重新输入')
        sys.exit(1)
if __name__ == "__main__":
    main()


    


        





