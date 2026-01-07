#!/usr/bin/env python2.7
# -*- coding: utf-8 -*-

"""
author: yafei.liu
date:  2019-10-31
email: yafei.liu@qingteng.cn
"""

import json
import os
import sys
import getopt
import commands
import re

reload(sys)
sys.setdefaultencoding('utf-8')


def help():
    print "----------------------------------------------------------"
    print "                   Usage information"
    print "----------------------------------------------------------"
    print ""
    print "./ip-config.py [Args] "
    print "  -n --number=   the number of Servers                    "
    print "     ./ip-config.py -n 2                                  "
    print "     ./ip-config.py -n 3                                  "
    print "     ./ip-config.py -n 4                                  "
    print "     ./ip-config.py -n 5                                  "
    print "     ./ip-config.py -n 6                                  "
    print "     ./ip-config.py -n 7                                  "
    print "----------------------------------------------------------"
    sys.exit(2)


__FILE_ABS_PATH = os.path.dirname(os.path.abspath(__file__))

__IP_TEMPLATE = "ip_template.json"
## One server
__DEFAULT_DOMAIN = "qingteng.cn"

## PHP
__PHP_PRI_IP = ["php_frontend_private",
                "php_backend_private",
                "php_agent_private",
                "php_download_private",
                "php_api_private",
                "php_inner_api",
                "php_worker_ip"]

__PHP_PUB_IP = ["php_frontend_public", "php_backend_public", "php_agent_public", "php_download_public", "php_api_public"]

__PHP_DOMAIN = ["php_frontend_domain",
                "php_backend_domain",
                "php_agent_domain",
                "php_download_domain",
                "php_api_domain",
                "php_inner_api_domain"]

java = None
docker = None
php = None
connect = None
java_mongo_db = None
ms_srv_mongo_db = None
bigdata = None
srv = None
cluster_number = None
number = None
#设置成固定开启状态 测试
ENABLE_MS_SRV = None
ENABLE_EVENT_SRV = None
ENABLE_DOCKER_SCAN = None
ENABLE_BIGDATA = None
ENABLE_THP = None
check_base = None
del_ms_ip = None
add_bigdata = None
DEFAULT_SSH_USER = "root"
DEFAULT_SSH_PORT = 22

#refer to https://unix.stackexchange.com/questions/4770/quoting-in-ssh-host-foo-and-ssh-host-sudo-su-user-c-foo-type-constructs
# use single quote, avoid escape.  single quote for Bourne shell evaluation
# Change ' to '\'' and wrap in single quotes.
# If original starts/ends with a single quote, creates useless
# (but harmless) '' at beginning/end of result.
def single_quote(cmd):
    return "'" + cmd.replace("'","'\\''") + "'" 

def ssh_qt_cmd(ip_addr, cmd, force=True):
    # if user is not root, need sudo
    if DEFAULT_SSH_USER != 'root':
        cmd = '''sudo bash -c ''' + single_quote(cmd)
    if ip_addr in ['127.0.0.1', '']:
        return cmd
    
    if force:
        return '''ssh -q -t -o StrictHostKeyChecking=no -o ConnectTimeout=8 -o LogLevel=Error -p {port} {user}@{ip_addr} {cmd} '''.format(port=DEFAULT_SSH_PORT,user=DEFAULT_SSH_USER,ip_addr=ip_addr,cmd=single_quote(cmd))
    else:
        return '''ssh -q -T -o StrictHostKeyChecking=no -o ConnectTimeout=8 -o LogLevel=Error -p {port} {user}@{ip_addr} {cmd} '''.format(port=DEFAULT_SSH_PORT,user=DEFAULT_SSH_USER,ip_addr=ip_addr,cmd=single_quote(cmd))

def exec_ssh_cmd_withresult(ip_addr, cmd, _cmd='', verbose=False):
    cmd = ssh_qt_cmd(ip_addr, cmd)
    if verbose:
        print("exec_ssh_cmd_withresult:" + (_cmd if _cmd != '' else cmd))
    status, output = commands.getstatusoutput(cmd)
    if status != 0 :
        print("\033[35m[WARN] Failed to execute command: " + (_cmd if _cmd != '' else cmd) + '\033[0m')  #should avoid print password
        print("(%d) %s" % (status, output if output else "-"))
    else:
        if verbose:
            print(output)
        # remove Pseudo-terminal will not be allocated because stdin is not a terminal.
        if output.startswith("Pseudo-terminal will"):
            return re.sub("^Pseudo-terminal will.*\.", "", output).strip()
        else:
            return output.strip()


def use_backup_template():
    """
    Using the backup ip_template.json when the default missing
    :return:
    """
    try:
        global __IP_CONF
        __IP_CONF = json.load(file(__FILE_ABS_PATH + "/.ip_template_bak.json"))

    except Exception as e:
        print str(e)
        exit(1)

try:
    __IP_CONF = json.load(file(__FILE_ABS_PATH + "/" + __IP_TEMPLATE))
#print (__IP_CONF)
except Exception as e:
    print "[WARN] ip_template.json not found, use backup file"
    use_backup_template()

def get_input(key, prompt="", default=""):
    """
    Interacting with users, get ip address or domain from terminal
    :param key: key of dict
    :param prompt: hint
    :param default: default value
    :return: IP address
    """

    if prompt == "":
        prompt = "Input the ip of " + key + "(default {0}) : "

        if "domain" in key:
            prompt = "Input the " + key + "(default {0}) : "

    try:
        ip = raw_input(prompt.format(default)).strip()

        if ip == "":
            if default != "":
                return default
            elif "domain" not in key and "public" not in key:
                return "127.0.0.1"
        return ip
    except Exception as e:
        print str(e)
        exit(1)


def dcoker_scan_option():
    print "Do you want to enable Docker-Scan? default is N"
    v = raw_input("Enter [Y/N]:")
    if v == "y" or v == "Y" or v == "Yes" or v == "YES":
        return True
    else:
        return False

def bigdata_option():
    print "Do you want to enable BigData? default is N"
    v = raw_input("Enter [Y/N]:")
    if v == "y" or v == "Y" or v == "Yes" or v == "YES":
        return True
    else:
        return False

def set_bigdata_info(install_param):
    if ENABLE_BIGDATA or ENABLE_THP:
        if ENABLE_BIGDATA:
            install_param["bigdata"]  = ENABLE_BIGDATA
            logstash_ipstr = get_input2('', "Input the ips of bigdata logstash: ")
            logstash_ips = get_iplist_from_str(logstash_ipstr)
            install_param["BIGDATA_LOGSTASH"] = logstash_ips
            viewer_ipstr = get_input2('', "Input the ips of bigdata viewer: ")
            viewer_ips = get_iplist_from_str(viewer_ipstr)
            install_param["BIGDATA_VIEWER"] = ''.join(viewer_ips)
        elif ENABLE_THP:
            install_param["thp"] = ENABLE_THP
            logstash_ipstr = get_input2('', "Input the ips of bigdata logstash: ")
            logstash_ips = get_iplist_from_str(logstash_ipstr)
            install_param["BIGDATA_LOGSTASH"] = logstash_ips
        else:
            pass
        get_es_info(logstash_ips[0], install_param)


def set_ms_srv_info(install_param):
    install_param["ms-srv"] = ENABLE_MS_SRV
    install_param["event-srv"] = ENABLE_EVENT_SRV
    if ENABLE_MS_SRV:
        if ms_srv_mongo_db is not None:
            if isinstance(ms_srv_mongo_db, list):
                install_param['MONGO_MS_SRV'] = ms_srv_mongo_db
            else:
                install_param['MONGO_MS_SRV'] = [ms_srv_mongo_db]
        else:
            ms_mongo_ip = get_input("MongoDB_MS_SRV", "", __IP_CONF["db_mongo_ms_srv"])
            install_param['MONGO_MS_SRV'] = [ms_mongo_ip]
        if len(install_param['MONGO_MS_SRV']) > 1 :
            ip_pris = install_param['MONGO_MS_SRV']
            mongo_ms_srv_cluster={
                "db_mongo_ms_srv_mongod_cs": ip_pris,
                "db_mongo_ms_srv_mongod_27019": ip_pris,
                "db_mongo_ms_srv_mongod_27020": ip_pris,
                "db_mongo_ms_srv_mongod_27021": ip_pris
            }
            install_param["MONGO_MS_SRV_CLUSTER"] = mongo_ms_srv_cluster
            ms_srv_ip = get_input("JAVA_APP_MS", "", __IP_CONF["java_ms-srv"])
            install_param['JAVA_APP_MS'] = [ms_srv_ip]
            install_param['JAVA_APP_EVENT'] = [ms_srv_ip]
        else:
            install_param['MONGO_MS_SRV'] = [ms_mongo_ip]
            install_param['JAVA_APP_MS'] = [ms_mongo_ip]
            install_param['JAVA_APP_EVENT'] = [ms_mongo_ip]
    elif ENABLE_EVENT_SRV:
        event_srv_ip = get_input("JAVA_APP_EVENT", "", __IP_CONF["java_event-srv"])
        install_param['JAVA_APP_EVENT'] = [event_srv_ip]
    else:
        pass

