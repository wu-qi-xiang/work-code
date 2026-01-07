#!/usr/bin/env python


"""Check runing status of Titan servers.

    Including process of console and service servers.

"""

import codecs
import commands
import datetime
import getopt
import json
import locale
import math
import os
import re
import smtplib
from email.MIMEText import MIMEText
import sys
import time
import logging
from shutil import copyfile


reload(sys)
sys.setdefaultencoding('utf-8')


# SSH user and port
DEFAULT_SSH_USER = "root"
DEFAULT_SSH_PORT = 22
DEFAULT_JAVA_JSON = "/data/app/titan-config/java.json"

# server ip config
SERVER_CONFIG_FILE = "ip.json"
# error log
ERROR_LOG_KEYWORD = "error_log.json"
ERROR_LOG_DIR = "/data/titan-logs"

# license API
LICENSE_API = "/v1/patrol/license/stat"
LICENSE_PORT = "6110"

# Java API
JAVA_PATROL_API = "/v1/patrol/record"
JAVA_PATROL_REPORT_API = "/v1/patrol/report/{jobId}"
JAVA_SERVER_PORT = "6110"

# php config file
PHP_CONFIG_FILE = "/data/app/www/titan-web/conf/build.json"

# log max age (in days)
LOG_MAX_AGE = 180
LOG_MAX_SIZE = 10485760
# disk usage percent threshold to trigger log trim
DISK_PERCENT = 80

# system status json file on Java server
JAVA_SYSTEM_STATUS_JSON_FILE = "/data/titan-logs/monitor/system_status.json"

# local ip
LOCAL_IP = "127.0.0.1"

RABBITMQ_DEFAULT_THRESHOLD = 1000
KAFKA_DEFAULT_THRESHOLD = 1000
RABBITMQ_THRESHOLD_DICT = {}
KAFKA_THRESHOLD_DICT = {}

def usage():
    print """Check status of titan server system.

Usage: titan_system_check.py [-apejlhvr] [ -t ndays ] [ --start-date=YYYmmdd ] [ --end-date=YYYmmdd ] [ -o result.json ] [ --restart server] [--stop server] [--self-check-api]

    -a                  Check all system status
    -p                  Check server process
    -e                  Check error log
    -t ndays            N days to check (default: 1 day)
    --start-date=start  Start date for check, format: YYYmmdd, e.g 20170316
    --end-date=end      End date for check, format: YYYmmdd, e.g 20170316
    -l                  Check license information
    -o result.json      Write output as json to file
    --copy-to-java      Copy output json file to Java server
    --post-to-java      Sending services and server status to Java server using HTTP Post method and restart Error services
    --post-to-java-no-restart      Sending services and server status to Java server using HTTP Post method
    --sendmail=file     Send file content as email
    --trim-log          Remove old log files to free disk space
    --compress-log      Compress daily log
    -h                  Print this help message
    --restart server    restart server
    --stop server       stop server
    --restart-node      restart server nodes,example: --restart-node java@127.0.0.1@cmd,java_gateway@172.16.2.184@cmd
    --stop-node         stop server nodes,,example: --stop-node java@127.0.0.1@cmd,java_gateway@172.16.2.184@cmd
    -v                  Sets the sync to verbose
    --self-check-api    Check all Server selfCheckAPI status

Example:
    Check all system status of today:
      $ titan_system_check.py -a

    Check all system status of this week:
      $ titan_system_check.py -a -t 7

    Check all system status of a time period:
      $ titan_system_check.py -a --start-date=20170101 --end-date=20170316

    Check titan server process status:
      $ titan_system_check.py -p

    Check titan server license status:
      $ titan_system_check.py -l

    Check error log status of this week:
      $ titan_system_check.py -e -t 7

    Check job status of today:
      $ titan_system_check.py -j -t 1

    Send system status to email configured in /data/app/www/titan-web/conf/build.json:
      $ titan_system_check.py --sendmail=/data/titan-logs/monitor/system_status_20170427.log

    Check all server selfCheckAPI status:
      $ titan_system_check.py --self-check-api
    """

def log(level, msg):
    """Format line as standard log.

    Args:
        msg: One line of string to be added to log.
    """
    now = time.strftime("%Y-%m-%d %H:%M:%S", time.localtime())
    print now + ' [' + level + '] - ' + msg

def log_info(msg):
    log('INFO', msg)

def log_error(msg):
    log('ERROR', msg)

#refer to https://unix.stackexchange.com/questions/4770/quoting-in-ssh-host-foo-and-ssh-host-sudo-su-user-c-foo-type-constructs
# use single quote, avoid escape.  single quote for Bourne shell evaluation
# Change ' to '\'' and wrap in single quotes.
# If original starts/ends with a single quote, creates useless
# (but harmless) '' at beginning/end of result.
def single_quote(cmd):
    return "'" + cmd.replace("'","'\\''") + "'" 

def ssh_cmd(ip_addr, cmd):
    # if user is not root, need sudo
    if DEFAULT_SSH_USER != 'root':
        cmd = '''sudo bash -c ''' + single_quote(cmd)
    if ip_addr in ['127.0.0.1', LOCAL_IP]:
        return cmd
    return 'ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -o LogLevel=Error -p ' + ('%d' % (DEFAULT_SSH_PORT)) + ' ' + DEFAULT_SSH_USER + '@' + ip_addr + " " + single_quote(cmd)

def ssh_t_cmd(ip_addr, cmd, force=True):
    # if user is not root, need sudo
    if DEFAULT_SSH_USER != 'root':
        cmd = '''sudo bash -c ''' + single_quote(cmd)
    if ip_addr in ['127.0.0.1', LOCAL_IP]:
        return cmd
    if force:
        return 'ssh -t -o StrictHostKeyChecking=no -o ConnectTimeout=10 -o LogLevel=Error -p ' + ('%d' % (DEFAULT_SSH_PORT)) + ' ' + DEFAULT_SSH_USER + '@' + ip_addr + " " + single_quote(cmd)
    else:
        return 'ssh -T -o StrictHostKeyChecking=no -o ConnectTimeout=10 -o LogLevel=Error -p ' + ('%d' % (DEFAULT_SSH_PORT)) + ' ' + DEFAULT_SSH_USER + '@' + ip_addr + " " + single_quote(cmd)

def exec_ssh_cmd_withresult(ip_addr, cmd, _cmd='', verbose=False):
    cmd = ssh_t_cmd(ip_addr, cmd)
    if verbose:
        print("exec_ssh_cmd_withresult:" + (_cmd if _cmd != '' else cmd))
    status, output = commands.getstatusoutput(cmd)
    if status != 0 :
        log_error("Failed to execute command: " + cmd)
        log_error("(%d) %s" % (status, output if output else "-"))
    else:
        if verbose:
            print("output:")
            print(output)
        # remove Pseudo-terminal will not be allocated because stdin is not a terminal.
        if output.startswith("Pseudo-terminal will"):
            return re.sub("^Pseudo-terminal will.*\.", "", output).strip()
        else:
            return output.strip()

def zh_len(msg):
    try:
        row_l = len(msg)
        utf8_l = len(msg.encode('utf-8'))
        return (utf8_l - row_l) / 2
    except UnicodeEncodeError:
        return None

def display_len(msg):
    return len(msg) + zh_len(msg)

def print_table(data):
    """Print table data.

    Args:
        data: 2-D arrawy, first row for table header, other rows for table data
    """
    # print data
    col_width = []
    n_col = len(data[0])
    n_row = len(data)
    for col in range(0, n_col):
        width = []
        for row in range(0, n_row):
            width.append(display_len(data[row][col]))
        col_width.append(max(width) + 1)
    # print col_width

    # print table header
    # '+-----------------+----------------+------+------+------+------------------------+-------+'
    # '|Server           |IP              |PID   |%CPU  |%MEM  |COMMAND                 |Status |'
    # '+=================+================+======+======+======+========================+=======+'
    line1 = '+'
    for width in col_width:
        line1 += '-' * width
        line1 += '+'
    print (line1)

    # print table header
    row = 0
    line = '|'
    for col in range(0, n_col):
        line += data[row][col].ljust(col_width[col])
        line += '|'
    print (line)

    line2 = '+'
    for width in col_width:
        line2 += '=' * width
        line2 += '+'
    print (line2)

    # print table body
    for row in range(1, n_row):
        line = '|'
        for col in range(0, n_col):
            # print data[row][col]
            # print zh_len(data[row][col])
            line += data[row][col].ljust(col_width[col] - zh_len(data[row][col]))
            line += '|'
        print (line)
        print (line1)

def sendmail(content_file):
    # read php config for SMTP config
    global PHP_CONFIG_FILE
    php_config_file = PHP_CONFIG_FILE
    if not os.path.isfile(php_config_file):
        log_info("php config file not exist - " + php_config_file)
        return
    file_obj = open(php_config_file, "r")
    content = file_obj.read()
    config = json.loads(content)

    smtp_server = config['email']['server']['host']
    smtp_user = config['email']['server']['user']
    smtp_password = config['email']['server']['password']
    mail_to = config['email']['address']['admin']
    mail_from = config['email']['server']['from']
    if not smtp_server:
        log_info('email.server.host not configured in %s, skip sending email' % php_config_file)
        return
    if not mail_from:
        log_info('email.server.from not configured in %s, skip sending email' % php_config_file)
        return
    if not mail_to:
        log_info('email.address.admin not configured in %s, skip sending email' % php_config_file)
        return

    # Create a text/html message
    with open(content_file) as fp:
        msg = MIMEText('<html><pre>' + fp.read() + '</pre></html>', 'html', 'utf-8')

    company = config['product_name']
    msg['Subject'] = '[' + company + '] Titan system status report - ' + os.path.basename(content_file)
    msg['From'] = mail_from
    msg['To'] = mail_to

    # Send the message via SMTP server.
    smtp = smtplib.SMTP()
    smtp.connect(smtp_server)
    smtp.login(str(smtp_user), str(smtp_password))
    smtp.sendmail(mail_from, mail_to.split(','), msg.as_string())
    ret = smtp.quit()
    if ret:
        log_info('send email success')

def compress_log():
    yesterday = datetime.datetime.today() + datetime.timedelta(days=-1)
    date = yesterday.strftime("%Y%m%d")
    #print 'yesterday: %s' % date
    cmd = "find " + ERROR_LOG_DIR + " ! -name '*.gz' -name '*" + date + "*' -type f | xargs echo"
    status, output = commands.getstatusoutput(cmd)
    if status != 0:
        log_error("Failed to execute command: " + cmd)
        log_error("(%d) %s" % (status, output if output else "-"))
        return
    if output:
        print output
        cmd = 'tar -cvzf ' + ERROR_LOG_DIR + '/titan-logs_' + date + '.tar.gz ' + output
        print cmd
        os.system(cmd)
    sys.exit()


