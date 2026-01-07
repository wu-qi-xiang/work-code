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


def config_hq_topic():
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

    _create_topic_cmd = '''{kafka_path}/bin/kafka-topics.sh --create --zookeeper {zkconnect} --replication-factor {rep_factor} --topic $topic_name --partitions $partition_num --config retention.ms=108000000 '''
    _create_topic_cmd = _create_topic_cmd.format(kafka_path=kafka_path,zkconnect=zkconnect,rep_factor=rep_factor)

    print("\n\n\n######创建业务库change stream topic######") 
    for topic in ["origin_db_change_stream_event","detect_origin_db_change_stream_event",
                    "vul_origin_db_change_stream_event","baseline_origin_db_change_stream_event"]:
        if topic not in exists_topics:
            exec_ssh_cmd_withresult(kafka_ip, _create_topic_cmd.replace("$topic_name",topic).replace("$partition_num",str(partition_num)))
        else:
            exec_ssh_cmd_withresult(kafka_ip, '''{kafka_path}/bin/kafka-configs.sh --alter --zookeeper {zkconnect} --entity-type topics --entity-name {topic_name} --add-config 'retention.ms=108000000' '''.format(kafka_path=kafka_path,zkconnect=zkconnect,topic_name=topic))
            exec_ssh_cmd_withresult(kafka_ip, '''{kafka_path}/bin/kafka-topics.sh --alter --zookeeper {zkconnect}  --topic {topic_name} --partitions 6 '''.format(kafka_path=kafka_path,zkconnect=zkconnect,topic_name=topic))
         
    print("\n\n\n######获取业务库topic属性######") 
    for topic in ["origin_db_change_stream_event","detect_origin_db_change_stream_event",
                    "vul_origin_db_change_stream_event","baseline_origin_db_change_stream_event"]:
        exec_ssh_cmd_withresult(kafka_ip, '''{kafka_path}/bin/kafka-configs.sh --zookeeper {zkconnect} --topic {topic_name} --describe '''.format(kafka_path=kafka_path,zkconnect=zkconnect,topic_name=topic))
    
    print("\n\n\n######创建标准库change stream topic######") 
    for topic in ["change_stream_event_asset","change_stream_event_detect",
                    "change_stream_event_vul","change_stream_event_baseline"]:
        if topic not in exists_topics: 
            exec_ssh_cmd_withresult(kafka_ip, _create_topic_cmd.replace("$topic_name",topic).replace("$partition_num",str(partition_num)))
        else:
            exec_ssh_cmd_withresult(kafka_ip, '''{kafka_path}/bin/kafka-configs.sh --alter --zookeeper {zkconnect} --entity-type topics --entity-name {topic_name} --add-config 'retention.ms=36000000' '''.format(kafka_path=kafka_path,zkconnect=zkconnect,topic_name=topic))
            exec_ssh_cmd_withresult(kafka_ip, '''{kafka_path}/bin/kafka-topics.sh --alter --zookeeper {zkconnect}  --topic {topic_name} --partitions 6 '''.format(kafka_path=kafka_path,zkconnect=zkconnect,topic_name=topic))


def ensure_hqdb_created(java_config): 
    mongos_ips = get_service_ips("db_mongo_java")
    mongo_ip = mongos_ips[0]
    
    pbeconfig = java_config["base"]["pbeconfig"]
    pbepwd,pbesalt = pbeconfig[:16],pbeconfig[16:]
    mongo_pwd = decrypt_string(pbepwd,pbesalt,java_config["mongodb"]["password"])

    _cmd = '''/usr/local/sbin/mongo -u qingteng -p $mongo_pwd --authenticationDatabase admin --eval "db.getSiblingDB('wisteria_standard').standard_init.insert({'name':'init'});" '''
    exec_ssh_cmd(mongo_ip, _cmd.replace("$mongo_pwd", mongo_pwd), _cmd)

    _cmd = '''/usr/local/sbin/mongo -u qingteng -p $mongo_pwd --authenticationDatabase admin --eval "db.getSiblingDB('wisteria_standard').createCollection('$collection');" '''
    for collection in ["asset_account_group","asset_account_key","asset_account","asset_app",
        "asset_bootitem_linux","asset_bootitem_win","asset_dbinfo","asset_disk","asset_hardware",
        "asset_domain_login_win","asset_domain_servers_win","asset_env","asset_host","asset_jar_pkg",
        "asset_kernel_module","asset_pkg","asset_port","asset_process","asset_root_certs",
        "asset_scheduled_task","asset_trust_certs","asset_web_app","asset_web_frame","asset_web_server",
        "asset_web_site","asset_web_site_httpd_nginx","asset_web_site_java","asset_web_site_iis_win",
        "asset_win_registry","baseline_check_result","vul_common","vul_fix_history","vul_patch_linux",
        "vul_patch_business_impact","vul_patch_win","vul_poc","vul_weak_password","detect_abnormal_login",
        "detect_backdoor","detect_bounce_shell","detect_honeypot","detect_local_rights",
        "detect_process_record","detect_shelllog","detect_virus","detect_webcommand","detect_webshell",
        "detect_brutecrack","detect_mem_backdoor","detect_mem_backdoor_history","detect_file_integrity",
        "detect_file_integrity_job_result"]:
        exec_ssh_cmd(mongo_ip, _cmd.replace("$mongo_pwd", mongo_pwd).replace("$collection",collection), _cmd.replace("$collection",collection))


def get_current_java_config():
    print "copy the current config files from Java Server...\n"
    java_ips = get_service_ips("java")

    java_config_directory = "/data/app/titan-config/java.json"
    scp_from_remote(java_config_directory, java_ips[0], ScriptPath + "/java.json")
    # load the current configuration
    java_config = json.load(file(ScriptPath + "/java.json"))
    return java_config

def init_hqkey_in_java_json():
    java_ips = set()

    for srv_name in ["java","java_connect-dh","java_connect-agent","java_connect-selector","java_connect-sh","java_scan-srv"]:
        java_ips.update(get_service_ips(srv_name))

    hq_key = randomString(30).upper()
    _cmd = '''sed -i -c -r '/hq_node_secret_key/s/:[^,]+/: "{hq_key}"/' /data/app/titan-config/java.json '''.format(hq_key=hq_key)

    for java_ip in java_ips:
        exec_ssh_cmd(java_ip, _cmd)

def init_hq_config():
    java_config = get_current_java_config()
    if java_config["app"]["wisteria"].get("hq_node_secret_key", "") == "":
        init_hqkey_in_java_json()

    # restart java
    print("Now restart all java service")
    restart_servers = ",".join(ALL_NEED_RESTART_SERVICE)
    restart_cmd = "python {script_path} --restart {servers}".format(script_path=TITAN_SYSYTEM_PY,servers=restart_servers)
    exec_ssh_cmd("", restart_cmd)

    config_hq_topic()
    ensure_hqdb_created(java_config)

ScriptPath = os.path.split(os.path.realpath(sys.argv[0]))[0]

if __name__ == "__main__":
    init_hq_config()
