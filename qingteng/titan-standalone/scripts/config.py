#! /usr/bin/python

import json
import os
import sys
import getopt
import re
from config_helper import *
from deploy_config import config_by_deploy

# macro
DEFAULT_SH_PORT = 7788

ENABLE_CONSOLE_HTTPS = None
ENABLE_BACKEND_HTTPS = None
ENABLE_AGENT_DOWNLOAD_HTTPS = None
ENABLE_API_HTTPS = None

IGNORE_CONFIG = False
ENABLE_MONGODB_CLUSTER = None
ENABLE_MS_MONGODB_CLUSTER = None
ENABLE_BIGDATA = None
ENABLE_THP = None
ENABLE_DOCKER_SCAN = None
ENABLE_MS_SRV = None
ENABLE_EVENT_SRV = None

CONFIG_SYSLOG = True

NGINX_CONSOLE_PORT = None
NGINX_BACKEND_PORT = None
NGINX_INNERAPI_PORT = 8000
NGINX_API_PORT = None
NGINX_AGENT_DOWNLOAD_PORT = None
FOR_INSTALL_OR_UPGRADE = None      # 0 for install, 1 for upgrade, 2 for other usage
UPGRADE_NORMAL_TO_CLUSTER = None

CUSTOMIZE = {
"mysql":{
    "port": 3306, 
    "user": "root"
},
"mongo":{
    "port": 27017, 
    "user": "qingteng"
},
"ms_mongo":{
    "port": 27017, 
    "user": "qingteng"
},
"redis_erlang":{
    "port": 6379
},
"redis_php":{
    "port": 6380
},
"redis_java":{
    "port": 6381
}
}

def default_java_config():
    return {"redis": {"ip": "127.0.0.1", "port": 6381, "password": "9pbsoq6hoNhhTzl"},
            "innerapi": {"ip": "127.0.0.1", "port": 8000},
            "api": {"ip": "127.0.0.1", "port": NGINX_API_PORT, "scheme": ""},
            "mongodb": {"ip": "127.0.0.1", "user": "qingteng", "password": "9pbsoq6hoNhhTzl"},
            "ms_mongodb": {"ip": "127.0.0.1", "user": "qingteng", "password": "9pbsoq6hoNhhTzl"},
            "rabbitmq": {"ip": "127.0.0.1"},
            "mysql": {"ip": "127.0.0.1", "port": 3306, "user": "root", "password":"9pbsoq6hoNhhTzl"},
            "kafka": {"ip": "127.0.0.1", "port": 9092},
            "console": {"ip": "127.0.0.1", "port": 80, "scheme": ""},
            "syslog": {"ip": "", "port": 514},
            "user-srv": {"privateip": "127.0.0.1", "port": 6120},
            "upload-srv": {"privateip": "127.0.0.1", "port": 6130},
            "bigdata_viewer": {"privateip": "127.0.0.1", "port": 80},
            "bigdata_logstash": {"privateip": "127.0.0.1", "port": 11112}}

# install cron for log collection
def install_cron(sync_to_java = None):
    PWD = os.path.dirname(os.path.abspath(__file__))
    print("install_cron")
    # install crontab
    cmd = "crontab -l > " + PWD + "/titan.cron.tmp"
    os.system(cmd)
    cmd = "grep -v 'titan_system_check.py' " + PWD + "/titan.cron.tmp | grep -v titan_collect_logs | grep -v agent_monitor_db_clean > " + PWD + "/titan.cron "
    os.system(cmd)
    cmd = "rm " + PWD + "/titan.cron.tmp"
    os.system(cmd)
    os.system("mkdir -p /data/titan-logs/monitor/")

    cmd = "echo '1 0 * * *  " + PWD + "/agent_monitor_db_clean.sh' >> " + PWD + "/titan.cron"
    os.system(cmd)
    # cron job to generate weekly system check report (weekly, Monday 00:01:00)
    cmd = "echo '1 0 * * 1  " + PWD + "/titan_system_check.py -a -t8 >> /data/titan-logs/monitor/system_status_`date +\"\%Y\%m\%d\"`.log 2>&1' >> " + PWD + "/titan.cron"
    os.system(cmd)
    # cron job to send weekly system check report to admin email, using smtp configuration in /data/app/www/titan-web/conf/build.json (weekly, Monday 01:01:00)
    cmd = "echo '1 1 * * 1  " + PWD + "/titan_system_check.py --sendmail=/data/titan-logs/monitor/system_status_`date +\"\%Y\%m\%d\"`.log >> /data/titan-logs/monitor/email_notify_`date +\"\%Y\%m\%d\"`.log 2>&1' >> " + PWD + "/titan.cron"
    os.system(cmd)
    # cron job to compress daily logs (daily 12:00:00)
    #cmd = "echo '0 20 * * *  " + PWD + "/titan_system_check.py --compress-log' >> " + PWD + "/titan.cron"
    #os.system(cmd)
    # cron job to trim log (weekly, Saturday 5:00:00)
    cmd = "echo '0 5 * * 6  " + PWD + "/titan_system_check.py --trim-log >> /data/titan-logs/monitor/trim_log_`date +\"\%Y\%m\%d\"`.log 2>&1' >> " + PWD + "/titan.cron"
    os.system(cmd)

    # cron job to send patrol log to Java server using HTTP Post (5 minutes)
    cmd = "echo '*/5 * * * * " + PWD + "/titan_system_check.py -p --post-to-java >> /data/titan-logs/monitor/post_to_java_`date +\"\%Y\%m\%d\"`.log 2>&1' >> " + PWD + "/titan.cron"
    os.system(cmd)

    global v
    if sync_to_java is None:
        # cron job to generate system status json file and copy to java server (1 minute)
        print ("Whether sync Titan system status to Java server every 1 minute? default is N")
        print ("Enter [N/y]: ")
        v = get_input("N")

    v = sync_to_java
    if v == "y" or v == "Y" or v == "Yes" or v == "YES":
        cmd = "echo '* * * * * " + PWD + "/titan_system_check.py -p -o " + PWD + "/system_status.json --copy-to-java >> /data/titan-logs/monitor/copy_to_java_`date +\"\%Y\%m\%d\"`.log 2>&1' >> " + PWD + "/titan.cron"
        os.system(cmd)

    cmd = '''head -n 3 ''' + PWD + '''/titan.cron | grep -q SHELL= || sed -i '1i\\SHELL=/bin/bash\\nPATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/java/default/bin:/usr/local/sbin:/usr/local/bin\\nMAILTO=root\\n' ''' + PWD + "/titan.cron"
    os.system(cmd)

    #cmd = "crontab " + PWD + "/titan.cron"
    #os.system(cmd)
    #os.system("crontab -l")

def update_config():
    """ Update config file based on ip_template.json
    1. load config file from remote server
    2. update the value of config files
    3. upload the new config files to remote servers
    :return:
    """
    global ENABLE_CONSOLE_HTTPS
    global ENABLE_BACKEND_HTTPS
    global ENABLE_AGENT_DOWNLOAD_HTTPS
    global ENABLE_API_HTTPS
    global IGNORE_CONFIG

    global NGINX_CONSOLE_PORT
    global NGINX_BACKEND_PORT
    global NGINX_INNERAPI_PORT
    global NGINX_API_PORT
    global NGINX_AGENT_DOWNLOAD_PORT
    global CUSTOMIZE

    global FOR_INSTALL_OR_UPGRADE

    retcode = 0
    # write the ip_config to ip.json
    f = open(ScriptPath + "/ip.json", "w+")
    f.write(json.dumps(ip_config, indent = 4, sort_keys = True))
    f.close()
    php_ips = get_service_ips("php_frontend_private")
    for php_ip in php_ips:
        scp_to_remote(ScriptPath + "/ip.json", php_ip, "/data/app/www/titan-web/config_scripts")

    # copy the PHP build.json from /data/app/www/titan-web/conf
    print ("copy the old config file from PHP server directory...\n")
    php_config_file = "/data/app/www/titan-web/conf/build.json"
    cmd = "cp " + php_config_file + " " + ScriptPath + "/build.json"
    os.system(cmd)
    
    # scp the config files from Connect to current directory
    # Connect olny have sh.json
    print ("copy the old config files from Connect-SH node...\n")
    connect_sh_config_directory = "/data/app/titan-config/sh.json"
    scp_from_remote(connect_sh_config_directory, ip_config["java_connect-sh"], ScriptPath + "/sh.json")

    try:
        print ("copy the old config files from Java Server...\n")
        java_config_directory = "/data/app/titan-config/java.json"
        #java_job_config_directory = "/data/app/titan-config/job.json"
        scp_from_remote(java_config_directory, ip_config["java"], ScriptPath + "/java.json")
        #scp_from_remote(java_job_config_directory, ip_config["java"], ScriptPath + "/job.json")
        java_config = json.load(file(ScriptPath + "/java.json"))
        #java_job_config = json.load(file(ScriptPath + "/job.json"))
    except Exception as e:
        print (str(e))
        print ("Get java.json from java server failed!")
        print ("Using default java.json.")
        java_config = default_java_config()

    php_config = json.load(file(ScriptPath + "/build.json"))

####################################################################################
    if ip_config["java_connect-sh_public"] == "":
        ip_config["java_connect-sh_public"] = ip_config["java_connect-sh"]
    if ip_config["java_connect-selector_public"] == "":
        ip_config["java_connect-selector_public"] = ip_config["java_connect-selector"]