def set_ms_srv_cluster_info(install_param,ms_mongo_status=False):
    install_param["ms-srv"] = ENABLE_MS_SRV
    install_param["event-srv"] = ENABLE_EVENT_SRV
    if ms_mongo_status :
        if ENABLE_MS_SRV:
            ip_pris,domain,ip_pubs = get_info_of_server("JAVA_APP_MS",server_count=6)
            install_param['JAVA_APP_MS'] = ip_pris
            install_param['JAVA_APP_EVENT'] = ip_pris
            #ip_pris,domain,ip_pubs = get_info_of_server("MONGO_MS_SRV", server_count=6)
            install_param['MONGO_MS_SRV'] = ip_pris
            get_mongo_cluster_detail(install_param,'mongo_ms_srv')
        elif ENABLE_EVENT_SRV:
            ip_pris,domain,ip_pubs = get_info_of_server("JAVA_APP_EVENT",server_count=6)
            install_param['JAVA_APP_EVENT'] = ip_pris
        else:
            pass
    else:
        if ENABLE_MS_SRV:
            ip_pris,domain,ip_pubs = get_info_of_server("JAVA_APP_MS",server_count=3)
            install_param['JAVA_APP_MS'] = ip_pris
            install_param['JAVA_APP_EVENT'] = ip_pris
            install_param['MONGO_MS_SRV'] = ip_pris
            mongo_ms_srv_cluster={
            "db_mongo_ms_srv_mongod_cs": ip_pris,
            "db_mongo_ms_srv_mongod_27019": ip_pris,
            "db_mongo_ms_srv_mongod_27020": ip_pris,
            "db_mongo_ms_srv_mongod_27021": ip_pris
            }
            install_param["MONGO_MS_SRV_CLUSTER"] = mongo_ms_srv_cluster
        elif ENABLE_EVENT_SRV:
            ip_pris,domain,ip_pubs = get_info_of_server("JAVA_APP_EVENT",server_count=3)
            install_param['JAVA_APP_EVENT'] = ip_pris
        else:
            pass
    
def standalone_one():

    global php
    global ENABLE_DOCKER_SCAN
    global ENABLE_BIGDATA
    global ENABLE_THP
    global ENABLE_MS_SRV
    global ENABLE_EVENT_SRV
    global ENABLE_ANTI_VIRUS

    if java is not None:
        domain = ""
        ip_pub = php
        ip_pri = php
    else:
        ip_pri = get_input("private", "Input the private ip of Server (default {0}): ", __IP_CONF["php_frontend_private"])
        domain = get_input("domain", "Input the domain of Server (default {0},if have no,just empty,please not input ip): ", __IP_CONF["php_frontend_domain"])
        ip_pub = get_input("public", "Input the public ip of Server (default {0},if have no,just empty,please not input private ip): ", __IP_CONF["php_frontend_public"])
        
    install_param = {}

    for role in ROLES:
        install_param[role] = [ip_pri]
        if role in ['PHP','CONNECT']:
            install_param[role+'_DOMAIN'] = domain
            install_param[role+'_PUBLIC'] = [ip_pub]        
            
    
    install_param["docker"] = ENABLE_DOCKER_SCAN
    install_param["ms-srv"] = ENABLE_MS_SRV
    install_param["event-srv"] = ENABLE_EVENT_SRV

    set_ms_srv_info(install_param)
    set_bigdata_info(install_param)

    if ENABLE_ANTI_VIRUS:
        install_param['ANTI_VIRUS'] = [ip_pri]

    config_by_installparam(install_param, True)
    
def standalone_four(manual=True):
    """
    Standard V3.0
    :return:
    """
    global java
    global php
    global connect
    global java_mongo_db
    global ms_srv_mongo_db
    global bigdata
    global srv
    global ENABLE_DOCKER_SCAN
    global ENABLE_BIGDATA
    global ENABLE_THP
    global ENABLE_MS_SRV
    global ENABLE_EVENT_SRV
    global ENABLE_ANTI_VIRUS

    install_param = {}

    
    if connect is not None:
        domain = ""
        ip_pub = connect
        ip_pri = connect
    else:
        ip_pri = get_input("connect_private",
                            "Input the private ip of Connect Server (default {0}): ",
                            __IP_CONF["java_connect-agent"])
        domain = get_input("connect_domain",
                            "Input the domain of Connect Server (default {0},if have no,just empty,please not input ip): ",
                            __IP_CONF["java_connect-selector_domain"])
        ip_pub = get_input("connect_public",
                            "Input the public ip of Connect Server (default {0},if have no,just empty,please not input private ip): ",
                            __IP_CONF["java_connect-selector_public"])
        

    install_param['CONNECT'] = [ip_pri]
    install_param['CONNECT_PUBLIC'] = [ip_pub]
    install_param['CONNECT_DOMAIN'] = domain
    install_param['RABBITMQ'] = [ip_pri]
    install_param['REDIS_ERLANG'] = [ip_pri]

    if php is not None:
        domain = ""
        ip_pub = php
        ip_pri = php
    else:
        ip_pri = get_input("php_private",
                            "Input the private ip of PHP Web Server (default {0}): ",
                            __IP_CONF["php_frontend_private"])
        domain = get_input("php_domain",
                            "Input the domain of PHP Web Server (default {0},if have no,just empty,please not input ip): ",
                            __IP_CONF["php_frontend_domain"])
        ip_pub = get_input("php_public",
                            "Input the public ip of PHP Web Server (default {0},if have no,just empty,please not input private ip): ",
                            __IP_CONF["php_frontend_public"])

    install_param['PHP'] = [ip_pri]
    install_param['PHP_PUBLIC'] = [ip_pub]
    install_param['PHP_DOMAIN'] = domain
    install_param['MYSQL'] = [ip_pri]
    install_param['REDIS_PHP'] = [ip_pri]
    install_param['KAFKA'] = [ip_pri]
    install_param['ZOOKEEPER'] = [ip_pri]

    if java is not None:
        ip = java
    else:
        ip = get_input("Java_Server", "", __IP_CONF["java"])
    
    if ENABLE_ANTI_VIRUS:
        install_param['ANTI_VIRUS'] = [ip]

    install_param['JAVA'] = [ip]
    install_param['REDIS_JAVA'] = [ip]
    install_param['docker'] = ENABLE_DOCKER_SCAN
    install_param['ms-srv'] = ENABLE_MS_SRV

    if java_mongo_db is not None:
        if isinstance(java_mongo_db, list):
            install_param['MONGO_JAVA'] = java_mongo_db
        else:
            install_param['MONGO_JAVA'] = [java_mongo_db]
    else:
        ip = get_input("Java_MongoDB", "", __IP_CONF["db_mongo_java"])
        #ips = get_iplist_from_str(ip)
        install_param['MONGO_JAVA'] = [ip]
    if len(install_param['MONGO_JAVA']) > 1:
        ip_pris = install_param['MONGO_JAVA']
        mongo_java_cluster={
            "db_mongo_java_mongod_cs": ip_pris,
            "db_mongo_java_mongod_27019": ip_pris,
            "db_mongo_java_mongod_27020": ip_pris,
            "db_mongo_java_mongod_27021": ip_pris
        }
        install_param["MONGO_JAVA_CLUSTER"] = mongo_java_cluster
    
    set_ms_srv_info(install_param)
    set_bigdata_info(install_param)
    config_by_installparam(install_param, manual)

def get_input2(default_value, prompt=""):
    v = raw_input(prompt)
    if v == "" or v.strip() == "":
        return default_value
    else:
        return v.strip()

def get_iplist_from_str(ipstr):
    ips = []
    for _ip in ipstr.split(","):
        ip = _ip.strip()
        if ip != '':
            ips.append(ip)

    return ips

def get_cluster_with_port(ips, port):
    if len(ips) <= 1: # <= 1, means not cluster, return ''
        return ''
    
    if port != '':
        _ips = [_ip + ":" + str(port) for _ip in ips]
        return ",".join(_ips)
    else:
        return ",".join(ips)

# standrad 3 hosts cluster deploy 3wx
def standalone_cluster_3():
    """
    Standard V3.4.0
    :return:
    """
    global ENABLE_DOCKER_SCAN
    global ENABLE_MS_SRV
    global ENABLE_EVENT_SRV
    global ENABLE_ANTI_VIRUS
    install_param = {}

    ip_pris,domain,ip_pubs = get_info_of_server("Server") 

    for role in ROLES:
        install_param[role] = ip_pris

    mongo_java_cluster={
        "db_mongo_java_mongod_cs": ip_pris,
        "db_mongo_java_mongod_27019": ip_pris
    }
    install_param["MONGO_JAVA_CLUSTER"] = mongo_java_cluster

    if domain is not None:
        for role in ["PHP","CONNECT"]:
            install_param[role+"_DOMAIN"] = domain
    if ip_pubs is not None:
        for role in ["PHP","CONNECT"]:
            install_param[role+"_PUBLIC"] = ip_pubs
    set_ms_srv_cluster_info(install_param)
    set_bigdata_info(install_param)
    config_vip(install_param)
    install_param["docker"] = ENABLE_DOCKER_SCAN    
    if ENABLE_ANTI_VIRUS:
        install_param['ANTI_VIRUS'] = ip_pris
    config_by_installparam(install_param, manual=True)