class ServerRestart(object):
    def __init__(self, ipconfig, server_name, serverNodes=''):
        self.ipconfig = ipconfig
        #print serverNodes
        if serverNodes == '':
            self.server_list = server_name.split(',')
            self.servers = self._server_lists()
        else:
            self.serverNodes = serverNodes
            self.servers = self._server_nodes()
            
    # return {"java:['127.0.0.1,127.0.0.2']"}
    def _server_lists(self):
        datas = []   # [{'name': 'java','ips':[ip,ip]},{'name': 'java','ips':[ip,ip]}]
        sort_names = []

        for server_name in self.server_list:
            # avoid restart php repeat times, only php need
            if server_name in ["php_agent", "php_frontend", "nginx"]:
                server_name = 'php_agent'
            elif server_name in ["php_api", "php_inner_api", "php_user_backend"]:
                server_name = 'php_api'
            elif server_name in ["php_worker", "supervisord"]:
                server_name = 'php_worker'

            tmp_ips = self.ipconfig.get_ips(server_name)
            if not tmp_ips or len(tmp_ips) == 0:
                print(server_name + " is not install")
                continue

            if server_name not in sort_names:
                sort_names.append(server_name)
                datas.append({'name':server_name, 'ips': tmp_ips})
        
        self._sort_mongo_java(datas)       
        return datas

    # example: serverNodes = "java_gateway:127.0.0.1:gateway.jar,mongo_java:127.0.0.1:mongod_cs:127.0.0.1"
    def _server_nodes(self):
        datas = []   # [{servername: ips/command},{servername: ips/command}] 
        # sorted server name, service need stop and restat as the sort
        sort_names = []
        temp_datas = {}

        srv_ips = self.serverNodes.split(',')

        for srv_ip in srv_ips:
            strs = srv_ip.split('@')
            srv = strs[0]
            ip = strs[1]

            # avoid restart php repeat times, only php need
            if srv in ["php_agent", "php_frontend", "nginx"]:
                srv = 'php_agent'
            elif srv in ["php_api", "php_inner_api", "php_user_backend"]:
                srv = 'php_api'
            elif srv in ["php_worker", "supervisord"]:
                srv = 'php_worker'

            # if ip not in config, discard it
            tmp_ips = self.ipconfig.get_ips(srv)
            if ip not in tmp_ips:
                print(srv + " not install at " + ip)
                continue
            if srv not in sort_names:
                sort_names.append(srv)

            temp_datas.setdefault(srv, [])
            # when restart , mongo cluster and redis cluster need the 'command', the command is configure in ProcessCheck.server_list and /etc/init.d/
            # mongo cluster have five service ,need command to know restart which one. if not cluster,then the command is 'mongod',also can be used to restart
            if srv.startswith('redis_'):
                command = strs[2]
                if ip + ':' + command not in temp_datas[srv]:
                    temp_datas[srv].append(ip + ':' + command)
            else:
                if ip not in temp_datas[srv]:
                    temp_datas[srv].append(ip)

        for srv_name in sort_names:
            if temp_datas.has_key(srv_name):
                datas.append({'name':srv_name, 'ips': temp_datas[srv_name]})

        self._sort_mongo_java(datas)
        return datas

    # mongo cluster need first start mongod_cs, then mongod_port, then mongos
    def _sort_mongo_java(self, datas):
        mongo_index = None  
        mongo_data = []

        need_pop = []   # find mongo, and pop from list
        for index, item in enumerate(datas):
            srv_name = item['name']
            if not srv_name.startswith("mongo"):
                continue

            if mongo_index is None:
                mongo_index = index

            mongo_data.append(item)
            need_pop.insert(0,index)
            
        for index in need_pop:
            datas.pop(index)

        def mongo_sort_key(item):
            name= item["name"]
            if name == 'java_mongod_cs' or name == 'ms_srv_mongod_cs':
                return 3
            elif name == 'mongo_java' or name == 'mongo_ms_srv':
                return 1
            else:
                return 2

        mongo_data.sort(key=mongo_sort_key)
        for item in mongo_data:
            datas.insert(mongo_index, item)

    #operation:stop/restart, for mongo and redis
    def _build_cluster_cmd(self,ip_command, operation):
            real_ip = ip_command.split(':')[0]
            real_command = ip_command.split(':')[1]
            cmd = ssh_t_cmd(real_ip, "service "+ real_command + " " + operation)
            return cmd

    def restart(self):
        print self.servers
        cmd=""

        for server_item in self.servers:
            srv,iplist = server_item['name'], server_item['ips']
            for ip in iplist:
                if "erlang_rabbitmq" == srv:
                    cmd = ssh_t_cmd(ip, "service rabbitmq-server restart")
                elif srv in ["php_agent", "php_frontend", "nginx"]:
                    cmd = ssh_t_cmd(ip, "service nginx restart")
                elif srv in ["php_api", "php_inner_api", "php_user_backend"]:
                    cmd = ssh_t_cmd(ip, "service php-fpm restart")
                elif srv in ["php_worker", "supervisord"]:
                    cmd = ssh_t_cmd(ip, "service supervisord restart ; supervisorctl reload")
                elif srv == "mysql":
                    if self.ipconfig.is_server_cluster(srv):
                        cmd = ssh_t_cmd(ip, "service mysql restart")
                    else:
                        cmd = ssh_t_cmd(ip, "service mysqld restart")
                elif "mongo_java" == srv or "mongo_ms_srv" == srv:
                    if self.ipconfig.is_server_cluster(srv):
                        cmd = ssh_t_cmd(ip, "/etc/init.d/mongos restart")
                    else:
                        cmd = ssh_t_cmd(ip, "service mongod restart")
                elif "ms_srv_mongod_cs" == srv or "java_mongod_cs" == srv :
                        cmd = ssh_t_cmd(ip, "/etc/init.d/mongod_cs restart")
                elif re.match(r"(.*)mongod_\d{5}", srv) :
                        cmd = ssh_t_cmd(ip, "/etc/init.d/{mongod_port} restart".format(mongod_port=srv[-12:]))
                elif "redis_php" == srv:
                    if self.ipconfig.is_server_cluster(srv):
                        if ":" in ip:
                            cmd = self._build_cluster_cmd(ip, "restart")
                        else:
                            cmd = ssh_t_cmd(ip,"service redis6380d restart && service redis6480d restart && service redis6580d restart")
                    else:
                        real_ip = ip.split(':')[0]
                        cmd = ssh_t_cmd(real_ip, "service redis6380d restart")
                elif "redis_erlang" == srv:
                    if self.ipconfig.is_server_cluster(srv):
                        if ":" in ip:
                            cmd = self._build_cluster_cmd(ip, "restart")
                        else:
                            cmd = ssh_t_cmd(ip,"service redis6379d restart && service redis6479d restart && service redis6579d restart")
                    else:
                        real_ip = ip.split(':')[0]
                        cmd = ssh_t_cmd(real_ip, "service redis6379d restart")
                elif "redis_java" == srv:
                    if self.ipconfig.is_server_cluster(srv):
                        if ":" in ip:
                            cmd = self._build_cluster_cmd(ip, "restart")
                        else:
                            cmd = ssh_t_cmd(ip,"service redis6381d restart && service redis6481d restart && service redis6581d restart")
                    else:
                        real_ip = ip.split(':')[0]
                        cmd = ssh_t_cmd(real_ip, "service redis6381d restart")
                elif "java_zookeeper" == srv:
                    cmd = ssh_t_cmd(ip, "service zookeeperd restart")
                elif "java_kafka" == srv:
                    cmd = ssh_t_cmd(ip, "service kafkad restart")
                # elif re.match(r"bigdata_es_(\d+)", srv):
                #     num = re.match(r"bigdata_es_(\d+)", srv).group(1)
                #     cmd = ssh_t_cmd(ip, "service elasticsearch_ins{num} restart".format(num=num))
                #elif "bigdata_logstash" == srv:
                #    cmd = ssh_t_cmd(ip, "service qingteng-consumer restart")
                #elif "bigdata_viewer" == srv:
                #    cmd = ssh_t_cmd(ip, "service qingteng-viewer restart && service nginx restart")
                elif "java" == srv:
                    cmd = ssh_t_cmd(ip, "su -s /bin/sh -c '/data/app/titan-wisteria/init.d/wisteria restart' titan")
                elif "java_gateway" == srv:
                    cmd = ssh_t_cmd(ip, "su -s /bin/sh -c '/data/app/titan-gateway/init.d/gateway restart' titan")
                elif "java_user-srv" == srv:
                    cmd = ssh_t_cmd(ip, "su -s /bin/sh -c '/data/app/titan-user-srv/init.d/user-srv restart' titan")
                elif "java_detect-srv" == srv:
                    cmd = ssh_t_cmd(ip, "su -s /bin/sh -c '/data/app/titan-detect-srv/init.d/detect-srv restart' titan")
                elif "java_scan-srv" == srv:
                    cmd = ssh_t_cmd(ip, "su -s /bin/sh -c '/data/app/titan-scan-srv/init.d/scan-srv restart' titan")
                elif "java_anti-virus-srv" == srv:
                    cmd = ssh_t_cmd(ip, "su -s /bin/sh -c '/data/app/titan-anti-virus-srv/init.d/anti-virus-srv restart' titan")
                elif "java_ms-srv" == srv:
                    cmd = ssh_t_cmd(ip, "su -s /bin/sh -c '/data/app/titan-ms-srv/init.d/ms-srv restart' titan")
                elif "java_event-srv" == srv:
                    cmd = ssh_t_cmd(ip, "su -s /bin/sh -c '/data/app/titan-event-srv/init.d/event-srv restart' titan")
                elif "java_job-srv" == srv:
                    cmd = ssh_t_cmd(ip, "su -s /bin/sh -c '/data/app/titan-job-srv/init.d/job-srv restart' titan")
                elif "java_connect-selector" == srv:
                    cmd = ssh_t_cmd(ip, "su -s /bin/sh -c '/data/app/titan-connect-selector/init.d/connect-selector restart' titan")
                elif "java_connect-sh" == srv:
                    cmd = ssh_t_cmd(ip, "su -s /bin/sh -c '/data/app/titan-connect-sh/init.d/connect-sh stop && sleep 15 && /data/app/titan-connect-sh/init.d/connect-sh restart' titan")
                elif "java_connect-dh" == srv:
                    cmd = ssh_t_cmd(ip, "su -s /bin/sh -c '/data/app/titan-connect-dh/init.d/connect-dh restart' titan")
                elif "java_connect-agent" == srv:
                    cmd = ssh_t_cmd(ip, "su -s /bin/sh -c '/data/app/titan-connect-agent/init.d/connect-agent restart' titan")
                elif "java_patrol-srv" == srv:
                    cmd = ssh_t_cmd(ip, "su -s /bin/sh -c '/data/app/titan-patrol-srv/init.d/patrol-srv restart' patrol")
                elif "java_upload-srv" == srv:
                    cmd = ssh_t_cmd(ip, "su -s /bin/sh -c '/data/app/titan-upload-srv/init.d/upload-srv restart' titan")
                elif "keepalived" == srv:
                    cmd = ssh_t_cmd(ip, "service keepalived restart")
                elif "glusterfs" == srv:
                    cmd = ssh_t_cmd(ip, "service glusterd restart")
                else:
                    cmd=""

                if cmd:
                    log_info("Execute Restart Command: " + cmd)
                    status, output = commands.getstatusoutput(cmd)
                    print(output)

    def stop(self):
        print (self.servers)
        cmd=""

        for server_item in self.servers:
            srv,iplist = server_item['name'], server_item['ips']
            for ip in iplist:
                if "erlang_rabbitmq" == srv:
                    cmd = ssh_t_cmd(ip, "service rabbitmq-server stop")
                elif srv in ["php_agent", "php_frontend", "nginx"]:
                    cmd = ssh_t_cmd(ip, "service nginx stop")
                elif srv in ["php_api", "php_inner_api", "php_user_backend"]:
                    cmd = ssh_t_cmd(ip, "service php-fpm stop")
                elif srv in ["php_worker", "supervisord"]:
                    cmd = ssh_t_cmd(ip, "service supervisord stop")
                elif srv == "mysql":
                    if self.ipconfig.is_server_cluster(srv):
                        cmd = ssh_t_cmd(ip, "service mysql stop")
                    else:
                        cmd = ssh_t_cmd(ip, "service mysqld stop")
                elif "mongo_java" == srv or "mongo_ms_srv" == srv:
                    if self.ipconfig.is_server_cluster(srv):
                        cmd = ssh_t_cmd(ip, "/etc/init.d/mongos stop")
                    else:
                        cmd = ssh_t_cmd(ip, "service mongod stop")
                elif "java_mongod_cs" == srv or "ms_srv_mongod_cs" == srv :
                        cmd = ssh_t_cmd(ip, "/etc/init.d/mongod_cs stop")
                elif re.match(r"(.*)mongod_\d{5}", srv):
                        cmd = ssh_t_cmd(ip, "/etc/init.d/{mongod_port} stop".format(mongod_port=srv[-12:]))
                elif "redis_php" == srv:
                    if self.ipconfig.is_server_cluster(srv):
                        if ":" in ip:
                            cmd = self._build_cluster_cmd(ip, "stop")
                        else:
                            cmd = ssh_t_cmd(ip,"service redis6380d stop && service redis6480d stop && service redis6580d stop")
                    else:
                        real_ip = ip.split(':')[0]
                        cmd = ssh_t_cmd(real_ip, "service redis6380d stop")
                elif "redis_erlang" == srv:
                    if self.ipconfig.is_server_cluster(srv):
                        if ":" in ip:
                            cmd = self._build_cluster_cmd(ip, "stop")
                        else:
                            cmd = ssh_t_cmd(ip,"service redis6379d stop && service redis6479d stop && service redis6579d stop")
                    else:
                        real_ip = ip.split(':')[0]
                        cmd = ssh_t_cmd(real_ip, "service redis6379d stop")
                elif "redis_java" == srv:
                    if self.ipconfig.is_server_cluster(srv):
                        if ":" in ip:
                            cmd = self._build_cluster_cmd(ip, "stop")
                        else:
                            cmd = ssh_t_cmd(ip,"service redis6381d stop && service redis6481d stop && service redis6581d stop")
                    else:
                        real_ip = ip.split(':')[0]
                        cmd = ssh_t_cmd(real_ip, "service redis6381d stop")
                elif "java_kafka" == srv:
                    cmd = ssh_t_cmd(ip, "service kafkad stop")
                # elif re.match(r"bigdata_es_(\d+)", srv):
                #     num = re.match(r"bigdata_es_(\d+)", srv).group(1)
                #     cmd = ssh_t_cmd(ip, "service elasticsearch_ins{num} stop".format(num=num))
                # elif "bigdata_logstash" == srv:
                    # cmd = ssh_t_cmd(ip, "service qingteng-consumer stop")
                # elif "bigdata_viewer" == srv:
                    # cmd = ssh_t_cmd(ip, "service qingteng-viewer stop")
                elif "java_zookeeper" == srv:
                    cmd = ssh_t_cmd(ip, "service zookeeperd stop")
                elif "java" == srv:
                    cmd = ssh_t_cmd(ip, "su -s /bin/sh -c '/data/app/titan-wisteria/init.d/wisteria stop' titan")
                elif "java_gateway" == srv:
                    cmd = ssh_t_cmd(ip, "su -s /bin/sh -c '/data/app/titan-gateway/init.d/gateway stop' titan")
                elif "java_user-srv" == srv:
                    cmd = ssh_t_cmd(ip, "su -s /bin/sh -c '/data/app/titan-user-srv/init.d/user-srv stop' titan")
                elif "java_patrol-srv" == srv:
                    cmd = ssh_t_cmd(ip, "su -s /bin/sh -c '/data/app/titan-patrol-srv/init.d/patrol-srv stop' patrol")
                elif "java_upload-srv" == srv:
                    cmd = ssh_t_cmd(ip, "su -s /bin/sh -c '/data/app/titan-upload-srv/init.d/upload-srv stop' titan")
                elif "java_detect-srv" == srv:
                    cmd = ssh_t_cmd(ip, "su -s /bin/sh -c '/data/app/titan-detect-srv/init.d/detect-srv stop' titan")
                elif "java_scan-srv" == srv:
                    cmd = ssh_t_cmd(ip, "su -s /bin/sh -c '/data/app/titan-scan-srv/init.d/scan-srv stop' titan")
                elif "java_anti-virus-srv" == srv:
                    cmd = ssh_t_cmd(ip, "su -s /bin/sh -c '/data/app/titan-anti-virus-srv/init.d/anti-virus-srv stop' titan")
                elif "java_ms-srv" == srv:
                    cmd = ssh_t_cmd(ip, "su -s /bin/sh -c '/data/app/titan-ms-srv/init.d/ms-srv stop' titan")
                elif "java_event-srv" == srv:
                    cmd = ssh_t_cmd(ip, "su -s /bin/sh -c '/data/app/titan-event-srv/init.d/event-srv stop' titan")
                elif "java_job-srv" == srv:
                    cmd = ssh_t_cmd(ip, "su -s /bin/sh -c '/data/app/titan-job-srv/init.d/job-srv stop' titan")
                elif "java_connect-selector" == srv:
                    cmd = ssh_t_cmd(ip, "su -s /bin/sh -c '/data/app/titan-connect-selector/init.d/connect-selector stop' titan")
                elif "java_connect-sh" == srv:
                    cmd = ssh_t_cmd(ip, "su -s /bin/sh -c '/data/app/titan-connect-sh/init.d/connect-sh stop' titan")
                elif "java_connect-dh" == srv:
                    cmd = ssh_t_cmd(ip, "su -s /bin/sh -c '/data/app/titan-connect-dh/init.d/connect-dh stop' titan")
                elif "java_connect-agent" == srv:
                    cmd = ssh_t_cmd(ip, "su -s /bin/sh -c '/data/app/titan-connect-agent/init.d/connect-agent stop' titan")
                elif "keepalived" == srv:
                    cmd = ssh_t_cmd(ip, "service keepalived stop")
                elif "glusterfs" == srv:
                    cmd = ssh_t_cmd(ip, "service glusterd stop")
                else:
                    cmd=""

                if cmd:
                    log_info("Execute Stop Command: " + cmd)
                    commands.getstatusoutput(cmd)