################### random passwd and encrypt configuration start ##################
    ENCRYPT_PASSWD_DICT = {}

    if FOR_INSTALL_OR_UPGRADE == "0":
        # for install
        pbeconfig = randomString(32)
        pbepwd = pbeconfig[:16]
        pbesalt = pbeconfig[16:]

        db_pwd = randomString(16)      #  also for rabbitmq
        redis_pwd = randomString(16)   #  also for kafka
        zk_pwd = randomString(16)
        es_pwd = randomString(16)

        # default, redis/kafka use same password, mysql/mongo/rabbitmq use same password
        
        passwd_dict = { "mysql": {"new_passwd":db_pwd}, "mongo":{"new_passwd":db_pwd}, 
                    "redis_java": {"new_passwd":redis_pwd},"ms_mongo":{"new_passwd":db_pwd},
                    "redis_php": {"new_passwd":redis_pwd},"redis_erlang": {"new_passwd":redis_pwd},
                    "kafka":{"new_passwd":redis_pwd},"rabbitmq":{"new_passwd":db_pwd},
                    "zookeeper": {"new_passwd": zk_pwd}, "es":{"new_passwd":es_pwd}}
        if not ENABLE_BIGDATA and not ENABLE_THP:
            del passwd_dict['es']
        if not ENABLE_MS_SRV:
            del passwd_dict['ms_mongo']

        if IGNORE_CONFIG:
            print("use random password for install")
        else:
            passwd_dict = check_customize_for_install_from_cmd(passwd_dict, CUSTOMIZE)
            print("INFO: password param for install is: \n"+ json.dumps(passwd_dict,sort_keys=True, indent=4))
            get_input("","Please remeber these passwords, press Enter to continue")

        ENCRYPT_PASSWD_DICT["mongo"] = encrypt_string(pbepwd,pbesalt,passwd_dict["mongo"]["new_passwd"])
        ENCRYPT_PASSWD_DICT["mysql"] = encrypt_string(pbepwd,pbesalt,passwd_dict["mysql"]["new_passwd"])
        ENCRYPT_PASSWD_DICT["redis_java"] = encrypt_string(pbepwd,pbesalt,passwd_dict["redis_java"]["new_passwd"])
        ENCRYPT_PASSWD_DICT["redis_php"] = encrypt_string(pbepwd,pbesalt,passwd_dict["redis_php"]["new_passwd"])
        ENCRYPT_PASSWD_DICT["redis_erlang"] = encrypt_string(pbepwd,pbesalt,passwd_dict["redis_erlang"]["new_passwd"])
        ENCRYPT_PASSWD_DICT["kafka"] = encrypt_string(pbepwd,pbesalt,passwd_dict["kafka"]["new_passwd"])
        ENCRYPT_PASSWD_DICT["rabbitmq"] = encrypt_string(pbepwd,pbesalt,passwd_dict["rabbitmq"]["new_passwd"])
        if ENABLE_BIGDATA or ENABLE_THP:
            ENCRYPT_PASSWD_DICT["es"] = encrypt_string(pbepwd,pbesalt,passwd_dict["es"]["new_passwd"])
        if ENABLE_MS_SRV:
            ENCRYPT_PASSWD_DICT["ms_mongo"] = encrypt_string(pbepwd,pbesalt,passwd_dict["ms_mongo"]["new_passwd"])

        # reset password for install if not customized
        if not passwd_dict['mongo'].get('customized', False):
            reset_mongo_pwd(passwd_dict['mongo']["new_passwd"],'mongo_java')
        if ENABLE_MS_SRV:
            if not passwd_dict['ms_mongo'].get('customized', False):
                reset_mongo_pwd(passwd_dict['ms_mongo']["new_passwd"],'mongo_ms_srv')
        if not passwd_dict['mysql'].get('customized', False):
            reset_mysql_pwd(passwd_dict['mysql']["new_passwd"])
            update_exist_user_for_install(pbeconfig, passwd_dict["mysql"]["new_passwd"])
        for redis_srv in ['redis_java','redis_php','redis_erlang']:
            if not passwd_dict[redis_srv].get('customized', False):
                reset_redis_pwd(passwd_dict[redis_srv]["new_passwd"], redis_srv)
        if not passwd_dict['rabbitmq'].get('customized', False):
            reset_rabbitmq_pwd(passwd_dict['rabbitmq']["new_passwd"])
        # kafka and zk now not support customized
        reset_zk_kafka_pwd(passwd_dict['zookeeper']["new_passwd"], passwd_dict['kafka']["new_passwd"])
        #if not passwd_dict['es'].get('customized', False)
        #    reset_es_pwd(passwd_dict['es']["new_passwd"])
        # kafka and zk now not support customized
        #reset_zk_kafka_pwd(passwd_dict['zookeeper']["new_passwd"], passwd_dict['kafka']["new_passwd"])

    elif FOR_INSTALL_OR_UPGRADE == "1":
        old_javaconfig = get_backup_javajson()
        old_pbeconfig = old_javaconfig["base"].get("pbeconfig",None)
        old_mongo_pwd = old_javaconfig["mongodb"]["password"]
        old_mysql_pwd = old_javaconfig["mysql"]["password"]
        old_redis_java_pwd = old_javaconfig["redis"]["java"]["password"]
        old_redis_php_pwd = old_javaconfig["redis"]["php"]["password"]
        old_redis_erl_pwd = old_javaconfig["redis"]["erl"]["password"]
        old_kafka_pwd = old_javaconfig["kafka"].get("password",'')
        old_rabbitmq_pwd = old_javaconfig["rabbitmq"].get("password",'')

        zk_pwd = get_zk_pwd()

        if 'ms_mongodb' in old_javaconfig.keys() :
            old_ms_mongo_pwd = old_javaconfig["ms_mongodb"]["password"]
        else:
            old_ms_mongo_pwd = randomString(16)

        if is_encrypted(old_mysql_pwd) and old_pbeconfig :
            # old version had encrypted, just use old config 
            print("Already encrypted, use old config")
            pbeconfig = old_pbeconfig
            ENCRYPT_PASSWD_DICT["mongo"] = old_mongo_pwd
            ENCRYPT_PASSWD_DICT["mysql"] = old_mysql_pwd
            ENCRYPT_PASSWD_DICT["redis_java"] = old_redis_java_pwd
            ENCRYPT_PASSWD_DICT["redis_php"] = old_redis_php_pwd
            ENCRYPT_PASSWD_DICT["redis_erlang"] = old_redis_erl_pwd
            ENCRYPT_PASSWD_DICT["kafka"] = old_kafka_pwd
            ENCRYPT_PASSWD_DICT["rabbitmq"] = old_rabbitmq_pwd

            if ENABLE_MS_SRV:
                ENCRYPT_PASSWD_DICT["ms_mongo"] = old_ms_mongo_pwd

            # upgrade from web maybe install redis,kafka,zookeeper,rabbitmq again, so check if password match, if not match, reset again 
            pbepwd = pbeconfig[:16]
            pbesalt = pbeconfig[16:]
            # redis maybe use customized, os check and confirm for redis
            if IGNORE_CONFIG or checkif_redis_managed("redis_java"):
                redis_java_plainpwd = decrypt_string(pbepwd, pbesalt, old_redis_java_pwd)
                if redis_java_plainpwd and not check_redis_passwd("redis_java", redis_java_plainpwd):
                    reset_redis_pwd(redis_java_plainpwd, "redis_java")
            if IGNORE_CONFIG or checkif_redis_managed("redis_php"):
                redis_php_plainpwd = decrypt_string(pbepwd, pbesalt, old_redis_php_pwd)
                if redis_php_plainpwd and not check_redis_passwd("redis_php", redis_php_plainpwd):
                    reset_redis_pwd(redis_php_plainpwd, "redis_php")
            if IGNORE_CONFIG or checkif_redis_managed("redis_erlang"):
                redis_erl_plainpwd = decrypt_string(pbepwd, pbesalt, old_redis_erl_pwd)
                if redis_erl_plainpwd and not check_redis_passwd("redis_erlang", redis_erl_plainpwd):
                    reset_redis_pwd(redis_erl_plainpwd, "redis_erlang")

            kafka_plainpwd = decrypt_string(pbepwd, pbesalt, old_kafka_pwd)
            if zk_pwd != '' and check_zk_pwd():
                if kafka_plainpwd and not check_kafka_passwd(kafka_plainpwd):
                    reset_kafka_pwd(kafka_plainpwd,zk_pwd)
            else:
                zk_pwd = randomString(16)
                reset_zk_kafka_pwd(zk_pwd, kafka_plainpwd)

            rabbit_plainpwd = decrypt_string(pbepwd, pbesalt, old_rabbitmq_pwd)
            if rabbit_plainpwd and not check_rabbitmq_passwd(rabbit_plainpwd):
                reset_rabbitmq_pwd(rabbit_plainpwd)
            
            # if upgrade cluster from normal, will need reset database password
            if UPGRADE_NORMAL_TO_CLUSTER:
                mongo_plainpwd = decrypt_string(pbepwd, pbesalt, old_mongo_pwd)
                if mongo_plainpwd and not check_mongo_passwd(mongo_plainpwd,'mongo_java'):
                    reset_mongo_pwd(mongo_plainpwd,'mongo_java')
                    
                mysql_plainpwd = decrypt_string(pbepwd, pbesalt, old_mysql_pwd)
                if mysql_plainpwd and not check_mysql_passwd(mysql_plainpwd):
                    reset_mysql_pwd(mysql_plainpwd)
                
            if ENABLE_MS_SRV:
                # ENCRYPT_PASSWD_DICT["ms_mongo"] = old_ms_mongo_pwd
                ms_mongo_plainpwd = decrypt_string(pbepwd, pbesalt, old_ms_mongo_pwd)
                if ms_mongo_plainpwd and not check_mongo_passwd(ms_mongo_plainpwd,'mongo_ms_srv'):
                    reset_mongo_pwd(ms_mongo_plainpwd,'mongo_ms_srv')

        else:  #old is not encrypted, just encrypt, not operation database
            pbeconfig = randomString(32)
            pbepwd = pbeconfig[:16]
            pbesalt = pbeconfig[16:]

            ENCRYPT_PASSWD_DICT["mongo"] = encrypt_string(pbepwd,pbesalt,old_mongo_pwd)
            ENCRYPT_PASSWD_DICT["mysql"] = encrypt_string(pbepwd,pbesalt,old_mysql_pwd)
            ENCRYPT_PASSWD_DICT["redis_java"] = encrypt_string(pbepwd,pbesalt,old_redis_java_pwd)
            ENCRYPT_PASSWD_DICT["redis_php"] = encrypt_string(pbepwd,pbesalt,old_redis_php_pwd)
            ENCRYPT_PASSWD_DICT["redis_erlang"] = encrypt_string(pbepwd,pbesalt,old_redis_erl_pwd)
            ENCRYPT_PASSWD_DICT["kafka"] = encrypt_string(pbepwd,pbesalt,old_kafka_pwd)
            ENCRYPT_PASSWD_DICT["rabbitmq"] = encrypt_string(pbepwd,pbesalt,old_rabbitmq_pwd)

            if ENABLE_MS_SRV:
                ENCRYPT_PASSWD_DICT["ms_mongo"] = encrypt_string(pbepwd,pbesalt,old_ms_mongo_pwd)

            if zk_pwd == '' or not check_zk_pwd():
                zk_pwd = randomString(16)
                reset_zk_kafka_pwd(zk_pwd, old_kafka_pwd)

        put_zk_client_jaas_tojava(zk_pwd)

    else: # other usage, do not change encrypt configuration
        print("For other usage, will not change password configuration")
        php_config,java_config = load_current_config()
        pbeconfig = java_config["base"]["pbeconfig"]
        ENCRYPT_PASSWD_DICT["mongo"] = java_config["mongodb"]["password"]
        ENCRYPT_PASSWD_DICT["mysql"] = java_config["mysql"]["password"]
        ENCRYPT_PASSWD_DICT["redis_java"] = java_config["redis"]["java"]["password"]
        ENCRYPT_PASSWD_DICT["redis_php"] = java_config["redis"]["php"]["password"]
        ENCRYPT_PASSWD_DICT["redis_erlang"] = java_config["redis"]["erl"]["password"]
        ENCRYPT_PASSWD_DICT["kafka"] = java_config["kafka"]["password"]
        ENCRYPT_PASSWD_DICT["rabbitmq"] = java_config["rabbitmq"]["password"]
        if ENABLE_MS_SRV:
            ENCRYPT_PASSWD_DICT["ms_mongo"] = java_config["ms_mongodb"]["password"]
    # restore old Dynamic configuration
    if FOR_INSTALL_OR_UPGRADE == "1":
        for immutable_field in  java_config.get("immutable_fields").split(","):
            ChangeKeyToValues(java_config, old_javaconfig, immutable_field.split("."))

    # restore old nginx port and ssl
    if FOR_INSTALL_OR_UPGRADE == "1":
        ENABLE_CONSOLE_HTTPS = old_javaconfig["host"]["frontend"]["ssl"]
        ENABLE_BACKEND_HTTPS = old_javaconfig["host"]["backend"]["ssl"]
        ENABLE_AGENT_DOWNLOAD_HTTPS = old_javaconfig["host"]["agent"]["ssl"]
        ENABLE_API_HTTPS = old_javaconfig["host"]["api"]["ssl"]

        NGINX_CONSOLE_PORT = old_javaconfig["host"]["frontend"]["port"]
        NGINX_BACKEND_PORT = old_javaconfig["host"]["backend"]["port"]
        NGINX_API_PORT = old_javaconfig["host"]["api"]["port"]
        NGINX_AGENT_DOWNLOAD_PORT = old_javaconfig["host"]["agent"]["port"]

    php_config["pbe"]["config"] = pbeconfig
    ## update the old configuration with the new IPs.
    # update the website Frontend's IP in build.json
    php_config["host"]["frontend"]["privateip"] = ip_config["php_frontend_private"]
    php_config["host"]["frontend"]["publicip"] = ip_config["php_frontend_public"]
    php_config["host"]["frontend"]["domain"] = ip_config["php_frontend_domain"]
    if ip_config["php_frontend_domain"].strip() == '':
        php_config["host"]["frontend"]["resolved"] = False
    else:
        php_config["host"]["frontend"]["resolved"] = True
    if NGINX_CONSOLE_PORT is not None:
        php_config["host"]["frontend"]["port"] = NGINX_CONSOLE_PORT
    if ENABLE_CONSOLE_HTTPS is not None:
        php_config["host"]["frontend"]["ssl"] = ENABLE_CONSOLE_HTTPS

    # update the website Backend's IP in build.json
    php_config["host"]["backend"]["privateip"] = ip_config["php_backend_private"]
    php_config["host"]["backend"]["publicip"] = ip_config["php_backend_public"]
    php_config["host"]["backend"]["domain"] = ip_config["php_backend_domain"]
    if NGINX_BACKEND_PORT is not None:
        php_config["host"]["backend"]["port"] = NGINX_BACKEND_PORT
    if ip_config["php_backend_domain"].strip() == '':
        php_config["host"]["backend"]["resolved"] = False
    else:
        php_config["host"]["backend"]["resolved"] = True

    if ENABLE_BACKEND_HTTPS is not None:
        php_config["host"]["backend"]["ssl"] = ENABLE_BACKEND_HTTPS

    # update the website Api's IP in build.json
    php_config["host"]["api"]["privateip"] = ip_config["php_api_private"]
    php_config["host"]["api"]["publicip"] = ip_config["php_api_public"]
    php_config["host"]["api"]["domain"] = ip_config["php_api_domain"]
    if NGINX_API_PORT is not None:
        php_config["host"]["api"]["port"] = NGINX_API_PORT
    if ip_config["php_api_domain"].strip() == '':
        php_config["host"]["api"]["resolved"] = False
    else:
        php_config["host"]["api"]["resolved"] = True
    if ENABLE_API_HTTPS is not None:
        php_config["host"]["api"]["ssl"] = ENABLE_API_HTTPS

    # update the website Agent's IP in build.json
    php_config["host"]["agent"]["privateip"] = ip_config["php_agent_private"]
    php_config["host"]["agent"]["publicip"] = ip_config["php_agent_public"]
    php_config["host"]["agent"]["domain"] = ip_config["php_agent_domain"]
    if NGINX_AGENT_DOWNLOAD_PORT is not None:
        php_config["host"]["agent"]["port"] = NGINX_AGENT_DOWNLOAD_PORT
    if ip_config["php_agent_domain"].strip() == '':
        php_config["host"]["agent"]["resolved"] = False
    else:
        php_config["host"]["agent"]["resolved"] = True
    if ENABLE_AGENT_DOWNLOAD_HTTPS is not None:
        php_config["host"]["agent"]["ssl"] = ENABLE_AGENT_DOWNLOAD_HTTPS

    # update the website Download's IP in build.json
    php_config["host"]["download"]["privateip"] = ip_config["php_download_private"]
    php_config["host"]["download"]["publicip"] = ip_config["php_download_public"]
    php_config["host"]["download"]["domain"] = ip_config["php_download_domain"]
    if NGINX_AGENT_DOWNLOAD_PORT is not None:
        php_config["host"]["download"]["port"] = NGINX_AGENT_DOWNLOAD_PORT
    if ip_config["php_download_domain"].strip() == '':
        php_config["host"]["download"]["resolved"] = False
    else:
        php_config["host"]["download"]["resolved"] = True
    if ENABLE_AGENT_DOWNLOAD_HTTPS is not None:
        php_config["host"]["download"]["ssl"] = ENABLE_AGENT_DOWNLOAD_HTTPS

    # update the website Innerapi's IP in build.json
    php_config["host"]["innerapi"]["privateip"] = ip_config["php_inner_api"]
    php_config["host"]["innerapi"]["domain"] = ip_config["php_inner_api_domain"]

    # add all java ips
    inner_ip_set = set()
    innerapi_services = ["java","java_gateway","java_user-srv","java_detect-srv","java_scan-srv","java_upload-srv","java_connect-agent","java_connect-dh","java_connect-selector","java_connect-agent","php_frontend_private","java_ms-srv","java_event-srv"]
    for service_name in innerapi_services:
        inner_ip_set.add(ip_config.get(service_name,""))
        inner_ip_set.update(get_service_ips(service_name))
    inner_ip_set.add(ip_config.get("vip",""))
    inner_ip_set.discard("")
    inner_ip_set.discard("127.0.0.1")
    php_config["host"]["innerapi"]["clients"] = ",".join(inner_ip_set)

    # php use rabbitmq after 3.3.13
    if len(get_service_ips("erl_rabbitmq",ip_config)) > 1:
        php_config["rabbit"]["hosts"] = ip_config["erl_rabbitmq_cluster"]
    else:
        php_config["rabbit"]["hosts"] = ip_config["erl_rabbitmq"] + ":5672"
    if ENCRYPT_PASSWD_DICT["rabbitmq"] != '':
        php_config["rabbit"]["user"] = "guest"
        php_config["rabbit"]["password"] = ENCRYPT_PASSWD_DICT["rabbitmq"]
    else:
        php_config["rabbit"]["user"] = ""
        php_config["rabbit"]["password"] = ""

    php_config["host"]["innerapi"]["port"] = NGINX_INNERAPI_PORT
    if ip_config["php_inner_api_domain"].strip() == '':
        php_config["host"]["innerapi"]["resolved"] = False
        php_config["host"]["innerapi"]["ssl"] = False
    else:
        php_config["host"]["innerapi"]["resolved"] = True
        php_config["host"]["innerapi"]["ssl"] = False

    # update the Java's IP in build.json
    php_config["host"]["java"]["privateip"] = ip_config["java"]

    # update db config in build.json
    php_config["db"]["web"]["ip"] = ip_config["db_mysql_php"]
    php_config["db"]["web"]["port"] = CUSTOMIZE["mysql"]["port"] 
    php_config["db"]["web"]["user"] = CUSTOMIZE["mysql"]["user"]
    php_config["db"]["web"]["password"] = ENCRYPT_PASSWD_DICT["mysql"]

    php_config["db"]["agent_monitor"]["ip"] = ip_config["db_mysql_php"]
    php_config["db"]["agent_monitor"]["port"] = CUSTOMIZE["mysql"]["port"] 
    php_config["db"]["agent_monitor"]["user"] = CUSTOMIZE["mysql"]["user"]
    php_config["db"]["agent_monitor"]["password"] = ENCRYPT_PASSWD_DICT["mysql"]

    php_config["redis"]["web"]["ip"] = ip_config["db_redis_php"]
    php_config["redis"]["web"]["port"] = CUSTOMIZE["redis_php"]["port"]
    php_config["redis"]["web"]["password"] = ENCRYPT_PASSWD_DICT["redis_php"]

    php_config["redis"]["server"]["ip"] = ip_config["db_redis_erlang"]
    php_config["redis"]["server"]["port"] = CUSTOMIZE["redis_erlang"]["port"]
    php_config["redis"]["server"]["password"] = ENCRYPT_PASSWD_DICT["redis_erlang"]


    if len(get_service_ips("db_redis_php",ip_config)) > 1:
        php_config["redis"]["web"]["cluster_enabled"] = 1
        php_config["redis"]["web"]["cluster_seeds"] = ip_config["db_redis_php_cluster"]
    else:
        php_config["redis"]["web"]["cluster_enabled"] = 0

    if len(get_service_ips("db_redis_erlang",ip_config)) > 1: 
        php_config["redis"]["server"]["cluster_enabled"] = 1
        php_config["redis"]["server"]["cluster_seeds"] = ip_config["db_redis_erlang_cluster"]
    else:
        php_config["redis"]["server"]["cluster_enabled"] = 0
    #rsync ip_template.json connect-sh ip to sh.json
    config_sh()
    if FOR_INSTALL_OR_UPGRADE  == "0" or FOR_INSTALL_OR_UPGRADE == "1":
        config_job_srv()
        config_upload_srv(java_config)
        config_scan_srv(java_config)
        config_wisteria_cluster(java_config)
        config_ms_srv_cluster(java_config)
        config_event_srv_cluster(java_config)
        config_zookeeper()
        config_kafka_hosts()

        #when install or upgrade, generate rsa 
        login_rsa_private_key,login_rsa_public_key = create_rsa_key()
        java_config['app']['gateway']['login_rsa_private_key'] = login_rsa_private_key
        java_config['app']['gateway']['login_rsa_public_key'] = login_rsa_public_key
        # create random token for connect thrift
        java_config['app']['connect']['thrift_token'] = randomString(16)

    java_config["base"]["pbeconfig"] = pbeconfig
    java_config["mysql"]["ip"] = ip_config["db_mysql_php"]
    java_config["mysql"]["port"] = CUSTOMIZE["mysql"]["port"] 
    java_config["mysql"]["username"] = CUSTOMIZE["mysql"]["user"]
    java_config["mysql"]["password"] = ENCRYPT_PASSWD_DICT["mysql"]

    java_config["mongodb"]["ip"] = ip_config["db_mongo_java"]
    java_config["mongodb"]["port"] = CUSTOMIZE["mongo"]["port"] 
    java_config["mongodb"]["username"] = CUSTOMIZE["mongo"]["user"]
    java_config["mongodb"]["password"] = ENCRYPT_PASSWD_DICT["mongo"]

    if ENABLE_MS_SRV:
        java_config["ms_mongodb"]["ip"] = ip_config["db_mongo_ms_srv"]
        java_config["ms_mongodb"]["port"] = CUSTOMIZE["ms_mongo"]["port"] 
        java_config["ms_mongodb"]["username"] = CUSTOMIZE["ms_mongo"]["user"]
        java_config["ms_mongodb"]["password"] = ENCRYPT_PASSWD_DICT["ms_mongo"]

    java_config["redis"]["java"]["ip"] = ip_config["db_redis_java"]
    java_config["redis"]["java"]["port"] = CUSTOMIZE["redis_java"]["port"]
    java_config["redis"]["java"]["password"] = ENCRYPT_PASSWD_DICT["redis_java"]

    java_config["redis"]["php"]["ip"] = ip_config["db_redis_php"]
    java_config["redis"]["php"]["port"] = CUSTOMIZE["redis_php"]["port"]
    java_config["redis"]["php"]["password"] = ENCRYPT_PASSWD_DICT["redis_php"]

    java_config["redis"]["erl"]["ip"] = ip_config["db_redis_erlang"]
    java_config["redis"]["erl"]["port"] = CUSTOMIZE["redis_erlang"]["port"]
    java_config["redis"]["erl"]["password"] = ENCRYPT_PASSWD_DICT["redis_erlang"]

    java_config["rabbitmq"]["ip"] = ip_config["erl_rabbitmq"]
    if ENCRYPT_PASSWD_DICT["rabbitmq"] != '':
        java_config["rabbitmq"]["username"] = "guest"
        java_config["rabbitmq"]["password"] = ENCRYPT_PASSWD_DICT["rabbitmq"]
    else:
        java_config["rabbitmq"]["username"] = ""
        java_config["rabbitmq"]["password"] = ""
    
    java_config["kafka"]["ip"] = ip_config["java_kafka"]
    if ENCRYPT_PASSWD_DICT["kafka"] != '':
        java_config["kafka"]["auth_enable"] = True
        java_config["kafka"]["password"] = ENCRYPT_PASSWD_DICT["kafka"]
    else:
        java_config["kafka"]["auth_enable"] = False
        java_config["kafka"]["password"] = ''

    java_config["zookeeper"]["ip"] = ip_config["java_zookeeper"]
    if len(get_service_ips("java_zookeeper",ip_config)) > 1: 
        java_config["zookeeper"]["cluster"] = True
        java_config["zookeeper"]["clusterNodes"] = ip_config["java_zookeeper_cluster"]
    else:
        java_config["zookeeper"]["cluster"] = False

    if len(get_service_ips("java_zookeeper",ip_config)) > 1:
        java_config["kafka"]["cluster"] = True
        java_config["kafka"]["clusterNodes"] = ip_config["java_kafka_cluster"]
    else:
        java_config["kafka"]["cluster"] = False

    if len(get_service_ips("erl_rabbitmq",ip_config)) > 1:
        java_config["rabbitmq"]["cluster"] = True
        java_config["rabbitmq"]["clusterNodes"] = ip_config["erl_rabbitmq_cluster"]
    else:
        java_config["rabbitmq"]["cluster"] = False

    if len(get_service_ips("db_redis_java",ip_config)) > 1:
        java_config["redis"]["java"]["cluster"] = True
        java_config["redis"]["java"]["clusterNodes"] = ip_config["db_redis_java_cluster"]
    else:
        java_config["redis"]["java"]["cluster"] = False

    if len(get_service_ips("db_redis_erlang",ip_config)) > 1:   
        java_config["redis"]["erl"]["cluster"] = True
        java_config["redis"]["erl"]["clusterNodes"] = ip_config["db_redis_erlang_cluster"]
    else:
        java_config["redis"]["erl"]["cluster"] = False

    if len(get_service_ips("db_mysql_php",ip_config)) > 1: 
        java_config["mysql"]["cluster"] = True
        java_config["mysql"]["clusterNodes"] = ip_config["db_mysql_php_cluster"]
    else:
        java_config["mysql"]["cluster"] = False

    if len(get_service_ips("db_mongo_java",ip_config)) > 1:
        java_config["mongodb"]["cluster"] = True
        java_config["mongodb"]["clusterNodes"] = ip_config["db_mongo_java_cluster"]
    else:
        java_config["mongodb"]["cluster"] = False
    
    if len(get_service_ips("db_mongo_ms_srv",ip_config)) > 1:
        java_config["ms_mongodb"]["cluster"] = True
        java_config["ms_mongodb"]["clusterNodes"] = ip_config["db_mongo_ms_srv_cluster"]
    else:
        java_config["ms_mongodb"]["cluster"] = False

    java_config["host"]["frontend"]["privateip"] = ip_config["php_frontend_private"]
    java_config["host"]["frontend"]["publicip"] = ip_config["php_frontend_public"]
    java_config["host"]["frontend"]["domain"] = ip_config["php_frontend_domain"]
    if ip_config["php_frontend_domain"].strip() == '':
        java_config["host"]["frontend"]["resolved"] = False
    else:
        java_config["host"]["frontend"]["resolved"] = True
    if ENABLE_CONSOLE_HTTPS is not None:
        java_config["host"]["frontend"]["ssl"] = ENABLE_CONSOLE_HTTPS
    if NGINX_CONSOLE_PORT is not None:
        java_config["host"]["frontend"]["port"] = NGINX_CONSOLE_PORT


    java_config["host"]["backend"]["privateip"] = ip_config["php_backend_private"]
    java_config["host"]["backend"]["publicip"] = ip_config["php_backend_public"]
    java_config["host"]["backend"]["domain"] = ip_config["php_backend_domain"]
    if NGINX_BACKEND_PORT is not None:
        java_config["host"]["backend"]["port"] = NGINX_BACKEND_PORT
    if ip_config["php_backend_domain"].strip() == '':
        java_config["host"]["backend"]["resolved"] = False
    else:
        java_config["host"]["backend"]["resolved"] = True
    if ENABLE_BACKEND_HTTPS is not None:
        java_config["host"]["backend"]["ssl"] = ENABLE_BACKEND_HTTPS


    java_config["host"]["api"]["privateip"] = ip_config["php_api_private"]
    java_config["host"]["api"]["publicip"] = ip_config["php_api_public"]
    java_config["host"]["api"]["domain"] = ip_config["php_api_domain"]
    if NGINX_API_PORT is not None:
        java_config["host"]["api"]["port"] = NGINX_API_PORT
    if ip_config["php_api_domain"].strip() == '':
        java_config["host"]["api"]["resolved"] = False
    else:
        java_config["host"]["api"]["resolved"] = True
    if ENABLE_API_HTTPS is not None:
        java_config["host"]["api"]["ssl"] = ENABLE_API_HTTPS


    java_config["host"]["agent"]["privateip"] = ip_config["php_agent_private"]
    java_config["host"]["agent"]["publicip"] = ip_config["php_agent_public"]
    java_config["host"]["agent"]["domain"] = ip_config["php_agent_domain"]
    if NGINX_AGENT_DOWNLOAD_PORT is not None:
        java_config["host"]["agent"]["port"] = NGINX_AGENT_DOWNLOAD_PORT
    if ip_config["php_agent_domain"].strip() == '':
        java_config["host"]["agent"]["resolved"] = False
    else:
        java_config["host"]["agent"]["resolved"] = True
    if ENABLE_AGENT_DOWNLOAD_HTTPS is not None:
        java_config["host"]["agent"]["ssl"] = ENABLE_AGENT_DOWNLOAD_HTTPS


    java_config["host"]["download"]["privateip"] = ip_config["php_download_private"]
    java_config["host"]["download"]["publicip"] = ip_config["php_download_public"]
    java_config["host"]["download"]["domain"] = ip_config["php_download_domain"]
    if NGINX_AGENT_DOWNLOAD_PORT is not None:
        java_config["host"]["download"]["port"] = NGINX_AGENT_DOWNLOAD_PORT
    if ip_config["php_download_domain"].strip() == '':
        java_config["host"]["download"]["resolved"] = False
    else:
        java_config["host"]["download"]["resolved"] = True
    if ENABLE_AGENT_DOWNLOAD_HTTPS is not None:
        java_config["host"]["download"]["ssl"] = ENABLE_AGENT_DOWNLOAD_HTTPS

    # if upgrade from 330x, ip.json still have erl_channel config, then upload need use erl_channel
    # For historical reasons, at first upload use erlang, then use upload-srv,
    # If upgrade, need use old upload config
    if ip_config.has_key("erl_channel_private"): 
        java_config["host"]["upload"]["privateip"] = ip_config["erl_channel_private"]
        java_config["host"]["upload"]["publicip"] = ip_config["erl_channel_public"]
        java_config["host"]["upload"]["domain"] = ip_config["erl_channel_domain"]
    else:
        java_config["host"]["upload"]["privateip"] = ip_config["php_download_private"]
        java_config["host"]["upload"]["publicip"] = ip_config["php_download_public"]
        java_config["host"]["upload"]["domain"] = ip_config["php_download_domain"]

    if java_config["host"]["upload"]["domain"].strip() == '':
        java_config["host"]["upload"]["resolved"] = False
    else:
        java_config["host"]["upload"]["resolved"] = True

    if len(get_service_ips("java_connect-selector",ip_config)) > 1:
        java_config["host"]["selector"]["domain"] = ip_config["php_frontend_domain"]
        java_config["host"]["selector"]["publicip"] = ip_config["php_frontend_public"]
        java_config["host"]["selector"]["privateip"] = ip_config["php_frontend_private"]
        if ip_config["php_frontend_domain"].strip() == '' :
            java_config["host"]["selector"]["resolved"] = False
        else:
            java_config["host"]["selector"]["resolved"] = True
    else:
        java_config["host"]["selector"]["domain"] = ip_config["java_connect-selector_domain"]
        java_config["host"]["selector"]["publicip"] = ip_config["java_connect-selector_public"]
        java_config["host"]["selector"]["privateip"] = ip_config["java_connect-selector"]
        if ip_config["java_connect-selector_domain"].strip() == '' :
            java_config["host"]["selector"]["resolved"] = False
        else:
            java_config["host"]["selector"]["resolved"] = True


    java_config["host"]["connect"]["publicip"] = ip_config["java_connect-sh_public"]
    java_config["host"]["connect"]["privateip"] = ip_config["java_connect-sh"]
    java_config["host"]["connect"]["domain"] = ip_config["java_connect-selector_domain"]
    if ip_config["java_connect-sh_domain"].strip() == '':
        java_config["host"]["connect"]["resolved"] = False
    else:
        java_config["host"]["connect"]["resolved"] = True


    java_config["host"]["innerapi"]["privateip"] = ip_config["php_inner_api"]

    java_config["host"]["flask"]["privateip"] = ip_config["bigdata_viewer"]

    java_config["host"]["bigdata_viewer"]["privateip"] = ip_config["bigdata_viewer"]
    logstash_ips = get_service_ips("bigdata_logstash", ip_config)
    if len(logstash_ips) > 0:
        java_config["host"]["bigdata_consumer"]["privateip"] = logstash_ips[0]

    java_config["host"]["patrol"]["privateip"] = ip_config["java_patrol-srv"]

    if ENABLE_BIGDATA is True or os.path.exists('/data/install/bigdata_version') :
        java_config["app"]["wisteria"]["bigdata"]["enable"] = True
    elif ENABLE_BIGDATA is False:
        java_config["app"]["wisteria"]["bigdata"]["enable"] = False
    
    if ENABLE_THP is True and not ENABLE_BIGDATA :
        java_config["app"]["wisteria"]["thp"]["enable"] = True

    if ENABLE_DOCKER_SCAN is True:
        java_config["app"]["wisteria"]["docker_scan"]["enable"] = True
    elif ENABLE_DOCKER_SCAN is False:
        java_config["app"]["wisteria"]["docker_scan"]["enable"] = False

    if IGNORE_CONFIG is False:
        if ENABLE_MONGODB_CLUSTER:
            java_config["mongodb"]["cluster"] = ENABLE_MONGODB_CLUSTER
            java_config["mongodb"]["clusterNodes"] = ip_config["db_mongo_java_cluster"]
        else:
            java_config["mongodb"]["cluster"] = ENABLE_MONGODB_CLUSTER

        if ENABLE_MS_MONGODB_CLUSTER:
            java_config["ms_mongodb"]["cluster"] = ENABLE_MS_MONGODB_CLUSTER
            java_config["ms_mongodb"]["clusterNodes"] = ip_config["db_mongo_ms_srv_cluster"]
        else:
            java_config["ms_mongodb"]["cluster"] = ENABLE_MS_MONGODB_CLUSTER

    portSuffix = ""
    if ((java_config["host"]["frontend"]["port"] != 443 and java_config["host"]["frontend"]["ssl"] == True) or (java_config["host"]["frontend"]["port"] != 80 and java_config["host"]["frontend"]["ssl"] == False)):
        portSuffix = ":" + str(java_config["host"]["frontend"]["port"])

    php_ip_domains = set()
    php_ip_domains.update(get_service_ips("php_frontend_private"))
    php_ip_domains.update(get_service_ips("php_frontend_public"))
    php_ip_domains.add(ip_config["php_frontend_domain"])
    php_ip_domains.add(ip_config["vip"])
    php_ip_domains.add(ip_config["eip"])
    php_ip_domains.discard("")
    php_ip_domains.discard("127.0.0.1")

    refs=[]
    for php_ip_domain in php_ip_domains:
        refs.append("http://" + php_ip_domain + portSuffix)
        refs.append("https://" + php_ip_domain + portSuffix)
    
    java_config["app"]["gateway"]["refer_domains"] = ",".join(set(refs))

    if IGNORE_CONFIG is False:
        if CONFIG_SYSLOG:
            config_syslog_server(java_config)

    # restore old default_uname
    if FOR_INSTALL_OR_UPGRADE == "1" and java_config["app"]["user-srv"].get("default_uname",'') == '':
        old_defaul_uname = exec_ssh_cmd_withresult("", '''grep -rlE 'default_uname".*".+"' /data/backup/system* | grep java.json$ | xargs ls -t |head -n 1 | grep java.json$ | xargs cat |grep default_uname | cut -d: -f 2 | tr -d '", ' ''')
        if old_defaul_uname != '':
            java_config["app"]["user-srv"]["default_uname"] = old_defaul_uname
        else:
            zk_ips = get_service_ips("java_zookeeper")
            zk_ip = zk_ips[0]
            license_content = exec_ssh_cmd_withresult(zk_ip, '''/usr/local/qingteng/zookeeper/bin/zkCli.sh -server {zk_ip}:2181 get /license/license.key '''.format(zk_ip=zk_ip))
            if '"multi_user":"0"' in license_content:
                print("single user version, will set defualt_uname")

                pbeconfig = java_config["base"]["pbeconfig"]
                mysql_pwd = decrypt_string(pbeconfig[:16],pbeconfig[16:],ENCRYPT_PASSWD_DICT["mysql"]) 
                default_uname = get_default_uname_fromdb(mysql_pwd)
                if default_uname != "":
                    java_config["app"]["user-srv"]["default_uname"] = default_uname

    # restore old hq_node_secret_key
    if FOR_INSTALL_OR_UPGRADE == "1" and java_config["app"]["wisteria"].get("hq_node_secret_key",'') == '':
        old_hq_key = exec_ssh_cmd_withresult("", '''grep -rlE 'hq_node_secret_key".*".+"' /data/backup/system* | grep java.json$ | xargs ls -t |grep java.json$ |head -n 1 |xargs cat |grep hq_node_secret_key | cut -d: -f 2 | tr -d '", ' ''')
        if old_hq_key != '':
            java_config["app"]["wisteria"]["hq_node_secret_key"] = old_hq_key
    php_ips = get_php_ips()
    # change proxy of gateway for non cluster
    exec_ssh_cmd(list(php_ips)[0], '''sed -i -r 's#(http://).*(:6000)#\\1{JAVA_IP}\\2#g' /data/app/conf/nginx.servers.conf '''.format(JAVA_IP=ip_config["java"]))
    # change cluster nginx config
    config_host_for_cluster(php_config, java_config)
    config_php_glusterfs()
    if ENABLE_EVENT_SRV:
        config_event_topic()

    if ENABLE_MS_SRV:
        config_ms_topic()
    for php_ip in php_ips:
        if ENABLE_CONSOLE_HTTPS == True and ENABLE_BACKEND_HTTPS == True:
            enable_ssl(php_ip,"enable_console_https",NGINX_CONSOLE_PORT)
            enable_ssl(php_ip,"enable_backend_https",NGINX_BACKEND_PORT)
        elif ENABLE_CONSOLE_HTTPS == False and ENABLE_BACKEND_HTTPS == False:
            enable_ssl(php_ip,"disable_console_https",NGINX_CONSOLE_PORT)
            enable_ssl(php_ip,"disable_backend_https",NGINX_BACKEND_PORT)
        elif ENABLE_CONSOLE_HTTPS == True:
            enable_ssl(php_ip,"enable_console_https",NGINX_CONSOLE_PORT)
        elif ENABLE_CONSOLE_HTTPS == False:
            enable_ssl(php_ip,"disable_console_https",NGINX_CONSOLE_PORT)
        elif ENABLE_BACKEND_HTTPS == True:
            enable_ssl(php_ip,"enable_backend_https",NGINX_BACKEND_PORT)
        elif ENABLE_BACKEND_HTTPS == False:
            enable_ssl(php_ip,"disable_backend_https",NGINX_BACKEND_PORT)
        
        if ENABLE_AGENT_DOWNLOAD_HTTPS == True:
            enable_ssl(php_ip,"enable_agent_download_https",NGINX_AGENT_DOWNLOAD_PORT)
        elif ENABLE_AGENT_DOWNLOAD_HTTPS == False:
            enable_ssl(php_ip,"disable_agent_download_https",NGINX_AGENT_DOWNLOAD_PORT) 
        
        if ENABLE_API_HTTPS == True:
            enable_ssl(php_ip,"enable_api_https",NGINX_API_PORT)
        elif ENABLE_API_HTTPS == False:    
            enable_ssl(php_ip,"disable_api_https",NGINX_API_PORT)
        else:
            enable_ssl(php_ip,None,None)
    # other usage,for example, config syslog, switch https, no need change bigdata config
    if (ENABLE_BIGDATA or ENABLE_THP) and (FOR_INSTALL_OR_UPGRADE == "0" or FOR_INSTALL_OR_UPGRADE == "1"):
        logstash_ips = get_service_ips("bigdata_logstash", ip_config)
        if ENABLE_BIGDATA:
            viewer_ip = ip_config["bigdata_viewer"]
        es_ip = get_esins1_ips()
        es_ips = [_ip + ":9200" for _ip in es_ip]
        es_addrs = '","'.join(es_ips)
        es_ip_lists = ','.join(es_ips)
        _es_addr = get_esins1_ip()
        es_addr = _es_addr + ":9200"
        kafka_servers = ip_config["java_kafka"] + ":9092"
        kafka_cluster_servers = ip_config["java_kafka_cluster"]
        if kafka_cluster_servers != '' and kafka_cluster_servers != '127.0.0.1':
            kafka_servers = kafka_cluster_servers
        java_config["bigdata_es"]["ip"]=es_ip_lists
        # after 3.3.13 bigdata use yaml format config file
        logstash_conf = "/usr/local/qingteng/logstash/conf.d/QT_BDI_v1.conf"

        for logstash_ip in logstash_ips:
            _cmd = '''sed -i 's#hosts.*#hosts => ["{es_addr}"]#g' ''' + logstash_conf
            exec_ssh_cmd(logstash_ip, _cmd.format(es_addr=es_addrs))

            _cmd = '''sed -i 's#bootstrap_servers.*#bootstrap_servers => "{kafka_servers}"#g' ''' + logstash_conf
            exec_ssh_cmd(logstash_ip, _cmd.format(kafka_servers=kafka_servers))
            
            _cmd = '''sed -i 's#topics.*#topics => "bigdata_event"#g' ''' + logstash_conf
            exec_ssh_cmd(logstash_ip, _cmd)

            # config auth and password for bigdata logstash
            config_bigdata_kafka(logstash_ip, ENCRYPT_PASSWD_DICT["kafka"],pbeconfig)

        # start to config bigdata viewer
        if ENABLE_BIGDATA:
            viewer_conf = "/usr/local/qingteng/bigdata/qt_viewer/config.yml"
            _cmd = '''sed -i 's/^\s\{1,\}hosts:.*/  hosts: $es_addr/' ''' + viewer_conf
            exec_ssh_cmd(viewer_ip, _cmd.replace("$es_addr",es_addr))
            _cmd = '''sed -i 's#^\s\{1,\}comid_group_api:.*#  comid_group_api: http://$java_ip:6000/v1/bizgroup/comid_bizgroup#' ''' + viewer_conf
            if ip_config["vip"] != "127.0.0.1":
                exec_ssh_cmd(viewer_ip, _cmd.replace("$java_ip",ip_config["vip"]))
            else:
                exec_ssh_cmd(viewer_ip, _cmd.replace("$java_ip",ip_config["java"]))
            _cmd = '''sed -i 's#^\s\{1,\}upload_api:.*#  upload_api: http://$java_ip:6100/v1/bigdata/file/upload#' ''' + viewer_conf
            exec_ssh_cmd(viewer_ip, _cmd.replace("$java_ip",ip_config["java"]))
            _cmd = '''sed -i 's/^pbeconfig:.*/pbeconfig: {pbeconfig}/' ''' + viewer_conf
            exec_ssh_cmd(viewer_ip, _cmd.format(pbeconfig=pbeconfig))

        config_bigdata_topic()
        
        if FOR_INSTALL_OR_UPGRADE == "0":
            reset_bigdata_es_pwd(passwd_dict["es"]["new_passwd"], ENCRYPT_PASSWD_DICT["es"],pbeconfig)
            # execute bigdata script after reset elasticsearch password
            print("now wait elasticsearch to finish restart")
            java_config["bigdata_es"]["password"] = ENCRYPT_PASSWD_DICT["es"]
            time.sleep(10)
        else:
            if 'bigdata_es' in old_javaconfig.keys():
                old_es_pw = old_javaconfig['bigdata_es']['password']
            else:
                old_es_pw_cmd = '''grep -rlE '^es_pw:[ ]*([[:alnum:]]+)' /data/backup/system/ | grep consumer.yml$ | xargs ls -t |head -n 1 | grep consumer.yml$ |xargs cat |grep ^es_pw | cut -d ':' -f 2 '''
                old_es_pw = exec_ssh_cmd_withresult("", old_es_pw_cmd)
            if re.search( 'ENC\(', old_es_pw, re.M):
                old_pbepwd,old_pbesalt = old_pbeconfig[:16],old_pbeconfig[16:]
                old_es_pw = decrypt_string(old_pbepwd,old_pbesalt,old_es_pw)
            old_es_pw_encrypt = encrypt_string(pbepwd,pbesalt,old_es_pw)
            # old es passwd check ok , use old es password

            if check_es_passwd(old_es_pw):
                if old_es_pw == '':
                    write_logstash_espwd_conf(logstash_ips, "qingteng",pbeconfig)
                    if ENABLE_BIGDATA:
                        write_viewer_espwd_conf(viewer_ip, "qingteng")
                else: 
                    write_logstash_espwd_conf(logstash_ips, old_es_pw_encrypt,pbeconfig)
                    if ENABLE_BIGDATA:
                        write_viewer_espwd_conf(viewer_ip,  old_es_pw_encrypt)
                java_config["bigdata_es"]["password"] = old_es_pw_encrypt
                es_passwd = old_es_pw
            else:
                # check failed , reset es password
                new_es_pwd = randomString(16)
                new_es_pwd_encrypt = encrypt_string(pbepwd,pbesalt,new_es_pwd)
                reset_bigdata_es_pwd(new_es_pwd, new_es_pwd_encrypt,pbeconfig)
                # execute bigdata script after reset elasticsearch password
                print("now wait elasticsearch to finish restart")
                time.sleep(10)
                restart_logstash_viewer()
                java_config["bigdata_es"]["password"] = new_es_pwd_encrypt
                es_passwd = new_es_pwd
        wait_for_cmd_ok(_es_addr, '''ss -tuln|grep -n ':9200'| wc -l''', 120, '1')
        
        cmd = ScriptPath + "/change_es_template.sh" + " " + es_addr + " " + es_passwd
        print (cmd)
        os.system(cmd)
        # exec_ssh_cmd_withresult(logstash_ips[0], "/usr/local/qingteng/bigdata/bin/create_template.sh")
        # exec_ssh_cmd_withresult(logstash_ips[0], "/usr/local/qingteng/bigdata/bin/create_ilm.sh")
        # exec_ssh_cmd_withresult(logstash_ips[0], "/usr/local/qingteng/bigdata/bin/es_cluster_settings.sh")

    if FOR_INSTALL_OR_UPGRADE  == "0" or FOR_INSTALL_OR_UPGRADE == "1":
        config_by_deploy()
        cp_rabbitmq_cookie()

    # delete not used queues
    if FOR_INSTALL_OR_UPGRADE == "1":
        rabbit_ips = get_service_ips("erl_rabbitmq")
        exec_ssh_cmd_withresult(rabbit_ips[0], '''/data/app/titan-rabbitmq/bin/rabbitmqctl eval '{ok, Q} = rabbit_amqqueue:lookup(rabbit_misc:r(<<"/">>, queue, <<"wisteria:detect-srv:queue:event_virus">>)), rabbit_amqqueue:delete_crashed(Q).' ''', alarm_error=False)
        exec_ssh_cmd_withresult(rabbit_ips[0], '''/data/app/titan-rabbitmq/bin/rabbitmqctl eval '{ok, Q} = rabbit_amqqueue:lookup(rabbit_misc:r(<<"/">>, queue, <<"wisteria:detect-srv:queue:event.intrusion_detect.400004">>)), rabbit_amqqueue:delete_crashed(Q).' ''', alarm_error=False) 
        exec_ssh_cmd_withresult(rabbit_ips[0], '''/data/app/titan-rabbitmq/bin/rabbitmqctl eval '{ok, Q} = rabbit_amqqueue:lookup(rabbit_misc:r(<<"/">>, queue, <<"wisteria:detect-srv:queue:event_suspicious_proc_script">>)), rabbit_amqqueue:delete_crashed(Q).' ''', alarm_error=False)
    
    # config 34015 ocsconfig_key 
    ocsconfig_key = randomString(16).lower()
    if FOR_INSTALL_OR_UPGRADE == "0":
        java_config["app"]["detect"]["out_connect"]["ocsconfig"] = ocsconfig_key
    if FOR_INSTALL_OR_UPGRADE == "1":
        if old_javaconfig["app"]["detect"].get("out_connect",'') == '':
            java_config["app"]["detect"]["out_connect"]["ocsconfig"] = ocsconfig_key
        else:
            java_config["app"]["detect"]["out_connect"]["ocsconfig"] = old_javaconfig["app"]["detect"]["out_connect"]["ocsconfig"]

    
    write_new_config(php_config,java_config)    
    clean_tmp()
    return retcode