# standrad 6 hosts cluster deploy 3wx+3ms
def standalone_cluster_6():
    """
    Standard V3.4.0
    :return:
    """
    global ENABLE_DOCKER_SCAN
    global ENABLE_MS_SRV
    global ENABLE_EVENT_SRV
    global ENABLE_ANTI_VIRUS
    install_param = {}

    ip_pris,domain,ip_pubs = get_info_of_server("Server") 

    for role in ROLES:
        install_param[role] = ip_pris

    if ENABLE_ANTI_VIRUS:
        install_param['ANTI_VIRUS'] = ip_pris

    # if ENABLE_MS_SRV or ENABLE_EVENT_SRV:
    #     ip_pris,domain,ip_pubs = get_info_of_server("MONGO_JAVA", server_count=3)
    #     mongo_java_cluster={
    #     "db_mongo_java_mongod_cs": ip_pris,
    #     "db_mongo_java_mongod_27019": ip_pris
    #     }
    #     install_param["MONGO_JAVA_CLUSTER"] = mongo_java_cluster
    # else:        
    ip_pris,domain,ip_pubs = get_info_of_server("MONGO_JAVA", server_count=3)
    install_param['MONGO_JAVA'] = ip_pris
    mongo_java_cluster={
        "db_mongo_java_mongod_cs": ip_pris,
        "db_mongo_java_mongod_27019": ip_pris,
        "db_mongo_java_mongod_27020": ip_pris,
        "db_mongo_java_mongod_27021": ip_pris
    }
    install_param["MONGO_JAVA_CLUSTER"] = mongo_java_cluster
    if domain is not None:
        for role in ["PHP","CONNECT"]:
            install_param[role+"_DOMAIN"] = domain
    if ip_pubs is not None:
        for role in ["PHP","CONNECT"]:
            install_param[role+"_PUBLIC"] = ip_pubs
    
    set_ms_srv_cluster_info(install_param)
    set_bigdata_info(install_param)
    config_vip(install_param)
    
    install_param["docker"] = ENABLE_DOCKER_SCAN    
    config_by_installparam(install_param, manual=True)

def get_info_of_server(server, server_count=3):
    ipstr = get_input2('', "Input the ips of {server} : ".format(server=server)) 
    ips = get_iplist_from_str(ipstr)
    if len(ips) != server_count:
        print("ERROR:Number of ip is worng, Please input correct ips")
        sys.exit(1)

    domain, ip_pubs = "", [] 
    if server in ["PHP","CONNECT","Server"]:
        domain = get_input2('', "Input the domain of {server} (default ,if have no,just empty,please not input ip) : ".format(server=server))
    if server in ["CONNECT","Server"]: 
        ip_pub_str = get_input2('', "Input the public ips of {server} (default ,if have no,just empty,please not input private ips) : ".format(server=server))   
        ip_pubs = get_iplist_from_str(ip_pub_str)
        if len(ip_pubs) >0 and len(ip_pubs) != len(ips):
            print("ERROR: public ip and private should be One-to-one correspondence")
            sys.exit(1)
    return ips, domain, ip_pubs

# 9 hosts cluster deploy
def standalone_cluster_9():
    """
    Standard V3.0
    :return:
    """

    global ENABLE_DOCKER_SCAN
    global ENABLE_ANTI_VIRUS
    install_param = {}

    ip_pris,domain,ip_pubs = get_info_of_server("CONNECT")  

    install_param['CONNECT'] = ip_pris
    install_param['CONNECT_PUBLIC'] = ip_pubs
    install_param['CONNECT_DOMAIN'] = domain
    install_param['RABBITMQ'] = ip_pris

    install_param['PHP'] = ip_pris
    install_param['PHP_PUBLIC'] = ip_pubs
    install_param['PHP_DOMAIN'] = domain
    install_param['MYSQL'] = ip_pris
    install_param['REDIS_PHP'] = ip_pris
    install_param['REDIS_ERLANG'] = ip_pris
    install_param['KAFKA'] = ip_pris
    install_param['ZOOKEEPER'] = ip_pris

    ip_pris,domain,ip_pubs = get_info_of_server("JAVA")

    install_param['JAVA'] = ip_pris
    install_param['REDIS_JAVA'] = ip_pris
    install_param['docker'] = ENABLE_DOCKER_SCAN
    if ENABLE_ANTI_VIRUS:
        install_param['ANTI_VIRUS'] = ip_pris

    ip_pris,domain,ip_pubs = get_info_of_server("MONGO_JAVA", server_count=3)
    install_param['MONGO_JAVA'] = ip_pris
    mongo_java_cluster={
        "db_mongo_java_mongod_cs": ip_pris,
        "db_mongo_java_mongod_27019": ip_pris,
        "db_mongo_java_mongod_27020": ip_pris,
        "db_mongo_java_mongod_27021": ip_pris
    }
    install_param["MONGO_JAVA_CLUSTER"] = mongo_java_cluster

    set_ms_srv_cluster_info(install_param,True)
    set_bigdata_info(install_param)
    config_vip(install_param)

    config_by_installparam(install_param, True)

# 15 hosts cluster deploy
def standalone_cluster_15():
    """
    Standard V3.0
    :return:
    """

    global ENABLE_DOCKER_SCAN
    global ENABLE_ANTI_VIRUS
    install_param = {}

    ip_pris,domain,ip_pubs = get_info_of_server("CONNECT")  

    install_param['CONNECT'] = ip_pris
    install_param['CONNECT_PUBLIC'] = ip_pubs
    install_param['CONNECT_DOMAIN'] = domain
    install_param['RABBITMQ'] = ip_pris
    
    ip_pris,domain,ip_pubs = get_info_of_server("PHP") 

    install_param['PHP'] = ip_pris
    install_param['PHP_PUBLIC'] = ip_pubs
    install_param['PHP_DOMAIN'] = domain
    install_param['MYSQL'] = ip_pris
    install_param['REDIS_PHP'] = ip_pris
    install_param['REDIS_ERLANG'] = ip_pris
    install_param['REDIS_JAVA'] = ip_pris
    install_param['KAFKA'] = ip_pris
    install_param['ZOOKEEPER'] = ip_pris

    ip_pris,domain,ip_pubs = get_info_of_server("JAVA")

    install_param['JAVA'] = ip_pris
    install_param['docker'] = ENABLE_DOCKER_SCAN
    if ENABLE_ANTI_VIRUS:
        install_param['ANTI_VIRUS'] = ip_pris

    ip_pris,domain,ip_pubs = get_info_of_server("MONGO_JAVA", server_count=6)
    install_param['MONGO_JAVA'] = ip_pris
    get_mongo_cluster_detail(install_param,'mongo_java')

    set_ms_srv_cluster_info(install_param,True)
    set_bigdata_info(install_param)
    config_vip(install_param)

    config_by_installparam(install_param, True)

def config_vip(install_param):
    vip = get_input2('', "Input the virtual ip : ")
    if vip == '':
        print("ERROR: please input correct virtual ip")
        sys.exit(1)
    install_param["VIP"] = vip

    eip = get_input2('', "Input the public ip of vip (default is empty, not need):")
    install_param["EIP"] = eip
def standalone_add_bigdata():
    ##only add bigdata_logstash bigdata_viewer bigdata_es ip info。
    install_param = {}
    logstash_ipstr = get_input2('', "Input the ips of bigdata logstash: ")
    logstash_ips = get_iplist_from_str(logstash_ipstr)
    install_param["BIGDATA_LOGSTASH"] = logstash_ips
    viewer_ipstr = get_input2('', "Input the ips of bigdata viewer: ")
    viewer_ips = get_iplist_from_str(viewer_ipstr)
    install_param["BIGDATA_VIEWER"] = ''.join(viewer_ips)
    #check wx logstash is not exits
    for logstash_ip in logstash_ips:
        check_logstash_status = exec_ssh_cmd_withresult(logstash_ip, ''' ls /usr/local/qingteng/logstash ''')
        if not check_logstash_status:
            return 2
    get_es_info(logstash_ips[0], install_param)
    config_by_installparam(install_param, manual=True, bigdata_manual=True)

def get_input3(role="",key=""):
    if role == "JAVA":
        return __IP_CONF["java"];
    elif role == "JAVA_APP_EVENT":
        return __IP_CONF["java_event-srv"];
    elif role == "JAVA_APP_MS":
        return __IP_CONF["java_ms-srv"];
    elif role == "ANTI_VIRUS":
        return __IP_CONF["java_anti-virus-srv"]
    elif role =="CONNECT":
        if key == "domin":
            return __IP_CONF["java_connect-sh_domain"]
        elif key == "public":
            return __IP_CONF["java_connect-sh_public"]
        else: 
            return __IP_CONF["java_connect-agent"]
    elif role =="PHP":
        if key == "domin":
            return __IP_CONF["php_agent_domain"]
        elif key == "public":
            return __IP_CONF["php_agent_public"]
        else:
            return __IP_CONF["php_agent_private"]
    elif role == "MONGO_JAVA":
        return __IP_CONF["db_mongo_java"]
    elif role == "MYSQL":
        return __IP_CONF["db_mysql_php"]
    elif role == "RABBITMQ":
        return __IP_CONF["erl_rabbitmq"]
    elif role == "KAFKA":
        return __IP_CONF["java_kafka"]
    elif role == "REDIS_JAVA":
        return __IP_CONF["db_redis_java"]
    elif role == "REDIS_PHP":
        return __IP_CONF["db_redis_php"]
    elif role == "REDIS_ERLANG":
        return __IP_CONF["db_redis_erlang"]
    elif role == "ZOOKEEPER":
        return __IP_CONF["java_zookeeper"]
    elif role == "BIGDATA_LOGSTASH":
        return __IP_CONF["bigdata_logstash"]
    elif role == "BIGDATA_VIEWER":
        return __IP_CONF["bigdata_viewer"]