class APICheck(object):
    """The class search error log and ."""
    def __init__(self, ipconfig):
        self.ipconfig = ipconfig
        if self.ipconfig.is_server_cluster("java_gateway"):
            self.server_map["java_gateway"]["port"] = "16000"
        if self.ipconfig.is_server_cluster("java_connect-selector"):
            self.server_map["java_connect-selector"]["port"] = "16677"

    """
    check server status
    """

    server_map = {
        "java": {
            "key": "wisteria",
            "selfCheckApi": "v1/assets/selfcheck/checkall",
            "port":"6100"
        },
        "java_patrol-srv": {
            "key": "patrol-srv",
            "selfCheckApi": "v1/patrol/api/ping",
            "port":"6110"
        },
        "java_gateway": {
            "key": "gateway",
            "selfCheckApi": "v1/api/front/checkall",
            "port":"6000"
        },
        "java_upload-srv": {
            "key": "upload-srv",
            "selfCheckApi": "internal/ping/checkall",
            "port":"6130"
        },
        "java_user-srv": {
            "key": "user-srv",
            "selfCheckApi": "api/checkall",
            "port":"6120"
        },
        "java_detect-srv": {
            "key": "detect-srv",
            "selfCheckApi": "api/checkall",
            "port":"6140"
        },
        "java_scan-srv": {
            "key": "scan-srv",
            "selfCheckApi": "api/checkall",
            "port":"6150"
        },
        "java_anti-virus-srv": {
            "key": "anti-virus-srv",
            "selfCheckApi": "api/checkall",
            "port":"6240"
        },
        "java_ms-srv": {
            "key": "ms-srv",
            "selfCheckApi": "api/checkall",
            "port":"6400"
        },
        "java_event-srv": {
            "key": "event-srv",
            "selfCheckApi": "api/checkall",
            "port":"6700"
        },
        "java_job-srv": {
            "key": "job-srv",
            "selfCheckApi": "api/checkall",
            "port":"6170"
        },
        "java_connect-agent": {
            "key": "connect-agent",
            "selfCheckApi": "api/checkall",
            "port":"6220"
        },
        "java_connect-selector": {
            "key": "connect-selector",
            "selfCheckApi": "api/checkall",
            "port":"6677"
        },
        "java_connect-dh": {
            "key": "connect-dh",
            "selfCheckApi": "api/checkall",
            "port":"6210"
        },
        # "bigdata_viewer": {
        #     "key": "bigdata_viewer",
        #     "selfCheckApi": "insight/v1.0/qt_viewer/monitor"
        # },
        # "bigdata_logstash": {
        #     "key": "bigdata_logstash",
        #     "selfCheckApi": "insight/v1.0/qt_consumer/monitor"
        # },
        "php_api": {
            "key": "api",
            "selfCheckApi": "testrun/check"
        },
        "php_agent": {
            "key": "agent",
            "selfCheckApi": "testrun/check"
        },
        "php_innerapi": {
            "key": "innerapi",
            "selfCheckApi": "testrun/check"
        },
        "php_backend": {
            "key": "backend",
            "selfCheckApi": "testrun/check"
        }
    }

    def _cp_java_config(self, java_ip, local_path):
        cmd = "scp -P %d %s@%s:%s %s" % (DEFAULT_SSH_PORT, DEFAULT_SSH_USER, java_ip, DEFAULT_JAVA_JSON, local_path)
        os.system(cmd)

    def load_config(self, confi_file):
        data = {}
        with open(confi_file) as f:
            data = json.load(f)
        if not data:
            return
        host_info = data.get("host", {})
        bigdata_enable = data.get("app", {}).get("wisteria", {}).get("bigdata", {}).get("enable", False)
        scan_enable = data.get("app", {}).get("wisteria", {}).get("docker_scan", {}).get("enable", False)
        ms_ip = self.ipconfig.get_ips("java_ms-srv")
        if ms_ip == []:
            ms_enable = False
        else:
            ms_enable = True

        anti_virus_ip = self.ipconfig.get_ips("java_anti-virus-srv")
        if anti_virus_ip == []:
            anti_virus_enable = False
        else:
            anti_virus_enable = True

        ret = {}

        for server in self.server_map.keys():
            # if not bigdata_enable and (server == "bigdata_viewer" or server == "bigdata_logstash"):
                # continue
            if not scan_enable and server == "java_scan-srv":
                continue
            if not ms_enable and server == "java_ms-srv":
                continue   
            if not anti_virus_enable and server == "java_anti-virus-srv":
                continue

            info = {"url": []}
            key = self.server_map[server]["key"]
            if server.startswith("java"):
                #in ip.json, cluster config's port maybe not correct
                ips = self.ipconfig.get_ips(server)
                for ip in ips:
                    java_url = "%s://%s:%s/%s" % ("http", ip, self.server_map[server]["port"], self.server_map[server]["selfCheckApi"])
                    ret.setdefault(server,{})
                    ret[server].setdefault("url",[])
                    ret[server]["url"].append(java_url)
                
                continue

            if host_info.get(key, {}):
                ssl = host_info[key].get("ssl")
                protocol = "https" if ssl else "http"
                privateip = host_info[key].get("privateip")
                if privateip == "none":
                    continue
                port = host_info[key].get("port")
                if privateip and port:
                    info["url"] = ["%s://%s:%s/%s" % (protocol, privateip, port, self.server_map[server]["selfCheckApi"])]
            ret[server] = info

        return ret

    def _do_request_with_curl(self, method, url, data=None):
        if method == "get":
            cmd = "curl -k --connect-timeout 10 -sS -X GET -H 'Content-Type: application/json; charset=utf-8' {0} 2>&1".format(url)
            status, content = commands.getstatusoutput(cmd)
            if status != 0:
                return content, 0
            else:
                return content, 200


    def check_status(self, java_ip):
        # copy java config file to get ip address
        local_path = os.path.dirname(os.path.abspath(__file__))
        config_file = local_path
        if java_ip != "127.0.0.1":
            config_file = os.path.join(local_path, os.path.basename(DEFAULT_JAVA_JSON))
            self._cp_java_config(java_ip, local_path)
        else:
            config_file = DEFAULT_JAVA_JSON
        config_json = self.load_config(config_file)
        server_api_list = {}
        for server in config_json.keys():
            urls = config_json[server]["url"]
            for url in urls:
                info = {"name": server, "url": url, "code": 200, "result": ""}
                info["result"], info["code"] = self._do_request_with_curl("get", url)
                server_api_list.setdefault(server, [])
                server_api_list[server].append(info)
        return server_api_list

    def parse_data(self, server_api_list, formation="list"):

        if formation == "list":
            table_data_api = [[]]
            table_data_api[0] = ['Server', 'API', 'Code', 'Result']
        else:
            table_data_api = []

        for server_name in sorted(server_api_list.keys()):
            api_results = server_api_list[server_name]
            for row in api_results:
                if formation == "list":
                    #result too long, then the output in console not easy to see, so limit 200
                    result = json.dumps(row["result"])
                    if len(result) > 200:
                        result = result[:200] + "......"
                    else:
                        result = json.loads(result)
                    rowdata = [row["name"], row["url"], str(row["code"]), result]
                else:
                    rowdata = row
                table_data_api.append(rowdata)

        return table_data_api

    def dump(self, server_api_list, server_info_list):
        now = time.strftime("%Y-%m-%d %H:%M:%S", time.localtime())
        print 'Server SelfCheckAPI Status'
        print '---------------------'
        print now
        print ''

        table_data_api = self.parse_data(server_api_list)
        print_table(table_data_api)

