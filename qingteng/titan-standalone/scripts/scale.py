#! /usr/bin/python

import json
import os
import sys
import getopt
import re
import time
from config_helper import *

def log_error(msg):
    print('\033[31m' + "ERROR:" + str(msg) + '\033[0m')
    sys.exit(1)

def log_warn(msg):
    print('\033[35m' + "WARN:" + str(msg) + '\033[0m')

def log_info(msg):
    print('\033[32m' + "INFO:" +str(msg) + "\033[0m")

def log_warn_and_confirm(msg):
    print('\033[35m' + str(msg) + "\033[0m")
    v = get_input("Y","Are you sure to continue, default is Y, Enter [Y/N]: ")
    if v == "n" or v == "no" or v == "N" or v == "NO" or v == "No":
        print "Abort, exit."
        exit(0)

def log_warn_and_continue(msg):
    print('\033[35m' + str(msg) + "\033[0m")
    get_input("","Press Enter to continue")

OS_VERSION = None
mongo_cluster = None
ScriptPath = os.path.split(os.path.realpath(sys.argv[0]))[0]
WISTERIA_ALL = ["wisteria", "gateway", "user-srv", "upload-srv", "detect-srv", "job-srv"]

def set_np_login(ip):
    os.system("test -f ~/.ssh/id_rsa.pub || ssh-keygen -t rsa -P '' -f ~/.ssh/id_rsa")
    
    status = os.system('''ssh-copy-id -o StrictHostKeyChecking=no {user}@{ip} '''.format(user=DEFAULT_SSH_USER, ip=ip))
    if status != 0:
        print("ERROR:set no password login to {ip} failed.".format(ip=ip))
        sys.exit(1)

    php_ips = get_service_ips("php_frontend_private")
    for php_ip in php_ips:
        if is_ip_local(ip):
            continue

        # config no password login of other php hosts 
        id_rsa_pub = exec_ssh_cmd_withresult(php_ip, "cat ~/.ssh/id_rsa.pub")
        exec_ssh_cmd(ip, "grep -q '{id_rsa_pub}' ~/.ssh/authorized_keys || echo '{id_rsa_pub}' >> ~/.ssh/authorized_keys".format(id_rsa_pub=id_rsa_pub))

# check if ip is localhost 
def is_ip_local(ip):
    is_local = False
    local_ipstr = exec_ssh_cmd_withresult("", "ip addr|grep inet| awk -F '/' '{print $1}' | grep {_ip} || echo not".replace("{_ip}", ip))
    local_ips = local_ipstr.splitlines()
    for local_ip in local_ips:
        if local_ip.endswith(ip):
            is_local = True

    return is_local

def check_env(ip, ports):
    log_info("check_env of {ip} begin".format(ip=ip))
    version = get_os_version(ip)
    if version != OS_VERSION:
        log_error("os verison of {ip} not match, please provide centos{ver}".format(ip=ip,ver=OS_VERSION) )
    
    check_hostname(ip)
    check_disk(ip)
    check_firewall(ip)
    check_ports(ip, ports)

    log_info("check_env of {ip} end".format(ip=ip))

def check_hostname(ip):
    hostname = exec_ssh_cmd_withresult(ip, "hostname -s")
    if re.match(r"[0-9 ]+$", hostname) or " " in hostname :
        log_warn("hostname must have no blankspace or not consist of numbers")
        log_error("hostname of {ip} is {hostname}, please change it".format(ip=ip,hostname=hostname))

def check_firewall(ip):
    if OS_VERSION == "6":
        result = exec_ssh_cmd_withresult(ip, "service iptables status | grep -i 'not run'")
    else:
        result = exec_ssh_cmd_withresult(ip, "systemctl status firewalld 2>&1 | grep -E 'not be found|inactive \(dead\)' ")
    
    if not result or result == "":
        log_warn_and_continue("The firewall maybe not close, please check and close it")
    else:
        log_info("firewall already closed")

def check_disk(ip):
    disk_size = exec_ssh_cmd_withresult(ip, '''df -BGB -l| awk 'NR>1 && /^\/dev\//{sum+=$2}END{print sum}' ''')

    if int(disk_size) < 500:
        log_warn_and_confirm("disk on {ip} is {size}G".format(ip=ip, size=disk_size))
    else:
        log_info("disk on {ip} is {size}G".format(ip=ip, size=disk_size))

def check_ports(ip, ports):
    ports_str = "|".join(ports)
    check_result = exec_ssh_cmd_withresult(ip, '''ss -tunlp | grep -E ':({ports_str})' || echo success'''.format(ports_str=ports_str))

    if check_result and "success" not in check_result:
        log_error("port check failed on {ip}".format(ip=ip))

def set_basic_config(ip):
    # close selinux
    exec_ssh_cmd(ip, "sed -i '/SELINUX/s/enforcing/disabled/' /etc/selinux/config")
    exec_ssh_cmd_withresult(ip, "setenforce 0", alarm_error=False)

#check and install rsync
def check_rsync(ip):
    result = exec_ssh_cmd_withresult(ip,"/bin/rpm -q rsync" ) 
    if result and "rsync" in result:
        print("rsync already installed")
    else:
        os.system("scp -P {port} /data/qt_base/base/qingteng/other/rsync-* {user}@{ip}:/tmp".format(port=DEFAULT_SSH_PORT,user=DEFAULT_SSH_USER,ip=ip))
        exec_ssh_cmd(ip, "rpm -ivh /tmp/rsync-*")

def scp_to_with_mkdir(local_file, remote_host, dest_dir, src_ip=None):
    """ Scp file to remote server
    Example: scp_to_with_mkdir("./ip.json", "192.168.199.59", "/data/app/titan-server/etc/commom.json")
    :param local_file: file
    :param remote_host: ip address
    :param dest_dir: remote directory
    :return:
    """
    if src_ip is not None:
        # some java rpm package may not exists in local, first get from java host
        # first check src_ip if is localhost, if not, delete local file, 
        # because if not delete local, after upgrade local may have two version packages
        src_is_local = is_ip_local(src_ip)

        if local_file.startswith("/data/qt") and not src_is_local:
            exec_ssh_cmd("", "rm -rf " + local_file)
        # some java rpm package may not exists in local, first get from java host
        local_dir = os.path.dirname(local_file)
        scp_from_remote(local_file, src_ip, local_dir)

    exec_ssh_cmd(remote_host, "mkdir -p " + dest_dir)
    cmd = '''rsync -rz --rsync-path="sudo rsync" -e "ssh -p {0}"  --delete {1} {2}@{3}:{4}'''.format(DEFAULT_SSH_PORT, local_file, DEFAULT_SSH_USER, remote_host, dest_dir)
    print(cmd)
    os.system(cmd)

# check_result is a function
def wait_unitl_ok(ip_addr, cmd, timeout, check_result, _cmd=''):
    for i in range(int(timeout/5)+1):
        result = exec_ssh_cmd_withresult(ip_addr, cmd, _cmd, False) 
        if check_result(result):
            return True

        time.sleep(5)
    
    return False

# for example: upgrade from 3303,mongodb version is 3.4.20, 340 now rpm package is 4.2.3
def check_mongo_version(ip):
    now_version = exec_ssh_cmd_withresult(ip, '''mongo --version | head -n 1 |cut -d ' ' -f 4 ''')
    rpm_version = exec_ssh_cmd_withresult(ip, '''find /data/qt_base/ -name qingteng-mongodb* | awk -F 'qingteng-mongodb-' '{print $2}'|cut -d '-' -f 1 ''')
    if now_version != rpm_version:
        log_error("you mongo current version is {now_version}, can't support".format(now_version=now_version))

def sync_mongo_rpm(ip):
    scp_to_remote("/etc/yum.repos.d/qingteng.repo", ip, "/etc/yum.repos.d/")

    scp_to_with_mkdir("/data/qt_base/base/qingteng/qingteng-base-el" + OS_VERSION, ip, "/data/qt_base/base/qingteng")
    scp_to_with_mkdir("/data/qt_base/base/qingteng/mongo", ip, "/data/qt_base/base/qingteng")
    scp_to_with_mkdir("/data/qt_base/base/qingteng/repodata", ip, "/data/qt_base/base/qingteng")

    exec_ssh_cmd(ip, '''yum clean all''')

def install_mongo_cluster(ip):
    exec_ssh_cmd_withresult(ip, '''yum -y install qingteng-mongocluster''')

# install but not start
def install_shard_member(ip, shard_name, mongo_port):
    if mongo_port != "27019":
        exec_ssh_cmd(ip, "cp -f /etc/init.d/mongod_27019 /etc/init.d/mongod_{port}  && chown mongodb:mongodb /etc/init.d/mongod_{port}".format(port=mongo_port))
        exec_ssh_cmd(ip, "cp -f /usr/local/qingteng/mongocluster/etc/mongod_27019.conf /usr/local/qingteng/mongocluster/etc/mongod_{port}.conf && chown mongodb:mongodb /usr/local/qingteng/mongocluster/etc/mongod_{port}.conf".format(port=mongo_port))

    exec_ssh_cmd(ip, "sed -i 's/27019/{port}/g' /etc/init.d/mongod_{port}".format(port=mongo_port))
    exec_ssh_cmd(ip, "sed -i 's/27019/{port}/g' /usr/local/qingteng/mongocluster/etc/mongod_{port}.conf".format(port=mongo_port))

    exec_ssh_cmd(ip, "sed -i 's/shard1/{shard_name}/g' /usr/local/qingteng/mongocluster/etc/mongod_{port}.conf".format(shard_name=shard_name, port=mongo_port))

    exec_ssh_cmd(ip, "mkdir -p /data/mongocluster/{shard_name} && chown mongodb:mongodb /data/mongocluster/{shard_name}".format(shard_name=shard_name))

    exec_ssh_cmd(ip, '''sed -i "s/^#OPTIONS/OPTIONS/"  /etc/sysconfig/mongod ''')

    if OS_VERSION == "7":
        exec_ssh_cmd(ip, "systemctl daemon-reload")


