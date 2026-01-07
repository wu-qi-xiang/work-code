#! /usr/bin/env python
# -*- coding: utf-8 -*-

import os
import sys
reload(sys)
sys.setdefaultencoding('utf8')
import json
import re
import commands
from config_helper import exec_ssh_cmd,exec_ssh_cmd_withresult,get_service_ips,get_cluster_ips

IP_REG = r"^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$"
ipjson = None
CLUSTER = False

jvm_config_map = {
    "one": {
        "wisteria": { "-Xmx":"5G", "-Xms":"2G", "-Dkb.receiver.max_threads=":"5","-Dkb.receiver.prefetch=":"1","-Dcommon_event_consumers=":"8"},
        "detect-srv": { "-Xmx":"2G" },
        "scan-srv": { "-Xmx":"512M" },
        "ms-srv": { "-Xmx": "12G","-Xms":"8G"},
        "event-srv": { "-Xmx": "2G","-Xss":"512k"},
        "job-srv": { "-Xmx":"1536M", "-Xms":"512M" },
        "user-srv": { "-Xmx":"512M", "-Xms":"256M" },
        "connect-agent": { "-Xmx":"1G", "-Xms":"512M" },
        "connect-dh": { "-Xmx":"1G", "-Xms":"512M" },
        "connect-sh": { "-Xmx":"1G", "-Xms":"512M" }
    }
}

other_config_map = {
    "one":  [
        '''sed -i -r '/boss_thread_num/s/:[^,]+/: 2/' /data/app/titan-config/sh.json ''',
        '''sed -i -r '/worker_thread_num/s/:[^,]+/: 8/' /data/app/titan-config/sh.json ''',
        '''sed -i -c -r '/tav_consumer_size/s/:[^,]+/: 3/' /data/app/titan-config/java.json ''',
        '''grep 'Xmx1536M -Xms1G' /usr/local/qingteng/kafka/bin/kafka-server-start.sh || (sed -i 's/export KAFKA_HEAP_OPTS=.*$/export KAFKA_HEAP_OPTS="-Xmx1536M -Xms1G"/' /usr/local/qingteng/kafka/bin/kafka-server-start.sh && service kafkad stop && sleep 15 && service kafkad restart && sleep 20)'''
    ]
}

def config_other(ip, mode):
    if get_service_ips("java_ms-srv") and ip in get_service_ips("java_ms-srv"):
        return
    other_config_cmds = other_config_map.get(mode, None)
    if not other_config_cmds:
        print("no need change other config")
        return
    
    for _cmd in other_config_cmds:
        exec_ssh_cmd(ip, _cmd)

def config_jvm_opt(ip, mode):
    scan_host = get_service_ips("java_scan-srv")
    ms_host = get_service_ips("java_ms-srv")
    if scan_host:
        pass
    else :
        scan_host = "127.0.0.1"
    jvm_config = jvm_config_map.get(mode, None)
    if not jvm_config:
        print("no need change jvm config")
        return

    _sed_delete_cmd = r's/({arg})[^ "]+[ ]?//g'
    _sed_append_cmd = r'/^JAVA_OPTS/s/ ?"$/ {arg}"/'
    
    for srv_name, configs in jvm_config.items():
        if srv_name == "scan-srv" and scan_host == "127.0.0.1" :
            continue
        if srv_name == "ms-srv" and ms_host == "127.0.0.1":
            continue
        if srv_name == "wisteria":
            if ip in get_service_ips("java"):
                pass
            else:
                continue
        elif ip in get_service_ips("java_"+srv_name):
            pass
        else:
            continue
        conf_path = "/data/app/titan-{srv_name}/{srv_name}.conf".format(srv_name=srv_name)
        delete_args = []
        append_args = []
        for key,value in configs.items():
            if key == "conf_path":
                conf_path = value
                continue

            delete_args.append(key)
            append_args.append(key + value)
        
        delete_cmd = _sed_delete_cmd.replace("{arg}", "|".join(delete_args))
        append_cmd = _sed_append_cmd.replace("{arg}", " ".join(append_args))
        
        # command like: sed -i -r 's/(-Xmx|-Xms)[^ "]+[ ]?//g;/^JAVA_OPTS/s/ ?"$/ -Xmx5G -Xms2G"/' /data/app/titan-wisteria/wisteria.conf
        sed_cmd = "sed -i -r '{cmd}' {conf_path} ".format(cmd=delete_cmd+";"+append_cmd, conf_path=conf_path) 
        
        exec_ssh_cmd(ip, sed_cmd)

