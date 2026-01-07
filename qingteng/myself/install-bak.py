# coding=utf-8
import json
import os
import sys
import subprocess
from time import sleep
import commands
import re

reload(sys)
sys.setdefaultencoding("utf-8")
titan_config_path = "/data/app/titan-config"
default_src = "/usr/local/src"
tmp_config_dir = "./tmp_config"
step_file = tmp_config_dir + "/step"
config_file = tmp_config_dir + "/config.json"
step = 0
# tmp_config = {
#     "default_src": "/usr/local/src",
#     "private_ip": "127.0.0.1",
#     "domain": "",
#     "public_ip": "",
#     "event_ip": "127.0.0.1",
#     "ms_ip": "127.0.0.1"
# }

# config_file = tmp_config_dir + "/config.json"
# service_ip_tpl = '''php %(private_ip)s
# mysql %(private_ip)s
# redis_php %(private_ip)s
# zookeeper %(private_ip)s
# kafka %(private_ip)s
# connect %(private_ip)s
# redis_erlang %(private_ip)s
# rabbitmq %(private_ip)s
# java %(private_ip)s
# redis_java %(private_ip)s
# mongo_java %(private_ip)s
# '''


#初始化配置文件
# def init_config_file():
#     # global tmp_config
#     global default_src
#     if os.path.exists(config_file):
#         with open(config_file, "r") as load_f:
#             tmp_config = json.load(load_f)
#             default_src = tmp_config["default_src"]
#         load_f.close()
#     else:
#         f = open(config_file, "w")
#         f.write(json.dumps(tmp_config))
#         f.close()

# 读取当前在哪个步骤，获取step
def init_step_file():
    global step
    if os.path.exists(step_file):
        f = open(step_file, "r")
        line = f.readline()
        if not (not line):
            step = int(line)
    else:
        f = open(step_file, "w")
        f.write(str(step))
        f.close()


# 更新配置文件
def update_config():
    global tmp_config
    f = open(config_file, "w")
    tmp_config["default_src"] = default_src
    print (tmp_config)
    f.write(json.dumps(tmp_config))
    f.close()


# 更新执行的步骤
def update_step(n):
    f = open(step_file, "w")
    f.write(str(n))
    f.close()


# 准备初始化配置文件
def init_tmp():
    if os.path.exists(tmp_config_dir):
        print ("初始化相关配置文件")
        init_step_file()
        # init_config_file()
    else:
        os.mkdir(tmp_config_dir)
        init_tmp()


# def config():
#     init_config_file()
#     global tmp_config
#     global service_ip_tpl
#     private_ip = raw_input("输入php安装的地址: ")
#     #domain = raw_input("Input the domain of Server (default ,if have no,just empty,please not input ip): ")
#     #public_ip = raw_input("Input the public ip of Server (default ,if have no,just empty,please not input private ip):")
    
#     print ("是否安装事件采集, default is Y")
#     event_key = raw_input("Enter [Y/N]:")
#     if event_key == "y" or event_key == "Y" or event_key == "Yes" or event_key == "YES" or event_key == '':
#         event_ip = raw_input("请输入事件采集event_srv的安装地址: ")
#         tmp_config["event_ip"] = event_ip
#         service_ip_tpl = service_ip_tpl + 'event_srv %(event_ip)s\n'
        


#     print ("是否安装微隔离, default is Y")
#     ms_key = raw_input("Enter [Y/N]:")
#     if ms_key == "y" or ms_key == "Y" or ms_key == "Yes" or ms_key == "YES" or ms_key == '':
#         ms_ip = raw_input("请输入微隔离ms_srv的安装地址: ")
#         tmp_config["ms_ip"] = ms_ip
#         service_ip_tpl = service_ip_tpl + 'ms_mongo %(ms_ip)s\n'
#         service_ip_tpl = service_ip_tpl + ' \nms_srv %(ms_ip)s\n'

#     tmp_config["private_ip"] = private_ip
#     #tmp_config["public_ip"] = public_ip
#     #tmp_config["domain"] = domain

#     print json.dumps(tmp_config)
#     update_config()
#     base_install()


#记录安装步骤
def pstree_kill(pid):
    pstree = commands.getoutput("sudo pstree -p %s" % pid)
    rule = r"\((.+?)\)"
    pids = re.findall(rule, pstree)
    print (pids)
    for p in pids:
        os.kill(int(p), 9)


# 解压整包的安装包
def patch_all():
    global default_src
    src = raw_input("请输入解压路径,(default %s):" % default_src)
    if not (not (src.strip())):
        default_src = src
    update_config()
    print ("开始解压安装包")
    p = subprocess.Popen("sudo bash patch_all.sh %s" % default_src, stdin=sys.stdin, stdout=sys.stdout,
                         shell=True)
    p.wait()
    print ("安装包解压完毕")
    update_step(1)