def replSet_deploy(ip_pri, ip_2nd, ip_arb, shard_name, _port):
    log_info("replSet_deploy begin")
    shard_port = "2" + str(_port)
    arb_port = "3" + str(_port)

    log_info("install shard replSet start")
    install_shard_member(ip_pri, shard_name, shard_port)
    install_shard_member(ip_2nd, shard_name, shard_port)
    install_shard_member(ip_arb, shard_name, arb_port)
    
    exec_ssh_cmd(ip_pri, "service mongod_{port} restart".format(port=shard_port))
    exec_ssh_cmd(ip_2nd, "service mongod_{port} restart".format(port=shard_port))
    exec_ssh_cmd(ip_arb, "service mongod_{port} restart".format(port=arb_port))
    log_info("install shard replSet end")

    log_info("config replSet start")
    replSet_init_cmd = ''' rs.initiate( { _id : "{shard_name}", members: [ { _id: 0, host: "{ip_pri}:{port}",priority:2 }, { _id: 1, host: "{ip_2nd}:{port}",priority:1 }, { _id: 2, host: "{ip_arb}:{arb_port}",arbiterOnly:true }]}) '''

    replSet_init_cmd = replSet_init_cmd.replace("{shard_name}", shard_name)\
                    .replace("{ip_pri}", ip_pri).replace("{ip_2nd}", ip_2nd)\
                    .replace("{ip_arb}", ip_arb).replace("{port}", shard_port)\
                    .replace("{arb_port}", arb_port)

    print(replSet_init_cmd)
    exec_ssh_cmd_withresult(ip_pri, "mongo --port {port} --eval '{init_cmd}' ".format(port=shard_port, init_cmd=replSet_init_cmd))
    
    check_cmd = ''' mongo --port {port} --eval "rs.status()" | grep stateStr '''.format(port = shard_port)

    def check_result(result_str):
        if result_str and 'PRIMARY' in result_str \
            and 'SECONDARY' in result_str and 'ARBITER' in result_str:
            return True
        return False

    isOk = wait_unitl_ok(ip_pri, check_cmd, 120, check_result, check_cmd)

    if isOk:
        log_info("replSet_deploy end")
    else:
        log_error("replSet_deploy failed")

# add replSet to shard
def add_replSet_to_shard(ip_pri, ip_2nd, ip_arb, shard_name, _port,mongo_pwd=None):
    log_info("add_shard begin")
    shard_port = "2" + str(_port)
    arb_port = "3" + str(_port)

    if mongo_pwd is None:
        mongo_pwd = mongo_cluster.passwd

    # set password for shard   
    _cmd = CLUSTER_MONGO + ''' --port {port} admin --eval 'db.createUser({user:"qingteng", pwd:"{mongo_pwd}", roles:["root"]})' '''.replace("{port}", shard_port)
    exec_ssh_cmd_withresult(ip_pri, _cmd.replace("{mongo_pwd}", mongo_pwd), _cmd, False)
    log_info("set password for {shard_name} end".format(shard_name=shard_name))

    #add shard via mongos
    add_shard_cmd = CLUSTER_MONGO + ''' -u qingteng -p {mongo_pwd}  --authenticationDatabase admin --eval 'sh.addShard( "{shard_name}/{ip_pri}:{shard_port},{ip_2nd}:{shard_port},{ip_arb}:{arb_port}")' '''
    add_shard_cmd = add_shard_cmd.format(shard_name=shard_name,ip_pri=ip_pri,
                            ip_2nd=ip_2nd,ip_arb=ip_arb,shard_port=shard_port,
                            arb_port=arb_port,mongo_pwd=mongo_pwd)
    
    exec_ssh_cmd_withresult(ip_pri, add_shard_cmd,
                            add_shard_cmd)

    log_info("add_shard end")

# install and start mongos 
def install_start_mongos(ip, configdb):
    exec_ssh_cmd(ip, "sed -i 's%configdb =.*%configdb = {configdb}%' /usr/local/qingteng/mongocluster/etc/mongos.conf".format(configdb=configdb))
    exec_ssh_cmd(ip, "/etc/init.d/mongos restart")
    log_info("install mongos at {ip} End".format(ip=ip))

# just stop mongos
def remove_mongos(ip, configdb):
    exec_ssh_cmd(ip, "/etc/init.d/mongos stop")
    log_info("stop mongos at {ip} End".format(ip=ip))

def add_shard_member(ip, port, pri_node):
    passwd = mongo_cluster.passwd
    # first restart, then add to replset
    exec_ssh_cmd(ip, "service mongod_{port} restart".format(port=("cs" if port == "27018" else port)))
    # add node to replSet
    ip_pri = pri_node.split(":")[0]
    pri_port = pri_node.split(":")[1]
    addFun = "add"
    if port.startswith("3"):
        addFun = "addArb"
    _cmd = '''mongo --port {pri_port} -u qingteng -p $passwd --authenticationDatabase admin --eval 'rs.{addFun}("{ip}:{port}")' '''.format(pri_port=pri_port, ip=ip, port=port, addFun=addFun)
    exec_ssh_cmd(ip_pri, _cmd.replace("$passwd",passwd), _cmd)
    # add node to replSet end
        
# remove a node from a shard replset
def remove_shard_member(ip, mongo_port):

    remove_node = ip + ":" + mongo_port
    log_info("remove {remove_node} begin".format(remove_node=remove_node))

    find = False
    pri_node = None
    remove_shard = None
    shard_detail = mongo_cluster.shard_members
    for shard_name, detail in shard_detail.items():
        for role, nodes in detail.items():
            if remove_node in nodes:
                find = True
                pri_node = detail["PRIMARY"][0]
                remove_shard = shard_name

    if not find:
        log_error("{remove_node} not in mongo cluster,maybe already removed".format(remove_node=remove_node)) 

    ip_pri = pri_node.split(":")[0]
    passwd = mongo_cluster.passwd

    # stop 
    exec_ssh_cmd(ip, "/etc/init.d/mongod_{port} stop".format(port=mongo_port))
    process = exec_ssh_cmd_withresult(ip, "ps -ef | grep -v grep | grep etc/mongod_{port} || echo stoped".format(port=mongo_port))
    if process and not "stoped" in process:
        log_warn_and_continue("mongod_{port} at {ip} stop failed, Please stop it manually and continue".format(port=mongo_port, ip=ip))
    
    # remove from replSet
    # rs.remove need execute at primary node
    pri_port = "2" + mongo_port[1:]
    _cmd = '''mongo --port {pri_port} -u qingteng -p $passwd --authenticationDatabase admin --eval 'rs.remove("{ip}:{port}")' '''.format(pri_port=pri_port, ip=ip, port=mongo_port)
    exec_ssh_cmd(ip_pri, _cmd.replace("$passwd",passwd), _cmd)
    # remove node end

    # remove old files
    if mongo_port not in ["27019","27020","27021"]:
        exec_ssh_cmd(ip, "! test -f /etc/init.d/mongod_{port} || mv -f /etc/init.d/mongod_{port} /etc/init.d/mongod_{port}_removed".format(port=mongo_port))
        exec_ssh_cmd(ip, "! test -f /usr/local/qingteng/mongocluster/etc/mongod_{port}.conf || mv -f /usr/local/qingteng/mongocluster/etc/mongod_{port}.conf /usr/local/qingteng/mongocluster/etc/mongod_{port}.conf_removed".format(port=mongo_port))

    exec_ssh_cmd(ip, "mv -f /data/mongocluster/{remove_shard} /data/mongocluster/{remove_shard}_removed".format(remove_shard=remove_shard))
    # remove old files end

    if OS_VERSION == "7":
        exec_ssh_cmd(ip, "systemctl daemon-reload")
    
    log_info("remove {remove_node} end".format(remove_node=remove_node))

def remove_cs_member(ip, ip_pri):
    remove_node = ip + ":27018"
    log_info("remove {remove_node} begin".format(remove_node=remove_node))
    passwd = mongo_cluster.passwd

    # remove from replSet
    # rs.remove need execute at primary node
    _cmd = '''mongo --port 27018 -u qingteng -p $passwd --authenticationDatabase admin --eval 'rs.remove("{ip}:27018")' '''.format(ip=ip)
    exec_ssh_cmd(ip_pri, _cmd.replace("$passwd",passwd), _cmd)
    # remove node end

    # exec_ssh_cmd(ip, "mv -f /data/mongocluster/mongod_cs /data/mongocluster/mongod_cs_removed")
    # stop 
    exec_ssh_cmd(ip, "/etc/init.d/mongod_cs stop")
    process = exec_ssh_cmd_withresult(ip, "ps -ef | grep -v grep | grep etc/mongod_cs || echo stoped")
    if process and not "stoped" in process:
        log_warn_and_continue("mongod_cs at {ip} stop failed, Please stop it manually and continue".format(ip=ip))

    log_info("remove {remove_node} end".format(remove_node=remove_node))