def standalone_by_role(install_param=None):
    """
    Standard V3.4.0
    :return:
    """
    global ENABLE_DOCKER_SCAN
    global ENABLE_BIGDATA
    global ENABLE_THP
    global ENABLE_MS_SRV
    global ENABLE_EVENT_SRV
    global ENABLE_ANTI_VIRUS
    install_param = {}

    domain_role = ["PHP","CONNECT"]   # PHP and CONNECT need domain
    for role in ROLES:
        ip_get_iptemplate=get_input3(role)
        if role == "MONGO_MS_SRV" and not ENABLE_MS_SRV:
            continue
        ipstr = get_input2(ip_get_iptemplate, "Input the ips of {0} (defaut: {1}): ".format(role , ip_get_iptemplate)) 
#       ipstr = get_input2('127.0.0.1', "Input the ips of {0} : ", __IP_CONF[role]") 
        ips = get_iplist_from_str(ipstr)

        domain = None
        if role in domain_role:
            ip_get_iptemplate=get_input3(role,"domin")
            domain = get_input2(ip_get_iptemplate, "Input the domain of {0}(defaut: {1}),if have no,just empty,please not input ip: ".format(role , ip_get_iptemplate)) 
        ip_pubs = None
        # when php is cluster, will use keepalived+vip, vip need use eip,which is publicip of vip
        if role == "CONNECT" or (role == "PHP" and len(ips) == 1) :
            ip_get_iptemplate=get_input3(role,"public")
            ip_pub_str = get_input2(ip_get_iptemplate, "Input the public ips of {0}(defaut: {1}),if have no,just empty,please not input private ips: ".format(role , ip_get_iptemplate))   
            ip_pubs = get_iplist_from_str(ip_pub_str)
            if len(ip_pubs) >0 and len(ip_pubs) != len(ips):
                print("ERROR: public ip and private should be One-to-one correspondence")
                sys.exit(1)


        install_param[role] = ips
        if domain is not None:
            install_param[role+"_DOMAIN"] = domain
        if ip_pubs is not None:
            install_param[role+"_PUBLIC"] = ip_pubs

    install_param["docker"] = ENABLE_DOCKER_SCAN
    install_param["bigdata"]  = ENABLE_BIGDATA
    install_param["thp"] = ENABLE_THP
    install_param["ms-srv"] = ENABLE_MS_SRV
    install_param["event-srv"] = ENABLE_EVENT_SRV
    # setting java app info
    if ENABLE_MS_SRV:
        install_param['ms-srv'] = True
        ms_srv_ip = get_input("JAVA_MS_SRV", "", __IP_CONF["java_ms-srv"])
        ms_srv_ips = get_iplist_from_str(ms_srv_ip)
        install_param['JAVA_APP_MS'] = ms_srv_ips
        if len(install_param["MONGO_MS_SRV"]) > 1:
            get_mongo_cluster_detail(install_param,'mongo_ms_srv')
        install_param['event-srv'] = True
        if ENABLE_EVENT_SRV:
            event_srv_ip = get_input("JAVA_EVENT_SRV", "", __IP_CONF["java_event-srv"])
        else:
            event_srv_ip = ms_srv_ip
        event_srv_ips = get_iplist_from_str(event_srv_ip)
        install_param['JAVA_APP_EVENT'] = event_srv_ips
    elif ENABLE_EVENT_SRV:
        install_param['event-srv'] = True
        event_srv_ip = get_input("JAVA_EVENT_SRV", "", __IP_CONF["java_event-srv"])
        event_srv_ips = get_iplist_from_str(event_srv_ip)
        install_param['JAVA_APP_EVENT'] = event_srv_ips
    else:
        pass
    if ENABLE_ANTI_VIRUS:
        anti_virus_srv_ip = get_input("ANTI_VIRUS_SRV", "", __IP_CONF["java_anti-virus-srv"])
        anti_virus_srv_ips = get_iplist_from_str(anti_virus_srv_ip)
        install_param['ANTI_VIRUS'] = anti_virus_srv_ips
    if install_param["bigdata"]:
        ip_get_iptemplate=get_input3("BIGDATA_LOGSTASH")
        logstash_ipstr = get_input2(ip_get_iptemplate, "Input the ips of bigdata logstash(defaut {0}): ".format(ip_get_iptemplate))
        logstash_ips = get_iplist_from_str(logstash_ipstr)
        install_param["BIGDATA_LOGSTASH"] = logstash_ips
        ip_get_iptemplate=get_input3("BIGDATA_VIEWER")
        viewer_ip = get_input2(ip_get_iptemplate, "Input the ip of bigdata viewer(defaut: {0}): ".format(ip_get_iptemplate))
        install_param["BIGDATA_VIEWER"] = ''.join(viewer_ip)
        get_es_info(logstash_ips[0], install_param)
    elif install_param["thp"]:
        ip_get_iptemplate=get_input3("BIGDATA_LOGSTASH")
        logstash_ipstr = get_input2(ip_get_iptemplate, "Input the ips of bigdata logstash(defaut {0}): ".format(ip_get_iptemplate))
        logstash_ips = get_iplist_from_str(logstash_ipstr)
        install_param["BIGDATA_LOGSTASH"] = logstash_ips
        get_es_info(logstash_ips[0], install_param)
    
    #setting vip
    php_ips = install_param["PHP"]
    if len(php_ips) > 1:
        config_vip(install_param)

    if len(install_param["MONGO_JAVA"]) > 1:
        get_mongo_cluster_detail(install_param,'mongo_java')

    config_by_installparam(install_param, manual=True)


# pasre mongo cluster networl detail from process
def get_mongo_cluster_detail(install_param,roles='mongo_java'):
    print("Parse mongo cluster detail begin, Please wait a moment")
    if roles == 'mongo_ms_srv':
        mongo_ips = install_param["MONGO_MS_SRV"]
    else:
        mongo_ips = install_param["MONGO_JAVA"]
    mongo_cluster = {}

    for mongo_ip in mongo_ips:
        process_list = exec_ssh_cmd_withresult(mongo_ip, '''ps -ef|grep etc/mongo | grep -v grep ''')

        for process in process_list.splitlines():
            ipjson_key = None
            if "mongos.conf" in process:
                ipjson_key = "db_{roles}_cluster".format(roles=roles)
            elif "mongod_cs.conf" in process:
                ipjson_key = "db_{roles}_mongod_cs".format(roles=roles)
            else:
                matchObj = re.search(r"etc/(mongod_\d{5})", process)
                if matchObj:
                    mongo_port = matchObj.group(1)
                    ipjson_key = "db_{roles}_".format(roles=roles) + mongo_port  
            if ipjson_key:
                mongo_cluster.setdefault(ipjson_key,[])
                mongo_cluster[ipjson_key].append(mongo_ip)
    # trans mongosip to mongosip:27017
    new_mongos = []
    mongos_ips = mongo_cluster["db_{roles}_cluster".format(roles=roles)]
    for mongos in mongos_ips:
        new_mongos.append(mongos + ":27017")
    mongo_cluster["db_{roles}_cluster".format(roles=roles)] = new_mongos

    print(mongo_cluster)
    print("Parse {roles} cluster detail end".format(roles=roles))

    if roles == 'mongo_ms_srv':
        install_param["MONGO_MS_SRV_CLUSTER"] = mongo_cluster
    else:
        install_param["MONGO_JAVA_CLUSTER"] = mongo_cluster
    

def get_es_nodes(master_ip=''):
    
    es_ips = set()
    print('If input one ip, will try to get all es nodes automatically')
    print('If input multiple ips, will use these ip as es nodes')
    es_ip_info = get_input2(master_ip, "Input ip of elasticsearch(default is {master_ip}): ".format(master_ip=master_ip))
    ips = get_iplist_from_str(es_ip_info)

    if len(ips) == 1:
        cmd = 'curl -s -u elastic:RskWkp0WeliKl http://127.0.0.1:9200/_cat/nodes?v'
        result = exec_ssh_cmd_withresult(ips[0], cmd, verbose=True)
        if result and not 'security_exception' in result:
            lines = result.splitlines()
            for line in lines[1:]:
                ip = line.split()[0]
                es_ips.add(ip)
        else:
            print("Can't get es nodes automatically, Please input all es nodes(such as ip1,ip2,ip3):")
            esipstr = get_input2('', "Input the ips of elasticsearch : ") 
            ips = get_iplist_from_str(esipstr)
            es_ips = set(ips)
    else:
        print('you input multiple host of es, will use this directly')
        es_ips = set(ips)

    return es_ips