def config_event_topic():
    kafka_cmd_conf = get_kafka_cmd_conf()
    exists_topics = get_kafka_topics(kafka_cmd_conf)
    event_ips = get_service_ips("java_event-srv")
    for topic in ["bigdata_event","bigdata_event_statistical","MICRO-SEGMENTATION-EVENT","MICRO-SEGMENTATION-EVENT_statistical","EVENT_STATISTICAL_DETAIL","EVENT_STATISTICAL_DETAIL_KEY","tc_radar_event"]:
        if topic == "MICRO-SEGMENTATION-EVENT":
            # store 2 hour data
            ext_config = {"retention.ms": "7200000"}
            partition_num = 6
        else:
            # store 7 days data
            ext_config = {"retention.ms": "604800000"}
            partition_num = 3 * len(event_ips)
        config_kafka_topic(topic,partition_num,ext_config=ext_config,kafka_cmd_conf=kafka_cmd_conf,exists_topics=exists_topics)

def config_ms_topic():
    kafka_cmd_conf = get_kafka_cmd_conf()
    exists_topics = get_kafka_topics(kafka_cmd_conf)
    partition_num = 12
    # store 8 hour data
    ext_config = {"retention.ms": "28800000"}
    for topic in ["ms_access_relation"]:
        config_kafka_topic(topic,partition_num,ext_config=ext_config,kafka_cmd_conf=kafka_cmd_conf,exists_topics=exists_topics)