def trans_ipkey_srv(ipjson_key):
    if ipjson_key == "java":
        return "wisteria"
    elif ipjson_key.startswith("java_"):
        return ipjson_key[5:]
    else:
        return ipjson_key

def collect_ip_servers():
    global ipjson  
    ip_servers = {} # {"172.16.6.63":"wisteria,gateway....,connect_agent"}
    for srv_name, ipstr in ipjson.items():
        if ipstr == '' or ipstr == '127.0.0.1':
            continue
        if srv_name in ["version", "vip"]:
            continue

        if srv_name.endswith("_cluster"):
            srv_name = srv_name[:-8]
        srv_name = trans_ipkey_srv(srv_name)

        ip_ports = ipstr.split(",")
        for ip_port in ip_ports:
            ip = ip_port.split(':')[0]
            if not re.match(IP_REG,ip):
                continue
            ip_servers.setdefault(ip, set())
            ip_servers[ip].add(srv_name)

    return ip_servers

# check which ip is single(three cluster is also single, because all service in one)
# this function ensure only change single deploy host
def check_single_deploy_hosts():
    ip_servers = collect_ip_servers()
    ip_singles = set()
    ip_singles_srv = set()  

    for ip, servers in ip_servers.items():
        # these service in one machine, regard as single
        #if servers.issuperset(set(["wisteria","job-srv","connect-agent","connect-dh","connect-sh","kafka","erl_rabbitmq","ms-srv"])):
        if servers.issuperset(set(["wisteria","job-srv","connect-agent","connect-dh","connect-sh","kafka","erl_rabbitmq"])):
            ip_singles.add(ip)
        if servers.issuperset(set(["event-srv","ms-srv"])):
            ip_singles.add(ip)
    return ip_singles

# get deploy mode for config connect topic
def get_deploy_mode():
    global ipjson
    php_hosts = get_service_ips("php_inner_api")
    java_hosts = get_service_ips("java")
    connect_hosts = get_service_ips("java_connect-agent")
    db_hosts = get_service_ips("db_mongo_java")

    vip = ipjson.get("vip",'')
    if vip == '' or vip == '127.0.0.1':
        CLUSTER = False
    else:
        CLUSTER = True

    mode = "one"
    if CLUSTER :
        if len(php_hosts) == 3 and set(php_hosts) == set(java_hosts) and set(php_hosts) == set(connect_hosts):
            mode = "cluster_3"
        else:
            mode = "cluster_other"
    else:
        if len(php_hosts) == 1 and len(java_hosts) == 1 and len(connect_hosts) == 1:
            if len(set([php_hosts[0], java_hosts[0], connect_hosts[0] ])) == 3:
                if len(db_hosts) == 3:
                    mode = "six"
                elif len(db_hosts) == 1:
                    mode = "four"
            elif len(set([php_hosts[0], java_hosts[0], connect_hosts[0] ])) == 1:
                mode = "one"
    return mode