class IpConfig(object):

    def __init__(self, config_file, verbose=False):
        self._ip_template =  json.load(open(config_file,'r'))
        self.server_ips = self.get_server_ips()

    def get_ip(self, name):
        """
        :param name:
        :return:
        """
        return self._ip_template[name]

    # from ip.json to servername
    def get_server_ips(self):
        server_ips = {}

        ipjson_servername_map = {
            "erl_rabbitmq": "erlang_rabbitmq",
            "php_worker_ip": "php_worker",
            "php_api_private": "php_api",
            "php_agent_private": "php_agent",
            "php_inner_api": "php_inner_api",
            "php_frontend_private": "php_frontend",
            "php_backend_private": "php_user_backend",
            # "bigdata_logstash": "bigdata_logstash",
            # "bigdata_viewer": "bigdata_viewer",
            # "bigdata_es": "bigdata_es",
            "java": "java",
            "java_gateway": "java_gateway",
            "java_patrol-srv": "java_patrol-srv",
            "java_upload-srv": "java_upload-srv",
            "java_detect-srv": "java_detect-srv",
            "java_scan-srv": "java_scan-srv",
            "java_anti-virus-srv": "java_anti-virus-srv",
            "java_ms-srv": "java_ms-srv",
            "java_event-srv": "java_event-srv",
            "java_user-srv": "java_user-srv",
            "java_job-srv": "java_job-srv",
            "java_connect-selector": "java_connect-selector",
            "java_connect-sh": "java_connect-sh",
            "java_connect-dh": "java_connect-dh",
            "java_connect-agent": "java_connect-agent",
            "java_zookeeper": "java_zookeeper",
            "java_kafka": "java_kafka",
            "db_mongo_java": "mongo_java",
            "db_mongo_java_mongod_cs": "java_mongod_cs",
            "db_mongo_ms_srv": "mongo_ms_srv",
            "db_mongo_ms_srv_mongod_cs": "ms_srv_mongod_cs",
            "db_mysql_php": "mysql",
            "db_redis_erlang": "redis_erlang",
            "db_redis_php": "redis_php",
            "db_redis_java": "redis_java",
            "keepalived": "keepalived",
            "glusterfs": "glusterfs"
        }
        
        for name, ip_addr in self._ip_template.items():
            ips = []
            cluster_addr = self._ip_template.get(name + "_cluster", None)
            if cluster_addr and not "127.0.0.1" in cluster_addr:
                ip_addr = cluster_addr

            ip_ports = ip_addr.split(',')
            for ip_port in ip_ports:
                ip = ip_port.split(':')[0]
                if ip != '' and ip != "127.0.0.1":
                    ips.append(ip)

            server_name = ipjson_servername_map.get(name, None)
            if server_name:
                if server_name == "bigdata_es":
                    server_ips[server_name + "_1"] = [ip_addr]
                    server_ips[server_name + "_2"] = [ip_addr]
                    server_ips[server_name + "_3"] = [ip_addr]
                    server_ips[server_name + "_4"] = [ip_addr]
                else:
                    server_ips[server_name] = ips
            else:
                matchObj = re.search(r"db_mongo_java_(mongod_\d{5})", name)
                if matchObj:
                    server_name = 'java_' + matchObj.group(1)
                    server_ips[server_name] = ips
                
                matchObj = re.search(r"db_mongo_ms_srv_(mongod_\d{5})", name)
                if matchObj:
                    server_name = 'ms_srv_' + matchObj.group(1)
                    server_ips[server_name] = ips
                    
                # matchObj = re.match(r"bigdata_es_(\d+)", name)
                # if matchObj:
                #     server_ips[name] = ips

        return server_ips

    def dump():
        return json.dumps(self._ip_template)

    def get_ips(self, name): 
        if not self.server_ips.has_key(name):
            return [] 
        result = []  
        for ip in self.server_ips[name]:
            if ip and ip !='' and ip != '127.0.0.1':
                result.append(ip) 
        return result

    def is_server_cluster(self, server_name):
        return len(self.server_ips[server_name]) > 1

    def get_local_ip(self):
        ip_cmd = '''ip addr|grep inet '''
        status, output = commands.getstatusoutput(ip_cmd)
        if status == 0:
            php_ips = self.get_ips("php_frontend")
            for ip in php_ips:
                if ip + "/" in output:
                    return ip
        
        return '127.0.0.1'