def config_bigdata_topic():
    kafka_cmd_conf = get_kafka_cmd_conf()
    exists_topics = get_kafka_topics(kafka_cmd_conf)

    logstash_ips = get_service_ips("bigdata_logstash")
    partition_num = 3 * len(logstash_ips)
    # QTEVENT store 3 days' data
    ext_config = {"retention.ms": "86400000"}
    for topic in ["QTEVENT"]:
        config_kafka_topic(topic,partition_num,ext_config=ext_config,kafka_cmd_conf=kafka_cmd_conf,exists_topics=exists_topics)


def config_syslog_server(java_config):

    try:
        ## Input the IP address and Port of the Syslog Server
        syslog_ip = get_input("", prompt="Please input the IP address of the Syslog Server, default is None\nEnter: ")
        syslog_port = get_input(str(java_config["syslog"]["port"]),
                                    prompt="Please input the Port of the Syslog Server, default is {0}\nEnter: ".format(java_config["syslog"]["port"]))

        if syslog_ip:
            _cmd = '''[ -z "`grep /var/log/qtalert.log /etc/rsyslog.conf`" ] && sed -i 's/#$ModLoad imudp/$ModLoad imudp/' /etc/rsyslog.conf && sed -i 's/#$UDPServerRun /$UDPServerRun /' /etc/rsyslog.conf && sed -i 's/$UDPServerRun [0-9]+/$UDPServerRun {syslog_port}/' /etc/rsyslog.conf && echo 'local6.*   /var/log/qtalert.log' > /etc/rsyslog.d/qingteng.conf && service rsyslog restart '''.format(syslog_port=syslog_port)
            exec_ssh_cmd(syslog_ip, _cmd)

            java_config["syslog"]["ip"] = syslog_ip.strip()
        if syslog_port:
            java_config["syslog"]["port"] = int(syslog_port.strip())

    except Exception as e:
        print (str(e))
        print ("[INFO] Ignore error if version is lite")


