import imp
import sys
import re
import jenkins
import xml.etree.ElementTree as ET

def get_node(pwd):
    username = 'xiang.wu01'
    password = pwd
    server = jenkins.Jenkins('https://jenkins.qingteng.cn/', username, password)
    nodes = server.get_nodes()
    # 获取jenkins的job信息
    #jobs = server.get_jobs()
    # for i in range(0, len(jobs)):
    #     if jobs[i]['name'] == 'titan-all-standalone':
    #         job_name = jobs[i]['name']
    #         job_config = server.get_job_config(job_name)
    #         job_info = server.get_job_info(job_name)
    #         server.job
    #         print(job_config)
    #         print("---------------")
    #         print(job_info)
    list = [] 
    for count in range(1, len(nodes)):
        node_name = nodes[count]['name']
        if node_name == 'master':
            continue
        else:
            node_label,node_ip = get_node_label_and_ip(server,node_name)
            node_info = server.get_node_info(node_name)
            node_status = node_info['offline']
            try:
                node_os = node_info['monitorData']['hudson.node_monitors.ArchitectureMonitor']
            except:
                node_os = 'NA'
            word = ("%s------%s------%s------%s------%s------%s"%(count,node_name,node_label,node_ip,node_os,node_status))
            list.append(word)
            # 按照字符串的末尾5个字符排序
            l = sorted(list, key=sort_str)
    for i in l:
        print(i)

# 按照字符串的末尾5个字符排序
def sort_str(word):
    return word[-5:]


def get_node_label_and_ip(server, node_name):
    try:
        node_config = server.get_node_config(node_name)
    except:
        print('get node config fail')
    for i in range(0,2):
        f = open('D:/node_config.xml', 'w')
        f.write(node_config)
        f.write('\n')
        f.close
    # 操作xml文件
    text = open('D:/node_config.xml').read()
    text = re.sub(u"[\x00-\x08\x0b-\x0e-\x1f]+",u"",text)
    root = ET.fromstring(text)
    try:
        node_label = root.find('label').text
    except:
        node_label = "NA"

    try:
        for launcher in root.findall('launcher'):
            host = launcher.find('host')
            node_ip = host.text
    except:
        node_ip = 'NA'
    return node_label,node_ip

if __name__ == '__main__':
    get_node('')

    