class ProcessCheck(object):
    """The class to retrieve process information from remote Titan servers."""

    # ordered list for dump
    server_name_list = ['erlang_rabbitmq',
                        'php_api',
                        'php_agent',
                        'php_inner_api',
                        'php_frontend',
                        'php_user_backend',
                        'php_worker',
                        'mysql',
                        'mongo_java',
                        'java_mongod_cs',
                        'java_mongod_{port}',
                        'mongo_ms_srv',
                        'ms_srv_mongod_cs',
                        'ms_srv_mongod_{port}',
                        'redis_erlang',
                        'redis_php',
                        'redis_java',
                        # 'bigdata_logstash',
                        # 'bigdata_viewer',
                        # 'bigdata_es_{num}',
                        'java',
                        'java_gateway',
                        'java_patrol-srv',
                        'java_upload-srv',
                        'java_user-srv',
                        'java_detect-srv',
                        'java_scan-srv',
                        'java_ms-srv',
                        'java_anti-virus-srv',
                        'java_event-srv',
                        'java_job-srv',
                        'java_connect-selector',
                        'java_connect-sh',
                        'java_connect-dh',
                        'java_connect-agent',
                        'java_zookeeper',
                        'java_kafka',
                        'keepalived',
                        'glusterfs'
                    ]
    server_list = {
        "erlang_rabbitmq": [
            {
                "keyword": "beam.smp.*rabbitmq",
                "name": "rabbit"
            }
        ],
        "php_api": [
            {
                "keyword": "nginx: master process",
                "name": "nginx"
            },
            {
                "keyword": "php-fpm: master process",
                "name": "php-fpm"
            }
        ],
        "php_agent": [
            {
                "keyword": "nginx: master process",
                "name": "nginx"
            },
            {
                "keyword": "php-fpm: master process",
                "name": "php-fpm"
            }
        ],
        "php_inner_api": [
            {
                "keyword": "nginx: master process",
                "name": "nginx"
            },
            {
                "keyword": "php-fpm: master process",
                "name": "php-fpm"
            }
        ],
        "php_frontend": [
            {
                "keyword": "nginx: master process",
                "name": "nginx"
            },
            {
                "keyword": "php-fpm: master process",
                "name": "php-fpm"
            }
        ],
        "php_user_backend": [
            {
                "keyword": "nginx: master process",
                "name": "nginx"
            },
            {
                "keyword": "php-fpm: master process",
                "name": "php-fpm"
            }
        ],
        "php_worker": [
            {
                "keyword": "supervisord",
                "name": "supervisord"
            }
        ],
        "mysql": [
            {
                "keyword": "mysqld ",
                "name": "mysqld"
            }
        ],
        "mongo_java": [
            {
                "keyword": "mongod ",
                "name": "java_mongod"
            }
        ],
        "mongo_java_cluster": [
            {
                "keyword": "mongos -f.*mongos",
                "name": "mongos"
            }
        ],
        "java_mongod_cs": [
            {
                "keyword": "mongod -f.*mongod_cs",
                "name": "mongod_cs"
            }
        ],
        "java_mongod_{port}": [
            {
                "keyword": "mongod -f.*mongod_{port}",
                "name": "mongod_{port}"
            }
        ],
        "mongo_ms_srv": [
            {
                "keyword": "mongod ",
                "name": "mongod"
            }
        ],
        "mongo_ms_srv_cluster": [
            {
                "keyword": "mongos -f.*mongos",
                "name": "mongos"
            }
        ],
        "ms_srv_mongod_cs": [
            {
                "keyword": "mongod -f.*mongod_cs",
                "name": "mongod_cs"
            }
        ],
        "ms_srv_mongod_{port}": [
            {
                "keyword": "mongod -f.*mongod_{port}",
                "name": "mongod_{port}"
            }
        ],
        "redis_erlang": [
            {
                "keyword": "redis-server.*6379",
                "name": "redis6379d"
            }
        ],
        "redis_erlang_cluster": [
            {
                "keyword": "redis-server.*6379",
                "name": "redis6379d"
            },
            {
                "keyword": "redis-server.*6479",
                "name": "redis6479d"
            },
            {
                "keyword": "redis-server.*6579",
                "name": "redis6579d"
            }
        ],
        "redis_php": [
            {
                "keyword": "redis-server.*6380",
                "name": "redis6380d"
            }
        ],
        "redis_php_cluster": [
            {
                "keyword": "redis-server.*6380",
                "name": "redis6380d"
            },
            {
                "keyword": "redis-server.*6480",
                "name": "redis6480d"
            },
            {
                "keyword": "redis-server.*6580",
                "name": "redis6580d"
            }
        ],
        "redis_java": [
            {
                "keyword": "redis-server.*6381",
                "name": "redis6381d"
            }
        ],
        "redis_java_cluster": [
            {
                "keyword": "redis-server.*6381",
                "name": "redis6381d"
            },
            {
                "keyword": "redis-server.*6481",
                "name": "redis6481d"
            },
            {
                "keyword": "redis-server.*6581",
                "name": "redis6581d"
            }
        ],
        # "bigdata_logstash": [
        #     {
        #         "keyword": "qt_consumer/master.py",
        #         "name": "bigdata_logstash"
        #     }
        # ],
        # "bigdata_viewer": [
        #     {
        #         "keyword": "bin/uwsgi .*qt_viewer",
        #         "name": "bigdata_viewer"
        #     }
        # ],
        # "bigdata_es_{num}": [
        #     {
        #         "keyword": "org.elasticsearch.bootstrap.Elasticsearch .*elasticsearch_ins{num}",
        #         "name": "bigdata_es_{num}"
        #     },
        # ],
        "java": [
            {
                "keyword": "wisteria.jar",
                "name": "wisteria.jar"
            }
        ],
        "java_gateway": [
            {
                "keyword": "gateway.jar",
                "name": "gateway.jar"
            }
        ],
        "java_patrol-srv": [
            {
                "keyword": "patrol-srv.jar",
                "name": "patrol-srv.jar"
            }
        ],
        "java_upload-srv": [
            {
                "keyword": "upload-srv.jar",
                "name": "upload-srv.jar"
            }
        ],
        "java_user-srv": [
            {
                "keyword": "user-srv.jar",
                "name": "user-srv.jar"
            }
        ],
        "java_detect-srv": [
            {
                "keyword": "detect-srv.jar",
                "name": "detect-srv.jar"
            }
        ],
        "java_scan-srv": [
            {
                "keyword": "scan-srv.jar",
                "name": "scan-srv.jar"
            }
        ],
        "java_ms-srv": [
            {
                "keyword": "ms-srv.jar",
                "name": "ms-srv.jar"
            }
        ],
        "java_anti-virus-srv": [
            {
                "keyword": "anti-virus-srv.jar",
                "name": "anti-virus-srv.jar"
            }
        ],
        "java_event-srv": [
            {
                "keyword": "event-srv.jar",
                "name": "event-srv.jar"
            }
        ],
        "java_job-srv": [
            {
                "keyword": "job-srv.jar",
                "name": "job-srv.jar"
            }
        ],
        "java_connect-selector": [
            {
                "keyword": "connect-selector.jar",
                "name": "connect-selector.jar"
            }
        ],
        "java_connect-sh": [
            {
                "keyword": "connect-sh.jar",
                "name": "connect-sh.jar"
            }
        ],
        "java_connect-dh": [
            {
                "keyword": "connect-dh.jar",
                "name": "connect-dh.jar"
            }
        ],
        "java_connect-agent": [
            {
                "keyword": "connect-agent.jar",
                "name": "connect-agent.jar"
            }
        ],
        "java_zookeeper": [
            {
                "keyword": "org.apache.zookeeper",
                "name": "org.apache.zookeeper"
            }
        ],
        "java_kafka": [
            {
                "keyword": "kafka.logs.dir",
                "name": "kafka.logs.dir"
            }
        ],
        "keepalived": [
            {
                "keyword": "keepalived",
                "name": "keepalived"
            }
        ],
        "glusterfs": [
            {
                "keyword": "glustershd",
                "name": "glustershd"
            },
            {
                "keyword": "glusterd.*glusterd.pid",
                "name": "glusterd"
            },
            {
                "keyword": "glusterfsd",
                "name": "glusterfsd"
            }
        ]
    }

    def __init__(self, ipconfig, verbose=False):
        self.ipconfig = ipconfig
        self.server_ips = ipconfig.get_server_ips()
        self.verbose = verbose

    def load_config(self):
        """Load titan server ip config file.

        Returns:
            json object of config file.
        """

        if self.verbose:
            print "ip config:"
            print(self.server_ips)

        # if is cluster, need use _cluster process keymap
        for server_name in ['mongo_java','mongo_ms_srv','redis_erlang','redis_php','redis_java']:
            if len(self.server_ips[server_name]) > 1:
                self.server_list[server_name] =  self.server_list[server_name + '_cluster']

    def get_process_conf(self, server_name):
        if self.server_list.has_key(server_name):
            return self.server_list[server_name]

        mongod_port_reg = r"mongod_\d{5}"
        matchObj = re.search(mongod_port_reg, server_name)
        if matchObj:
            mongod_port = matchObj.group(0)
            mongo_server_match_name_ms = r"ms_srv"
            mongo_server_match_name_java = r"java"
            result_conf = []
            matchObj_ms = re.search(mongo_server_match_name_ms, server_name)
            matchObj_java = re.search(mongo_server_match_name_java, server_name)
            if matchObj_ms:                
                result_conf.append({
                    "keyword": "mongod -f.*" + mongod_port,
                    "name": mongod_port  })
                index_no = self.server_name_list.index("ms_srv_mongod_{port}")
                self.server_name_list.insert(index_no, 'ms_srv_{mongod_port}'.format(mongod_port=mongod_port))                
            elif matchObj_java:
                result_conf.append({
                    "keyword": "mongod -f.*" + mongod_port,
                    "name": mongod_port  })
                index_no = self.server_name_list.index("java_mongod_{port}")
                self.server_name_list.insert(index_no, 'java_{mongod_port}'.format(mongod_port=mongod_port))
            else:
                pass
            return result_conf
        # es_num_reg = r"bigdata_es_(\d+)"
        # matchObj = re.match(es_num_reg, server_name)
        # if matchObj:
        #     num = matchObj.group(1)
        #     result_conf = []
        #     result_conf.append({
        #             "keyword": "org.elasticsearch.bootstrap.Elasticsearch .*elasticsearch_ins" + num,
        #             "name": "bigdata_es_" + num })
        #     index_no = self.server_name_list.index("bigdata_es_{num}")
        #     self.server_name_list.insert(index_no, "bigdata_es_" + num)
        #     return result_conf

        return None

    def _merge_servers(self):
        """Merge server role with the same ip address.

        Args:
            server_list: The predefined server list, e.g.:
                server_list = {
                    "java": [
                            { "keyword": "wisteria.jar", "name": "java" }
                    ],
                    "gateway": [
                            { "keyword": "gateway.jar", "name": "gateway"}
                    ]
                }

                server_ips = {
                    "java":[127.0.0.1,127.0.0.2],
                    "gateway":[127.0.0.1,127.0.0.2]
                }

        Returns:
            The ip list info, e.g.:
                ip_server_process_list: [
                    "127.0.0.1": {
                        "java": [
                            { "keyword": "wisteria.jar", "name": "java" }
                        ],
                        "gateway": [
                            { "keyword": "gateway.jar", "name": "gateway"}
                        ]
                    }
                ]
        """
        ip_server_process_list = {}
        for server_name, ip_addr_list in self.server_ips.items():
            process_list = self.get_process_conf(server_name)
            for ip_addr in ip_addr_list:
                if not ip_addr:
                    continue
                ip_server_process_list.setdefault(ip_addr, {})
                ip_server_process_list[ip_addr][server_name] = process_list

        return ip_server_process_list

    def _get_process_info(self, ip_addr, keywords):
        """Get process info from remote ip address.

        Args:
            ip_addr: The server ip address.
            keywords: The keyword used for grep to find process.

        Returns:
            The output of shell command "ps aux | grep keywords".
        """
        cmd = "|".join(keywords)

        if keywords:
            cmd = 'ps auxf |egrep "' + cmd + '" | grep -v grep | grep -v titan_system_check'
        else:
            cmd = 'ps auxf | grep -v grep'
        # because bigdata logstash and bigdata_viewer have subprocess  ps auxf then grep -v \_ 
        #if "qt_logstash" in cmd or "qt_viewer" in cmd:
        #        cmd = cmd + "|egrep -v '\_ .*qt_consumer/master.py|\_ .*bin/uwsgi .*qt_viewer'"
        if "keepalived" in cmd:
                cmd = cmd + "|egrep -v '\_ .*keepalived'"

        cmd = ssh_cmd(ip_addr, cmd)
        if self.verbose:
            print cmd

        status, output = commands.getstatusoutput(cmd)
        if status != 0:
            log_error("Failed to execute command: " + cmd)
            log_error("(%d) %s" % (status, output if output else "-"))
        return status, output

    def _get_system_info(self, ip_addr):
        """Get system cpu/memory/disk info from remote ip address.

        Args:
            ip_addr: The server ip address.
            keywords: The keyword used for grep to find process.

        Returns:
            The output of shell command "ps aux | grep keywords".
        """
        ret = {}
        # cpu usage %
        cmd = "top -b -n 2 -d.5 | grep 'Cpu' | grep -v 'grep' | tail -1 | sed -r 's/.*,(.*)id.*/\\1/'|tr ',' '.'"
        cmd = ssh_cmd(ip_addr, cmd)

        if self.verbose:
            print cmd

        status, output = commands.getstatusoutput(cmd)
        cpu = '-'
        if status == 0:
            cpu = output.strip()
            if "%" in output:
                cpu = cpu.replace('%', '')
            cpu = str(100 - float(cpu))
        else:
            log_error("Failed to execute command: " + cmd)
            log_error("(%d) %s" % (status, output if output else "-"))
        ret['cpu'] = cpu

        # cpu number
        cmd = "grep ^processor /proc/cpuinfo | wc -l"
        cmd = ssh_cmd(ip_addr, cmd)

        if self.verbose:
            print cmd

        status, output = commands.getstatusoutput(cmd)
        cpu_num = '-'
        if status == 0:
            cpu_num = output.strip()
        else:
            log_error("Failed to execute command: " + cmd)
            log_error("(%d) %s" % (status, output if output else "-"))
        ret['cpu_num'] = cpu_num

        # memory usage %
        cmd = "grep -E '^MemTotal:|^MemFree:|^Cached:' /proc/meminfo | awk '{print $2}' | awk -vRS='' -vOFS=' ' NF+=0"
        cmd = ssh_cmd(ip_addr, cmd)

        if self.verbose:
            print cmd

        status, output = commands.getstatusoutput(cmd)
        mem = '-'
        mem_size = '-'
        if status == 0:
            mems = output.strip().split()
            mem = (int(mems[0]) - int(mems[1]) - int(mems[2])) * 100 / int(mems[0])
            # memory size
            mem_size = int(mems[0])
            mem_float = float(mem_size)
            mem_float = mem_float / (1024 * 1024)
            mem_float = math.ceil(mem_float)
            mem_int = int(mem_float)
            mem_size = str(mem_int)
            mem_size = mem_size + 'G'
        else:
            log_error("Failed to execute command: " + cmd)
            log_error("(%d) %s" % (status, output if output else "-"))

        ret['mem'] = str(mem)+"%" if mem != '-' else mem
        ret['mem_size'] = mem_size
        
        # disk size (/)
        cmd = "df -Ph 2>/dev/null | grep /$"
        cmd = ssh_cmd(ip_addr, cmd)

        if self.verbose:
            print cmd

        status, output = commands.getstatusoutput(cmd)
        disk_root_size = '-'
        disk_root = '-'
        if status == 0:
            disk_infos = output.strip().split()
            size, usage = disk_infos[1], disk_infos[4]
            if "T" in output:
                disk_root_size = "%sG" % (float(size.strip()[:-1]) * 1024)
            elif "G" in output:
                disk_root_size = size
            elif "M" in output:
                disk_root_size = "%.2f" % (float(size.strip()[:-1]) / 1024.0) + 'G'

            if '%' in usage:
                disk_root = usage
        else:
            log_error("Failed to execute command: " + cmd)
            log_error("(%d) %s" % (status, output if output else "-"))
        ret['disk_root_size'] = disk_root_size
        ret['disk_root'] = disk_root

        # disk size (/data)
        cmd = "df -Ph 2>/dev/null | grep /data$ || echo no_data_disk"
        cmd = ssh_cmd(ip_addr, cmd)

        if self.verbose:
            print cmd

        status, output = commands.getstatusoutput(cmd)
        disk_data_size = '-'
        disk_data = '-'
        if status == 0:
            if 'no_data_disk' not in output:
                disk_infos = output.strip().split()
                size, usage = disk_infos[1], disk_infos[4]
                if "T" in output:
                    disk_data_size = "%sG" % (float(size.strip()[:-1]) * 1024)
                elif "G" in output:
                    disk_data_size = size.strip()
                elif "M" in output:
                    disk_data_size = "%.2f" % (float(size.strip()[:-1]) / 1024.0) + 'G'

                if '%' in usage:
                    disk_data = usage
        else:
            log_error("Failed to execute command: " + cmd)
            log_error("(%d) %s" % (status, output if output else "-"))
            if not disk_data_size:
                disk_data_size = '-'
        ret['disk_data_size'] = disk_data_size
        ret['disk_data'] = disk_data

        return ret

    def _extract_process_info(self, process_list, process_output):
        """Parse ps command output and extract process name/pid/cpu/mem.

        Args:
            process_list: The processlist which need have data structure.
            process_output: The output of shell ps command.

        Returns:
            The list of process info, e.g.:
            [
                {
                    "name": "servicer_1_1"
                    "pid": "1120"
                    "cpu": "0.1"
                    "mem": "0.2"
                }, {
                    "name": "servicer_1_2"
                    "pid": "1121"
                    "cpu": "0.1"
                    "mem": "0.2"
                }
            ]
        """
        process_info_list = []
        for process in process_list:
            process_exist = False
            for line in process_output.splitlines():
                process_info = {}
                if re.search(process['keyword'], line):
                    process_exist = True
                    rows = line.split()
                    process_info['pid'] = rows[1]
                    process_info['cpu'] = rows[2]
                    process_info['mem'] = rows[3]
                    process_info['name'] = process['name']
                    process_info_list.append(process_info)
                    process_exist = True

            if not process_exist:
                process_info_list.append({'pid':"-", 'cpu':"-", 'mem':"-", 'name': process['name']})

        return process_info_list

    def _remove_duplicate_php_process(self, process_info):
        """Remove duplicate process information.

        Multiple PHP server role may share one server, and share the same
        process, i.e. nginx and php-fpm. So, only one copy of the process info
        need be reported to log.

        Args:
            process_info: Return of check_process().

        Returns:
            process_info which duplicate process info are removed.
        """
        ip_list = set()
        for server_name in process_info:
            if not server_name.startswith('php') or server_name == 'php_worker':
                continue
            for ip_addr in process_info[server_name].keys():
                if self.verbose:
                    print server_name
                    print ip_addr
                if ip_addr in ip_list:
                    # duplicate host, remove it
                    del process_info[server_name][ip_addr]
                else:
                    ip_list.add(ip_addr)
        return process_info

    def check_process(self):
        """Check process information of each titan server role.

        Args:
            server_list: The server list data structure.

        Returns:
            Server list with process info, e.g.:
                server_process_list = {
                    "erlang_sh": {
                        "127.0.0.1": [{
                                "name": "servicer_1_1",
                                "pid": "1120",
                                "cpu": "0.1",
                                "mem": "0.2",
                            }, {
                                "name": "servicer_1_2"
                                "pid": "1121"
                                "cpu": "0.1"
                                "mem": "0.2"
                            }
                        ]
                    }
                }
        """
        # load server config file to get ip address
        self.load_config()

        ip_server_process_list = self._merge_servers()
        if self.verbose:
            print "\nip_server_process_list:"
            print ip_server_process_list
            print "\ncheck remote process:"

        server_process_list = {} # process info
        server_info_list = {}   # cpu memory disk eg..

        for ip_addr, server_process in ip_server_process_list.items():
            if self.verbose:
                print "ip: " + ip_addr
            if ip_addr == "127.0.0.1":
                continue

            server_info_list[ip_addr] = self._get_system_info(ip_addr)

            keywords = set()
            for server_name, process_list in server_process.items():
                for process in process_list:
                    keywords.add(process["keyword"]) 

            status, process_output = self._get_process_info(ip_addr, keywords)
            if status != 0 or not process_output:
                process_output = ''   # for _extract_process_info 
            if self.verbose:
                print process_output

            for server_name, process_list in server_process.items():
                process_info_list = self._extract_process_info(process_list, process_output)

                server_process_list.setdefault(server_name, {})
                server_process_list[server_name][ip_addr] = process_info_list

        return server_process_list, server_info_list

    def parse_data(self, server_process_list, server_info_list, formation="list"):

        if formation == "list":
            table_data_process = [[]]
            table_data_process[0] = ['Server', 'IP', 'PID', '%CPU', '%MEM', 'COMMAND', 'Status']

            table_data_server = [[]]
            table_data_server[0] = ['IP', 'CPU Num', 'CPU Use%', 'Memory Size', 'Memory Use%', 'Disk Size(/)', 'Disk Use%(/)', 'Disk Size(/data)', 'Disk Use%(/data)', 'Status']
        else:
            table_data_process = []
            table_data_server = []

        ip_cpunum_map = {}
        for ip_addr in server_info_list:
            info = server_info_list[ip_addr]
            if not info['cpu_num'] == '-':
                ip_cpunum_map[ip_addr] = int(info['cpu_num'])

        ip_status_map = {}
        for server_name in self.server_name_list:
            if not self.server_ips.has_key(server_name):
                continue
            for ip_addr in self.server_ips[server_name]:
                if ip_addr == '127.0.0.1':
                    continue
                if not ip_status_map.get(ip_addr):
                    ip_status_map[ip_addr] = 'OK'

                for process2 in server_process_list[server_name][ip_addr]:
                    if process2['pid'] != '-' :
                                # self._dump_row(server_name, ip_addr, process2, True)
                        cpu_num = ip_cpunum_map[ip_addr]
                        status = 'OK'
                        if formation == "list":
                            row = [server_name, ip_addr, process2['pid'], "%.2f" % (float(process2['cpu'])/cpu_num), process2['mem'], process2['name'], status]
                        else:
                            row = {
                                "server_name": server_name,
                                "ip": ip_addr,
                                "pid": process2['pid'],
                                "cpu": "%.2f" % (float(process2['cpu'])/cpu_num),
                                "memory": "%.2f" % float(process2['mem']),
                                "command": process2['name'],
                                "status": status
                            }
                        table_data_process.append(row)
                    else:
                        status = 'Not OK'
                        ip_status_map[ip_addr] = 'Not OK'
                        # self._dump_row(server_name, ip_addr, process2, False)
                        if formation == "list":
                            row = [server_name, ip_addr, process2['pid'], process2['cpu'], process2['mem'], process2['name'], status]
                        else:
                            row = {
                                "server_name": server_name,
                                "ip": ip_addr,
                                "pid": None if process2['pid'] == '-' else process2['pid'],
                                "cpu": None if process2['cpu'] == '-' else "%.2f" % float(process2['cpu']),
                                "memory": None if process2['mem'] == '-' else "%.2f" % float(process2['mem']),
                                "command": process2['name'],
                                "status": status
                            }
                        table_data_process.append(row)

        ##
        for ip_addr in server_info_list:
            info = server_info_list[ip_addr]
            if formation == "list":
                row = [ip_addr, info['cpu_num'], info['cpu'], info['mem_size'], info['mem'], info['disk_root_size'], info['disk_root'], info['disk_data_size'], info['disk_data'], ip_status_map.get(ip_addr, None)]
            else:
                ## "%.2f" % float('57.23'), compatibility in python2.6
                row = {
                    "ip": ip_addr,
                    "cpu_num": None if info['cpu_num'] == '-' else int(info['cpu_num']),
                    "cpu_usage": None if info['cpu'] == '-' else  "%.2f" % float(info['cpu'][:-1]),
                    "memory_size": None if info['mem_size'] == '-' else int(info['mem_size'][:-1]),
                    "memory_usage": None if info['mem'] == '-' else  "%.2f" % float(info['mem'][:-1]),
                    "disk_size_root": None if info['disk_root_size'] == '-' else  "%.2f" % float(info['disk_root_size'][:-1]),
                    "disk_usage_root": None if info['disk_root'] == '-' else  "%.2f" % float(info['disk_root'][:-1]),
                    "disk_size_data": None if info['disk_data_size'] == '-' else  "%.2f" % float(info['disk_data_size'][:-1]),
                    "disk_usage_data": None if info['disk_data'] == '-' else  "%.2f" % float(info['disk_data'][:-1]),
                    "status": ip_status_map.get(ip_addr, None)
                }
            table_data_server.append(row)

        return table_data_process, table_data_server

    def auto_restart(self, server_process_list):
        server_node_list = []
        for server_name, ip_processlist in server_process_list.items():
            for ip, processlist in ip_processlist.items():
                for process in processlist:
                    if process['pid'] == '-':
                        server_node_list.append(":".join([server_name,ip,process['name']]))

        server_nodes =  ','.join(server_node_list)
        if server_nodes:
            print("these service will be restart:" + str(server_node_list))
            server=ServerRestart(self.ipconfig, server_name,server_nodes)
            server.restart()

    def dump(self, server_process_list, server_info_list):
        now = time.strftime("%Y-%m-%d %H:%M:%S", time.localtime())
        print 'Server process status'
        print '---------------------'
        print now
        print ''

        table_data_process, table_data_server = self.parse_data(server_process_list, server_info_list)

        print_table(table_data_process)

        print ''
        print 'Server status'
        print '-------------'
        print now
        print ''
        print_table(table_data_server)