def checkif_redis_managed(redis_name):
    # check redis if is in qingteng host, not customized
    # if in qingteng host, we need check if redis password lost after upgrade
    # if customized, we can't check and reset password 
    redis_ips = get_service_ips("db_" + redis_name)
    server_ips = set()
    for srv_name in ["php_frontend_private", "java", "java_connect-agent"]:
        tmp_ips = get_service_ips(srv_name)
        server_ips.update(tmp_ips)

    redis_ip = redis_ips[0]
    if redis_ip in server_ips:
        return True
    # if redis is customized, we can't check
    if CUSTOMIZE.get(redis_name,{}).get("port") != redis_port_dict[redis_name]:
        return False

    print("Please confirm that if {redis_name} is CUSTOMIZE. default is Y".format(redis_name=redis_name))
    v = get_input("Y","Enter [Y/N]: ")
    if v == "y" or v == "Y" or v == "Yes" or v == "YES":
        return False
    else:
        return True

## Connect-sh
def config_sh():
    # load the old configuration
    connect_sh_config = json.load(file(ScriptPath + "/sh.json"))

    node = 1
    sh_ips = get_service_ips("java_connect-sh")
    sh_publicips = get_service_ips("java_connect-sh_public")
    connect_domain = ip_config["java_connect-sh_domain"]
    for ip in sh_ips:
        sh_ipv4 = ip
        if sh_publicips and len(sh_publicips) == len(sh_ips):
            sh_ipv4 = sh_publicips[node-1]
        connect_sh_config["connect_address"]["ipv4"] = sh_ipv4
        connect_sh_config["connect_address"]["domain"] = connect_domain

        connect_sh_config["node"] = node
        node=node+1

        # write the connect config
        f = open(ScriptPath + "/sh.json", "w+")
        f.write(json.dumps(connect_sh_config, indent = 4, sort_keys = True))
        f.close()

        #cp sh.json to sh node 
        scp_to_remote(ScriptPath + "/sh.json", ip, '/data/app/titan-config/sh.json')

def config_job_srv():
    _job_cmd='''sed -i -r '/node/s/:[^,]+/: {node}/' /data/app/titan-config/job.json'''
    node = 1
    job_ips = get_service_ips("java_job-srv")
    for ip in job_ips:
        exec_ssh_cmd(ip, _job_cmd.format(node=node))
        node=node+1

# if cluster, image_scan_layer_dir will use titan-dfs
def config_scan_srv(java_config):
    scan_ips = get_service_ips("java_scan-srv")
    if len(scan_ips) <= 1:
        return

    scan_ip = scan_ips[0]
    exec_ssh_cmd(scan_ip, "mkdir -p /data/app/titan-dfs/java/titan-scan/layer && chown -R titan:titan /data/app/titan-dfs/java/titan-scan/")
    java_config["app"]["scan"]["image_scan_layer_dir"] = "/data/app/titan-dfs/java/titan-scan/layer"

