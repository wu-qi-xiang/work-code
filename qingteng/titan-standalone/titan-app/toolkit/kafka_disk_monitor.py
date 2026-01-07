#!/usr/bin/env python
# -*- coding:utf-8 -*-
# Aluther: dlh
# desc: 此脚本为kafka磁盘水位线监控，使磁盘始终处于安全水位线以内。

import json
import sys
import os
import time
import heapq
import datetime

# 定义kafka所在磁盘的磁盘百分比安全线
''' 按照以下2个参数配置，kafka节点达到90% 开始清理，直到所有的数据节点下降到85%时停止清理,对数据量大小前5的topic进行清理,最低保留时间为12h '''
disk_clean_threshold = 90
disk_safe_threshold = 85
'''移除特定的topic，移除的topic将不再进行任何处理，默认值为None，如果需要请填入，以逗号隔开，例如：remove_topic_name = 'topic_name1,topic_name2' '''
remove_topic_name = None
'''对选中需要清理的topic进行计算，当选中的topic达到了总数据量大小的0.5(默认)，才开始清理，最大值为1(选中所有的topic) '''
top_max_topic_occupancy_percent = 0.5
'''对清理的topic最低保障时间，单位为h,默认为最低时间36小时 '''
min_save_time = 36
''' 当kafka集群最大磁盘占比小于等于delete_retention_ms_disk_percent且已经设置了过期时间的topic，
是否清除其设置且和server.properties配置保持一致，默认False，需要清除请修改成True '''
delete_retention_ms = False
delete_retention_ms_disk_percent = 40
'''kafka实际占用磁盘大小百分比，当kafka集群达到水位线(disk_clean_threshold)之后但是实际磁盘占比低于kafka_size_disk_percent值时，
kafka集群不再清理数据，如果需要关闭请将check_kafka_size_disk_occupancy_percent设置成False，默认为True。'''
check_kafka_size_disk_occupancy_percent = True
kafka_size_disk_percent = 0.4
''' kafka_disk_monitor.py 进程运行产生的logs保留天数'''
kafka_disk_monitor_logs_save_time = 7
'''ssh的默认端口，如有改变请修改成实际端口号'''
ssh_port = 22

kafka_zk_conf_path = "/data/app/www/titan-web/config_scripts/ip.json"
kafka_path = '/usr/local/qingteng/kafka'
kafka_ip = ''
zookeeper_ip = ''
kafka_cluster_ips = ''
delete_retention_ms_execute = 0

with open(kafka_zk_conf_path, 'r') as f:
    json_dict = json.load(f)
zookeeper_ip = json_dict['java_zookeeper'].encode('utf-8')
if zookeeper_ip == '':
    zookeeper_ip = '127.0.0.1'
print("zk:"+zookeeper_ip,type(zookeeper_ip))

kafka_ip = json_dict['java_kafka'].encode('utf-8')
print(kafka_ip,"======",type(kafka_ip))
if kafka_ip == '':
    kafka_ip == '127.0.0.1'
kafka_cluster_ips = json_dict['java_kafka_cluster'].encode('utf-8').split(',')

print(kafka_cluster_ips,type(kafka_cluster_ips),len(kafka_cluster_ips))
print(type(kafka_cluster_ips))