class MongoClusterInfo():

    def __init__(self, mongos_ips, mongo_passwd):
        self.passwd = mongo_passwd
        self.mongos_ips = mongos_ips
        self.shard_info = {}
        self.shard_members = {}
        self.abnormal_nodes = []

        self.pasre_cluster_info()
        
    def pasre_cluster_info(self):
        # first get shard info from mongos
        mongos_ip = self.mongos_ips[0]
        self.get_configdb(mongos_ip)
        # shard info have no arbiter node
        self.get_current_shards(mongos_ip)
        # get shard info with arbiter node
        self.get_shardmember_info()

    # shard info have no arbiter node
    def get_current_shards(self, mongo_ip):

        _cmd = '''mongo -u qingteng -p {passwd} --authenticationDatabase admin --eval "db.adminCommand({ listShards: 1 })" '''
        shard_info_str = exec_ssh_cmd_withresult(mongo_ip, _cmd.replace("{passwd}", self.passwd), _cmd)

        shards_reg = r'"shards".*:.*(\[[^\]]*\])'
        matchObj = re.search(shards_reg, shard_info_str)
        if matchObj:
            print(matchObj.group(0))
        else:
            print("ERROR:get current mongo cluster info failed, exit")
            sys.exit(1)

        shards = json.loads(matchObj.group(1))
        print(shards)

        for shard in shards:
            shard_name = shard["_id"]
            host_str = shard["host"]
            # if here exception, means not cluster.. 
            ip_ports = host_str.split("/")[1].split(",")

            self.shard_info[shard_name] = ip_ports

        print(self.shard_info)

    # get which ip install mongos
    def get_mongos(self, ips):
        mongos_ips = set()
        for ip in ips:
            result = exec_ssh_cmd_withresult(ip, "ps auxf | grep mongos.*mongos.conf | grep -v grep | wc -l")
            if result and result == "1":
                mongos_ips.add(ip)
    
        print(mongos_ips)
        self.mongos_ips = mongos_ips

    def get_configdb(self, mongos_ip):
        _cmd = "grep configdb /usr/local/qingteng/mongocluster/etc/mongos.conf"
        configdb_str = exec_ssh_cmd_withresult(mongos_ip, _cmd)
        self.configdb = configdb_str.split("/")[1].split(",")

    def _get_replSet_info_(self, ip, port):
        print(ip + ":" + str(port))
        _cmd = '''mongo --port $port -u qingteng -p {passwd} --authenticationDatabase admin --eval 'rs.status()' | grep -E '"name"|"stateStr"' '''.replace("$port",port)

        rs_info = exec_ssh_cmd_withresult(ip, _cmd.format(passwd=self.passwd), _cmd)

        rs_members = {}
        nodes = re.findall(r'"name" : [^,]+', rs_info)
        states = re.findall(r'"stateStr" : [^,]+', rs_info)
        # nodes and states number must match,if not,just exception and exit
        for index, node in enumerate(nodes):
            state = states[index]
            matchObj = re.search(r'"([^"]+:\d{5})"', node) # search "172.16.6.174:27019"
            stateObj = re.search(r': "([^"]+)"', state) # search SECONDARY/PRIMARY
            
            instance = matchObj.group(1)
            stateStr = stateObj.group(1)

            if "not reachable/healthy" in stateStr:
                self.abnormal_nodes.append(instance + ":" + stateStr)
                origin_state = stateStr
                if ":3" in instance:
                    stateStr = "ARBITER"
                else:
                    stateStr = "SECONDARY"
                log_warn("state of {instance} is {origin_state}, will regard as {stateStr}".format(instance=instance,origin_state=origin_state,stateStr=stateStr))

            if stateStr not in ["PRIMARY","SECONDARY","ARBITER"]:
                self.abnormal_nodes.append(instance + ":" + stateStr)

            rs_members.setdefault(stateStr,[])
            rs_members[stateStr].append(instance)
    
        print(rs_members)
        return rs_members

    def get_shardmember_info(self):
        
        for shard_name, ip_ports in self.shard_info.items():
            ip_port = ip_ports[0]
            ip = ip_port.split(":")[0]
            port = ip_port.split(":")[1]
            rs_members = self._get_replSet_info_(ip, port)

            self.shard_members[shard_name] = rs_members
    
        print(self.shard_members)

    def dumps(self):
        log_info("MongoCluster details:")
        print("configdb:" + str(self.configdb))
        print("mongos:" + str(self.mongos_ips))
        #print("shardinfo:" + json.dumps(self.shard_info, indent=4, sort_keys=True))
        print("shardmembers:" + json.dumps(self.shard_members, indent=4, sort_keys=True))

        if len(self.abnormal_nodes) > 0:
            log_warn("abnormal nodes are:" + json.dumps(self.abnormal_nodes, indent=4, sort_keys=True))
            log_warn("Please refer to https://docs.mongodb.com/manual/reference/replica-states/ for detail")

    # get next shard cluster config: sharname, port
    def get_next_shardconf(self):
        current_max = 1
        port1 = 7019

        shard_nos = []
        for shardname in self.shard_info:
            shard_no = int(shardname[5:])
            shard_nos.append(shard_no)
        shard_nos.sort()
        
        # new arbiter need install at last shard's secondary node
        last_shard = "shard" + str(max(shard_nos))
        last_secondary = self.shard_members[last_shard]["SECONDARY"][0]

        next_no = max(shard_nos) + 1
        next_port = 7019 + next_no - 1   # shard2 7020, shard3 7021

        conf = { "shard_name": "shard"+str(next_no),
                "port": str(next_port),
                "arb_ip": last_secondary.split(":")[0]
               } 
        
        print(conf)
        return conf

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


## for java service
def sync_java_rpm(ip):
    scp_to_remote("/etc/yum.repos.d/qingteng.repo", ip, "/etc/yum.repos.d/")

    os_version = get_os_version(ip)
    scp_to_with_mkdir("/data/qt_base/base/qingteng/qingteng-base-el" + os_version, ip, "/data/qt_base/base/qingteng")

    scp_to_with_mkdir("/data/qt_base/base/qingteng/jdk", ip, "/data/qt_base/base/qingteng")
    scp_to_with_mkdir("/data/qt_base/base/qingteng/glusterfs", ip, "/data/qt_base/base/qingteng")
    scp_to_with_mkdir("/data/qt_base/java", ip, "/data/qt_base/")

    java_ip = get_service_ips("java")[0]
    agent_ip = get_service_ips("java_connect-agent")[0]
    sh_ip = get_service_ips("java_connect-sh")[0]
    selector_ip = get_service_ips("java_connect-selector")[0]
    dh_ip = get_service_ips("java_connect-sh")[0]
    scan_ips = get_service_ips("java_scan-srv")

    scp_to_with_mkdir("/data/qt_rpms/titan-java-lib*", ip, "/data/qt_rpms/", src_ip=java_ip)
    scp_to_with_mkdir("/data/qt_rpms/titan-connect-agent*", ip, "/data/qt_rpms/", src_ip=agent_ip)
    scp_to_with_mkdir("/data/qt_rpms/titan-connect-sh*", ip, "/data/qt_rpms/", src_ip=sh_ip)
    scp_to_with_mkdir("/data/qt_rpms/titan-connect-dh*", ip, "/data/qt_rpms/", src_ip=dh_ip)
    scp_to_with_mkdir("/data/qt_rpms/titan-connect-selector*", ip, "/data/qt_rpms/", src_ip=selector_ip)
    if scan_ips and len(scan_ips) > 0:
        scp_to_with_mkdir("/data/qt_rpms/titan-scan-srv*", ip, "/data/qt_rpms/", src_ip=scan_ips[0])
    scp_to_with_mkdir("/data/qt_rpms/titan-wisteria*", ip, "/data/qt_rpms/", src_ip=java_ip)

    scp_to_with_mkdir("/data/qt_base/base/qingteng/repodata", ip, "/data/qt_base/base/qingteng")

    exec_ssh_cmd(ip, '''yum clean all''')

def install_java_dependency(ip):

    exec_ssh_cmd(ip, "yum -y install qingteng-jdk && yum -y update qingteng-jdk")

    # install python2.7
    exec_ssh_cmd(ip, "yum -y install qingteng-python && yum -y update  qingteng-python")

    exec_ssh_cmd(ip, "yum -y install qingteng-openjdk && yum -y update  qingteng-openjdk")

    exec_ssh_cmd(ip, "mkdir -p /usr/local/qingteng/arthas && cp -rb /data/qt_base/java/arthas-packaging-3.1.1-bin/* /usr/local/qingteng/arthas/")
    exec_ssh_cmd(ip, "bash /usr/local/qingteng/arthas/install-local.sh")

def install_glusterfs(ip1, ip2, ip3):
    old_gluster_ips = get_service_ips("glusterfs")
    if ip1 in old_gluster_ips or ip2 in old_gluster_ips or ip3 in old_gluster_ips:
        log_error("The new ip which will new install glusterfs in old glusterfs hosts")
    
    if ip1 == ip2 or ip2 == ip3 or ip1 == ip3:
        log_error("The three ips must unique")

    old_gluster_ip = old_gluster_ips[0]

    for ip in [ip1, ip2, ip3]:
        exec_ssh_cmd_withresult(ip, "yum -y install glusterfs-server glusterfs && yum -y update  glusterfs-server glusterfs")

        exec_ssh_cmd_withresult(ip, "chkconfig --add glusterd && chkconfig glusterd on",alarm_error=False)
        exec_ssh_cmd(ip, "service glusterd restart")
        exec_ssh_cmd(ip, "mkdir -p /data/storage")
        exec_ssh_cmd(old_gluster_ip, "gluster peer probe {ip}".format(ip=ip))

    exec_ssh_cmd(old_gluster_ip, "gluster volume add-brick java {ip1}:/data/storage/ {ip2}:/data/storage/ {ip3}:/data/storage/".format(ip=ip))

    exec_ssh_cmd(old_gluster_ip, "gluster volume info")