# if cluster, titan-ave and other some config will use titan-dfs
def config_upload_srv(java_config):
    upload_ips = get_service_ips("java_upload-srv")
    if len(upload_ips) <= 1:
        return

    upload_ip = upload_ips[0]
    # do not use -R, /data/app/titan-dfs/java may have too many files, -R will take long time
    exec_ssh_cmd(upload_ip, "mkdir -p /data/app/titan-dfs/java/titan-upload && chown titan:titan /data/app/titan-dfs && chown titan:titan /data/app/titan-dfs/java && chown titan:titan /data/app/titan-dfs/java/titan-upload && cp -r -f /data/app/titan-upload-srv/titan_ave /data/app/titan-dfs/java/titan-upload/ && chown -R titan:titan /data/app/titan-dfs/java/titan-upload/titan_ave")
    java_config["app"]["upload"]["avira_bin_path"] = "/data/app/titan-dfs/java/titan-upload/titan_ave/dist"

    exec_ssh_cmd(upload_ip, "mkdir -p /data/app/titan-dfs/java/titan-upload/root && chown -R titan:titan /data/app/titan-dfs/java/titan-upload/root")
    java_config["app"]["upload"]["root"] = "/data/app/titan-dfs/java/titan-upload/root"

    exec_ssh_cmd(upload_ip, "mkdir -p /data/app/titan-dfs/java/titan-upload/yara/rules && chown -R titan:titan /data/app/titan-dfs/java/titan-upload/yara")
    java_config["app"]["upload"]["yara_rule_path"] = "/data/app/titan-dfs/java/titan-upload/yara/rules"

# if cluster, titan-wisteria_file will use titan-dfs
def config_wisteria_cluster(java_config):
    java_ips = get_service_ips("java")
    if len(java_ips) <= 1:
        return

    java_config['base']['cluster'] = True
    java_ip = java_ips[0]
    exec_ssh_cmd(java_ip, "mkdir -p /data/app/titan-dfs/java/titan-wisteria/files && chown titan:titan /data/app/titan-dfs/java/titan-wisteria/ && chown -R titan:titan /data/app/titan-dfs/java/titan-wisteria/files")
    java_config["app"]["wisteria"]["file_service_file_dir"] = "/data/app/titan-dfs/java/titan-wisteria/files"
    exec_ssh_cmd(java_ip, "mkdir -p /data/app/titan-dfs/java/titan-wisteria/excellog/ && chown -R titan:titan /data/app/titan-dfs/java/titan-wisteria/excellog/")
    java_config["resolveExcel"] = java_config.get("resolveExcel",{})
    java_config["resolveExcel"]["excellog"] = "/data/app/titan-dfs/java/titan-wisteria/excellog/"

def config_ms_srv_cluster(java_config):
    ms_srv_ips = get_service_ips("java_ms-srv")
    if not ENABLE_MS_SRV:
        return
    
    if len(ms_srv_ips) <= 1:
        return
    java_config['base']['ms_srv_cluster'] = True
    ms_srv_ip = ms_srv_ips[0]
    exec_ssh_cmd(ms_srv_ip, "mkdir -p /data/app/titan-dfs/ms-srv/files && chown -R titan:titan /data/app/titan-dfs/ms-srv/files")
    exec_ssh_cmd(ms_srv_ip, "chown -R titan:titan /data/app/titan-dfs/ms-srv ")

def config_event_srv_cluster(java_config):
    event_srv_ips = get_service_ips("java_event-srv")
    if not ENABLE_EVENT_SRV:
        return
    
    if len(event_srv_ips) <= 1:
        return
    java_config['base']['event_srv_cluster'] = True
    

def config_zookeeper():
    zk_ips = get_service_ips("java_zookeeper")
    # comment #clientPortAddress=127.0.0.1, if not maybe java can't connect to zookeeper
    for zk_ip in zk_ips:
        tmp_num = exec_ssh_cmd_withresult(zk_ip, '''grep  "^clientPortAddress=" /usr/local/qingteng/zookeeper/conf/zoo.cfg | wc -l ''')
        if tmp_num == '0':
            continue

        exec_ssh_cmd(zk_ip, '''sed -i 's/^clientPortAddress=/#clientPortAddress=/g' /usr/local/qingteng/zookeeper/conf/zoo.cfg ''')
        exec_ssh_cmd(zk_ip, '''service zookeeperd restart ''')


def config_php_glusterfs():
    php_ips = get_service_ips("php_frontend_private")
    if len(php_ips) <= 1:
        return

    if FOR_INSTALL_OR_UPGRADE  == "0" or FOR_INSTALL_OR_UPGRADE == "1":
        time_str = time.strftime("%Y%m%d_%H%M%S")
        php_1 = php_ips[0]
        exec_ssh_cmd(php_1, '''mkdir -p /data/app/titan-dfs/agent-update/ ''')
        exec_ssh_cmd(php_1, '''test -L /data/app/www/agent-update || cp -rf /data/app/www/agent-update/* /data/app/titan-dfs/agent-update/ ''')
        exec_ssh_cmd(php_1, '''chown -R nginx:nginx /data/app/titan-dfs/agent-update/ ''')

        for php_ip in php_ips:
            exec_ssh_cmd(php_ip, '''test -L /data/app/www/agent-update || mv -f /data/app/www/agent-update /data/app/www/agent-update_''' + time_str)
            exec_ssh_cmd(php_ip, '''ln -f -s /data/app/titan-dfs/agent-update/ /data/app/www/agent-update && chown nginx:nginx /data/app/www/agent-update''')
        
# if cluster, all host in java.json need use vip
def config_host_for_cluster(php_config, java_config):
    php_ips = get_service_ips("php_frontend_private")
    if len(php_ips) <= 1:
        return

    # enable nginx cluster config, cluster gateway use 16000,selector use 16677
    if FOR_INSTALL_OR_UPGRADE  == "0" or FOR_INSTALL_OR_UPGRADE == "1":
        enable_nginx_cluster()

    vip = ip_config['vip']
    eip = ip_config['eip']

    for name in ['agent','api','backend','download','frontend','selector','upload','patrol']:
        java_config['host'][name]['privateip'] = vip
        java_config['host'][name]['publicip'] = eip

    sh_publicips = get_service_ips("java_connect-sh_public")
    if len(sh_publicips) > 0:
        java_config['host']["connect"]['publicip'] = sh_publicips[0]

    java_config['host']["innerapi"]['privateip'] = vip
            
    java_config['host']['selector']['port'] = 6677

    php_config["host"]["java"]["privateip"] = vip
    php_config["host"]["java"]["port"] = 6000

    for name in ['agent','api','backend','download','frontend']:
        php_config['host'][name]['privateip'] = vip
        php_config['host'][name]['publicip'] = eip

    php_config["db"]["web"]["ip"] = vip
    php_config["db"]["web"]["port"] = 3305
    php_config["db"]["agent_monitor"]["ip"] = vip
    php_config["db"]["agent_monitor"]["port"] = 3305

    if FOR_INSTALL_OR_UPGRADE  == "0" or FOR_INSTALL_OR_UPGRADE == "1":
        config_keepalived()

def config_keepalived():
    keepalived_ips = get_service_ips("keepalived")
    # config keepalived notify script and track_script
    for kp_ip in keepalived_ips:
        now_kp_conf = exec_ssh_cmd_withresult(kp_ip, '''cat /etc/keepalived/keepalived.conf ''')
        if "vrrp_script chk_nginx_patrol" in now_kp_conf and re.search(r"[^#]*notify_master.*notify_master.sh", now_kp_conf):
            print("{kp_ip}'s keepalived already config ".format(kp_ip=kp_ip))
            continue

        exec_ssh_cmd(kp_ip,'''sed -i 's%#notify_master.*$%notify_master /data/app/www/titan-web/config_scripts/notify_master.sh%' /etc/keepalived/keepalived.conf ''')
        exec_ssh_cmd(kp_ip,'''sed -i 's%#notify_backup.*$%notify_backup /data/app/www/titan-web/config_scripts/notify_backup.sh%' /etc/keepalived/keepalived.conf ''')
        exec_ssh_cmd(kp_ip,'''sed -i 's%#notify.*$%notify /data/app/www/titan-web/config_scripts/notify.sh%' /etc/keepalived/keepalived.conf ''')

        # add track_script
        exec_ssh_cmd(kp_ip,'''sed -i -e '/^vrrp_script chk_nginx_patrol/,+3d' /etc/keepalived/keepalived.conf ''')
        exec_ssh_cmd(kp_ip,'''sed -i -e '/track_script/,+2d' /etc/keepalived/keepalived.conf ''')
        exec_ssh_cmd(kp_ip,'''sed -i -e '/vrrp_instance/i vrrp_script chk_nginx_patrol { \\n    script /data/app/www/titan-web/config_scripts/chk_nginx_patrol.sh\\n    interval 10\\n}\\n' /etc/keepalived/keepalived.conf ''')
        exec_ssh_cmd(kp_ip,'''sed -i -e '/notify_master/i\\    track_script {\\n       chk_nginx_patrol\\n    }\\n' /etc/keepalived/keepalived.conf ''')

        exec_ssh_cmd(kp_ip, "chmod +x /data/app/www/titan-web/config_scripts/notify*.sh")
        exec_ssh_cmd(kp_ip, "chmod +x /data/app/www/titan-web/config_scripts/chk_nginx_patrol.sh")
        exec_ssh_cmd(kp_ip, "service keepalived restart")

def update_etc_host():
    """
    Write "ip domain" to /etc/hosts
    :return:
    """

    global ip_config

    map_ip_domain_1 = (ip_config["php_frontend_private"], ip_config["php_frontend_public"])[ ip_config["php_frontend_public"] != "" ] + " " + ip_config["php_frontend_domain"]
    map_ip_domain_2 = (ip_config["php_api_private"], ip_config["php_api_public"])[ ip_config["php_api_public"] != "" ] + " " + ip_config["php_api_domain"]
    map_ip_domain_3 = ip_config["php_inner_api"] + " " + ip_config["php_inner_api_domain"]

    cmd = '''[ -z "`grep '{0}' /etc/hosts`" ] && echo '{0}' >> /etc/hosts '''

    os.system(ssh_qt_cmd(ip_config["java"], cmd.format(map_ip_domain_1)))
    os.system(ssh_qt_cmd(ip_config["java"], cmd.format(map_ip_domain_2)))
    os.system(ssh_qt_cmd(ip_config["java"], cmd.format(map_ip_domain_3)))

    os.system(ssh_qt_cmd(ip_config["java_connect-sh"], cmd.format(map_ip_domain_3)))

def enable_ssl(ip,enable_domain_https,port):
    """

    :param ip: IP address
    :return:
    """

    _cmd = '''[ -f /data/app/conf/cert/config_ssl.sh ] && bash /data/app/conf/cert/config_ssl.sh {0} {1} '''.format(enable_domain_https,port)
    exec_ssh_cmd(ip, _cmd)


def clean_tmp():
    """
    Clean the tmp files
    :return:
    """
    tmp_files = ["sh.json", "build.json", "java.json"]
    for f in tmp_files:
        try:
            os.remove(ScriptPath + "/" + f)
        except:
            pass

#Replace the location in the old java.json file with the new java.json by immutable_fields.

def ChangeKeyToValues(new_dict, old_dict, target_keys):
    if len(target_keys) == 1:
        key = target_keys[0]
        if old_dict.get(key):
            new_dict[key] = old_dict[key]
        else:
            return
    elif len(target_keys) > 1:
        key = target_keys[0]
        if old_dict.get(key):
            ChangeKeyToValues(new_dict[key], old_dict[key], target_keys[1:])
        else:
            return
    else:
        raise Exception("error format of immutable fields")

def merge_ip_config():
    """ Merge the ip.json and ip_template.json.
    Only the config items in ip_template.json are valid,
    the items in ip.json but not in ip_template.json will be dropped.
    If there is no "ip.json" when initially install, use the ip_template.json.
    :return: Json Obj
    """
    global CUSTOMIZE

    customize_file = ScriptPath + "/CUSTOMIZE.json"
    if os.path.exists(customize_file):
        try:
            customize_config = json.load(file(customize_file))
            for k,v in customize_config.items():
                for k2,v2 in v.items():
                    try:
                        CUSTOMIZE[k][k2]=v2
                    except:
                        pass
        except:
            pass
    try:
        ip_file = ScriptPath + "/ip.json"
        ip_config = json.load(file(ip_file))
    except:
        ip_config = {}

    ip_template_file = ScriptPath + "/ip_template.json"
    ip_template_config = json.load(file(ip_template_file))

    # add the items that in ip_template.json but not in ip.json to ip_config
    for i in ip_template_config.keys():
        if i in ip_config.keys():
            continue
        else:
            ip_config[i] = ip_template_config[i]

    # remove the items that doesn`t exist in ip_template.json from ip_config
    for i in ip_config.keys():
        if i in ip_template_config.keys():
            continue
        else:
            del ip_config[i]

    return ip_config