class LogParser(object):
    """The class search error log"""

    def __init__(self, module, log_dir, keyword_file, log_date, ips, verbose=False):
        self.module = module
        self.log_dir = log_dir
        self.log_date = log_date
        self.error_log_keyword = keyword_file
        self.log_files = {}
        self.file_list = []
        self.error_logs = None
        if isinstance(ips,list):
            self.ips = ips
        else:
            self.ips = [ips]
        self.verbose = verbose

    def load_config(self):
        file_obj = open(self.error_log_keyword, "r")
        content = file_obj.read()
        config = json.loads(content)
        self.error_logs = config[self.module]
        if self.verbose:
            print "config file:"
            print self.error_logs

    def init_log_files(self):
        """Search for log files in given directory, with """
        today = time.strftime("%Y%m%d", time.localtime())
        init_cmd = 'find ' + self.log_dir + ' \\( '
        first = True
        for day in self.log_date:
            if not first:
                init_cmd += ' -or '
            if day >= today:
                init_cmd = init_cmd + '-regextype posix-extended -not -regex ".*\\.20[0-9]{6}.*" -type f'
            else:
                init_cmd = init_cmd + '-name "*' + day + '*" -type f'
            first = False
        init_cmd += ' \\)'
        #if not os.path.isdir(self.log_dir):
        #    return
        
        for ip in self.ips:
            cmd = ssh_t_cmd(ip, init_cmd, False)
            if self.verbose:
                print cmd
            status, output = commands.getstatusoutput(cmd)
            # print output
            if status != 0:
                log_error("Failed to execute command: " + cmd)
                log_error("(%d) %s" % (status, output if output else "-"))
                return
            if output:
                files = output.splitlines()
                for i in files:
                    if i.startswith("Connection to"):
                        files.pop(files.index(i))

                self.log_files.setdefault(ip,[])
                self.log_files[ip] = self.log_files[ip] + files
                # print self.log_files

    def analyze(self):
        self.load_config()
        self.init_log_files()

        for ip,thefiles in self.log_files.items():
            files = ' '.join(thefiles)
            for error in self.error_logs:
                error.setdefault('count',0)
                if files:
                    keyword = error['keyword'].replace("[", "\\[")
                    keyword = keyword.replace("]", "\\]")
                    cmd = 'grep "' + keyword + '" ' + files + '| wc -l'
                    cmd = ssh_t_cmd(ip, cmd, False)
                    if self.verbose:
                        print cmd
                    status, output = commands.getstatusoutput(cmd)
                else:
                    status = 0
                    output = '0'
                if status == 0:
                    error['count'] = error['count'] + int(output.splitlines().pop(0))
                else:
                    print output                   
        if self.verbose:
            print self.error_logs

    def dump(self):
        """dump the error list"""
        print 'Error log summary - ' + self.module
        print '--------------------------'
        num = len(self.log_date)
        if num == 1:
            print '(%s)' % self.log_date[0]
        else:
            print '(%s - %s)' % (self.log_date[0], self.log_date[num - 1])
        print ''

        table_data = [[]]
        table_data[0] = ['Name', 'Keyword', 'Description', 'Count']
        # for i, error in enumerate(self.error_logs):
        for error in self.error_logs:
            row = []
            row.append(error['name'])
            row.append(error['keyword'])
            row.append(error['desc'])
            row.append(str(error.get('count',0)))
            table_data.append(row)
        print_table(table_data)

class PhpLogParser(LogParser):
    """The class to parse php error logs."""

    def __init__(self, log_date, ip, verbose=False):
        LogParser.__init__(self,
                           'php',
                           ERROR_LOG_DIR + '/php',
                           ERROR_LOG_KEYWORD,
                           log_date,
                           ip,
                           verbose)

class JavaLogParser(LogParser):
    """The class to parse java error logs."""

    def __init__(self, log_date, ip, verbose=False):
        LogParser.__init__(self,
                           'java',
                           ERROR_LOG_DIR + '/java',
                           ERROR_LOG_KEYWORD,
                           log_date,
                           ip,
                           verbose)

# class BigDataViewerLogParser(LogParser):
#     """The class to parse bigdata error logs."""

#     def __init__(self, log_date, ip, verbose=False):
#         LogParser.__init__(self,
#                             'bigdata_viewer',
#                             ERROR_LOG_DIR + '/bigdata/qt_viewer',
#                             ERROR_LOG_KEYWORD,
#                             log_date,
#                             ip,
#                             verbose)

class BigDataConsumerLogParser(LogParser):
    """The class to parse bigdata error logs."""

    def __init__(self, log_date, ip, verbose=False):
        LogParser.__init__(self,
                            'bigdata_logstash',
                            ERROR_LOG_DIR + '/bigdata/qt_consumer',
                            ERROR_LOG_KEYWORD,
                            log_date,
                            ip,
                            verbose)

class GrokPattern(object):
    """Match Grok pattern and return dict."""

    def __init__(self, pat):
        self.types = {
            'WORD': r'\w+',
            'NUMBER': r'-?\d+',
            'BASE16NUM': r'(?<![0-9A-Fa-f])(?:[+-]?(?:0x)?(?:[0-9A-Fa-f]+))',
            'TIMESTAMP_ISO8601': r'(\d){4}-(\d){2}-(\d){2} (\d){2}:(\d){2}:(\d){2}',
            'DATA': r'.*?'
        }
        self.pattern = self._compile(pat)
        # print self.pattern

    def _compile(self, pat):
        return re.sub(r'%{(\w+):(\w+)}',
                      lambda m: "(?P<" + m.group(2) + ">" + self.types[m.group(1)] + ")", pat)

    def match(self, line):
        ret = re.search(self.pattern, line)
        if ret:
            return ret.groupdict()
        else:
            return None