def get_es_cluster_inst(es_ips):

    es_inst_map = {}
    for es_ip in es_ips:
        process_list = exec_ssh_cmd_withresult(es_ip, '''ps -ef|grep elasticsearch_ins | grep -v grep ''')
        for process in process_list.splitlines():
            matchObj = re.search(r"/usr/local/qingteng/elasticsearch/elasticsearch_ins(\d+)/etc", process)
            if matchObj:
                inst_name = 'bigdata_es_' + matchObj.group(1)
                es_inst_map.setdefault(inst_name,[])
                es_inst_map[inst_name].append(es_ip)

    print(es_inst_map)
    return es_inst_map

def get_es_info(bigdata_ip, install_param):

    es_ips = get_es_nodes(bigdata_ip)
    es_inst_map = get_es_cluster_inst(es_ips)
    install_param["ES_CLUSTER"] = es_inst_map


ROLES = ['JAVA', 'CONNECT', 'PHP', 'MONGO_JAVA', 'MYSQL', 'RABBITMQ',  
        'KAFKA', 'REDIS_JAVA', 'REDIS_PHP', 'REDIS_ERLANG', 'ZOOKEEPER','MONGO_MS_SRV']

JAVA_SERVICES = ['java','java_gateway','java_user-srv','java_detect-srv','java_upload-srv','java_job-srv','java_scan-srv']

JAVA_APP_MS = ['java_ms-srv']
JAVA_APP_EVENT = ['java_event-srv']

CONNECT_SERVICES = ['java_connect-agent','java_connect-dh','java_connect-sh','java_connect-selector']

PHP_SERVICES = ["java_patrol-srv", "php_frontend_private", "php_backend_private", "php_agent_private", 
                "php_download_private", "php_api_private", "php_inner_api", "php_worker_ip"]

SERVICE_PORT_MAP = {
    "java":6100,
    "java_gateway":16000,
    "java_user-srv":6120,
    "java_detect-srv":6140,
    "java_upload-srv":6130,
    "java_job-srv":6170,
    "java_scan-srv":6150,
    "java_connect-agent":6220,
    "java_connect-dh":6210,
    "java_connect-sh":7788,
    "java_connect-selector":16677,
    "java_ms-srv":6400,
    "java_event-srv":6700,
    "erl_rabbitmq": 5672,
    "db_mongo_java": 27017,
    "db_mongo_ms_srv": 27017,
    "db_mysql_php": 3306,
    "db_redis_java": 6381,
    "db_redis_php": 6380,
    "db_redis_erlang": 6379,
    "java_kafka":9092,
    "java_zookeeper":2181,
    "java_anti-virus-srv":6240
}

def config_by_installparam(install_param, manual=False, bigdata_manual=None):
    '''installParam" : {
            "docker" : false,
            "bigdata" : false,
            "MONGO_JAVA": [172.16.2.184,172.16.2.185,172.16.2.186],
            "MONGO_MS_SRV": [172.16.2.181,172.16.2.182,172.16.2.183],
            "KAFKA": [172.16.2.184,172.16.2.185,172.16.2.186],
            "MYSQL": [172.16.2.184,172.16.2.185,172.16.2.186],
            "CONNECT": [172.16.2.184,172.16.2.185,172.16.2.186],
            "CONNECT_PUBLIC": [172.16.3.184,172.16.3.185,172.16.3.186],
            "CONNECT_DOMAIN": 'test.qingteng.cn',
            "PHP": [172.16.2.184,172.16.2.185,172.16.2.186],
            "PHP_PUBLIC": [172.16.3.184,172.16.3.185,172.16.3.186],
            "PHP_DOMAIN": 'test.qingteng.cn',
            "RABBITMQ": [172.16.2.187],
            "BIGDATA_LOGSTASH": [172.16.2.187],
            "BIGDATA_VIEWER": 172.16.2.187,
            "VIP": "172.16.2.183",
            "MONGO_JAVA_CLUSTER": {},
            "ES_CLUSTER": {}
        }

        # all roles:  MONGO_JAVA KAFKA MYSQL CONNECT RABBITMQ JAVA 
                    REDIS_JAVA REDIS_PHP PHP ZOOKEEPER REDIS_ERLANG SRV
    '''
    #print(install_param)

    #JAVA
    if bigdata_manual is None:
        java_ips = install_param["JAVA"]
        if not install_param.get("docker", False):
            JAVA_SERVICES.remove("java_scan-srv")    

        for service_name in JAVA_SERVICES:
            __IP_CONF[service_name] = java_ips[0]
            __IP_CONF[service_name + "_cluster"] = get_cluster_with_port(java_ips, SERVICE_PORT_MAP[service_name])

        # cluster will install glusterfs with java
        if len(java_ips) > 1:
            __IP_CONF["glusterfs"] = ",".join(java_ips)
        #JAVA_APP
        if install_param.get("ms-srv", False):
            ms_srv_ips = install_param["JAVA_APP_MS"]
            event_srv_ips = install_param["JAVA_APP_EVENT"]
            __IP_CONF['java_ms-srv'] = ms_srv_ips[0]
            __IP_CONF['java_ms-srv_cluster'] = get_cluster_with_port(ms_srv_ips, SERVICE_PORT_MAP['java_ms-srv'])
            __IP_CONF['java_event-srv'] = event_srv_ips[0]
            __IP_CONF['java_event-srv_cluster'] = get_cluster_with_port(event_srv_ips, SERVICE_PORT_MAP['java_event-srv'])
        elif install_param.get("event-srv", False):
            event_srv_ips = install_param["JAVA_APP_EVENT"]
            __IP_CONF['java_event-srv'] = event_srv_ips[0]
            __IP_CONF['java_event-srv_cluster'] = get_cluster_with_port(event_srv_ips, SERVICE_PORT_MAP['java_event-srv'])
        else:
            pass
        # ANTI_VIRUS
        anti_virus_srv_ips = install_param.get("ANTI_VIRUS", False)
        if  anti_virus_srv_ips:
            __IP_CONF["java_anti-virus-srv"] =  anti_virus_srv_ips[0]
            __IP_CONF["java_anti-virus-srv_cluster"] = get_cluster_with_port(anti_virus_srv_ips, SERVICE_PORT_MAP["java_anti-virus-srv"])
        #CONNECT
        connect_ips = install_param["CONNECT"]
        connect_public_ips = install_param.get("CONNECT_PUBLIC", None)
        connect_domain = install_param.get("CONNECT_DOMAIN", None)
        for service_name in CONNECT_SERVICES:
            __IP_CONF[service_name] = connect_ips[0]
            __IP_CONF[service_name + "_cluster"] = get_cluster_with_port(connect_ips, SERVICE_PORT_MAP[service_name])

            if service_name in ['java_connect-sh','java_connect-selector']:
                if connect_domain:
                    __IP_CONF[service_name + "_domain"] = connect_domain
                if connect_public_ips:
                    __IP_CONF[service_name + "_public"] = ",".join(connect_public_ips)

        #PHP
        php_ips = install_param["PHP"]
        vip = install_param.get("VIP", None)
        if vip:
            __IP_CONF['vip'] = vip

        eip = install_param.get("EIP", None)
        if eip:
            __IP_CONF['eip'] = eip

        php_public_ips = install_param.get("PHP_PUBLIC", None)
        php_domain = install_param.get("PHP_DOMAIN", None)
        for service_name in PHP_SERVICES:
            __IP_CONF[service_name] = php_ips[0]
            __IP_CONF[service_name + "_cluster"] = get_cluster_with_port(php_ips, SERVICE_PORT_MAP.get(service_name,''))

            short_name = service_name[:-8] if service_name.endswith('_private') else service_name 
            if php_domain and short_name + "_domain" in __PHP_DOMAIN:
                __IP_CONF[short_name + "_domain"] = php_domain
            if php_public_ips and short_name + "_public" in __PHP_PUB_IP:
                __IP_CONF[short_name + "_public"] = ",".join(php_public_ips)

        # cluster will install keepalived with php
        if len(php_ips) > 1:
            __IP_CONF["keepalived"] = ",".join(php_ips)

        #MONGO_JAVA
        mongo_java_ips = install_param["MONGO_JAVA"]
        __IP_CONF['db_mongo_java'] = mongo_java_ips[0]
        __IP_CONF['db_mongo_java_cluster'] = get_cluster_with_port(mongo_java_ips, SERVICE_PORT_MAP['db_mongo_java'])
        print __IP_CONF['db_mongo_java_cluster']
        # if has mongo cluster info, 
        if install_param.has_key("MONGO_JAVA_CLUSTER"):
            for key, ips in install_param["MONGO_JAVA_CLUSTER"].items():
                __IP_CONF[key] = ",".join(ips)
    
        #MONGO_MS_SRV
        if install_param.get("ms-srv", False):
            mongo_ms_srv_ips = install_param["MONGO_MS_SRV"]
            __IP_CONF['db_mongo_ms_srv'] = mongo_ms_srv_ips[0]
            __IP_CONF['db_mongo_ms_srv_cluster'] = get_cluster_with_port(mongo_ms_srv_ips, SERVICE_PORT_MAP['db_mongo_ms_srv'])

        # if has mongo cluster info, 
            if install_param.has_key("MONGO_MS_SRV_CLUSTER"):
                for key, ips in install_param["MONGO_MS_SRV_CLUSTER"].items():
                    __IP_CONF[key] = ",".join(ips)

    #MYSQL
        mysql_ips = install_param["MYSQL"]
        __IP_CONF['db_mysql_php'] = mysql_ips[0]
        __IP_CONF['db_mysql_php_cluster'] = get_cluster_with_port(mysql_ips, SERVICE_PORT_MAP['db_mysql_php'])

    #KAFKA
        kafka_ips = install_param["KAFKA"]
        __IP_CONF['java_kafka'] = kafka_ips[0]
        __IP_CONF['java_kafka_cluster'] = get_cluster_with_port(kafka_ips, SERVICE_PORT_MAP['java_kafka'])

    #REDIS_JAVA
        redis_java_ips = install_param["REDIS_JAVA"]
        __IP_CONF['db_redis_java'] = redis_java_ips[0]
        __IP_CONF['db_redis_java_cluster'] = get_cluster_with_port(redis_java_ips, SERVICE_PORT_MAP['db_redis_java'])

    #REDIS_PHP
        redis_php_ips = install_param["REDIS_PHP"]
        __IP_CONF['db_redis_php'] = redis_php_ips[0]
        __IP_CONF['db_redis_php_cluster'] = get_cluster_with_port(redis_php_ips, SERVICE_PORT_MAP['db_redis_php'])

    #REDIS_ERLANG
        redis_erl_ips = install_param["REDIS_ERLANG"]
        __IP_CONF['db_redis_erlang'] = redis_erl_ips[0]
        __IP_CONF['db_redis_erlang_cluster'] = get_cluster_with_port(redis_erl_ips, SERVICE_PORT_MAP['db_redis_erlang'])

    #ZOOKEEPER
        zookeepr_ips = install_param["ZOOKEEPER"]
        __IP_CONF['java_zookeeper'] = zookeepr_ips[0]
        __IP_CONF['java_zookeeper_cluster'] = get_cluster_with_port(zookeepr_ips, SERVICE_PORT_MAP['java_zookeeper'])

    #RABBITMQ
        rabbitmq_ips = install_param["RABBITMQ"]
        __IP_CONF['erl_rabbitmq'] = rabbitmq_ips[0]
        __IP_CONF['erl_rabbitmq_cluster'] = get_cluster_with_port(rabbitmq_ips, SERVICE_PORT_MAP['erl_rabbitmq'])


    if bigdata_manual:
        # bigdata_ip
        logstash_ips = install_param["BIGDATA_LOGSTASH"]
        if len(logstash_ips) > 1 :
            __IP_CONF["bigdata_logstash_cluster"] = ",".join(logstash_ips)
            __IP_CONF["bigdata_logstash"] = logstash_ips[0].split(',')[0]
        else:
            __IP_CONF["bigdata_logstash"] = logstash_ips[0]
        viewer_ips = install_param["BIGDATA_VIEWER"] 
        __IP_CONF["bigdata_viewer"] = viewer_ips
        if __IP_CONF.has_key("bigdata_es"):
            del __IP_CONF["bigdata_es"]
        for inst_name, inst_ips in install_param["ES_CLUSTER"].items():
            __IP_CONF[inst_name] = ",".join(inst_ips)

    if manual:
        print json.dumps(__IP_CONF, indent = 4, sort_keys = True)
        while True:
            print "Do you want to change some config? default is N"
            v = raw_input("Enter [Y/N]:")
            if v == "y" or v == "Y" or v == "Yes" or v == "YES":
                conf = raw_input("Please input the config need change (such as java:172.16.2.181): ")
                conf = conf.strip()
                key_value = conf.split(':')
                if len(key_value) != 2:
                    print("WRONG INPUT")
                    continue
                else:
                    key, value = key_value[0], key_value[1]
                    if not __IP_CONF.has_key(key):
                        print("WRONG INPUT, config of {0} not exist".format(key))
                        continue 
                    elif not ENABLE_BIGDATA and key in ['bigdata_es','bigdata_logstash','bigdata_viewer']:
                        print("License File not enable bigdata, can't config bigdata ip")
                    elif not ENABLE_DOCKER_SCAN and key in ['java_scan-srv']:
                        print("License File not enable docker, can't config docker scan ip")
                    elif not ENABLE_THP and key in ['bigdata_es','bigdata_logstash']:
                        print("License File not enable thp, can't config logstash/es ip")
                    elif not ENABLE_MS_SRV and key in ['java_ms-srv']:
                        print("License File not enable ms-srv, can't config java ms srv  ip")
                    elif not ENABLE_EVENT_SRV and key in ['java_event-srv']:
                        print("License File not enable event-srv, can't config java event srv ip")            
                    elif not ENABLE_ANTI_VIRUS and key in ['java_anti-virus-srv']:
                        print("License File not enable anti-virus-srv, can't config javaanti-virus-srv ip") 
                    else:
                        __IP_CONF[key] = value
                        print json.dumps(__IP_CONF, indent = 4, sort_keys = True)
            else:
                break

