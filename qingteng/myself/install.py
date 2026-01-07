# coding=utf-8
# date 2022-8-1
# auth wuxiang
import json
import os
import sys
import subprocess
from time import sleep
import commands
import re

reload(sys)
sys.setdefaultencoding("utf-8")
file_path = os.path.dirname(os.path.abspath(__file__))
titan_config_path = "/data/app/titan-config"
default_src = "/usr/local/src"
tmp_config_dir = "./tmp_config"
step_file = tmp_config_dir + "/step"
config_file = tmp_config_dir + "/config.json"
step = 0


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


# 更新配置文件，保存默认的安装路径
def update_config():
    global default_src
    f = open(config_file, "w")
    f.write("default_src = %s" % (default_src))
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
    else:
        os.mkdir(tmp_config_dir)
        init_tmp()


# 环境检查
def check_env():
    pass


# 解压整包的安装包
def decompress_all():
    global default_src
    src = raw_input("请输入解压路径,(default %s):" % default_src)
    if not (not (src.strip())):
        default_src = src
    update_config()
    print ("开始解压安装包，需要输入解压密码")
    p = subprocess.Popen("sudo bash patch_all.sh %s" % default_src, stdin=sys.stdin, stdout=sys.stdout, shell=True)
    p.wait()
    print ("安装包解压完毕")
    update_step(1)


# 解压base包
def decompress_base():
    cmd_args = "cd %s && sudo tar -zxf titan-base-*" % default_src
    p = subprocess.Popen(cmd_args, stdin=subprocess.PIPE, stdout=subprocess.PIPE, shell=True)
    while p.poll() is None:  # None表示正在执行中
        r = p.stdout.readline().strip()
        print (r)
    print ("base包解压完毕")
    update_step(2)


# 安装base包
def base_install():
    cmd_path = file_path + "/" + "config.conf"
    cmd_args = "cp -f %s %s/titan-base/server_ip.conf"%(cmd_path, default_src)
    os.system(cmd_args)
    print ("\033[31m---------请仔细检查一遍service_ip, 写错了可以退出再次执行---------\033[0m")
    print ("\033[31m---------检查---检查----检查----检查----检查---------\033[0m")
    service_ip = os.system("cat %s/titan-base/server_ip.conf"%(default_src))
    print (service_ip)
    sleep (5)
    print ("判断配置文件是否正确, 是否继续执行, 默认继续执行")
    key = raw_input("Enter [Y/N]:")
    if key == "y" or key == "Y" or key == "Yes" or key == "YES" or key == '':
        pass
    else:
        print("请仔细检查config.conf文件")
        sys.exit()
          
    print ("开始安装base组件")
    titan_base = default_src + "/titan-base"
    cmd_args = "cd %s && sudo bash titan-base.sh all" % titan_base
    p = subprocess.Popen(cmd_args, stdout=subprocess.PIPE, shell=True)
    while p.poll() is None:  # None表示正在执行中
        r = p.stdout.readline().strip()
        print (r)
    print ("base组件安装结束")
    update_step(3)


# 解压app包
def decompress_app():
    print ("解压app包")
    cmd_args = "cd %s && sudo tar -zxf  titan-app-*" % default_src
    p = subprocess.Popen(cmd_args, stdin=subprocess.PIPE, stdout=subprocess.PIPE, shell=True)
    while p.poll() is None:  # None表示正在执行中
        r = p.stdout.readline().strip()
        print (r)
    print ("app包解压完毕")
    update_step(4)


# 回填ip_template.json文件
def backfill_app_config():
    pass



# 检查app目录授权文件和规则文件
def check_license_and_rules():
    print ("开始检查授权和规则文件")
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
    print ("开始安装APP")
    cmd_args = ["sudo", "bash", "titan-app.sh", "install", "v3"]
    p = subprocess.Popen(cmd_args, stdin=sys.stdin, stdout=sys.stdout, shell=False, cwd=titan_app)
    p.wait()
    print ("APP安装结束")
    update_step(5)


# 安装步骤拆分
def install():
    # 获取当前步骤
    init_tmp()
    if step < 1:
        check_env()
    if step < 2:
        decompress_all()
    if step < 3:
        decompress_base()
    if step < 4:
        base_install()
    if step < 5:
        decompress_app()
    if step < 6:
        backfill_app_config() 
    if step < 7:    
        app_install()


# 更新步骤拆分
def upgrade():
    print ("还没开始写，等着吧") 
    pass



cmd_dict = {
    "install": install,
    "upgrade": upgrade,
}

if __name__ == '__main__':
    cmd = sys.argv[1]
    cmd_exec = cmd_dict.get(cmd)
    cmd_exec()