class TitanLicense(object):
    """The class search error log and ."""
    def __init__(self, api_url, verbose=False):
        self.url = api_url
        self.verbose = verbose
        self.license = None

    def request(self):
        cmd = "curl -k --connect-timeout 3 -sS -X GET -H 'Content-Type: application/json; charset=utf-8' {0} 2>&1".format(self.url)
        status, content = commands.getstatusoutput(cmd)
        if status != 0 :
            content = ''
            log_error('Failed to get license status from ' + self.url)
        else:
            self.license = json.loads(content)

    def dump(self):
        """dump the license info"""
        if not self.license:
            return

        for key in self.license.keys():
            if self.license[key] is None:
                del self.license[key]

        now = time.strftime("%Y-%m-%d %H:%M:%S", time.localtime())
        print ''
        print 'License status'
        print '--------------'
        print now
        print ''

        # print job
        table_data = [[]]
        table_data[0] = ['Description', 'Value']
        row = ['License status', str(self.license.get('status',''))]
        table_data.append(row)
        expire_date = self.license.get('expiredDate','') 
        row = ['Wanxiang license expire date', expire_date]
        table_data.append(row)
        row = ['Wanxiang licensed agent number', str(self.license.get('agentLimit',''))]
        table_data.append(row)

        fengchao_expire_date = self.license.get('dockerExpiredDate','')
        row = ['Hive license expire date', fengchao_expire_date]
        table_data.append(row)
        row = ['Hive licensed agent number', str(self.license.get('dockerAgentLimit',''))]
        table_data.append(row)
        row = ['Hive sell strategy', str(self.license.get('dockerStrategy',''))]
        table_data.append(row)

        if self.license.get('status','') != 'valid':
            row = ['Licensed invalid reason', self.license.get('reason','')]
            table_data.append(row)
        else:
            row = ['Registered Agent number', str(self.license['registeredAgentNumber'])]
            table_data.append(row)
            row = ['Online Agent number', str(self.license['onlineAgentNumber'])]
            table_data.append(row)

        print_table(table_data)


class LogTrim(object):
    """The class trim server logs"""

    def __init__(self, ipconfig, verbose=False):
        self.verbose = verbose
        self.server_log_list = {
            "php_frontend": {
                "log_path": ['/data/titan-logs/php', '/data/titan-logs/nginx/', '/data/titan-logs/php-fpm/']
            },
            "java": {
                "log_path": ['/data/titan-logs/java/detect-srv/', '/data/titan-logs/java/ms-srv/', '/data/titan-logs/java/event-srv/', '/data/titan-logs/java/scan-srv/', '/data/titan-logs/java/gateway/', '/data/titan-logs/java/patrol-srv/', '/data/titan-logs/java/upload-srv/', '/data/titan-logs/java/user-srv/', '/data/titan-logs/java/wisteria/', '/data/titan-logs/java/job-srv/', '/data/titan-logs/java/connect-agent/', '/data/titan-logs/java/connect-sh/', '/data/titan-logs/java/connect-dh/', '/data/titan-logs/java/connect-selector/']
            }
        }
        for server_name in self.server_log_list:
            self.server_log_list[server_name]['ip_list'] = ipconfig.get_ips(server_name)

    def trim_server_log(self, ip_addr, log_dirs, age):
        if age == 0:
            return
        log_info('trim server log %s %s log_age:%d days' % (ip_addr, log_dirs, age))
        for log_dir in log_dirs:
            cmd = 'find %s -mtime +%d -type f | xargs rm' % (log_dir, age)
            cmd = ssh_cmd(ip_addr, cmd)
            if self.verbose:
                print cmd
            status, output = commands.getstatusoutput(cmd)

    def get_server_disk_percent(self, ip_addr):
        # try to get use percentage of /data
        cmd = '''df -Ph | awk '$NF=="/data" {printf "%s\t\t", $5}' '''
        cmd = ssh_cmd(ip_addr, cmd)

        if self.verbose:
            print cmd

        status, output = commands.getstatusoutput(cmd)
        disk_data = '%'
        if status != 0:
            log_error("Failed to execute command: " + cmd)
            log_error("(%d) %s" % (status, output if output else "-"))
        else:
            disk_data = output.strip()
        disk_data = disk_data.replace('%', '')
        if disk_data:
            return float(disk_data)

        # no /data partition, get usage percent of / instead
        cmd = '''df -Ph | awk '$NF=="/" {printf "%s\t\t", $5}' '''
        cmd = ssh_cmd(ip_addr, cmd)

        if self.verbose:
            print cmd

        status, output = commands.getstatusoutput(cmd)
        disk_root = '%'
        if status == 0:
            if "%" in output:
                disk_root = output.strip()
        else:
            log_error("Failed to execute command: " + cmd)
            log_error("(%d) %s" % (status, output if output else "-"))
        disk_root = disk_root.replace('%', '')
        if disk_root:
            return float(disk_root)

        # fail to get disk usage percent
        return 0


    def get_server_log_size(self, ip_addr):
        cmd = "du -s /data/titan-logs/|awk '{print $1}'"
        cmd = ssh_cmd(ip_addr, cmd)

        if self.verbose:
            print cmd

        status, output = commands.getstatusoutput(cmd)
        disk_size = 0
        if status != 0:
            log_error("Failed to execute command: " + cmd)
            log_error("(%d) %s" % (status, output if output else "-"))
        else:
            disk_size = output.strip().split()[0]

        return int(disk_size)

    def trim(self):
        global DISK_PERCENT
        global LOG_MAX_AGE
        global LOG_MAX_SIZE

        # trim all log with max age of LOG_MAX_AGE
        for server_name in self.server_log_list:
            if server_name.startswith('erlang_'):
                LOG_MAX_AGE=7
            else:
                LOG_MAX_AGE=180
            ip_list = self.server_log_list[server_name]['ip_list']
            log_path = self.server_log_list[server_name]['log_path']
            for ip in ip_list:
                self.trim_server_log(ip, log_path, LOG_MAX_AGE)

        # if disk usage not satisfied, trim log with max age of LOG_MAX_AGE/2
        all_trimed = True
        for server_name in self.server_log_list:
            ip_list = self.server_log_list[server_name]['ip_list']
            log_path = self.server_log_list[server_name]['log_path']
            for ip in ip_list:
                #percent = self.get_server_disk_percent(ip)
                size = self.get_server_log_size(ip)
                if size > LOG_MAX_SIZE:
                    log_info('after trim %s disk_log_size:%d' % (ip, size))
                    self.trim_server_log(ip, log_path, LOG_MAX_AGE/2)
                    all_trimed = False
        if all_trimed:
            return

        # if disk usage not satisfied, trim log with max age of LOG_MAX_AGE/4
        all_trimed = True
        for server_name in self.server_log_list:
            ip_list = self.server_log_list[server_name]['ip_list']
            log_path = self.server_log_list[server_name]['log_path']
            for ip in ip_list:
                #percent = self.get_server_disk_percent(ip)
                size = self.get_server_log_size(ip)
                if size > LOG_MAX_SIZE:
                    log_info('after trim %s disk_log_size:%d' % (ip, size))
                    self.trim_server_log(ip, log_path, LOG_MAX_AGE/4)
                    all_trimed = False
        if all_trimed:
            return

        # if disk usage not satisfied, trim log with max age of LOG_MAX_AGE/8
        all_trimed = True
        for server_name in self.server_log_list:
            ip_list = self.server_log_list[server_name]['ip_list']
            log_path = self.server_log_list[server_name]['log_path']
            for ip in ip_list:
                #percent = self.get_server_disk_percent(ip)
                size = self.get_server_log_size(ip)
                if  size > LOG_MAX_SIZE:
                    log_info('after trim %s disk_log_size:%d' % (ip, size))
                    self.trim_server_log(ip, log_path, LOG_MAX_AGE/8)
                    all_trimed = False
        if all_trimed:
            return

        # still not satisfied?
        log_error("Failed to trim log to percent %d" % DISK_PERCENT)


class QueueCheck(object):
    """The class list and check queues, contains kafka and rabbitmq."""
    def __init__(self, ipconfig, verbose=False):
        self.ipconfig = ipconfig
        self.verbose = verbose
        self.queue_data = {"kafka":[],"rabbitmq":[]}

    def check_queue(self):

        rabbit_queue_cmd = '''/data/app/titan-rabbitmq/bin/rabbitmqctl list_queues name messages consumers | grep -v    'Listing queues' '''
        rabbitmq_ips = self.ipconfig.get_ips("erlang_rabbitmq")

        queue_result = exec_ssh_cmd_withresult(rabbitmq_ips[0],rabbit_queue_cmd,verbose=self.verbose)
        if queue_result is None:
            log_error("can't list rabbitmq queues")
            self.queue_data["rabbitmq"] = None
        else:
            for queue_info in queue_result.splitlines():
                if not queue_info:
                    continue

                tmp_strs = queue_info.split()
                if len(tmp_strs) < 3:
                    continue

                name,msgNum,consumers = tmp_strs[0],tmp_strs[1],tmp_strs[2]
                if not msgNum.isdigit():
                    continue
                self.queue_data["rabbitmq"].append({"name":name,"msgNum":msgNum,"consumers":consumers})

        kafka_ips = self.ipconfig.get_ips("java_kafka")
        kafka_queue_cmd = '''/usr/local/qingteng/kafka/bin/kafka-consumer-groups.sh --command-config  /usr/local/qingteng/kafka/config/consumer.properties --bootstrap-server $kafkahost:9092 --describe --all-groups 2>&1 | grep -v LOG-END-OFFSET |grep -v "tc_outgoing_packet_consumer.* tc_outgoing_job" | grep -v org.apache.kafka |grep -v 'has no active members' | awk '{print $2" "$3" "$4" "$5" "$6" "$8}' | tr -d '/' '''.replace("$kafkahost",kafka_ips[0])

        kafka_data = {}
        queue_result = exec_ssh_cmd_withresult(kafka_ips[0],kafka_queue_cmd,verbose=self.verbose)
        if queue_result is None:
            log_error("can't list kafka queues")
            self.queue_data["kafka"] = None
        else:
            for queue_info in queue_result.splitlines():
                if not queue_info:
                    continue

                tmp_strs = queue_info.split()
                if len(tmp_strs) < 5:
                    continue

                name,msgNum,consumer = tmp_strs[0],(int(tmp_strs[4]) if tmp_strs[4].isdigit() else 0), (  1 if (len(tmp_strs) > 5 and tmp_strs[5] != '' and tmp_strs[5] != '-') else  0)

                old_info = kafka_data.get(name,[0,0])
                kafka_data[name] = [old_info[0] + msgNum, old_info[1] + consumer]

        for name, queue_info in kafka_data.items():
            msgNum,consumers = queue_info[0],queue_info[1]
            self.queue_data["kafka"].append({"name":name,"msgNum":str(msgNum),"consumers":str(consumers)})

        return self.queue_data

    def dump(self):
        print ''
        print 'Rabbitmq and Kafka Queues Status'
        print '--------------'
        print time.strftime("%Y-%m-%d %H:%M:%S", time.localtime())
        print ''

        if self.queue_data["rabbitmq"] is None:
            print("can't list rabbitmq queues")
        else:
            rabbitmq_info = list(self.queue_data["rabbitmq"])
            rabbitmq_table = [["queue_name","message_num","consumer_num"]]
            for item in rabbitmq_info:
                rabbitmq_table.append([item["name"],item["msgNum"],item["consumers"]])
            print_table(rabbitmq_table)

        print("")
        
        if self.queue_data["kafka"] is None:
            print("can't list kafka queues")
        else:
            kafka_info = list(self.queue_data["kafka"])
            kafka_table = [["topic_name","message_num","consumer_num"]]
            for item in kafka_info:
                kafka_table.append([item["name"],"unkonw" if int(item["msgNum"]) < 0 else item["msgNum"],item["consumers"]])
            print_table(kafka_table)
    
    def check_abnormal(self):
        warn_info = [["abnormal queue name", "abnormal info"]]

        if self.queue_data["rabbitmq"] is None:
            warn_info.append("can't list rabbitmq queues")
        else:
            rabbitmq_info = list(self.queue_data["rabbitmq"])
            for item in rabbitmq_info:
                name, message_num, consumer_num = item["name"],int(item["msgNum"]),int(item["consumers"])
                if message_num >= RABBITMQ_THRESHOLD_DICT.get(name,RABBITMQ_DEFAULT_THRESHOLD):
                    warn_info.append(["rabbitmq: {name}".format(name=name), "unhandled messages: {message_num} ".format(message_num=message_num)])
                
                if consumer_num <= 0:
                    warn_info.append(["rabbitmq: {name}".format(name=name), "have no consumers"])

        if self.queue_data["kafka"] is None:
            print("can't list kafka queues")
        else:
            kafka_info = list(self.queue_data["kafka"])
            for item in kafka_info:
                name, message_num, consumer_num = item["name"],int(item["msgNum"]),int(item["consumers"])
                if message_num >= KAFKA_THRESHOLD_DICT.get(name,KAFKA_DEFAULT_THRESHOLD) or int(message_num) < 0 :
                    warn_info.append(["kafka: {name}".format(name=name), "unhandled messages: {message_num} ".format( message_num=("unkonw" if int(message_num) < 0 else message_num) )])
                
                if consumer_num <= 0:
                    warn_info.append(["kafka: {name}".format(name=name), "have no consumers"])
        
        if len(warn_info) > 1:
            print ''
            print 'Rabbitmq and Kafka Queues Abnormal Info'
            print '--------------'
            print time.strftime("%Y-%m-%d %H:%M:%S", time.localtime())
            print ''
            print_table(warn_info)