def save_user_input():
    """
    Update ip_template.json
    :return:
    """
    with open(__FILE_ABS_PATH + "/" + __IP_TEMPLATE, "w+") as f:
        f.write(json.dumps(__IP_CONF, indent = 4, sort_keys = True))


def check_license():
    global ENABLE_DOCKER_SCAN
    global ENABLE_ANTI_VIRUS
    global ENABLE_BIGDATA
    global ENABLE_THP
    global ENABLE_MS_SRV
    global ENABLE_EVENT_SRV
    _command = "ls -t *-license*.zip | head -n 1"
    status, output = commands.getstatusoutput(_command)
    if status != 0:
        print("Lincese file not exists, exit")
        sys.exit(1)
    
    license_file = output.strip()
    license_path = __FILE_ABS_PATH + "/" + license_file
    status, output = commands.getstatusoutput("unzip -cp {0} license.key".format(license_path))
    if status != 0:
        print(output)
        print("Lincese file unzip exception, exit")
        sys.exit(1)

    license_info = json.loads(output.strip())
    ENABLE_DOCKER_SCAN = license_info["docker"]
    '''兼容license没有bigdata的场景'''
    if license_info.has_key("bigdata"):
        ENABLE_BIGDATA = license_info["bigdata"]
    else:
        ENABLE_BIGDATA = False
    '''兼容license没有thp的场景'''
    if license_info.has_key("thp"):
        ENABLE_THP = license_info["thp"]
    else:
        ENABLE_THP = False
    '''兼容license没有ms-srv的场景'''
    if license_info.has_key("ms-srv"):
        ENABLE_MS_SRV = license_info["ms-srv"]
    else:
        ENABLE_MS_SRV = False

    '''兼容license没有anti-virus-srv的场景'''
    if license_info.has_key("anti-virus-srv"):
        ENABLE_ANTI_VIRUS = license_info["anti-virus-srv"]
    else:
        ENABLE_ANTI_VIRUS = False
    
    '''兼容license没有event-srv的场景'''
    if license_info.has_key("event-srv"):
        ENABLE_EVENT_SRV = license_info["event-srv"]
    else:
        ENABLE_EVENT_SRV = False
    
    print("Refer to license file, your docker is " + ("enable" if ENABLE_DOCKER_SCAN else "not enable"))
    print("Refer to license file, your ms-srv is " + ("enable" if ENABLE_MS_SRV else "not enable"))
    print("Refer to license file, your event-srv is " + ("enable" if ENABLE_EVENT_SRV else "not enable"))
    print("Refer to license file, your anti-virus-srv is " + ("enable" if ENABLE_ANTI_VIRUS else "not enable")) 
    

    print "Is License File correct? Do you want to continue? default is Y"
    v = raw_input("Enter [Y/N]:")
    if v == "y" or v == "Y" or v == "Yes" or v == "YES" or v == '':
        pass
    else:
        sys.exit(1)

abnormal_log = []

def check_all_base():
    print("Begin to check base service")

    check_keepalived()
    check_gluster()

    check_rabbitmq()
    check_zookeeper()
    check_kafka()
    check_redis_php()
    check_redis_java()
    check_redis_erlang()
    check_mongo('mongo_java')
    check_mongo('mongo_ms_srv')
    check_mysql()
    check_nginx()

    if len(abnormal_log) > 0:
        for abnormal_msg in abnormal_log:
            print('\033[35m' + "WARN:" + str(abnormal_msg) + '\033[0m')

        print('\033[35m' + "WARN:Some base service abnormal,Please check it manually" + '\033[0m')
    else:
        print("all base service check ok")  

def check_nginx():
    global abnormal_log
    nginx_ips = get_ipset(None, "php_worker_ip")
    if len(nginx_ips) == 0:
        return

    for ip in nginx_ips:
        processinfo = exec_ssh_cmd_withresult(ip, '''nginx -t ''')
        if not processinfo or "emerg" in processinfo:
            abnormal_log.append("nginx at {ip} status exception, please check".format(ip=ip))
            continue
    print ("check nginx end")
        
def check_keepalived():
    global abnormal_log
    keepalived_ips = get_ipset(None, "keepalived")
    if len(keepalived_ips) == 0:
        return

    for ip in keepalived_ips:
        processinfo = exec_ssh_cmd_withresult(ip, '''ps auxf| grep keepalived | grep -v grep | grep -v \_ ''')
        if not processinfo or not 'keepalived' in processinfo:
            abnormal_log.append("keepalived server " + ip + " process abnormal")

    print("check keepalived end")