#解压base包
def decompression_base():
    cmd_args = "cd %s && sudo tar -zxf titan-base-*" % default_src
    p = subprocess.Popen(cmd_args, stdin=subprocess.PIPE, stdout=subprocess.PIPE, shell=True)
    while p.poll() is None:  # None表示正在执行中
        r = p.stdout.readline().strip()
        print (r)
    print ("base包解压完毕")
    update_step(2)


#解压app包
def decompression_app():
    print ("解压app包")
    cmd_args = "cd %s && sudo tar -zxf  titan-app*" % default_src
    p = subprocess.Popen(cmd_args, stdin=subprocess.PIPE, stdout=subprocess.PIPE, shell=True)
    while p.poll() is None:  # None表示正在执行中
        r = p.stdout.readline().strip()
        print (r)
    print ("app包解压完毕")
    update_step(5)


# 安装base包
def base_install():
    global service_ip_tpl
    print ("---------开始配置service_ip.conf文件---------")
    service_ip = service_ip_tpl % tmp_config
    f = open(default_src + "/titan-base/service_ip.conf", "w")
    f.write(service_ip)
    f.close()
    print ("\033[31m---------请仔细检查一遍service_ip, 写错了可以退出再次执行---------\033[0m")
    print ("\033[31m---------检查---检查----检查----检查----检查---------\033[0m")
    print (service_ip)
    sleep (5)
    print ("判断配置文件是否正确, 是否继续执行, 默认继续执行")
    key = raw_input("Enter [Y/N]:")
    if key == "y" or key == "Y" or key == "Yes" or key == "YES" or key == '':
        pass
    else:
        sys.exit()
          
    print ("开始安装base组件")
    titan_base = default_src + "/titan-base"
    cmd_args = "cd %s && sudo bash titan-base.sh all" % titan_base
    p = subprocess.Popen(cmd_args, stdout=subprocess.PIPE, shell=True)
    while p.poll() is None:  # None表示正在执行中
        r = p.stdout.readline().strip()
        print (r)
    print ("base组件安装结束")
    update_step(4)


#检查授权文件和规则文件
def check_license_and_rules():
    print ("开始检查授权文件")
    titan_app = default_src + "/titan-app"
    license_command = "ls -t ./*-license*.zip | head -n 1"
    status, output = commands.getstatusoutput(license_command)
    if status != 0:
        print ("Lincese file not exists, exit")
        sys.exit()

    rule_command = "ls -t ./*-rule*-v*.zip | head -n 1"
    status, output = commands.getstatusoutput(rule_command)
    if status != 0:
        print ("rule file not exists, exit")
        sys.exit()

    _command = "sudo cp ./*.zip %s" % titan_app
    status, output = commands.getstatusoutput(_command)
    if status != 0:
        print ("move file error")
        sys.exit()
    print ("检查授权文件结束")


# 安装app包
def app_install():
    check_license_and_rules()
    print ("开始配置app相关信息")
    titan_app = default_src + "/titan-app"
    cmd_args = "sudo python ip-config.py -n 1"
    p = subprocess.Popen(cmd_args, stdin=subprocess.PIPE, shell=True, cwd=titan_app)
    p.stdin.write("\n")
    p.stdin.write(tmp_config["private_ip"] + "\n")
    p.stdin.write(tmp_config["domain"] + "\n")
    p.stdin.write(tmp_config["public_ip"] + "\n")
    p.stdin.write(tmp_config["event_ip"] + "\n")
    p.stdin.write("\n")
    p.wait()
    print ("app相关信息配置结束")

    print ("开始安装APP")
    cmd_args = ["sudo", "bash", "titan-app.sh", "install", "v3"]
    p = subprocess.Popen(cmd_args, stdin=sys.stdin, stdout=sys.stdout, shell=False, cwd=titan_app)
    p.wait()
    print ("APP安装结束")
    update_step(6)


# 安装步骤拆分
def install():
    init_tmp()
    if step < 1:
        patch_all()
    elif step < 2:
        decompression_base()
    elif step < 3:
        base_install()
    elif step < 4:
        decompression_app()
    elif step < 5:
        app_install()


# 更新步骤拆分
def upgrade():
    pass

cmd_dict = {
    "install": install,
    "upgrade": upgrade,
    "config": config

}

if __name__ == '__main__':
    cmd = sys.argv[1]
    cmd_exec = cmd_dict.get(cmd)
    cmd_exec()