def do_http_request(ip, data=None, restart=False):
    """
    HTTP request
    :param url: api
    :param data: json
    :return:
    """

    if ip == "":
        log_error("do_http_request: empty url")
        sys.exit(1)
    else:
        fo = open("/data/app/titan-patrol-srv/patrol-srv.conf", "r")
        patrolsrvconf = fo.read()
        is_http = re.search("#JAVA_OPTS.*/server.jks.*", patrolsrvconf)
        url = ('http' if is_http else 'https') + "://" + ip + ":" + JAVA_SERVER_PORT + JAVA_PATROL_API
        post_data = json.dumps(data, sort_keys=True)
        cmd = "curl -k --connect-timeout 3 -sS -X POST -H 'Content-Type: application/json; charset=utf-8' --data '{0}' {1} > /dev/null 2>&1".\
                format(post_data, url)
        status = os.system(cmd)
        if status == 0:
            log_info('Post_to_Java_Server: Successfully')
        else:
            log_error('Post_to_Java_Server: Failed')
            sys.exit(1)
        

def main():
    global SERVER_CONFIG_FILE
    global ERROR_LOG_KEYWORD
    global LOCAL_IP
    pwd = os.path.dirname(os.path.abspath(__file__))
    SERVER_CONFIG_FILE = pwd + '/' + SERVER_CONFIG_FILE
    ERROR_LOG_KEYWORD = pwd + '/' + ERROR_LOG_KEYWORD
    api_status_flag = False
    process_flag = False
    queue_flag =  False
    process_log = False
    config_file = SERVER_CONFIG_FILE
    error_log_flag = False
    license_flag = False
    json_flag = False
    json_file = None
    copy_to_java_flag = False
    post_to_java_flag = False
    post_to_java_restart_flag = False
    java_ip = None
    mail_flag = False
    mail_file = None
    trim_log_flag = False
    compress_log_flag = False
    json_result = {}
    verbose = False
    start_date = datetime.datetime.today()
    end_date = start_date
    java_req_id = None
    restart_server = False
    stop_server = False
    server_name = ''
    restart_server_node = False
    stop_server_node = False
    server_nodes = ''
    only_self_api = False

    short_args = "apeljdvhc:r:s:t:o:"
    long_args = ["all", "self-check-api", "check_queue", "stop=", "restart=", "stop-node=", "restart-node=", "process", "process-log", "log", "license", "start-date=", "end-date=", "req-id=", "sendmail=", "copy-to-java", "post-to-java", "post-to-java-no-restart", "trim-log", "compress-log", "verbose", "help"]

    # Wrap sys.stdout into a StreamWriter to allow writing unicode.
    sys.stdout = codecs.getwriter(locale.getpreferredencoding())(sys.stdout)

    try:
        opts, args = getopt.getopt(sys.argv[1:], short_args, long_args)
    except getopt.GetoptError:
        usage()
        sys.exit(2)

    if not opts:
        usage()
        sys.exit()

    for opt, arg in opts:
        if opt in "-a":
            process_flag = True
            queue_flag = True
            error_log_flag = True
            license_flag = True
            api_status_flag = True
        if opt in ("-p", "--process"):
            process_flag = True
        if opt == "--process-log":
            process_log = True
        if opt in ("-e", "--log"):
            error_log_flag = True
        if opt == "-l":
            license_flag = True
        if opt in "-t":
            ndays = int(arg)
            if ndays > 0:
                ndays -= 1
                start_date = end_date + datetime.timedelta(days=-ndays)
        if opt == "--start-date":
            start_date = datetime.datetime.strptime(arg, '%Y%m%d')
        if opt == "--end-date":
            end_date = datetime.datetime.strptime(arg, '%Y%m%d')
        if opt == "--req-id":
            java_req_id = arg
        if opt == "-o":
            json_flag = True
            json_file = arg
            json_result['timestamp'] = int(time.time())
        if opt == "--copy-to-java":
            copy_to_java_flag = True
        if opt == "--post-to-java":
            post_to_java_flag = True
            queue_flag = True
            # take over restart feature
            post_to_java_restart_flag = False
        if opt == "--post-to-java-no-restart":
            post_to_java_flag = True
            queue_flag = True
            post_to_java_restart_flag = False
        if opt == "--sendmail":
            mail_flag = True
            mail_file = arg
        if opt == "--trim-log":
            trim_log_flag = True
        if opt == "--compress-log":
            compress_log_flag = True
        if opt in ("-v", "--verbose"):
            verbose = True
        if opt == "-c":
            config_file = arg
        if opt in ("-r", "--restart"):
            restart_server = True
            server_name = arg
        if opt in ("-s", "--stop"):
            stop_server = True
            server_name = arg
        if opt == "--restart-node":
            restart_server_node = True
            server_nodes = arg
        if opt == "--stop-node":
            stop_server_node = True
            server_nodes = arg
        if opt == "--self-check-api":
            process_flag = True
            api_status_flag = True
            only_self_api = True
        if opt == "--check_queue":
            queue_flag = True
        if opt in ("-h", "--help"):
            usage()
            sys.exit()

    ipconfig = IpConfig(config_file)
    process_check = ProcessCheck(ipconfig, verbose)
    LOCAL_IP = ipconfig.get_local_ip()
    delta = end_date - start_date
    ndays = delta.days + 1
    check_date = []
    start = start_date
    num = ndays
    while num > 0:
        date = start.strftime("%Y%m%d")
        check_date.append(date)
        start = start + datetime.timedelta(days=1)
        num = num - 1

    # send email
    if mail_flag:
        if not mail_file:
            print 'Please input email content file.'
            sys.exit()

        if not os.path.isfile(mail_file):
            print 'Email content file not exist: ' + mail_file
            sys.exit()

        sendmail(mail_file)
        sys.exit()

    # compress log
    if compress_log_flag:
        compress_log()
        sys.exit()

    if process_flag or process_log :
        process_check.load_config()
        if process_flag or process_log:
            server_process_list, server_info_list = process_check.check_process()

    if api_status_flag and java_req_id is None:
        api_check = APICheck(ipconfig)
        java_ip = next(iter(ipconfig.get_ips('java')))
        server_status_list = api_check.check_status(java_ip)

    # trim log
    if trim_log_flag:
        log_trimer = LogTrim(ipconfig, verbose)
        log_trimer.trim()
        sys.exit()

    if process_log:
        process_info_text = json.dumps(server_process_list, sort_keys=True)
        log_info('titan_system_process:'+process_info_text)
        sys.exit()

    if not json_flag and not post_to_java_flag:
        print ''
        print 'Titan System Status Report'
        print '=========================='

    if api_status_flag and java_req_id is None:
        api_check.dump(server_status_list, None)
        if only_self_api:
            sys.exit()

    queue_data = {"kafka":None,"rabbitmq":None}
    if queue_flag :
        queue_check = QueueCheck(ipconfig,verbose)
        try:
            queue_data = queue_check.check_queue()

            # if also check process, only check abnormal. if not, will print to many content
            if process_flag:
                queue_check.check_abnormal()
            else:
                queue_check.dump()
                queue_check.check_abnormal()
        except Exception,err:
            print("check_queue exception")
            logging.exception(err)
            queue_data = {"kafka":None,"rabbitmq":None}

    # dump process check result
    if process_flag:
        if json_flag:
            json_result['process'] = server_process_list
            json_result['server_status'] = server_info_list
            java_ip = next(iter(server_process_list['java']))
        elif post_to_java_flag:
            patrol_ip = "127.0.0.1"
            service_status, server_status = process_check.parse_data(server_process_list, server_info_list, formation="object")
            post_data = {"server_process_status": service_status, "server_status": server_status,"kafka_queue": queue_data['kafka'], "rabbitmq_queue": queue_data['rabbitmq']}
            do_http_request(patrol_ip, data=post_data)

            if post_to_java_restart_flag:
                process_check.auto_restart(server_process_list)
        else:
            print ''
            process_check.dump(server_process_list, server_info_list)

    # sumary agent error log
    if error_log_flag:

        php_log = PhpLogParser(check_date, ipconfig.get_ips("php_frontend"), verbose)
        php_log.analyze()
        if json_flag:
            json_result['error_log']['php'] = php_log.error_logs
        else:
            print ''
            php_log.dump()

        java_log = JavaLogParser(check_date, ipconfig.get_ips("java"), verbose)
        java_log.analyze()
        if json_flag:
            json_result['error_log']['java'] = java_log.error_logs
        else:
            print ''
            java_log.dump()

        # big data perhaps not deploy, if not deploy, don't check bigdata error log
        # qt_viewer_ip = ipconfig.get_ip("bigdata_viewer")
        # if qt_viewer_ip != '' and qt_viewer_ip != '127.0.0.1':
        #     bigdata_viewer_log = BigDataViewerLogParser(check_date, qt_viewer_ip, verbose)
        #     bigdata_viewer_log.analyze()
        #     if json_flag:
        #         json_result['error_log']['bigdata_viewer'] = bigdata_viewer_log.error_logs
        #     else:
        #         print ''
        #         bigdata_viewer_log.dump()

        # qt_logstash_ips = ipconfig.get_ips("bigdata_logstash")
        # if qt_logstash_ips and len(qt_logstash_ips) > 0:
        #     bigdata_logstash_log = BigDataConsumerLogParser(check_date, qt_logstash_ips, verbose)
        #     bigdata_logstash_log.analyze()
        #     if json_flag:
        #         json_result['error_log']['bigdata_logstash'] = bigdata_logstash_log.error_logs
        #     else:
        #         print ''
        #         bigdata_logstash_log.dump()

    fo = open("/data/app/titan-patrol-srv/patrol-srv.conf", "r")
    patrolsrvconf = fo.read()
    is_http = re.search("#JAVA_OPTS.*/server.jks.*", patrolsrvconf)
    if license_flag:
        api = ('http' if is_http else 'https') + '://' + LOCAL_IP + ':' + LICENSE_PORT + LICENSE_API

        if verbose:
            print "License api: " + api
        titan_license = TitanLicense(api, verbose)
        titan_license.request()
        if json_flag:
            json_result['license'] = titan_license.license
        else:
            titan_license.dump()

    # upload system_report.log to java server
    if java_req_id and process_flag and error_log_flag:
        filename = "system_report_" + java_req_id + ".log"
        file_path = "/data/titan-logs/monitor/" + filename
        dest_path = "/data/app/titan-patrol-srv/report/" + filename
        patrol_ip = '127.0.0.1'
        if os.path.exists(file_path):
            sys.stdout.flush()
            copyfile(file_path, dest_path)
            cmd = "chown patrol:patrol " + dest_path
            os.system(cmd)
            report_api = JAVA_PATROL_REPORT_API.format(jobId=java_req_id)
            cmd = "curl -X POST -k --connect-timeout 3 -sS {0} > /dev/null 2>&1".\
                format(('http' if is_http else 'https') + "://" + patrol_ip + ":" + JAVA_SERVER_PORT + report_api)
            os.system(cmd)

    # write to json
    if json_flag:
        if verbose:
            print json_result
        fobj = open(json_file, 'w')
        fobj.write(json.dumps(json_result, indent = 4, sort_keys=True))
        fobj.close()
        if copy_to_java_flag and java_ip:
            # copy system status json to java server
            cmd = "scp -P " + ('%d' % (DEFAULT_SSH_PORT)) + " " + json_file + " " + DEFAULT_SSH_USER + "@" + java_ip + ":" + JAVA_SYSTEM_STATUS_JSON_FILE
            os.system(cmd)

    if restart_server:
        server=ServerRestart(ipconfig, server_name)
        server.restart()

    if stop_server:
        server=ServerRestart(ipconfig, server_name)
        server.stop()

    if restart_server_node:
        server=ServerRestart(ipconfig, server_name,server_nodes)
        server.restart()

    if stop_server_node:
        server=ServerRestart(ipconfig, server_name,server_nodes)
        server.stop()

if __name__ == "__main__":
    main()