def install_glusterfs_client(ip):
    result = exec_ssh_cmd_withresult(ip, '''df -h | grep /data/app/titan-dfs || echo notinstall ''')
    if result and "notinstall" not in result:
        log_info("glusterfs client already installed")
        return

    gluster_servers = get_service_ips("glusterfs")
    gluster_server = gluster_servers[0]
    # install all ,but only use as client
    exec_ssh_cmd(ip, "yum -y install glusterfs-server glusterfs && yum -y update  glusterfs-server glusterfs")

    exec_ssh_cmd(ip, "mkdir -p /data/app/titan-dfs")

    exec_ssh_cmd(ip, '''grep -q glusterfs /etc/fstab || echo "{gluster_server}:/java /data/app/titan-dfs    glusterfs   defaults,_netdev 0 0" >> /etc/fstab '''.format(gluster_server=gluster_server))
    exec_ssh_cmd(ip, "mount -a")

def remove_glusterfs_client(ip):
    # just umount
    exec_ssh_cmd(ip, '''sed -i '/\/data\/app\/titan-dfs/d' /etc/fstab && umount -l /data/app/titan-dfs''')

# check and install
def check_java_lib(ip):
    javalib_pkg = exec_ssh_cmd_withresult(ip, "find /data/qt_rpms/ -name titan-java-lib* | xargs ls -t | head -n 1", alarm_error=False)

    if not javalib_pkg or javalib_pkg == '':
        log_error("can't find titan-java-lib, exception")

    javalib_rpm = exec_ssh_cmd_withresult(ip, "rpm -qa|grep titan-java-lib || echo notinstall")

    if javalib_rpm and javalib_rpm != '' and javalib_rpm in javalib_pkg:
        log_info("titan-java-lib already installed")
    else:
        exec_ssh_cmd_withresult(ip, "rpm -ivh " + javalib_pkg, alarm_error=False)

# if package not found, install , if package already exists, just return
def install_java_service(ip, service_name, ext={}):
    check_java_lib(ip)

    rpm_package_map = {
        "connect-sh": "/data/qt_rpms/titan-connect-sh*",
        "connect-selector": "/data/qt_rpms/titan-connect-selector*",
        "connect-dh": "/data/qt_rpms/titan-connect-dh*",
        "connect-agent": "/data/qt_rpms/titan-connect-agent*",
        "scan-srv": "/data/qt_rpms/titan-scan-srv*",
        "wisteria": "/data/qt_rpms/titan-wisteria-*",
        "gateway": "/data/qt_rpms/titan-wisteria-*",
        "user-srv": "/data/qt_rpms/titan-wisteria-*",
        "upload-srv": "/data/qt_rpms/titan-wisteria-*",
        "detect-srv": "/data/qt_rpms/titan-wisteria-*",
        "job-srv": "/data/qt_rpms/titan-wisteria-*"
    }

    # backup java.json
    time_str = time.strftime("%Y%m%d_%H%M%S")
    nodfs =  exec_ssh_cmd_withresult(ip,"test -d /data/app/titan-dfs || echo nodfs ")
    if nodfs and "nodfs" in nodfs:
        exec_ssh_cmd(ip,"! test -f /data/app/titan-dfs/titan-config/java.json || cp -f /data/app/titan-dfs/titan-config/java.json /data/app/titan-dfs/titan-config/java.json_bak_scale" + time_str)
    else:
        exec_ssh_cmd(ip,"! test -f /data/app/titan-config/java.json || cp -f /data/app/titan-config/java.json /data/app/titan-config/java.json_bak_scale" + time_str)

    if service_name in WISTERIA_ALL:
        result = exec_ssh_cmd_withresult(ip, '''test -f /data/app/titan-{name}/{name}.jar || echo notinstalled'''.format(name=service_name))

        if result and "notinstalled" in result:
            exec_ssh_cmd_withresult(ip, "rpm -ivh " + rpm_package_map[service_name], alarm_error=False)
             
        if service_name == "job-srv":
            node = ext["job_node"]
            _job_cmd='''sed -i -r '/node/s/:[^,]+/: {node}/' /data/app/titan-config/job.json'''
            exec_ssh_cmd(ip, _job_cmd.format(node=node))
        elif service_name == "gateway":
            _server_port_cmd = '''sed -i -r 's/-Dserver.port=[^ "]+[ ]?//g;/^JAVA_OPTS/s/ ?"$/ -Dserver.port=16000"/' /data/app/titan-gateway/gateway.conf '''
            exec_ssh_cmd(ip, _server_port_cmd)

    elif service_name in ["connect-sh", "connect-selector", 
                        "connect-dh", "connect-agent", "scan-srv"]:
        exec_ssh_cmd_withresult(ip, "rpm -ivh " + rpm_package_map[service_name], alarm_error=False)
        if service_name == "connect-sh":
            sh_ip = ext.get("sh_public_ip", ip)
            sh_node = ext["sh_node"]
            
            config_sh(ip, sh_ip, sh_node)
        elif service_name == "connect-selector":
            _server_port_cmd = '''sed -i -r 's/-Dserver.port=[^ "]+[ ]?//g;/^JAVA_OPTS/s/ ?"$/ -Dserver.port=16677"/' /data/app/titan-connect-selector/connect-selector.conf '''
            exec_ssh_cmd(ip, _server_port_cmd)
    
    exec_ssh_cmd(ip, '''mkdir -p /data/titan-logs/java/{name} && chown titan:titan /data/titan-logs/java/{name} '''.format(name=service_name))


def start_java_service(ip, service_names):
    for service_name in service_names:
        exec_ssh_cmd_withresult(ip, "/data/app/titan-{name}/init.d/{name} restart".format(name=service_name))

def backup_javajson():
    java_ips = get_service_ips("java")
    scp_from_remote("/data/app/titan-config/java.json", java_ips[0], ScriptPath)
    log_info("backup java.json at " + ScriptPath)

def put_javajson_to_new(ips):
    for ip in ips:
        exec_ssh_cmd(ip, "mkdir -p /data/app/titan-config/")
        # check in glusterfs or not
        java_dfs_path = exec_ssh_cmd_withresult(ip, '''ls -l /data/app/titan-config/java.json ''', alarm_error=False)
        if java_dfs_path and "->" in java_dfs_path and java_dfs_path.startswith('l'):
            java_dfs_path = java_dfs_path.split("->")[1].strip()
            scp_to_remote(ScriptPath + "/java.json", ip, java_dfs_path)
        else:
            scp_to_remote(ScriptPath + "/java.json", ip, "/data/app/titan-config/")

# service_ips is {"gateway":[127.0.0.1,127.0.0.2],"connect-selector":[127.0.0.1,127.0.0.2]}
def add_cluster_slb(service_ips):
    local_path = ScriptPath + '/nginx.cluster.conf'
    os.system("cp -f /data/app/conf/cluster/nginx.cluster.conf " + local_path)
    content = ""
    with open(local_path) as file_obj:
        content = file_obj.read()
    
    if service_ips.has_key("upload-srv"):
        local_proxy_path = ScriptPath + '/nginx.proxy.conf'
        os.system("cp -f /data/app/conf/proxy/nginx.proxy.conf " + local_proxy_path)
        proxy_content = ""
        with open(local_path) as file_obj:
            proxy_content = file_obj.read()
        
        _upload_cmd = '''sed -i '/upstream upload-srv/a \    server {server};'  ''' + local_proxy_path

    _selector_cmd = '''sed -i '/upstream connectselector/a \    server {server};'  ''' + local_path
    _java_cmd = '''sed -i '/upstream javaserver/a \    server {server};'  ''' + local_path

    for service_name, ips in service_ips.items():
        for ip in ips:
            configured = False
            if service_name == "connect-selector":
                up_server = ip + ':16677'
                configured = up_server in content 
            elif service_name == "gateway":
                up_server = ip+':16000'
                configured = up_server in content
            elif service_name == "upload-srv":
                up_server = ip + ':6130'
                configured = up_server in content

            if configured:
                log_warn(up_server + " already configed in nginx")
                continue
        
            if service_name == "connect-selector":
                os.system(_selector_cmd.format(server=up_server))
            elif service_name == "gateway":
                os.system(_java_cmd.format(server=up_server))
            elif service_name == "upload-srv":
                os.system(_upload_cmd.format(server=up_server))

    php_ips = get_service_ips("php_backend_private")
    for ip in php_ips:
        scp_to_remote(local_path, ip, '/data/app/conf/cluster/')
        if service_ips.has_key("upload-srv"):
            scp_to_remote(local_proxy_path, ip, '/data/app/conf/proxy/')

        exec_ssh_cmd(ip, 'chown -R nginx:nginx /data/app/conf/ && service nginx restart')

def add_innerapi_clients(ips):
    php_ips = get_service_ips("php_backend_private")
    innerapi_clients = exec_ssh_cmd_withresult(php_ips[0], "grep host.innerapi.clients /data/app/www/titan-web/conf/product/application.ini")

    add_ips = set()
    for ip in ips:
        if ip in innerapi_clients:
            continue
        add_ips.add(ip)
    
    if len(add_ips) > 0:
        add_ip_str = ",".join(add_ips)
        for ip in php_ips:
            exec_ssh_cmd(ip, '''sed -i '/host.innerapi.clients=/s/"$/,{add_ip_str}"/' /data/app/www/titan-web/conf/product/application.ini'''.format(add_ip_str=add_ip_str))

def remove_cluster_slb(service_ips):

    php_ips = get_service_ips("php_backend_private")
    for php_ip in php_ips:
        for service_name, ips in service_ips.items():
            for ip in ips:
                if service_name == "connect-selector":
                    up_server = ip + ':16677'
                    exec_ssh_cmd(php_ip, '''sed -i '/{up_server}/d' /data/app/conf/cluster/nginx.cluster.conf '''.format(up_server=up_server))
                elif service_name == "gateway":
                    up_server = ip+':16000'
                    exec_ssh_cmd(php_ip, '''sed -i '/{up_server}/d' /data/app/conf/cluster/nginx.cluster.conf '''.format(up_server=up_server))
                elif service_name == "upload-srv":
                    up_server = ip + ':6130'
                    exec_ssh_cmd(php_ip, '''sed -i '/{up_server}/d' /data/app/conf/proxy/nginx.proxy.conf '''.format(up_server=up_server)) 
        
        exec_ssh_cmd(php_ip, 'chown -R nginx:nginx /data/app/conf/ && service nginx restart')