def check_gluster():
    global abnormal_log
    gluster_ips = get_ipset(None, "glusterfs")
    if len(gluster_ips) == 0:
        return

    gluster_ips = list(gluster_ips)
    for ip in gluster_ips:
        processinfo = exec_ssh_cmd_withresult(ip, '''ps auxf| ps -ef|grep -E 'glustershd|glusterd.*glusterd.pid|glusterfsd' | grep -v grep | grep -v \_ ''')
        if not processinfo or not (
            'glustershd' in processinfo and 'glusterfsd' in processinfo 
            and 'glusterd.pid' in processinfo ):
            abnormal_log.append("gluster server " + ip + " process abnormal")

    gluster_ip = gluster_ips[0]
    volume_status = exec_ssh_cmd_withresult(gluster_ip, '''gluster volume status java | grep -E 'Brick' ''')
    if not volume_status or 'N/A' in volume_status:
        abnormal_log.append("gluster volume java exception, execute 'gluster volume status java' to check")

    ip_set = set()
    ip_set.update(get_ipset("java","java_cluster"))
    ip_set.update(get_ipset("php_agent_private","php_agent_private_cluster"))
    ip_set.update(get_ipset("java_ms-srv","java_ms-srv_cluster"))
    ip_set.update(get_ipset("java_event-srv","java_event-srv_cluster"))

    for ip in ip_set:
        dfs_result = exec_ssh_cmd_withresult(ip, '''df -h /data/app/titan-dfs | grep /data/app/titan-dfs''')
        if not dfs_result or not '/data/app/titan-dfs' in dfs_result:
            abnormal_log.append("glusterfs which mount /data/app/titan-dfs at " + ip + " abnormal, please check")

    print("check glusterfs end")

def check_rabbitmq():
    global abnormal_log
    ip_set = get_ipset("erl_rabbitmq","erl_rabbitmq_cluster")

    rabbit_ips = list(ip_set)
    rabbit_ip = rabbit_ips[0]

    rabbitmq_ok = False
    # after 3.3.13, rabbitmq run as rabbitmq user, first copy erlang.cookie, ensure can use rabbitmqctl correctly
    exec_ssh_cmd_withresult(rabbit_ip, "cp /data/app/titan-rabbitmq/.erlang.cookie /root/ && chmod 600 /data/app/titan-rabbitmq/.erlang.cookie") 
    cluster_nodes = exec_ssh_cmd_withresult(rabbit_ip, '''/data/servers/rabbitmq_root/bin/rabbitmqctl cluster_status|sed -n '/Running Nodes/,/Versions/p'|grep -c ^rabbit''')
    if cluster_nodes == str(len(rabbit_ips)):
            rabbitmq_ok = True

    if not rabbitmq_ok:
        abnormal_log.append("rabbitmq status exception, please check")

    print("check rabbitmq end")

def check_zookeeper():
    global abnormal_log
    ip_set = get_ipset("java_zookeeper","java_zookeeper_cluster")

    leaders = []
    followers = []
    standalones = []
    for ip in ip_set:
        zk_status = exec_ssh_cmd_withresult(ip, '''/usr/local/qingteng/zookeeper/bin/zkServer.sh status ''')
        if not zk_status:
            abnormal_log.append("zookeeper at {ip} status exception, please check".format(ip=ip))
            continue

        if "follower" in zk_status:
            followers.append(ip)
        elif "leader" in zk_status:
            leaders.append(ip)
        elif "standalone" in zk_status:
            standalones.append(ip)
        else:
            abnormal_log.append("zookeeper at {ip} status exception, please check".format(ip=ip))

    if len(ip_set) > 1:
        if len(leaders) < 1:
            abnormal_log.append("zookeeper have no leader, please check")
    else:
        if len(standalones) < 1:
            abnormal_log.append("zookeeper exception, please check")

    print("check zookeeper end")

def check_kafka():
    global abnormal_log
    ip_set = get_ipset("java_kafka","java_kafka_cluster")

    for ip in ip_set:
        kafka_status = exec_ssh_cmd_withresult(ip, '''ps -ef|grep kafka.logs.dir | grep -v grep ''')
        if not kafka_status or 'kafka.logs.dir' not in kafka_status:
            abnormal_log.append("kafka at {ip} status exception, please check".format(ip=ip))
    
    print("check kafka end")

def check_redis_php():
    global abnormal_log
    ip_set = get_ipset("db_redis_php","db_redis_php_cluster")


    if len(ip_set) > 1:
        redis_ip = ip_set.pop()
        for ip in ip_set:
            redis_passwd = exec_ssh_cmd_withresult(redis_ip, '''cat /etc/redis/6380.conf | grep requirepass | cut -d ' ' -f 2 ''')
            redis_auth = '' if (redis_passwd is None or redis_passwd == '') else " -a " + redis_passwd
            cluster_status = exec_ssh_cmd_withresult(redis_ip, '''/usr/local/qingteng/redis/bin/redis-cli -p 6380 {redis_auth} cluster info | grep cluster_state '''.format(redis_auth=redis_auth))
            if not cluster_status or not 'ok' in cluster_status:
                abnormal_log.append("redis_php cluster state exception, please check".format(ip=ip))
    else:
        redis_ip = ip_set.pop()
        redis_process = exec_ssh_cmd_withresult(redis_ip, '''ps auxf|grep -E 'redis-server.*6380'|grep -v grep ''')
        if not redis_process or not 'redis-server' in redis_process:
            abnormal_log.append("redis_php at {ip} status exception, please check".format(ip=redis_ip))

    print("check redis_php end")

def check_redis_java():
    global abnormal_log
    ip_set = get_ipset("db_redis_java","db_redis_java_cluster")


    if len(ip_set) > 1:
        redis_ip = ip_set.pop()
        for ip in ip_set:
            redis_passwd = exec_ssh_cmd_withresult(redis_ip, '''cat /etc/redis/6381.conf | grep requirepass | cut -d ' ' -f 2 ''')
            redis_auth = '' if (redis_passwd is None or redis_passwd == '') else " -a " + redis_passwd
            cluster_status = exec_ssh_cmd_withresult(redis_ip, '''/usr/local/qingteng/redis/bin/redis-cli -p 6381 {redis_auth} cluster info | grep cluster_state '''.format(redis_auth=redis_auth))
            if not cluster_status or not 'ok' in cluster_status:
                abnormal_log.append("redis_java cluster state exception, please check".format(ip=ip))
    else:
        redis_ip = ip_set.pop()
        redis_process = exec_ssh_cmd_withresult(redis_ip, '''ps auxf|grep -E 'redis-server.*6381'|grep -v grep ''')
        if not redis_process or not 'redis-server' in redis_process:
            abnormal_log.append("redis_java at {ip} status exception, please check".format(ip=redis_ip))

    print("check redis_java end")

def check_redis_erlang():
    global abnormal_log
    ip_set = get_ipset("db_redis_erlang","db_redis_erlang_cluster")


    if len(ip_set) > 1:
        redis_ip = ip_set.pop()
        for ip in ip_set:
            redis_passwd = exec_ssh_cmd_withresult(redis_ip, '''cat /etc/redis/6379.conf | grep requirepass | cut -d ' ' -f 2 ''')
            redis_auth = '' if (redis_passwd is None or redis_passwd == '') else " -a " + redis_passwd
            cluster_status = exec_ssh_cmd_withresult(redis_ip, '''/usr/local/qingteng/redis/bin/redis-cli -p 6379 {redis_auth} cluster info | grep cluster_state '''.format(redis_auth=redis_auth))
            if not cluster_status or not 'ok' in cluster_status:
                abnormal_log.append("redis_erlang cluster state exception, please check".format(ip=ip))
    else:
        redis_ip = ip_set.pop()
        redis_process = exec_ssh_cmd_withresult(redis_ip, '''ps auxf|grep -E 'redis-server.*6379'|grep -v grep ''')
        if not redis_process or not 'redis-server' in redis_process:
            abnormal_log.append("redis_erlang at {ip} status exception, please check".format(ip=redis_ip))

    print("check redis_erlang end")            

def check_mysql():
    global abnormal_log
    ip_set = get_ipset("db_mysql_php","db_mysql_php_cluster")

    for ip in ip_set:
        mysql_process = exec_ssh_cmd_withresult(ip, '''ps auxf|grep mysqld | grep -v grep ''')
        if not mysql_process or 'mysqld' not in mysql_process:
            abnormal_log.append("mysql at {ip} status exception, please check".format(ip=ip))

    print("check mysql end")