# for other normal usage,for example: change password, only reset password, switch https
# config syslog
def load_current_config():
    print ("copy the current config file from PHP server directory...\n")
    php_config_file = "/data/app/www/titan-web/conf/build.json"
    cmd = "cp " + php_config_file + " " + ScriptPath + "/build.json"
    os.system(cmd)

    print ("copy the current config files from Java Server...\n")
    java_config_directory = "/data/app/titan-config/java.json"
    scp_from_remote(java_config_directory, ip_config["java"], ScriptPath + "/java.json")
    
    # load the current configuration
    php_config = json.load(file(ScriptPath + "/build.json"))
    java_config = json.load(file(ScriptPath + "/java.json"))

    return php_config,java_config

def write_new_config(php_config,java_config):
    # write the php config
    f = open(ScriptPath + "/build.json", "w+")
    # separators default is (', ',': '),change to (',',': ')
    # separators makes no blank after ',' . to be the same with php json lib, or it will makes some mistakes when doing diff
    f.write(json.dumps(php_config, indent = 4, separators=(',',': '), sort_keys = True))
    f.close()

    # write the java config
    f = open(ScriptPath + "/java.json", "w+")
    f.write(json.dumps(java_config, indent = 4, sort_keys = True))
    f.close()

    put_javajson_to_javaserver()
    backup_javajson()

    put_phpconf_to_phpserver()
    
def write_new_java_config(java_config):
    # write the java config
    f = open(ScriptPath + "/java.json", "w+")
    f.write(json.dumps(java_config, indent = 4, sort_keys = True))
    f.close()

    put_javajson_to_javaserver()
    backup_javajson()

#copy java.json to /data/backup/system_configpy
def backup_javajson():
    javajson_file = ScriptPath + "/java.json"
    php_ips = get_service_ips("php_frontend_private")
    for ip in php_ips:
        exec_ssh_cmd(ip,"mkdir -p /data/backup/system_configpy/")
        scp_to_remote(javajson_file, ip, "/data/backup/system_configpy/")


def get_php_ips():
    _PHP_Servers = ["php_frontend_private", "php_backend_private", "php_agent_private", 
                    "php_download_private", "php_api_private", "php_inner_api"]

    php_ips = set()
    for srv_name in _PHP_Servers:
        php_ips.update(get_service_ips(srv_name, ip_config))
    php_ips.discard("")
    php_ips.discard("127.0.0.1")
    return php_ips

def put_phpconf_to_phpserver():
    # copy build.json to php config directory
    php_config_directory = "/data/app/www/titan-web/conf"
    php_ips = get_php_ips()

    print ("generate the application.ini on PHP server....\n")

    for php_ip in php_ips:
        exec_ssh_cmd_withresult(php_ip, "service nginx restart")
        time.sleep(5)
    for php_ip in php_ips:
        try:
            scp_to_remote(ScriptPath + "/build.json", php_ip, php_config_directory)
            print(php_ip + " run: /data/app/www/titan-web/script/update.sh install") 
            exec_ssh_cmd_withresult(php_ip, "/data/app/www/titan-web/script/update.sh install")
        except Exception as e:
            print (str(e))
            print("\033[31m[ERROR] sync build.json to php server failed! \033[0m")  

def put_javajson_to_javaserver():
    # copy java.json to java config directory
    
    java_config_directory = "/data/app/titan-config/"
    java_ips = set()

    for srv_name in ["java","java_connect-dh","java_connect-agent","java_connect-selector","java_connect-sh","java_patrol-srv"]:
        java_ips.update(get_service_ips(srv_name, ip_config))

    scan_ips = get_service_ips("java_scan-srv", ip_config)
    for scan_ip in scan_ips:
        # if /data/app/titan-config/ not exits create it
        os.system(ssh_qt_cmd(scan_ip, "mkdir -p /data/app/titan-config/"))
    java_ips.update(scan_ips)
    ms_srv_ips = get_service_ips("java_ms-srv", ip_config)
    #os.system(ssh_qt_cmd(scan_ip, "mkdir -p /data/app/titan-config/"))
    java_ips.update(ms_srv_ips)
    event_srv_ips = get_service_ips("java_event-srv", ip_config)
    java_ips.update(event_srv_ips)

    for java_ip in java_ips:
        try:
            # check in glusterfs or not
            java_dfs_path = exec_ssh_cmd_withresult(java_ip, '''ls -l /data/app/titan-config/java.json ''', alarm_error=False)
            if java_dfs_path and "->" in java_dfs_path and java_dfs_path.startswith('l'):
                java_dfs_path = java_dfs_path.split("->")[1].strip()
                scp_to_remote(ScriptPath + "/java.json", java_ip, java_dfs_path)
            else:
                scp_to_remote(ScriptPath + "/java.json", java_ip, java_config_directory)

        except Exception as e:
            print (str(e))
            print("\033[31m[ERROR] scp java.json to java server failed! \033[0m") 
            print ("")

def change_db_pwd(only_change_conf=False):
    """ Change mysql/mongo database passwd and configuration in java.json and build.json in php
        need provide old password
    """
    print("change_db_pwd start")
    php_config,java_config = load_current_config()
    # get config key for encrypt passwd
    pbeconfig = java_config["base"]["pbeconfig"]
    pbepwd = pbeconfig[:16]
    pbesalt = pbeconfig[16:]

    if not pbeconfig:
        print("ERROR: can not get pbeconfig")
        sys.exit(1)

    passwd_dict = get_input_password("1")
    if len(passwd_dict) == 0:
        print("ERROR: password param wrong")
        return


    for key in sorted(passwd_dict.keys()):
        pwds = passwd_dict[key]
        new_passwd = pwds["new_passwd"]
        if key == 'mongo':
            old_passwd = pwds["old_passwd"]
            change_mongo_pwd(old_passwd, new_passwd)
        elif key == 'mysql':
            old_passwd = pwds["old_passwd"]
            change_mysql_pwd(old_passwd, new_passwd)

    for key, pwds in passwd_dict.items():
        new_passwd = pwds["new_passwd"]
        encrypt_new_passwd = encrypt_string(pbepwd,pbesalt,new_passwd)
        if key == 'mongo':
            java_config["mongodb"]["password"] = encrypt_new_passwd
        elif key == 'mysql':
            php_config["db"]["web"]["password"] = encrypt_new_passwd
            php_config["db"]["agent_monitor"]["password"] = encrypt_new_passwd
            java_config["mysql"]["password"] = encrypt_new_passwd

    write_new_config(php_config,java_config)

    # restart php and java
    restart_servers = ",".join(ALL_NEED_RESTART_SERVICE)
    restart_cmd = "python {script_path} --restart {servers}".format(script_path=TITAN_SYSYTEM_PY,servers=restart_servers)
    exec_ssh_cmd("", restart_cmd)


def only_change_config_pwd():
    """ only change password in config file, need provide new password
    """
    print("only_change_config_pwd start")
    php_config,java_config = load_current_config()
    # get config key for encrypt passwd
    pbeconfig = java_config["base"]["pbeconfig"]
    pbepwd = pbeconfig[:16]
    pbesalt = pbeconfig[16:]

    if not pbeconfig:
        print("ERROR: can not get pbeconfig")
        sys.exit(1)

    passwd_dict = get_input_password("0")
    if len(passwd_dict) == 0:
        print("ERROR: password param wrong")
        return

    # if only change password config, not change database password, only encrypt in config file
    for key, pwds in passwd_dict.items():
        new_passwd = pwds["new_passwd"]
        encrypt_new_passwd = encrypt_string(pbepwd,pbesalt,new_passwd)
        if key == 'mongo':
            java_config["mongodb"]["password"] = encrypt_new_passwd
        elif key == 'mysql':
            php_config["db"]["web"]["password"] = encrypt_new_passwd
            php_config["db"]["agent_monitor"]["password"] = encrypt_new_passwd
            java_config["mysql"]["password"] = encrypt_new_passwd
        elif key == 'redis_php':
            php_config["redis"]["web"]["password"] = encrypt_new_passwd
            java_config["redis"]["php"]["password"] = encrypt_new_passwd
        elif key == 'redis_java':
            java_config["redis"]["java"]["password"] = encrypt_new_passwd
        elif key == 'redis_erlang':
            php_config["redis"]["server"]["password"] = encrypt_new_passwd
            java_config["redis"]["erl"]["password"] = encrypt_new_passwd
        elif key == 'kafka':
            java_config["kafka"]["password"] = encrypt_new_passwd
            if new_passwd != '': 
                java_config["kafka"]["auth_enable"] = True 
            else:
                java_config["kafka"]["auth_enable"] = False  
        elif key == 'rabbitmq':
            java_config["rabbitmq"]["password"] = encrypt_new_passwd
            java_config["rabbitmq"]["username"] = "guest"
            php_config["rabbit"]["password"] = encrypt_new_passwd
            php_config["rabbit"]["user"] = "guest" 

    write_new_config(php_config,java_config)

    include_zk = 'zookeeper' in passwd_dict.keys(); 
    if include_zk:
        zk_pwd = passwd_dict['zookeeper']['new_passwd']
        put_zk_client_jaas_tojava(zk_pwd)

    restart_bigdata_logstash = False
    bigdata_logstash_ips = get_service_ips("bigdata_logstash")
    if passwd_dict.has_key("kafka") and len(bigdata_logstash_ips) > 0:
        bigdata_logstash_ip = bigdata_logstash_ips[0]
        encrypt_new_passwd = encrypt_string(pbepwd,pbesalt,passwd_dict["kafka"]["new_passwd"])
        config_bigdata_kafka(bigdata_logstash_ip,encrypt_new_passwd,pbeconfig)
        restart_bigdata_logstash = True

    # restart php and java
    restart_servers = ",".join(ALL_NEED_RESTART_SERVICE)
    if restart_bigdata_logstash:
        restart_servers = restart_servers + ",bigdata_logstash"
    restart_cmd = "python {script_path} --restart {servers}".format(script_path=TITAN_SYSYTEM_PY,servers=restart_servers)

    exec_ssh_cmd("", restart_cmd)


def reset_es_pwd_auto():
    php_config,java_config = load_current_config()
    # get config key for encrypt passwd
    pbeconfig = java_config["base"]["pbeconfig"]
    pbepwd = pbeconfig[:16]
    pbesalt = pbeconfig[16:]
    print("INFO: you are starting to reset elasticsearch password")   
    es_pwd = get_input(randomString(16),"Please input elasticsearch password,default use random new: ")
    es_pwd_encrypt = encrypt_string(pbepwd,pbesalt,es_pwd)
    es_pwd = es_pwd.strip()
    reset_bigdata_es_pwd_manual(pbeconfig,es_pwd,es_pwd_encrypt)
    java_config["bigdata_es"]['password'] = es_pwd_encrypt
    write_new_config(php_config,java_config)
    
def reset_config_pwd():
    """ Change database passwd and configuration in java.json and build.json in php
    """
    php_config,java_config = load_current_config()
    # get config key for encrypt passwd
    pbeconfig = java_config["base"]["pbeconfig"]
    pbepwd = pbeconfig[:16]
    pbesalt = pbeconfig[16:]

    if not pbeconfig:
        print("ERROR: can not get pbeconfig")
        sys.exit(1)

    passwd_dict = get_input_password("2")

    if 'es' in passwd_dict.keys():
        print ("The version does not support es. Run the python config.py --reset_es_pwd command to reset the ES password")
        return
    
    include_zk = 'zookeeper' in passwd_dict.keys(); 
    if include_zk:
        zk_pwd = passwd_dict['zookeeper']['new_passwd']
    else:
        zk_pwd = get_zk_pwd()

    if 'kafka' in passwd_dict.keys():
        kafka_pwd = passwd_dict['kafka']['new_passwd']
    else:
        kafka_pwd = decrypt_string(pbepwd, pbesalt, java_config["kafka"].get("password",''))

    for key, pwds in passwd_dict.items():
        new_passwd = pwds["new_passwd"]
        encrypt_new_passwd = encrypt_string(pbepwd,pbesalt,new_passwd)
        if key == 'mongo':
            reset_mongo_pwd(new_passwd,'mongo_java')
            java_config["mongodb"]["password"] = encrypt_new_passwd
        elif key =='ms_mongo':
            reset_mongo_pwd(new_passwd,'mongo_ms_srv')
            java_config["ms_mongodb"]["password"] = encrypt_new_passwd
        elif key == 'mysql':
            reset_mysql_pwd(new_passwd)
            php_config["db"]["web"]["password"] = encrypt_new_passwd
            php_config["db"]["agent_monitor"]["password"] = encrypt_new_passwd
            java_config["mysql"]["password"] = encrypt_new_passwd
        elif key == 'redis_php':
            reset_redis_pwd(new_passwd,"redis_php")
            php_config["redis"]["web"]["password"] = encrypt_new_passwd
            java_config["redis"]["php"]["password"] = encrypt_new_passwd
        elif key == 'redis_java':
            reset_redis_pwd(new_passwd,"redis_java")
            java_config["redis"]["java"]["password"] = encrypt_new_passwd
        elif key == 'redis_erlang':
            reset_redis_pwd(new_passwd,"redis_erlang")
            php_config["redis"]["server"]["password"] = encrypt_new_passwd
            java_config["redis"]["erl"]["password"] = encrypt_new_passwd
        elif key == 'kafka' and not include_zk:
            reset_kafka_pwd(new_passwd, zk_pwd)
            java_config["kafka"]["password"] = encrypt_new_passwd
            if new_passwd != '': 
                java_config["kafka"]["auth_enable"] = True 
            else:
                java_config["kafka"]["auth_enable"] = False  
        elif key == 'rabbitmq':
            reset_rabbitmq_pwd(new_passwd)
            java_config["rabbitmq"]["password"] = encrypt_new_passwd
            java_config["rabbitmq"]["username"] = "guest"
            php_config["rabbit"]["password"] = encrypt_new_passwd
            php_config["rabbit"]["user"] = "guest" 
        elif key == 'zookeeper':
            reset_zk_kafka_pwd(zk_pwd, kafka_pwd)
            java_config["kafka"]["password"] = encrypt_string(pbepwd,pbesalt,kafka_pwd)
            if kafka_pwd != '': 
                java_config["kafka"]["auth_enable"] = True 
            else:
                java_config["kafka"]["auth_enable"] = False

    write_new_config(php_config,java_config)
    if include_zk:
        put_zk_client_jaas_tojava(zk_pwd)

    restart_bigdata_logstash = False
    bigdata_logstash_ips = get_service_ips("bigdata_logstash")
    if passwd_dict.has_key("kafka") and len(bigdata_logstash_ips) > 0:
        bigdata_logstash_ip = bigdata_logstash_ips[0]
        encrypt_new_passwd = encrypt_string(pbepwd,pbesalt,passwd_dict["kafka"]["new_passwd"])
        config_bigdata_kafka(bigdata_logstash_ip,encrypt_new_passwd,pbeconfig)
        restart_bigdata_logstash = True

    # restart java
    if 'ms_mongo' in passwd_dict.keys() and len(passwd_dict) == 1 :
        restart_servers = "java_ms-srv"
    else:
        restart_servers = ",".join(ALL_NEED_RESTART_SERVICE)
    if restart_bigdata_logstash:
        restart_servers = restart_servers + ",bigdata_logstash"
    restart_cmd = "python {script_path} --restart {servers}".format(script_path=TITAN_SYSYTEM_PY,servers=restart_servers)

    exec_ssh_cmd("", restart_cmd)