def config_connect_topic(mode):
    if mode is None:
        return

    connect_num =  len(get_service_ips("java_connect-dh"))
    wisteria_num =  len(get_service_ips("java"))
    detect_num =  len(get_service_ips("java_detect-srv"))

    custer_partition_nums = 32 if (8 * connect_num) > 32 else 8 * connect_num
    tc_incoming_packet_nums = 16 if (4 * connect_num) > 16 else 4 * connect_num
    tc_frame_packet_nums = 16 if (4 * connect_num) > 16 else 4 * connect_num

    tc_outgoing_nums = 8 if (2 * connect_num) > 8 else 2 * connect_num

    tc_common_event_nums = 12 if (3 * wisteria_num) > 12 else 3 * wisteria_num
    tc_detect_event_nums = 12 if (3 * detect_num) > 12 else 3 * detect_num

    topic_config_map = {
        "one": {
            "tc_incoming_packet":{"partitions":4, "hours":12},
            "tc_frame_packet":{"partitions":4, "hours":12},
            "tc_outgoing_request":{"partitions":4, "hours":12},
            "tc_outgoing_job":{"partitions":4, "hours":12},
            "tc_event_bash_cmd":{"partitions":3, "hours":24},
            "tc_event_virus":{"partitions":3, "hours":24},
            "tc_common_event":{"partitions":3, "hours":24}
        },
        "four|six|cluster_3": {
            "tc_incoming_packet":{"partitions":8, "hours":12},
            "tc_frame_packet":{"partitions":8, "hours":12},
            "tc_outgoing_request":{"partitions":4, "hours":12},
            "tc_outgoing_job":{"partitions":4, "hours":12},
            "tc_event_bash_cmd":{"partitions":3, "hours":24},
            "tc_event_virus":{"partitions":3, "hours":24},
            "tc_common_event":{"partitions":3, "hours":24}
        },
        "cluster_other": {
            "tc_incoming_packet":{"partitions": tc_incoming_packet_nums, "hours":12},
            "tc_frame_packet":{"partitions": tc_frame_packet_nums, "hours":12},
            "tc_outgoing_request":{"partitions": tc_outgoing_nums, "hours":12},
            "tc_outgoing_job":{"partitions": tc_outgoing_nums, "hours":12},
            "tc_event_bash_cmd":{"partitions":tc_detect_event_nums, "hours":24},
            "tc_event_virus":{"partitions":tc_detect_event_nums, "hours":24},
            "tc_common_event":{"partitions":tc_common_event_nums, "hours":24}
        }
    }

    if mode == "six" or mode == "four" or mode == "cluster_3":
        connect_topics_conf = topic_config_map["four|six|cluster_3"]
    elif mode == "one":
        connect_topics_conf = topic_config_map["one"]
    elif mode == "cluster_other":
        connect_topics_conf = topic_config_map["cluster_other"]
    else:
        return 
    

    kafka_ips = get_service_ips("java_kafka")
    kafka_count = len(kafka_ips) 
    kafka_ip = kafka_ips[0]
    one_hour_ms = 60 * 60 * 1000
    rep_factor = 3 if len(kafka_ips) >= 3 else 1   # default.replication.factor  
    zkconnect = "127.0.0.1:2181"

    # get kafka properties
    server_properties = exec_ssh_cmd_withresult(kafka_ip,'''cat /usr/local/qingteng/kafka/config/server.properties''')
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

    _create_topic_cmd = '''{kafka_path}/bin/kafka-topics.sh --create --zookeeper {zkconnect} --replication-factor {rep_factor} --topic $topic_name --partitions $partition_num --config retention.ms=$retentionms'''
    _alert_topic_cmd = '''{kafka_path}/bin/kafka-topics.sh --alter --zookeeper {zkconnect} --topic $topic_name --partitions $partition_num --config retention.ms=$retentionms'''
    _alert_topic_retention_cmd = '''{kafka_path}/bin/kafka-topics.sh --alter --zookeeper {zkconnect} --topic $topic_name --config retention.ms=$retentionms'''
    _partitions_cmd = '''{kafka_path}/bin/kafka-topics.sh --zookeeper {zkconnect} --describe --topic $topic_name'''

    _create_topic_cmd = _create_topic_cmd.format(kafka_path=kafka_path,zkconnect=zkconnect,rep_factor=rep_factor)
    _alert_topic_cmd = _alert_topic_cmd.format(kafka_path=kafka_path,zkconnect=zkconnect)
    _partitions_cmd = _partitions_cmd.format(kafka_path=kafka_path,zkconnect=zkconnect)
    _alert_topic_retention_cmd = _alert_topic_retention_cmd.format(kafka_path=kafka_path,zkconnect=zkconnect)

    for topic, conf in connect_topics_conf.items():
        partition_num = conf["partitions"]
        retentionms = one_hour_ms * conf["hours"]
        if topic in exists_topics:
            cur_partitions = None
            cur_retentionms = None

            desc_result = exec_ssh_cmd_withresult(kafka_ip, _partitions_cmd.replace("$topic_name",topic))
            matchObj = re.search(r"PartitionCount:(\d+)",desc_result)
            if matchObj:
                cur_partitions =  int(matchObj.group(1))

            retentionMatchObj = re.search(r"retention.ms=(\d+)",desc_result)
            if retentionMatchObj:
                cur_retentionms =  int(retentionMatchObj.group(1))
                if cur_retentionms and cur_retentionms < retentionms:
                    retentionms = cur_retentionms


            if cur_partitions and cur_partitions >= partition_num:
                print("partitions already config ok, no need change again, only change retention time")
                exec_ssh_cmd_withresult(kafka_ip, _alert_topic_retention_cmd.replace("$topic_name",topic).replace("$retentionms",str(retentionms)))
                continue

            exec_ssh_cmd_withresult(kafka_ip, _alert_topic_cmd.replace("$topic_name",topic).replace("$partition_num",str(partition_num)).replace("$retentionms",str(retentionms)))
        else:
            exec_ssh_cmd_withresult(kafka_ip, _create_topic_cmd.replace("$topic_name",topic).replace("$partition_num",str(partition_num)).replace("$retentionms",str(retentionms)))