def update_ipjson(update_map, action):
    log_info("update ip.json begin")
    ipjson_dir = "/data/app/www/titan-web/config_scripts"
    ipjson_path =  ipjson_dir + "/ip.json"
    # load the old configuration
    ip_config = json.load(open(ipjson_path))

    for service_name, ips in update_map.items():
        ipjson_key = get_ipjson_key(service_name)

        if action == "replace":
            old_conf = ip_config.get(ipjson_key,"")
            port = ""
            ip_port = old_conf.split(",")[0]
            tmp_strs = ip_port.split(":")
            if len(tmp_strs) > 1:
                port = ":" + tmp_strs[1]
    
            # replace
            ip_config[ipjson_key] = ",".join([ip+port for ip in ips])
            continue
        
        for _ip in ips:
            old_conf = ip_config.get(ipjson_key,"")
            if _ip in old_conf and action == "add":
                log_info(_ip + " already in " + ipjson_key)
                continue
    
            if _ip not in old_conf and action == "del":
                log_info(_ip + " already del from " + ipjson_key)
                continue

            if action == "add":
                port = ""
                ip_port = old_conf.split(",")[0]
                tmp_strs = ip_port.split(":")
                if len(tmp_strs) > 1:
                    port = ":" + tmp_strs[1]
    
                # append new service
                ip_config[ipjson_key] = ("" if old_conf == "" else old_conf + ",") + _ip + port
            elif action == "del":
                ip_port_list = old_conf.split(",")
                # filter the ip from ip_port_list
                filter_result = filter(lambda ip_port:_ip not in ip_port, ip_port_list)
        
                ip_config[ipjson_key] = ",".join(list(filter_result))

    # write the ipjson config
    f = open(ipjson_path, "w+")
    f.write(json.dumps(ip_config, indent = 4, sort_keys = True))
    f.close()
    os.system("cp -f {ipjson_dir}/ip.json {ipjson_dir}/ip_template.json".format(ipjson_dir=ipjson_dir))

    #cp ip.json/ip_template.json to other php node 
    php_ips = get_service_ips("php_frontend_private")
    for php_ip in php_ips:
        scp_to_remote(ipjson_path, php_ip, ipjson_dir)
        scp_to_remote(ipjson_dir + "/ip_template.json", php_ip, ipjson_dir)

    log_info("update ip.json end")

def get_ipjson_key(service_name):
    if service_name == "wisteria":
        return "java_cluster"
    elif service_name in ["connect-sh", "connect-selector", "connect-dh", 
            "connect-agent", "scan-srv", "gateway", "user-srv",
            "upload-srv", "detect-srv", "job-srv"]:
        return "java_" + service_name + "_cluster"
    elif service_name.startswith("mongod_"):
        return "db_mongo_java_" + service_name

    return service_name 

def config_sh(ip, sh_ip, sh_node):
    old_sh_ips = get_service_ips("java_connect-sh")
    # get exists sh config
    scp_from_remote("/data/app/titan-config/sh.json", old_sh_ips[0], ScriptPath)
    # load the old configuration
    old_sh_config = json.load(file(ScriptPath + "/sh.json"))

    old_sh_config["node"] = sh_node
    old_sh_config["connect_address"]["ipv4"] = sh_ip
            
    # write the connect config
    f = open(ScriptPath + "/sh.json", "w+")
    f.write(json.dumps(old_sh_config, indent = 4, sort_keys = True))
    f.close()

    #cp sh.json to sh node 
    scp_to_remote(ScriptPath + "/sh.json", ip, '/data/app/titan-config/sh.json')

def remove_java_service(ip, service_name):
    # backup java.json
    exec_ssh_cmd(ip, '''mkdir -p /data/backup/tmp_for_scale && /bin/cp -f /data/app/titan-config/java.json /data/backup/tmp_for_scale/ ''')
    if service_name != "wisteria-all":
        exec_ssh_cmd_withresult(ip, "/data/app/titan-{name}/init.d/{name} stop".format(name=service_name))
        exec_ssh_cmd(ip, "rm -rf /data/titan-logs/java/{name}".format(name=service_name))
        
        if service_name in ["connect-sh", "connect-selector", 
                        "connect-dh", "connect-agent", "scan-srv"]:
            exec_ssh_cmd_withresult(ip, "rpm -e titan-{name}".format(name=service_name))
            exec_ssh_cmd(ip, "! test -d /data/app/titan-{name} || rm -rf /data/app/titan-{name}".format(name=service_name))
            exec_ssh_cmd(ip, "rm -f /etc/init.d/{name}".format(name=service_name))
    else:
        exec_ssh_cmd_withresult(ip, "/etc/init.d/wisteria stop")
        exec_ssh_cmd_withresult(ip, "rpm -e titan-{name}".format(name="wisteria"))
    #restore java.json, after uninstall wisteria,connect maybe still exists, so restore it
    exec_ssh_cmd(ip, '''mkdir -p /data/app/titan-config && /bin/cp -f /data/backup/tmp_for_scale/java.json  /data/app/titan-config/''')


def mongo_from_three_to_six(ip1, ip2, ip3):

    # get current cluster info
    # print cluster info will change to
    log_info("MongoCluster Change Detail:")
    print("will install mongod_27019/mongod_37020 at " + ip1)
    print("will install mongod_27020/mongod_37021 at " + ip2)
    print("will install mongod_27021/mongod_37019 at " + ip3)

    shard1_pri = mongo_cluster.shard_members["shard1"]["PRIMARY"][0]
    shard2_pri = mongo_cluster.shard_members["shard2"]["PRIMARY"][0]
    shard3_pri = mongo_cluster.shard_members["shard3"]["PRIMARY"][0]

    print(shard1_pri,shard2_pri,shard3_pri)

    shard1_sec = mongo_cluster.shard_members["shard1"]["SECONDARY"]
    shard2_sec = mongo_cluster.shard_members["shard2"]["SECONDARY"]
    shard3_sec = mongo_cluster.shard_members["shard3"]["SECONDARY"]

    print("will remove " + str(shard1_sec))
    print("will remove " + str(shard2_sec))
    print("will remove " + str(shard3_sec))

    v = get_input("Y", "Please confirm to continue? default is Y. Enter [Y/N]:")
    if v == "n" or v == "N" or v == "No" or v == "NO":
        sys.exit(0)

    for ip in [ip1, ip2, ip3]:
        set_np_login(ip)
        set_basic_config(ip)

    # check host env
    check_env(ip1, ["27019","37020","27017"])
    check_env(ip2, ["27020","37021","27017"])
    check_env(ip3, ["27021","37019","27017"])

    # ensure mongo cluster package install
    log_info("Install mongocluster rpm begin")
    for ip in [ip1,ip2,ip3]:
        check_rsync(ip)
        sync_mongo_rpm(ip)
        install_mongo_cluster(ip)
    log_info("Install mongocluster rpm end") 

    install_shard_member(ip1, "shard1","27019")
    add_shard_member(ip1, "27019", shard1_pri)
    install_shard_member(ip2, "shard1","37019")
    add_shard_member(ip2, "37019", shard1_pri)

    install_shard_member(ip2, "shard2","27020")
    add_shard_member(ip2, "27020", shard2_pri)
    install_shard_member(ip3, "shard2","37020")
    add_shard_member(ip3, "37020", shard2_pri)

    install_shard_member(ip3, "shard3","27021")
    add_shard_member(ip3, "27021", shard3_pri)
    install_shard_member(ip1, "shard3","37021")
    add_shard_member(ip1, "37021", shard3_pri)

    # install mongos on ip1,ip2,ip3
    for ip in [ip1, ip2, ip3]:
        install_start_mongos(ip, "cs/" + ",".join(mongo_cluster.configdb))

    update_ipjson({"db_mongo_java_cluster":[ip1,ip2,ip3],
                   "db_mongo_java_mongod_27019":[ip1],
                   "db_mongo_java_mongod_37019":[ip2],
                   "db_mongo_java_mongod_27020":[ip2],
                   "db_mongo_java_mongod_37020":[ip3],
                   "db_mongo_java_mongod_27021":[ip3],
                   "db_mongo_java_mongod_37021":[ip1]},"add")

    # wait 30s
    print("now wait 30 seconds")
    time.sleep(30)
    
    # remove old seondary on old hosts
    log_info("remove old secondary node start")
    shard1_pri_ip,shard2_pri_ip,shard3_pri_ip = shard1_pri.split(":")[0],shard2_pri.split(":")[0],shard3_pri.split(":")[0]
    remove_shard_member(shard2_pri_ip, "27019")
    remove_shard_member(shard3_pri_ip, "27019")
    remove_shard_member(shard1_pri_ip, "27020")
    remove_shard_member(shard3_pri_ip, "27020")
    remove_shard_member(shard1_pri_ip, "27021")
    remove_shard_member(shard2_pri_ip, "27021")
    update_ipjson({"db_mongo_java_mongod_27019":[shard2_pri_ip,shard3_pri_ip],
                   "db_mongo_java_mongod_27020":[shard1_pri_ip,shard3_pri_ip],
                   "db_mongo_java_mongod_27021":[shard1_pri_ip,shard2_pri_ip]},
                   "del")


def sync_redis_rpm(ip):
    scp_to_remote("/etc/yum.repos.d/qingteng.repo", ip, "/etc/yum.repos.d/")

    scp_to_with_mkdir("/data/qt_base/base/qingteng/qingteng-base-el" + OS_VERSION, ip, "/data/qt_base/base/qingteng")
    scp_to_with_mkdir("/data/qt_base/base/qingteng/redis", ip, "/data/qt_base/base/qingteng")
    scp_to_with_mkdir("/data/qt_base/redis", ip, "/data/qt_base/")
    scp_to_with_mkdir("/data/qt_base/base/qingteng/repodata", ip, "/data/qt_base/base/qingteng")

    exec_ssh_cmd(ip, '''yum clean all''')