############# start from here ######################
print ("start configuration")
VERSION = "v3"

ScriptPath = os.path.split(os.path.realpath(sys.argv[0]))[0]

# merge the ip.json and ip_template.json
ip_config = merge_ip_config()

def usage():
    print ("=========== Usage Info =============")
    print ("python config.py -v {version} [https=N] [console_port=80] [backend_port=81] [api_port=8001] [agent_download_port=8002] [ignore_config=Y] [cluster=N] [bigdata=N] [docker_scan=N] [ms_srv=N] [change_pwd] [only_change_pwdconf] [reset_pwd] [install_or_up=2] [encrypt] [reset_es_pwd] [get_plain] [install_cron]")
    print ("version: [v2, v3]")
    print ("install_or_up: [0:install, 1:upgrade, 2:other usage, 3:upgrade from normal to cluster]")

def main():
    short_args = "hv:a"
    long_args = ["help", "version=", "https=", "console_https=", "backend_https=", "api_https=", "agent_download_https=", "console_port=", "backend_port=", "api_port=", "agent_download_port=", "ignore_config=", "cluster=", "bigdata=", "docker_scan=", "ms_srv=","change_pwd", "only_change_pwdconf", "reset_pwd", "install_or_up=", "encrypt", "reset_es_pwd", "get_plain", "install_cron"]
    try:
        opts, args = getopt.getopt(sys.argv[1:], short_args, long_args)
    except getopt.GetoptError:
        usage()
        sys.exit(2)

    global v

    https = None
    console_https = None
    backend_https = None
    agent_download_https = None
    api_https = None
    cluster = None
    ignore_config = None
    bigdata = None
    docker_scan = None
    ms_srv= None
    event_srv= None
    console_port = None
    backend_port = None
    api_port = None
    agent_download_port = None
    change_db_pwd = None
    only_change_pwdconf = None
    reset_pwd = None
    install_or_up = None
    manual_encrypt = None
    reset_es_pwd = None
    get_plain = None
    installcron = None

    for opt, arg in opts:
        if opt == "--https":
            https = arg
        if opt == "--console_https":
            console_https = arg
        if opt == "--backend_https":
            backend_https = arg
        if opt == "--api_https":
            api_https = arg
        if opt == "--agent_download_https":
            agent_download_https = arg
        if opt == "--console_port":
            console_port = int(arg)
        if opt == "--backend_port":
            backend_port = int(arg)
        if opt == "--api_port":
            api_port = int(arg)
        if opt == "--agent_download_port":
            agent_download_port = int(arg)
        if opt == "--ignore_config":
            ignore_config = arg
        if opt == "--cluster":
            cluster = arg
        if opt == "--bigdata":
            bigdata = arg
        if opt == "--docker_scan":
            docker_scan = arg
        if opt == "--ms_srv":
            ms_srv = arg 
        if opt == "--event_srv":
            event_srv = arg      
        if opt == "--change_pwd":
            change_pwd = True
        if opt == "--change_db_pwd":
            change_db_pwd = True
        if opt == "--only_change_pwdconf":
            only_change_pwdconf = True
        if opt == "--reset_pwd":
            reset_pwd = True
        if opt == "--install_or_up":
            install_or_up = arg
        if opt == "--encrypt":
            manual_encrypt = True
        if opt == "--reset_es_pwd":
            reset_es_pwd = True
        if opt == "--get_plain":
            get_plain = True
        if opt == "--install_cron":
            installcron = True
        if opt in ("-h", "--help"):
            usage()
            sys.exit(1)

    if manual_encrypt is not None:
        manual_encrypt_pwd()
        sys.exit()

    if get_plain is not None:
        get_plainpwd()
        sys.exit()

    if installcron is not None:
        install_cron("N")
        sys.exit()
        
    print ("start configuration")


    if only_change_pwdconf is not None:
        only_change_config_pwd()
        sys.exit()

    if change_db_pwd is not None:
        change_db_pwd()
        sys.exit()

    if reset_pwd is not None:
        reset_config_pwd()
        sys.exit()

    if reset_es_pwd is not None:
        reset_es_pwd_auto()
        sys.exit()

    global NGINX_CONSOLE_PORT
    global NGINX_BACKEND_PORT
    global NGINX_INNERAPI_PORT
    global NGINX_API_PORT
    global NGINX_AGENT_DOWNLOAD_PORT
    global ENABLE_CONSOLE_HTTPS
    global ENABLE_BACKEND_HTTPS
    global ENABLE_AGENT_DOWNLOAD_HTTPS
    global ENABLE_API_HTTPS
    global ENABLE_MONGODB_CLUSTER
    global ENABLE_MS_MONGODB_CLUSTER    
    global IGNORE_CONFIG
    global ENABLE_BIGDATA
    global ENABLE_DOCKER_SCAN
    global ENABLE_THP
    global ENABLE_MS_SRV
    global ENABLE_EVENT_SRV
    global FOR_INSTALL_OR_UPGRADE
    global UPGRADE_NORMAL_TO_CLUSTER

    if console_port is not None:
        NGINX_CONSOLE_PORT = console_port
    if backend_port is not None:
        NGINX_BACKEND_PORT = backend_port
    if api_port is not None:
        NGINX_API_PORT = api_port
    if agent_download_port is not None:
        NGINX_AGENT_DOWNLOAD_PORT = agent_download_port

    if https in ["y", "Y", "Yes", "YES"]:
        ENABLE_CONSOLE_HTTPS = True
        ENABLE_BACKEND_HTTPS = True
    elif https in ["n", "N", "No", "NO"]:
        ENABLE_CONSOLE_HTTPS = False
        ENABLE_BACKEND_HTTPS = False
    if console_https in ["y", "Y", "Yes", "YES"]:
        ENABLE_CONSOLE_HTTPS = True
    elif console_https in ["n", "N", "No", "NO"]:
        ENABLE_CONSOLE_HTTPS = False
    if backend_https in ["y", "Y", "Yes", "YES"]:
        ENABLE_BACKEND_HTTPS = True
    elif backend_https in ["n", "N", "No", "NO"]:
        ENABLE_BACKEND_HTTPS = False     
    if api_https in ["y", "Y", "Yes", "YES"]:
        ENABLE_API_HTTPS = True
    elif api_https in ["n", "N", "No", "NO"]:
        ENABLE_API_HTTPS = False
    if agent_download_https in ["y", "Y", "Yes", "YES"]:
        ENABLE_AGENT_DOWNLOAD_HTTPS = True
    elif agent_download_https in ["n", "N", "No", "NO"]:
        ENABLE_AGENT_DOWNLOAD_HTTPS = False
    if bigdata in ["y", "Y", "Yes", "YES"]:
        ENABLE_BIGDATA = True
    elif bigdata in ["n", "N", "No", "NO"]:
        ENABLE_BIGDATA = False
    if docker_scan in ["y", "Y", "Yes", "YES"]:
        ENABLE_DOCKER_SCAN = True
    elif docker_scan in ["n", "N", "No", "NO"]:
        ENABLE_DOCKER_SCAN = False
    if ms_srv in ["y", "Y", "Yes", "YES"]:
        ENABLE_MS_SRV = True
    elif ms_srv in ["n", "N", "No", "NO"]:
        ENABLE_MS_SRV = False
    
    if event_srv in ["y", "Y", "Yes", "YES"]:
        ENABLE_EVENT_SRV = True
    elif event_srv in ["n", "N", "No", "NO"]:
        ENABLE_EVENT_SRV = False

    if install_or_up == "0" or install_or_up == "1":
        FOR_INSTALL_OR_UPGRADE = install_or_up
    elif install_or_up == "3":
        FOR_INSTALL_OR_UPGRADE = "1"
        UPGRADE_NORMAL_TO_CLUSTER = True

    if ignore_config in ["y", "Y", "Yes", "YES"]:
        IGNORE_CONFIG = True
        if FOR_INSTALL_OR_UPGRADE is None:
            FOR_INSTALL_OR_UPGRADE = "2"

    if IGNORE_CONFIG is False:
        if install_or_up is None :
            print ("Please confirm for Install or Upgrade or Others? [0:install, 1:upgrade, 2:other usage], default is 0:install")
            print ("Enter [0/1/2]: ")
            v = get_input("0")
            if v == "0" or v == "1":
                FOR_INSTALL_OR_UPGRADE = v
            else:
                FOR_INSTALL_OR_UPGRADE = "2"

        if ENABLE_BIGDATA is None:
            bigdata_viewer_ip = ip_config["bigdata_viewer"]
            if bigdata_viewer_ip != '' and bigdata_viewer_ip != '127.0.0.1':
                ENABLE_BIGDATA = True
            else:
                ENABLE_BIGDATA = False
        if ENABLE_THP is None:
            bigdata_logstash_ip = ip_config["bigdata_logstash"]
            if bigdata_logstash_ip != '' and bigdata_logstash_ip != '127.0.0.1':
                ENABLE_THP = True
            else:
                ENABLE_THP = False
        if ENABLE_DOCKER_SCAN is None:
            scan_ips = get_service_ips("java_scan-srv", ip_config)
            if len(scan_ips) > 0:
                ENABLE_DOCKER_SCAN = True
            else:
                ENABLE_DOCKER_SCAN = False
        
        if ENABLE_MS_SRV is None:
            ms_ips = get_service_ips("java_ms-srv",ip_config)
            if len(ms_ips) > 0:
                ENABLE_MS_SRV = True
            else:
                ENABLE_MS_SRV = False
        
        if ENABLE_EVENT_SRV is None:
            ms_ips = get_service_ips("java_event-srv",ip_config)
            if len(ms_ips) > 0:
                ENABLE_EVENT_SRV = True
            else:
                ENABLE_EVENT_SRV = False

        if ENABLE_MONGODB_CLUSTER is None:
            mongo_ips = get_service_ips("db_mongo_java", ip_config)
            if len(mongo_ips) > 1:
                ENABLE_MONGODB_CLUSTER = True
            else:
                ENABLE_MONGODB_CLUSTER = False
        
        if ENABLE_MS_MONGODB_CLUSTER is None:
            ms_mongo_ips = get_service_ips("db_mongo_ms_srv", ip_config)
            if len(ms_mongo_ips) > 1:
                ENABLE_MS_MONGODB_CLUSTER = True
            else:
                ENABLE_MS_MONGODB_CLUSTER = False

    if https or console_https or backend_https or api_https or agent_download_https or bigdata or docker_scan:
        update_config()
        print ("config done.")
        if FOR_INSTALL_OR_UPGRADE == "0" or FOR_INSTALL_OR_UPGRADE == "1":
            print ("install crontab")
            install_cron('N')
    else:
        print ("Do you really want to change the configurations? default is Y")
        print ("Enter [Y/N]: ")
        v = get_input("Y")
        if v == "n" or v == "no" or v == "N" or v == "NO" or v == "No":
            print ("nothing changed, exit.")
            exit(0)
        elif v == "y" or v == "Y" or v == "Yes" or v == "YES":
            update_config()
            print ("config done.")
            if FOR_INSTALL_OR_UPGRADE == "0" or FOR_INSTALL_OR_UPGRADE == "1":
                print ("install crontab")
                install_cron()
        else:
            print ("wrong input, nothing changed, exit.")
            exit(0)

if __name__ == "__main__":
    main()