def get_kafka_boolean_disk(kafka_ip,kafka_cluster_ips):
    kafka_disk_status = False
    kafka_disk_percent = []
    list_kafka_occupancy_percent = []
    if kafka_cluster_ips == ['']:
        print(11111)
        kafka_shell = 'ssh -p %s root@%s "df -hl /data|tail -1"' % (ssh_port, kafka_ip)
        kafka_disk_percent.append(int(os.popen(kafka_shell).read().split()[4].strip('%')))
        print(kafka_disk_percent, "2222222")
    else:
        for ip in kafka_cluster_ips:
            print("ip:", ip)
            kafka_shell = 'ssh -p %s root@%s "df -hl /data|tail -1"' % (ssh_port,ip)
            kafka_disk_percent.append(int(os.popen(kafka_shell).read().split()[4].strip('%')))
        print(kafka_disk_percent,"@@@@@@@@")
    if min(kafka_disk_percent) >= disk_clean_threshold:
        if check_kafka_size_disk_occupancy_percent:
            if kafka_cluster_ips == ['']:
                kafka_size_occupancy_total_shell = 'ssh -p %s root@%s "du -shc /data/kafka-data/|tail -1;df -hl /data|tail -1"' % (ssh_port,kafka_ip)
                kafka_size_occupancy_percent = os.popen(kafka_size_occupancy_total_shell).read()
                kafka_size_occupancy_total = int(kafka_size_occupancy_percent.split('\t')[0].strip('G'))
                disk_total = int(kafka_size_occupancy_percent.split('\n')[1].split()[1].strip('G'))
                kafka_actual_occupancy_percent = round(float(kafka_size_occupancy_total)/disk_total,2)
                if kafka_actual_occupancy_percent <= kafka_size_disk_percent:
                    print("/data directory disk usage greater than %d%% ,but kafka actual size occupancy %s%% percent less than %s%% No modification" % (disk_clean_threshold, kafka_actual_occupancy_percent*100, kafka_size_disk_percent*100))
                    return kafka_disk_status, max(kafka_disk_percent)
                else:
                    print("/data directory disk usage greater than %d%% and kafka actual size occupancy %s%% " % (disk_clean_threshold, kafka_actual_occupancy_percent*100))
                    kafka_disk_status = True
            else:
                for ip in kafka_cluster_ips:
                    kafka_size_occupancy_total_shell = 'ssh -p %s root@%s "du -shc /data/kafka-data/|tail -1;df -hl /data|tail -1"' % (ssh_port, ip)
                    kafka_size_occupancy_percent = os.popen(kafka_size_occupancy_total_shell).read()
                    kafka_size_occupancy_total = int(kafka_size_occupancy_percent.split('\t')[0].strip('G'))
                    disk_total = int(kafka_size_occupancy_percent.split('\n')[1].split()[1].strip('G'))
                    kafka_actual_occupancy_percent = round(float(kafka_size_occupancy_total) / disk_total, 2)
                    list_kafka_occupancy_percent.append(kafka_actual_occupancy_percent)
                if max(list_kafka_occupancy_percent) <= kafka_size_disk_percent:
                    print("/data directory disk usage greater than %d%% ,but kafka actual size occupancy %s percent less than %s no modification" % (disk_clean_threshold, max(list_kafka_occupancy_percent), kafka_size_disk_percent))
                    return kafka_disk_status, max(kafka_disk_percent)
                else:
                    print("/data directory disk usage greater than %d%% and kafka actual size occupancy percent greater than %s" % (kafka_size_disk_percent, disk_clean_threshold))
                    kafka_disk_status = True
        else:
            print(min(kafka_disk_percent), "++++++++")
            print("kakfa disk usage greater than %d%% " % disk_clean_threshold)
            kafka_disk_status = True
    if max(kafka_disk_percent) <= disk_safe_threshold:
        print("kakfa disk usage less than disk safe threshold %d%%" % disk_safe_threshold)
    else:
        print("kakfa disk usage more than disk safe threshold %d%%" % disk_safe_threshold)
        kafka_disk_status = True
    return kafka_disk_status, max(kafka_disk_percent)

def get_topic_list():
    zk_topic_shell = 'ssh -p %s root@%s "/usr/local/qingteng/zookeeper/bin/zkCli.sh -server 127.0.0.1:2181 ls /brokers/topics|tail -2|head -1"' % (ssh_port, zookeeper_ip)
    topic_shell_result = os.popen(zk_topic_shell).read().strip('\n').strip(']').strip('[').strip().split(',')
    topic_list = [topic.strip() for topic in topic_shell_result]
    topic_list.remove('__consumer_offsets')
    if remove_topic_name != None:
        for remove_topic in remove_topic_name.split(','):
            print("remove topic is %s" % remove_topic)
            topic_list.remove(remove_topic)
    return topic_list