def install_redis_cluster_rpm(ip):
    exec_ssh_cmd(ip, '''yum -y install qingteng-rediscluster''')

def start_redis_cluster(ip, port="81"):
    for pre in ["63","64","65"]:
        redis_port = pre + port
        exec_ssh_cmd_withresult(ip,'''chkconfig redis{redis_port}d on && service redis{redis_port}d restart'''.format(redis_port=redis_port))

def install_redis_cluster(ip1,ip2,ip3,redis_pwd,redis_name="java"):
    redis_port_map = {"erlang":"79","php":"80","java":"81"}
    port = redis_port_map[redis_name]

    # check and sync mongo rpm to new
    log_info("will install redis cluster at " + ",".join([ip1, ip2, ip3]))
    v = get_input("Y", "Please confirm to continue? default is Y. Enter [Y/N]:")
    if v == "n" or v == "N" or v == "No" or v == "NO":
        sys.exit(0)

    for ip in [ip1, ip2, ip3]:
        set_np_login(ip)
        set_basic_config(ip)
        check_env(ip, ["63"+port,"64"+port,"65"+port])

    log_info("Install rediscluster rpm begin")
    for ip in [ip1,ip2,ip3]:
        check_rsync(ip)
        sync_redis_rpm(ip)
        install_redis_cluster_rpm(ip)
    log_info("Install rediscluster rpm end") 
    # check and sync redis rpm

    # start redis
    for ip in [ip1,ip2,ip3]:
        start_redis_cluster(ip)
    
    # redis-trib.rb  create --replicas  0  172.16.4.81:6379 172.16.4.82:6379 172.16.4.83:6379
    os.system(ssh_qt_cmd(ip1,'''redis-trib.rb create --replicas 0 {ip1}:63{port} {ip2}:63{port} {ip3}:63{port} '''.format(ip1=ip1,ip2=ip2,ip3=ip3,port=port)))

    node_dict = {}
    _node_cmd = '''/usr/local/qingteng/redis/bin/redis-cli -c -p 63{port}  CLUSTER NODES '''.format(port=port)
    node_infos = exec_ssh_cmd_withresult(ip1, _node_cmd)
    for node_info in node_infos.splitlines():
        strs = node_info.split()
        node_id,node_str = strs[0],strs[1]
        ip = node_str.split(":")[0]
        node_dict[ip] = node_id
    
    add_node_cmd1 = '''redis-trib.rb add-node --slave --master-id {msater_id} {slave_ip}:64$port {master_ip}:63$port '''.replace("$port", port)
    add_node_cmd2 = '''redis-trib.rb add-node --slave --master-id {msater_id} {slave_ip}:65$port {master_ip}:63$port '''.replace("$port", port)

    # ip1
    exec_ssh_cmd_withresult(ip1,add_node_cmd1.format(master_ip=ip1,msater_id=node_dict[ip1],slave_ip=ip2))
    exec_ssh_cmd_withresult(ip1,add_node_cmd2.format(master_ip=ip1,msater_id=node_dict[ip1],slave_ip=ip3))
    # ip2
    exec_ssh_cmd_withresult(ip1,add_node_cmd1.format(master_ip=ip2,msater_id=node_dict[ip2],slave_ip=ip3))
    exec_ssh_cmd_withresult(ip1,add_node_cmd2.format(master_ip=ip2,msater_id=node_dict[ip2],slave_ip=ip1))
    # ip3
    exec_ssh_cmd_withresult(ip1,add_node_cmd1.format(master_ip=ip3,msater_id=node_dict[ip3],slave_ip=ip1))
    exec_ssh_cmd_withresult(ip1,add_node_cmd2.format(master_ip=ip3,msater_id=node_dict[ip3],slave_ip=ip2))
    
    auth_cmd = '''for i in 63{port} 64{port} 65{port};do  echo "config set masterauth {passwd}"  | /usr/local/qingteng/redis/bin/redis-cli -c -p $i && echo "config set requirepass {passwd}" | /usr/local/qingteng/redis/bin/redis-cli -c -p $i && echo "config rewrite" | /usr/local/qingteng/redis/bin/redis-cli -c -p $i -a {passwd};done '''
    for ip in [ip1,ip2,ip3]:
        exec_ssh_cmd(ip,'''chown -R redis:redis /etc/redis/ ''')
        exec_ssh_cmd(ip,auth_cmd.format(port=port,passwd=redis_pwd))
        exec_ssh_cmd(ip,'''chown -R root:root /etc/redis/ ''')


def move_redis_cluster(ip1,ip2,ip3,redis_name="java"):
    redis_port_map = {"erlang":"79","php":"80","java":"81"}
    port = redis_port_map[redis_name]

    log_info("will install redis cluster at new hosts and stop old redis cluster,then restart java services")

    old_ips = get_service_ips("db_redis_"+redis_name)
    for ip in [ip1,ip2,ip3]:
        if ip in old_ips:
            log_error("old redis cluster already have " + ip )
    
    passwd_dict = get_plainpwd("redis_"+redis_name,False)
    cur_redis_pwd = passwd_dict["redis_"+redis_name]
    
    install_redis_cluster(ip1,ip2,ip3,redis_pwd=cur_redis_pwd,redis_name=redis_name)

    # stop old
    for ip in old_ips:
        exec_ssh_cmd(ip,"service redis63{port}d stop && service redis64{port}d stop && service redis65{port}d stop ".format(port=port))

    update_ipjson({"db_redis_{role}_cluster".format(role=redis_name):[ip1,ip2,ip3],
                    "db_redis_{role}".format(role=redis_name):[ip1]},"replace")

    update_java_redis_config([ip1,ip2,ip3],redis_name,port)
    
    if redis_name != "java":
        update_php_redis_config([ip1,ip2,ip3],redis_name,port)

    if redis_name == "java":
        restart_servers = ",".join(['java_user-srv','java_upload-srv','java_detect-srv','java_scan-srv','java_job-srv','java','java_patrol-srv','java_gateway'])
    elif redis_name == "erlang":
        restart_servers = ",".join(['java_connect-agent','java_connect-dh','java_upload-srv','java_patrol-srv'])

    restart_cmd = "python {script_path} --restart {servers}".format(script_path=TITAN_SYSYTEM_PY,servers=restart_servers)
    exec_ssh_cmd("", restart_cmd)    

def update_java_redis_config(redis_ips,redis_name,port):
    java_ip = get_service_ips("java")[0]
    print "copy the current config files from Java Server...\n"
    java_config_directory = "/data/app/titan-config/java.json"
    scp_from_remote(java_config_directory, java_ip, ScriptPath + "/java.json")
    
    # load the current configuration
    java_config = json.load(file(ScriptPath + "/java.json"))

    redis_nodes = [ip+":63"+port for ip in redis_ips]
    java_config["redis"]["erl" if redis_name == "erlang" else redis_name]["clusterNodes"] = ",".join(redis_nodes)

    java_ips = get_all_java_ips()

    # write the java config
    f = open(ScriptPath + "/java.json", "w+")
    f.write(json.dumps(java_config, indent = 4, sort_keys = True))
    f.close()
    put_javajson_to_new(java_ips)

def update_php_redis_config(redis_ips,redis_name,port):
    _PHP_Servers = ["php_frontend_private", "php_backend_private", "php_agent_private", 
                    "php_download_private", "php_api_private", "php_inner_api"]

    php_ips = set()
    for srv_name in _PHP_Servers:
        php_ips.update(get_service_ips(srv_name))
    php_ips.discard("")
    php_ips.discard("127.0.0.1")

    php_conf = "/data/app/www/titan-web/conf/product/application.ini"
    
    redis_nodes = [ip+":63"+port for ip in redis_ips]
    redis_nodestr = ",".join(redis_nodes)
    for ip in php_ips:
        if redis_name == "erlang":
            for name in ["monitor","synctoken"]:
                exec_ssh_cmd(ip, '''sed -i 's/redis.{name}.host=.*/redis.{name}.host="{redis_ip}:{port}"/g' {conf_path} '''.format(redis_ip=redis_ips[0],conf_path=php_conf,name=name))
                exec_ssh_cmd(ip, '''sed -i 's/redis.{name}.cluster_seeds=.*/redis.{name}.cluster_seeds="{redis_nodestr}"/g {conf_path} '''.format(redis_nodestr=redis_nodestr,conf_path=php_conf,name=name))
            
        if redis_name == "php":
            for name in ["default","cache","inform"]:
                exec_ssh_cmd(ip, '''sed -i 's/redis.{name}.host=.*/redis.{name}.host="{redis_ip}:{port}"/g' {conf_path} '''.format(redis_ip=redis_ips[0],conf_path=php_conf,name=name))
                exec_ssh_cmd(ip, '''sed -i 's/redis.{name}.cluster_seeds=.*/redis.{name}.cluster_seeds="{redis_nodestr}"/g {conf_path} '''.format(redis_nodestr=redis_nodestr,conf_path=php_conf,name=name))

def get_sh_nodes():
    nodes = []
    sh_ips = get_service_ips("java_connect-sh")
    for ip in sh_ips:
        nodeid = exec_ssh_cmd_withresult(ip, '''cat /data/app/titan-config/sh.json | grep 'node"' | tr -c '[0-9]' ' ' | tr -d ' ' ''')
        nodes.append(nodeid)

    nodes.sort()

    return nodes

