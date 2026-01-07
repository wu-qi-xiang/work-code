#! /usr/bin/env python
# -*- coding: utf-8 -*-

import os
import sys
reload(sys)
sys.setdefaultencoding('utf8')
import json
import re
import commands
from config_helper import *

def init_datasync_config():
    kafka_ips = get_service_ips("java_kafka")
    kafka_ip = kafka_ips[0]
    rep_factor = 3 if len(kafka_ips) >= 3 else 1   # default.replication.factor  
    zkconnect = "127.0.0.1:2181"
    partition_num = 6

    # get kafka properties
    server_properties = exec_ssh_cmd_withresult(kafka_ip,'''cat /usr/local/qingteng/kafka/config/server.properties | grep -E 'zookeeper.connect|default.replication' ''')
    for propline in server_properties.splitlines():
        if not propline:
            continue

        if re.match(r"^default.replication.factor[ ]{0,}=",propline):
            rep_factor = int(propline.split("=")[1])
        elif re.match(r"^zookeeper.connect[ ]{0,}=",propline):
            zkconnect = propline.split("=")[1]
        else:
            continue

    kafka_path = "/usr/local/qingteng/kafka"
    list_topic_cmd = '''{kafka_path}/bin/kafka-topics.sh --list --zookeeper {zkconnect}'''
    exists_topics = exec_ssh_cmd_withresult(kafka_ip, list_topic_cmd.format(kafka_path=kafka_path,zkconnect=zkconnect))
    if exists_topics is None:
        # exec kafka-topics.sh --list failed , return 
        return

    _create_topic_cmd = '''{kafka_path}/bin/kafka-topics.sh --create --zookeeper {zkconnect} --replication-factor {rep_factor} --topic $topic_name --partitions $partition_num --config retention.ms=43200000 '''
    _create_topic_cmd = _create_topic_cmd.format(kafka_path=kafka_path,zkconnect=zkconnect,rep_factor=rep_factor)

    print("\n\n\n######创建change stream topic######") 
    for topic in ["origin_db_change_stream_event","detect_origin_db_change_stream_event",
                    "vul_origin_db_change_stream_event","baseline_origin_db_change_stream_event"]:
        if topic not in exists_topics:
            exec_ssh_cmd_withresult(kafka_ip, _create_topic_cmd.replace("$topic_name",topic).replace("$partition_num",str(partition_num)))
        else:
            exec_ssh_cmd_withresult(kafka_ip, '''{kafka_path}/bin/kafka-configs.sh --alter --zookeeper {zkconnect} --entity-type topics --entity-name {topic_name} --add-config 'retention.ms=43200000' '''.format(kafka_path=kafka_path,zkconnect=zkconnect,topic_name=topic))
            exec_ssh_cmd_withresult(kafka_ip, '''{kafka_path}/bin/kafka-topics.sh --alter --zookeeper {zkconnect}  --topic {topic_name} --partitions 6 '''.format(kafka_path=kafka_path,zkconnect=zkconnect,topic_name=topic))

    print("\n\n\n######获取Topic属性######") 
    for topic in ["origin_db_change_stream_event","detect_origin_db_change_stream_event",
                    "vul_origin_db_change_stream_event","baseline_origin_db_change_stream_event"]:
        exec_ssh_cmd_withresult(kafka_ip, '''{kafka_path}/bin/kafka-configs.sh --zookeeper {zkconnect} --topic {topic_name} --describe '''.format(kafka_path=kafka_path,zkconnect=zkconnect,topic_name=topic))
        
        
if __name__ == "__main__":
    init_datasync_config()