def get_topic_data_size_name():
    topic_size_dict = {}
    topic_top_size_name = []
    clean_top_max_topic = 2
    global delete_retention_ms_execute
    topic_list = get_topic_list()
    if get_kafka_boolean_disk(kafka_ip, kafka_cluster_ips)[0]:
        print(topic_list, type(topic_list), len(topic_list))
        for topic in topic_list:
            topic_size_total = 0
            kafka_topic_shell = 'ssh -p %s root@%s "cd %s;bin/kafka-log-dirs.sh  --bootstrap-server %s:9092  --describe  --topic-list %s --command-config config/consumer.properties|tail -1"' % (
                ssh_port, kafka_ip, kafka_path, kafka_ip, topic)
            kafka_topic_shell_result = os.popen(kafka_topic_shell).read().strip('\n')
            topic_dict = json.loads(kafka_topic_shell_result)
            for json_dict in topic_dict['brokers']:
                for partitions_dict in json_dict['logDirs']:
                    for data_size in partitions_dict['partitions']:
                        topic_size_total += data_size['size']
                topic_size_dict[topic] = topic_size_total
        all_topic_size_total = sum(topic_size_dict.values())
        print("all_topic_size_total:", all_topic_size_total)
        while True:
            for num in range(clean_top_max_topic):
                sum_select_size = 0
                topic_top_size_name = heapq.nlargest(clean_top_max_topic, topic_size_dict, key=topic_size_dict.get)
                for topics in topic_top_size_name:
                    sum_select_size += topic_size_dict.get(topics)
                select_topic_occupancy_percent = round(float(sum_select_size) / all_topic_size_total, 2)
                print("选中的topic：%s,length:%d,占比%s%%" % (topic_top_size_name, len(topic_top_size_name), (select_topic_occupancy_percent * 100)))
                if select_topic_occupancy_percent >= top_max_topic_occupancy_percent:
                    print("selected topic size is more than %s%%" % (top_max_topic_occupancy_percent * 100))
                    print("sum_select_size:", sum_select_size)
                    return topic_top_size_name
                else:
                    print("selected topic size is less than %s%%" % (top_max_topic_occupancy_percent * 100))
                    clean_top_max_topic += 2
    return topic_top_size_name