# for example, if now have 2,3,4, get 3 new nodes, will return 1,5,6
def get_new_nodeid(nodes,count=1):
    new_nodes = []
    for i in range(1,100):
        if str(i) not in nodes:
            new_nodes.append(str(i))
            count = count -1
        if count <= 0 :
            return new_nodes
        
def get_job_nodes():
    nodes = []
    job_ips = get_service_ips("java_job-srv")
    for ip in job_ips:
        nodeid = exec_ssh_cmd_withresult(ip, '''cat /data/app/titan-config/job.json | grep 'node"' | tr -c '[0-9]' ' ' | tr -d ' ' ''')
        nodes.append(nodeid)

    nodes.sort()

    return nodes

# install new connect services at ips
def install_connect_role(ips,ip_pub_dict={}):

    backup_javajson()

    for ip in ips:
        set_np_login(ip)
        set_basic_config(ip)
        # check host env
        check_env(ip, ["6220","6210","16677","7788"])

    log_info("Install connect services begin")
    
    # get sh nodeids
    new_sh_nodes = get_new_nodeid(get_sh_nodes(),len(ips))

    for ip in ips:
        check_rsync(ip)
        sync_java_rpm(ip)
        install_java_dependency(ip)
        install_java_service(ip, "connect-selector")
        install_java_service(ip, "connect-agent")
        install_java_service(ip, "connect-dh")

        sh_ext = {"sh_node":new_sh_nodes.pop(0)}
        if ip_pub_dict.get(ip, "") != "":
            sh_ext["sh_public_ip"] = ip_pub_dict.get(ip, "")
        install_java_service(ip, "connect-sh", sh_ext)

    log_info("Install connect services end")

    put_javajson_to_new(ips)

    for ip in ips:
        start_java_service(ip, ["connect-sh", "connect-selector", 
                                "connect-dh", "connect-agent"])

    # config nginx 
    add_cluster_slb({"connect-selector": ips})
    add_innerapi_clients(ips)

    # update ip
    update_ipjson({ "connect-dh": ips,
                    "connect-sh": ips,
                    "connect-agent": ips,
                    "connect-selector": ips,}, "add")

    log_warn_and_continue("New connect-agent install, Please update license from patrol.") 

# remove connect role
def remove_connect_role(ips):

    for ip in ips:
        remove_java_service(ip, "connect-selector")
        remove_java_service(ip, "connect-agent")
        remove_java_service(ip, "connect-dh")
        remove_java_service(ip, "connect-sh") 
            
    # config nginx 
    remove_cluster_slb({"connect-selector": ips})

    # update ip
    update_dict = { "connect-selector": ips, "connect-agent": ips,
                    "connect-dh": ips, "connect-sh": ips}
    update_ipjson(update_dict, "del")

# 
def install_java_role(ips):

    scan_ips = get_service_ips("java_scan-srv")
    if len(scan_ips) > 0:
        docker_enable = True
    else:
        docker_enable = False

    for ip in ips:
        set_np_login(ip)
        set_basic_config(ip)
        # check host env
        ports = ["16000","6100","6120","6130","6140","6170","6171","6172"]
        if docker_enable:
            ports.append("6150")
        check_env(ip, ports)

    log_info("Install java services begin")

    backup_javajson()
    # get job nodeids
    new_job_nodes = get_new_nodeid(get_job_nodes(),len(ips))

    for ip in ips:
        check_rsync(ip)
        sync_java_rpm(ip)
        install_java_dependency(ip)
        install_glusterfs_client(ip)
        install_java_service(ip, "gateway")
        install_java_service(ip, "wisteria")
        install_java_service(ip, "user-srv")
        install_java_service(ip, "upload-srv")
        install_java_service(ip, "detect-srv")
        if docker_enable:
            install_java_service(ip, "scan-srv")
        install_java_service(ip, "job-srv", {"job_node":new_job_nodes.pop(0)})

    log_info("Install java services end")

    put_javajson_to_new(ips)

    for ip in ips:
        services = list(WISTERIA_ALL)
        if docker_enable:
            services.append("scan-srv")
        start_java_service(ip, services)

    # config nginx 
    add_cluster_slb({"gateway": ips, "upload-srv": ips})
    add_innerapi_clients(ips)

    # update ip
    update_dict = { "gateway": ips, "wisteria": ips,
                    "user-srv": ips, "upload-srv": ips,
                    "detect-srv": ips, "job-srv": ips}
    if docker_enable:
        update_dict["scan-srv"] = ips
    update_ipjson(update_dict, "add") 

# remove java role
def remove_java_role(ips):
    log_info("remove java role begin")

    scan_ips = get_service_ips("java_scan-srv")
    del_scan_ips = []
    for ip in ips:
        remove_java_service(ip, "wisteria-all")
        if ip in scan_ips:
            remove_java_service(ip, "scan-srv")
            del_scan_ips.append(ip) 

        remove_glusterfs_client(ip)
            
    # config nginx 
    remove_cluster_slb({"gateway": ips, "upload-srv": ips})

    # update ip
    update_dict = { "gateway": ips, "wisteria": ips,
                    "user-srv": ips, "upload-srv": ips,
                    "detect-srv": ips, "job-srv": ips}
    if len(del_scan_ips) > 0:
        update_dict["scan-srv"] = del_scan_ips
    update_ipjson(update_dict, "del") 

SERVICE_PORT_MAP = {
    "wisteria":6100,
    "gateway":16000,
    "user-srv":6120,
    "detect-srv":6140,
    "upload-srv":6130,
    "job-srv":6170,
    "scan-srv":6150,
    "connect-agent":6220,
    "connect-dh":6210,
    "connect-sh":7788,
    "connect-selector":16677
}

# install one java service
def install_one_service(ip, service_name, ip_pub=None):
    if not SERVICE_PORT_MAP.has_key(service_name):
        log_error(service_name + " is invalid")

    ipjson_key = get_ipjson_key(service_name)
    exist_ips = get_service_ips(ipjson_key)
    if ip in exist_ips:
        log_error(ip + "already install " + service_name)

    set_np_login(ip)
    set_basic_config(ip)
    # check host env
    port = SERVICE_PORT_MAP.get(service_name)
    check_env(ip, [str(port)])
    log_info("check env end")

    backup_javajson()

    check_rsync(ip)
    sync_java_rpm(ip)
    install_java_dependency(ip)

    if service_name in WISTERIA_ALL or service_name == "scan-srv":
        install_glusterfs_client(ip)
    
    log_info("check dependency end")

    ext = {}
    if service_name == "job-srv":
        new_job_nodes = get_new_nodeid(get_job_nodes(),1)
        ext["job_node"] = new_job_nodes[0]
    elif service_name == "connect-sh":
        new_sh_nodes = get_new_nodeid(get_sh_nodes(),1)
        ext["sh_node"] = new_sh_nodes[0]
        if ip_pub:
            ext["sh_public_ip"] = ip_pub

    install_java_service(ip, service_name, ext)

    put_javajson_to_new([ip])

    start_java_service(ip, [service_name])
            
    # config nginx
    if service_name in ["gateway","upload-srv","connect-selector"]:
        add_cluster_slb({service_name: [ip]})

    # update ip
    update_dict = { service_name: [ip] }
    update_ipjson(update_dict, "add")

# remove one java service
def remove_one_service(ip, service_name):
    if not SERVICE_PORT_MAP.has_key(service_name):
        log_error(service_name + " is invalid")

    remove_java_service(ip, service_name)

    if service_name in WISTERIA_ALL or service_name == "scan-srv":
        # if hava no other wisteria service on host, confirm to remove all data
        pass
        # remove_glusterfs_client(ip)
            
    # config nginx
    if service_name in ["gateway","upload-srv","connect-selector"]:
        remove_cluster_slb({service_name: [ip]})

    # update ip
    update_dict = { service_name: [ip] }
    update_ipjson(update_dict, "del")


def add_shard_member_for_input():
    shard_detail = mongo_cluster.shard_members

    shard_name = get_input('', "Input the shard name to add member: ") 
    if shard_name == "":
        log_error("shard_name must not empty")
    
    if not shard_detail.has_key(shard_name):
        log_error("Current Mongo Cluster have no shard : " + shard_name)

    replSet = shard_detail[shard_name]
    log_info("current detail of {0} is:".format(shard_name) + json.dumps(replSet, indent=4, sort_keys=True))

    pri_node = replSet["PRIMARY"][0]
    pri_port = pri_node.split(":")[1]

    isSecondary = get_input("Y", "Add a secondary or arbiter,(Y is secondary, N is arbiter, default is Y, input Y/N ): ")
    if isSecondary in ["y", "Y", "Yes", "YES"]:
        member_port = pri_port
    else:
        member_port = "3" + pri_port[1:]
    
    ips = get_ip_of_server(shard_name + " of mongo cluster to add memeber",1)
    ip = ips[0]

    for nodes in replSet.values():
        for node in nodes:
            if ip in node:
                log_error("Replica Set Membees must in different host, can't add new member to host which already have " + node)
    
    set_np_login(ip)
    set_basic_config(ip)
    check_env(ip, [member_port])

    # ensure mongo cluster package install
    log_info("Install mongocluster rpm begin")
    check_rsync(ip)
    sync_mongo_rpm(ip)
    install_mongo_cluster(ip)
    log_info("Install mongocluster rpm end")

    install_shard_member(ip, shard_name, member_port)
    add_shard_member(ip, member_port, pri_node)

    update_ipjson({"db_mongo_java_mongod_"+member_port: [ip]},"add")