def check_mongo(roles='mongo_java'):
    ipset = get_ipset("db_{roles}".format(roles=roles),"db_{roles}_cluster".format(roles=roles))
    if not ipset:
        return
    if len(ipset) == 1:
        mongo_ip = ipset.pop()
        mongo_process = exec_ssh_cmd_withresult(mongo_ip, '''ps auxf|grep mongod | grep -v grep ''')
        if not mongo_process or 'mongod' not in mongo_process:
            abnormal_log.append("mongo at {ip} status exception, please check".format(ip=mongo_ip))

        return

    # check mongo cluster
    mongo_cluster = {}
    for key, ip_port_list in __IP_CONF.items():
        if not key.startswith("db_{roles}".format(roles=roles)):
            continue

        if ip_port_list == "" or ip_port_list == "127.0.0.1":
            continue

        if key == "db_{roles}".format(roles=roles) or key == "db_{roles}_cluster".format(roles=roles):
            role = "mongos"
        else:
            role = key.replace("db_{roles}_".format(roles=roles), "") 
        ipset = set(mongo_cluster.get(role,[]))
        ipset.update(get_cluster_ips(ip_port_list))
        mongo_cluster[role] = list(ipset)

    #print(mongo_cluster)
    for role,ips in mongo_cluster.items():
        for ip in ips:
            if role == "mongos":
                mongo_process = exec_ssh_cmd_withresult(ip, '''ps auxf|grep -E 'mongos -f.*mongos' | grep -v grep ''')
            else:
                mongo_process = exec_ssh_cmd_withresult(ip, '''ps auxf|grep -E 'mongod -f.*{role}' | grep -v grep '''.format(role=role))

            if not mongo_process or role not in mongo_process:
                abnormal_log.append("{role} at {ip} status exception, please check".format(ip=ip,role=role))   

    print("check {roles} end".format(roles=roles))

# get ips from ip:port,ip:port or ip,ip,ip
def get_cluster_ips(clusterip):
    # get cluster ips
    ips = []
    ip_ports = clusterip.split(',')
    for ip_port in ip_ports:
        temp_ip = ip_port.split(':')[0]
        if temp_ip != '' and temp_ip != '127.0.0.1':
            ips.append(temp_ip)

    return ips

def get_ipset(name=None, cluster_name=None):
    ip_set = set()
    if cluster_name:
        ip_set.update(get_cluster_ips(__IP_CONF.get(cluster_name, '')))
    if name:
        ip_set.add(__IP_CONF.get(name, ''))
    ip_set.discard('')
    ip_set.discard('127.0.0.1')

    return ip_set   

def check_license_status(status=True):
    if status:
        #如果MS_SRV 和EVENT_SRV 中有一个true 则报错
        if ENABLE_MS_SRV or ENABLE_EVENT_SRV:
            print("ERROR: The lincense is inconsistent with the deployment type")  
            sys.exit(1)
    #其他 status 状态没有传True
    else:
        #如果有一个true ,则通过。否则报错
        #如果两个都为False，则报错
        if not ENABLE_EVENT_SRV and not ENABLE_MS_SRV:
            print("ERROR: The lincense is inconsistent with the deployment type")  
            sys.exit(1)
def set_mongo_info():
    global java_mongo_db
    global ms_srv_mongo_db
    java_mongo_ipstr = get_input2('', "Input the ips of java_Mongo Cluster : ")
    if not java_mongo_ipstr or java_mongo_ipstr.strip == '':
        print("ERROR: please input correct java_mongo cluster ips")
        sys.exit(1)
    java_mongo_db = get_iplist_from_str(java_mongo_ipstr)
    if len(java_mongo_db) != 3:
        print("ERROR: please input correct java_mongo cluster ips")
        sys.exit(1)
    if ENABLE_MS_SRV:
       ms_srv_mongo_ipstr = get_input2('', "Input the ips of ms_srv_Mongo Cluster : ")
       if not ms_srv_mongo_ipstr or ms_srv_mongo_ipstr.strip == '':
           print("ERROR: please input correct ms_srv_mongo cluster ips")
           sys.exit(1)
       ms_srv_mongo_db = get_iplist_from_str(ms_srv_mongo_ipstr)
       if len(ms_srv_mongo_db) != 3 :
           print("ERROR: please input correct ms_srv_mongo cluster ips")
           sys.exit(1)
    

def handle_bigdatafile(handle_status):
    if handle_status == 'remove':
        _command = "sudo rm -rf /data/install/bigdata_version"
    else:
        _command = "sudo touch /data/install/bigdata_version"    
    status, output = commands.getstatusoutput(_command)
    if status != 0:
        print(output)
        print(_command + "Command execution failure!")
        sys.exit(1)


#卸载微隔离时修改ip_template.json和ip.json
def del_ms_template():
    template_path = __FILE_ABS_PATH + "/" + __IP_TEMPLATE
    __IP_CONF = json.load(file(template_path))
    cmd = "sudo grep mongo_ms_srv_mongod ip_template.json|awk -F ':' '{print $1}'|awk -F '\"' '{print $2}'"
    ms_mongo_lists = exec_ssh_cmd_withresult('127.0.0.1',cmd)
    if len(ms_mongo_lists) != 0:
    # 设置换行为string的分隔符
        ms_mongo_lists = ms_mongo_lists.rstrip().split('\n')
        for ms_mongo_list in ms_mongo_lists:
            del __IP_CONF[ms_mongo_list]
    __IP_CONF['db_mongo_ms_srv'] = "127.0.0.1"
    __IP_CONF['db_mongo_ms_srv_cluster'] = "127.0.0.1"
    __IP_CONF['java_ms-srv'] = "127.0.0.1"
    __IP_CONF['java_ms-srv_cluster'] = "127.0.0.1"
    print(json.dumps(__IP_CONF, indent = 4, sort_keys = True))
    with open(template_path, "w+") as f:
        f.write(json.dumps(__IP_CONF, indent = 4, sort_keys = True))
    os.system("cp -f %s /data/app/www/titan-web/config_scripts/ip.json"%(template_path))            


def main(argv):
    global php
    global java
    global docker
    global connect
    global java_mongo_db
    global ms_srv_momgo_db
    global ENABLE_DOCKER_SCAN
    global ENABLE_ANTI_VIRUS
    global ENABLE_BIGDATA
    global ENABLE_THP
    global ENABLE_MS_SRV
    global ENABLE_EVENT_SRV
    global bigdata
    global cluster_number

    global check_base
    global add_bigdata
    global del_ms_ip
    global number
    try:
        opts, args = getopt.getopt(argv, "n:", ["number=", "php=", "java=", "connect=", "java_mongo_db=","ms_srv_momgo_db=", "bigdata=", "docker-enable=", "docker=", "cluster=", "check_base", "add_bigdata_info", "del_ms_ip"])
    except getopt.GetoptError:
        help()
    for opt, arg in opts:
        if opt in ("-n", "--number"):
            number = arg
        elif opt == "--php":
            php = arg
        elif opt == "--java":
            java = arg
        elif opt == "--docker":
            docker = arg
        elif opt == "--connect":
            connect = arg
        elif opt == "--java_mongo_db" or opt == "--ms_srv_momgo_db":
            db = arg
        elif opt == "--bigdata":
            bigdata = arg
            ENABLE_BIGDATA = True
        elif opt == "--docker-enable":
            if arg in ("Y", "y", "yes", "Yes", "YES"):
                ENABLE_DOCKER_SCAN = True
            else:
                ENABLE_DOCKER_SCAN = False
        elif opt == "--cluster":
            cluster_number = arg
        elif opt == "--check_base":
            check_base = True
        elif opt == "--add_bigdata_info":
            add_bigdata = True
        elif opt == "--del_ms_ip":
            del_ms_ip = True
        else:
            help()
            exit(1)
    #  use --check_base to check all base service
    if check_base:   
        check_all_base()
        exit(0)
    if add_bigdata:
        handle_bigdatafile('remove')
        check_license()
        standalone_add_bigdata()
        print json.dumps(__IP_CONF, indent = 4, sort_keys = True)
        save_user_input()
        handle_bigdatafile('add')
        exit(0)
    if del_ms_ip:
        del_ms_template()
        exit(0)

    web_install = False
    
    #romove /data/install/bigdata_vesrion
    handle_bigdatafile('remove')
    # if php is set means web install, else install use command , need check license file
    if php is None:
        check_license()
    else:
        web_install = True
    if php is not None:
        standalone_four(False)
    elif '1' == number:
        check_license_status(True)
        standalone_one()
    elif '2' == number:
        check_license_status(False)
        standalone_one()     
    elif number in ['4']:
        check_license_status(True)
        standalone_four()
    elif number in ['6']:
        check_license_status(True)
        set_mongo_info() 
        standalone_four()
    elif number in ['5']:
        check_license_status(False)
        standalone_four()
    elif number in ['10', '7']:
        check_license_status(False)
        set_mongo_info()
        standalone_four()
    elif '3' == cluster_number:
        check_license_status(True)
        standalone_cluster_3()
    elif '6' == cluster_number:
        if ENABLE_EVENT_SRV or ENABLE_MS_SRV:
            standalone_cluster_3()
        else:
            standalone_cluster_6()
    elif '9' == cluster_number:
        if ENABLE_EVENT_SRV or ENABLE_MS_SRV:
            standalone_cluster_6()
        else:
            standalone_cluster_9()
    elif '15' == cluster_number:
        if ENABLE_EVENT_SRV or ENABLE_MS_SRV:
            standalone_cluster_9()
        else:
            standalone_cluster_15()
    elif '21' == cluster_number:
        check_license_status(False)
        standalone_cluster_15()
    else:
        standalone_by_role()

    print json.dumps(__IP_CONF, indent = 4, sort_keys = True)
    # check base service before install app
    if not web_install:
        check_all_base()

    save_user_input()


if __name__ == '__main__':
    main(sys.argv[1:])