def clean_topic_max_top_name():
    ##获取当前的topic默认保留时长
    kafka_save_time_shell = 'ssh -p %s root@%s "cat %s/config/server.properties|grep -w log.retention.hours|head -1|cut -d"=" -f2"' % (ssh_port, kafka_ip, kafka_path)
    kafka_save_time = int(os.popen(kafka_save_time_shell).read().strip('\n'))
    if kafka_save_time < min_save_time:
        print("集群保留时间低于或等于最低保障时间%dh,不再清理，如需继续清理，请降低最低保障时间设置(慎重！)" % min_save_time)
        return
    else:
        while True:
            if get_kafka_boolean_disk(kafka_ip, kafka_cluster_ips)[0]:
                executions_count = 0
                clean_topic_name = get_topic_data_size_name()
                print("max topic size list: %s,length:%s" % (clean_topic_name, len(clean_topic_name)))
                if len(clean_topic_name) == 0:
                    print("kafka disk percent is healthy")
                    return
                for topic_name in clean_topic_name:
                    executions_count += 1
                    topic_name_save_time_shell = 'ssh -p %s root@%s "%s/bin/kafka-topics.sh --zookeeper %s:2181 --topic %s --describe|head -1|cut -d":" -f6"' % (ssh_port, kafka_ip, kafka_path,zookeeper_ip, topic_name)
                    topic_name_save_time_result = os.popen(topic_name_save_time_shell).read().strip('\n').strip()
                    if 'retention.ms' in topic_name_save_time_result:
                        topic_name_save_time = int(topic_name_save_time_result.split('retention.ms')[1].strip('=').split(',')[0])
                        decrease_topic_time = topic_name_save_time - 1000 * 3600
                        if decrease_topic_time < min_save_time*1000*3600:
                            print("topic:%s is min save time no deleted" % topic_name)
                            continue
                        kafka_save_time_decrease_shell = 'ssh -p %s root@%s "%s/bin/kafka-configs.sh --zookeeper %s:2181 --alter --entity-name %s --entity-type topics --add-config retention.ms=%d"' % (ssh_port, kafka_ip, kafka_path,zookeeper_ip, topic_name, decrease_topic_time)
                        kafka_delete_topic_shell = 'ssh -p %s root@%s "%s/bin/kafka-topics.sh --zookeeper %s:2181 --alter --topic %s --config cleanup.policy=delete"' % (ssh_port,kafka_ip,kafka_path,zookeeper_ip,topic_name)
                        os.system(kafka_save_time_decrease_shell)
                        os.system(kafka_delete_topic_shell)
                        print("%s is set time %s" % (topic_name, decrease_topic_time))
                        if executions_count == len(clean_topic_name):
                            print("wait time 360s")
                            time.sleep(360)
                    else:
                        print(22222,"xxxxxxxxxx")
                        decrease_topic_time = kafka_save_time*1000*3600 - 1*1000*3600
                        if decrease_topic_time < min_save_time*1000*3600:
                            print("topic:%s is min save time not deleted" %topic_name)
                            continue
                        kafka_save_time_decrease_shell = 'ssh -p %s root@%s "%s/bin/kafka-configs.sh --zookeeper %s:2181 --alter --entity-name %s --entity-type topics --add-config retention.ms=%d"' % (ssh_port, kafka_ip, kafka_path,zookeeper_ip, topic_name, decrease_topic_time)
                        kafka_delete_topic_shell = 'ssh -p %s root@%s "%s/bin/kafka-topics.sh --zookeeper %s:2181 --alter --topic %s --config cleanup.policy=delete"' % (ssh_port, kafka_ip, kafka_path, zookeeper_ip, topic_name)
                        os.system(kafka_save_time_decrease_shell)
                        os.system(kafka_delete_topic_shell)
                        print("%s is set times %s" % (topic_name, decrease_topic_time))
                        if executions_count == len(clean_topic_name):
                            print("wait times 360s")
                            time.sleep(360)
            else:
                current_disk_percent = get_kafka_boolean_disk(kafka_ip, kafka_cluster_ips)[1]
                print(current_disk_percent)
                if delete_retention_ms and current_disk_percent <= delete_retention_ms_disk_percent:
                    print("start delete topic config")
                    for topics in get_topic_list():
                        print("topic name is :%s" % topics)
                        topic_get_retention_ms_shell = 'ssh -p %s root@%s "%s/bin/kafka-topics.sh --zookeeper %s:2181 --topic %s --describe|head -1|cut -d":" -f6"' % (ssh_port, kafka_ip, kafka_path, zookeeper_ip, topics)
                        topic_get_retention_ms_result = os.popen(topic_get_retention_ms_shell).read().strip('\n').strip()
                        print(topic_get_retention_ms_result, "$$$$$$$")
                        print(topic_get_retention_ms_result.split('=')[0], "#######")
                        if 'retention.ms' in topic_get_retention_ms_result:
                            if int(topic_get_retention_ms_result.split('retention.ms')[1].strip('=').split(',')[0]) <= min_save_time * 3600 * 1000:
                                print("topic :%s config retention.ms set is less than min save time %sh not delete" % (topics, min_save_time))
                                continue
                            topic_delete_retention_ms_shell = 'ssh -p %s root@%s "%s/bin/kafka-configs.sh --zookeeper %s:2181 --entity-type topics --entity-name %s --alter --delete-config retention.ms"' % (ssh_port, kafka_ip, kafka_path, zookeeper_ip, topics)
                            print(topic_delete_retention_ms_shell, "**********")
                            topic_delete_retention_ms_result = os.system(topic_delete_retention_ms_shell)
                            if topic_delete_retention_ms_result == 0:
                                print("topic:%s delete retention.ms config successful" % topics)
                            else:
                                print("topic:%s delete retention.ms config failed" % topics)
                    print("all topic retention.ms config is deleted if again runing kafka_disk_monitor set delete_retention_ms=False")
                    sys.exit()
                break

def main():
    while True:
        clean_topic_max_top_name()
        current_time = int(datetime.datetime.now().strftime('%H'))
        if current_time == 2:
            clean_logs_shell = 'find /data/titan-logs/monitor/kafka -mtime +%d -name "*" -exec rm -rf {} \;' % kafka_disk_monitor_logs_save_time
            clean_logs_result = os.system(clean_logs_shell)
            if clean_logs_result == 0:
                print("clean more than %d logs is successfull" % kafka_disk_monitor_logs_save_time)
            else:
                print("clean logs is failed")
        print("wait 10min")
        time.sleep(600)

if __name__ == '__main__':
    main()