def remove_shard_member_for_input():
    shard_detail = mongo_cluster.shard_members

    shard_name = get_input('', "Input the shard name to remove member: ") 
    if shard_name == "":
        log_error("shard_name must not empty")
    
    if not shard_detail.has_key(shard_name):
        log_error("Current Mongo cluster have no shard : " + shard_name)
    
    replSet = shard_detail[shard_name]
    log_info("current detail of {0} is:".format(shard_name) + json.dumps(replSet, indent=4, sort_keys=True))

    remove_node = get_input('', "Input the node to remove(for example: 127.0.0.1:27019): ")
    if remove_node == "":
        log_error("remove_node must not empty")

    ip = remove_node.split(":")[0]
    member_port = remove_node.split(":")[1]
    remove_shard_member(ip,member_port)

    update_ipjson({"db_mongo_java_mongod_"+member_port: [ip]},"del")


def add_new_shard_for_input():
    new_conf = mongo_cluster.get_next_shardconf()
    shard_name, port, arb_ip = new_conf["shard_name"],new_conf["port"],new_conf["arb_ip"]

    new_ips = get_ip_of_server("Mongo Cluster " + shard_name, 2)
    ip_pri, ip_2nd = new_ips[0], new_ips[1]

    print("will install {ip}:2{port}".format(ip=ip_pri,port=port))
    print("will install {ip}:2{port}".format(ip=ip_2nd,port=port))
    print("will install {ip}:3{port}".format(ip=arb_ip,port=port))

    v = get_input("Y", "Please confirm to continue? default is Y. Enter [Y/N]:")
    if v == "n" or v == "N" or v == "No" or v == "NO":
        sys.exit(0)

    for ip in [ip_pri,ip_2nd]:
        set_np_login(ip)
        set_basic_config(ip)
        check_env(ip, ["2" + port])

    # ensure mongo cluster package install
    log_info("Install mongocluster rpm begin")
    for ip in [ip_pri, ip_2nd]:
        check_rsync(ip)
        sync_mongo_rpm(ip)
        install_mongo_cluster(ip)

    log_info("Install mongocluster rpm end")

    # install and add mongos at new mongo host
    for ip in [ip_pri, ip_2nd]:
        install_start_mongos(ip, "cs/" + ",".join(mongo_cluster.configdb))

    replSet_deploy(ip_pri,ip_2nd,arb_ip,shard_name,port)
    add_replSet_to_shard(ip_pri,ip_2nd,arb_ip,shard_name,port)
    
    update_ipjson({"db_mongo_java_mongod_2"+port:[ip_pri,ip_2nd],
                   "db_mongo_java_mongod_3"+port:[arb_ip]},
                   "add")
    
    # confirm to move arbiter node


def get_iplist_from_str(ipstr):
    ips = []
    for _ip in ipstr.split(","):
        ip = _ip.strip()
        if ip == '':
            continue
        
        ip = ip.split(":")[0]
        ips.append(ip)

    return ips

def get_ip_of_server(name, server_count=-1, public=False):
    ipstr = get_input('', "Input ip of {name} : ".format(name=name)) 
    if ipstr == "":
        log_error("can't be empty")
    ips = get_iplist_from_str(ipstr)
    if server_count > 0 and len(ips) != server_count:
        log_error("Number of ips is worng, Please input correct ips")
    
    if len(ips) > len(set(ips)):
        log_error("Ip must be unique")
    
    if public:
        ip_pub_str = get_input('', "Input public ip of {name} (default empty, not need) : ".format(name=name))   
        ip_pubs = get_iplist_from_str(ip_pub_str)
        if len(ip_pubs) >0 and len(ip_pubs) != len(ips):
            log_error("public ip and private should be One-to-one correspondence")
        
        ip_pub_dict = {}
        if len(ip_pubs) == 0:
            return ips, ip_pub_dict

        for index, ip in enumerate(ips):
            ip_pub_dict[ip] = ip_pubs[index]
        return ips,ip_pub_dict
    else:
        return ips

def show_help():
    print "=========== Usage Info ============="
    print "python scale.py [mongo_status] [from_9_to_15] [add_java] [remove_java] [add_connect] [remove_connect] [add_glusterfs] [add_shard_mem] [remove_shard_mem] [add_new_shard] [add_one_srv] [remove_one_srv]"

def main(argv):
    global OS_VERSION
    global mongo_cluster

    mongo_status = None
    from_9_to_15 = None
    from_6_to_9 = None
    add_java = None
    remove_java = None
    add_connect = None
    remove_connect = None
    add_glusterfs = None
    add_one_srv = None
    remove_one_srv = None
    add_shard_mem = None
    remove_shard_mem = None
    add_new_shard = None
    move_redis = None
    redis_name = "java"

    opts = None
    try:
        opts, args = getopt.getopt(argv, "", 
                                ["help","mongo_status","from_9_to_15",
                                "add_java","remove_java","add_connect",
                                "remove_connect","add_glusterfs","add_shard_mem",
                                "remove_shard_mem","add_new_shard","add_one_srv",
                                "remove_one_srv","from_6_to_9","move_redis"
                                ])
    except getopt.GetoptError:
        show_help()
        sys.exit()      

    for opt, arg in opts:
        if opt == "--mongo_status":
            mongo_status = True
        elif opt == "--from_9_to_15":
            from_9_to_15 = True
        elif opt == "--from_6_to_9":
            from_6_to_9 = True
        elif opt == "--add_java":
            add_java = True
        elif opt == "--remove_java":
            remove_java = True
        elif opt == "--add_connect":
            add_connect = True
        elif opt == "--remove_connect":
            remove_connect = True
        elif opt == "--add_glusterfs":
            add_glusterfs = True
        elif opt == "--add_shard_mem":
            add_shard_mem = True
        elif opt == "--remove_shard_mem":
            remove_shard_mem = True
        elif opt == "--add_new_shard":
            add_new_shard = True
        elif opt == "--add_one_srv":
            add_one_srv = True
        elif opt == "--remove_one_srv":
            remove_one_srv = True
        elif opt == "--move_redis":
            move_redis = True
            if arg is not None and arg != "":
                redis_name = arg
            if redis_name not in ["java","php","erlang"]:
                log_error("redis name error, exit")
        elif opt == "--help":
            show_help()
            sys.exit(1)
        else:
            show_help()
            sys.exit(1)

    OS_VERSION = get_os_version("")
    if OS_VERSION not in ["6","7"]:
        log_error("something wrong, current os verison:{0} exception".format(OS_VERSION))

    # mongo_status or from_9_to_15 need mong cluster info
    if mongo_status or from_9_to_15 or add_shard_mem or remove_shard_mem or add_new_shard:
        passwd_dict = get_plainpwd("mongo",False)
        #print(passwd_dict)
        mongos_ips = get_service_ips("db_mongo_java")
        check_mongo_version(mongos_ips[0])

        mongo_cluster = MongoClusterInfo(mongos_ips, passwd_dict["mongo"])
        mongo_cluster.dumps()

    if from_9_to_15:
        # input three mongo ips
        new_mongo_ips = get_ip_of_server("MONGODB to new install", 3)
        mongo_from_three_to_six(new_mongo_ips[0],new_mongo_ips[1],new_mongo_ips[2])

        old_connect_ips =  get_service_ips("java_connect-agent")
        new_connect_ips, ip_pub_dict = get_ip_of_server("CONNECT to new install", 3, True)
        install_connect_role(new_connect_ips,ip_pub_dict)

        log_info("Please update license from patrol, after that you can run python scale.py --remove_connect to remove old connect role")
    
    if from_6_to_9:
        new_ips = get_ip_of_server("3 new hosts", 3)
        move_redis_cluster(new_ips[0],new_ips[1],new_ips[2],redis_name)

        old_java_ips =  get_service_ips("java")

        print("Will install JAVA at " + ",".join(new_ips))
        print("Will remove JAVA at " + ",".join(old_java_ips))
        # move java to new, install and remove old
        install_java_role(new_ips)
        remove_java_role(old_java_ips)

    if add_java:
        new_java_ips = get_ip_of_server("JAVA to new install")
        install_java_role(new_java_ips)
    if remove_java:
        del_java_ips = get_ip_of_server("JAVA to remove")
        remove_java_role(del_java_ips)
    
    if add_connect:
        new_conn_ips = get_ip_of_server("CONNECT to new install")
        install_connect_role(new_conn_ips)
    if remove_connect:
        del_conn_ips = get_ip_of_server("CONNECT to remove")
        remove_connect_role(del_conn_ips)
    
    if add_one_srv:
        service_name = get_input('', "Input the service name to new install: ") 
        if service_name == "":
            log_error("service name must not empty")

        if service_name == "connect-sh":
            new_ips, ip_pub_dict = get_ip_of_server(service_name + " to new install", 1, True)
            install_one_service(new_ips[0], service_name, ip_pub_dict.get(new_ips[0], None))
        else:
            new_ips = get_ip_of_server(service_name + " to new install", 1)
            install_one_service(new_ips[0], service_name, None)
        
    if remove_one_srv:
        service_name = get_input('', "Input the service name to remove: ") 
        if service_name == "":
            log_error("service name must not empty")
        
        ipjson_key = get_ipjson_key(service_name)
        exist_ips = get_service_ips(ipjson_key)
        log_info(service_name + " current nodes are: " + ",".join(exist_ips))

        del_ips = get_ip_of_server(service_name + " to remove", 1)
        remove_one_service(del_ips[0],service_name)
    
    if add_glusterfs:
        new_gluster_ips = get_ip_of_server("Glusterfs to new install", 3)
        install_glusterfs(new_gluster_ips[0],new_gluster_ips[1],new_gluster_ips[2])
    
    if move_redis:
        new_redis_ips = get_ip_of_server("redis cluster to move", 3)
        move_redis_cluster(new_redis_ips[0],new_redis_ips[1],new_redis_ips[2],redis_name)
    
    if add_shard_mem:
        add_shard_member_for_input()
    
    if remove_shard_mem:
        remove_shard_member_for_input()
    
    if add_new_shard:
        add_new_shard_for_input()

if __name__ == '__main__':

    main(sys.argv[1:])