def config_rabbitmq_conf(mode):
    if mode is None:
        return

    rabbit_config_map = {
        "one": {
            'vm_memory_high_watermark': '{absolute, "2048MiB"}',
            'vm_memory_high_watermark_paging_ratio': '0.5',
            'disk_free_limit': '5000000000',
            'loopback_users': '\[\]'
        },
        "four|six": {
            'vm_memory_high_watermark': '{absolute, "8192MiB"}',
            'vm_memory_high_watermark_paging_ratio': '0.5',
            'disk_free_limit': '5000000000',
            'loopback_users': '\[\]'
        }
    }

    if mode == "one" or mode == "cluster_3":
        rabbit_conf = rabbit_config_map["one"]
    elif mode == "four" or mode == "six" or mode == "cluster_other":
        rabbit_conf = rabbit_config_map["four|six"]
    else:
        return

    rabbit_ips = get_service_ips("erl_rabbitmq")
    for ip in rabbit_ips:
        exec_ssh_cmd(ip, '''test -f /data/servers/rabbitmq_root/etc/rabbitmq/rabbitmq.config || (echo -e "[\\n  {rabbit, [\\n  ]}\\n]." > /data/servers/rabbitmq_root/etc/rabbitmq/rabbitmq.config && chown rabbitmq:rabbitmq /data/servers/rabbitmq_root/etc/rabbitmq/rabbitmq.config)''')

        old_conf_content = exec_ssh_cmd_withresult(ip, "cat /data/servers/rabbitmq_root/etc/rabbitmq/rabbitmq.config")

        changed = False
        _cmd = '''sed -i -r '/$key,/d; /^[ ]*]}[ ]*$/i\\    {$key, $value},' /data/servers/rabbitmq_root/etc/rabbitmq/rabbitmq.config '''
        for key, value in rabbit_conf.items():
            if re.search(r"" + key + ", " + value, old_conf_content):
                continue

            exec_ssh_cmd(ip, _cmd.replace("$key",key).replace("$value",value))
            changed = True

        if changed:
            # this sed encure format, {key,value} need ',' and last {key,value} line should not have ','.
            exec_ssh_cmd(ip, '''sed -i -r 's/([^\{]*\\{.+\\})$/\\1,/' /data/servers/rabbitmq_root/etc/rabbitmq/rabbitmq.config && sed -i -r '$!N;s/,(\\n[ ]*]})/\\1/;P;D' /data/servers/rabbitmq_root/etc/rabbitmq/rabbitmq.config''')
            exec_ssh_cmd(ip, "service rabbitmq-server restart")


# According to the deployment, config some param
def config_by_deploy():
    global ipjson
    if ipjson is None:
        ipjson = json.load(file("/data/app/www/titan-web/config_scripts/ip.json"))

    mode = get_deploy_mode()
    print("deploy mode is " + mode)
    if mode == "one" or mode == "cluster_3":
        print ("-----------------start------------")
        ip_singles = check_single_deploy_hosts()
        for ip in ip_singles:
            # if single deploy and memory bigger than 32G, no need config
            memory = exec_ssh_cmd_withresult(ip, "grep MemTotal /proc/meminfo | awk '{print $2}' ")
            memory_GB = int(memory)/1000/1000
            print (memory_GB)
            if memory_GB > 32:
                print("config not apply to this machine")
                continue
            print ("---------start config--------")
            config_jvm_opt(ip, "one")
            config_other(ip, "one")
    config_connect_topic(mode)
    config_rabbitmq_conf(mode)

if __name__ == "__main__":
    config_by_deploy()
