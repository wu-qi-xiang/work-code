# -*- coding: utf-8 -*-
#!/usr/bin/env python

"""Monitor iptables status of Titan servers.

"""
import json
import os
import re
import smtplib
from email.MIMEText import MIMEText
import sys
import time
from config_helper import *
import socket 


reload(sys)
sys.setdefaultencoding('utf-8')

USE_FIREWALL = True

# php config file
PHP_CONFIG_FILE = "/data/app/www/titan-web/conf/build.json"

OLD_IPTABLES_LIST_PATH = "/data/app/www/titan-web/config_scripts/old_iptables_list.txt"

FIREWALL_DIFFRESULT = "/data/app/www/titan-web/config_scripts/firewall_diffresult.txt"

ports=(80,81,6110,8001,8002,8443,6000,6677,7788,443)

HEAD_IPTABLES = [
    "-P INPUT ACCEPT",
    "-A INPUT -m state --state RELATED,ESTABLISHED -j ACCEPT",
    "-A INPUT -p tcp -m state --state NEW -m tcp --dport 22 -j ACCEPT",
    "-A INPUT -i lo -j ACCEPT",
    "-A INPUT -s 127.0.0.1/32 -j ACCEPT"
]

END_IPTABLES = "-A INPUT -j DROP"

HEAD_FIREWALL = {'services':['ssh','dhcpv6-client'],'rich rules':['rule family="ipv4" source address="127.0.0.1" accept'],'port':[]}

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

    msg['Subject'] = ' Titan firewall monitor alert '
    msg['From'] = mail_from
    msg['To'] = mail_to
    # Send the message via SMTP server.
    smtp = smtplib.SMTP()
    smtp.connect(smtp_server)
    smtp.login(str(smtp_user), str(smtp_password))
    smtp.sendmail(mail_from, mail_to.split(','), msg.as_string())
    ret = smtp.quit()
    if ret:
        print 'send email success'

def get_all_ips():
    ipjson = json.load(file("/data/app/www/titan-web/config_scripts/ip.json"))
    ip_list = list(set(re.findall(r'(?<![\.\d])(?:(?:25[0-5]|2[0-4]\d|[01]?\d\d?)\.){3}(?:25[0-5]|2[0-4]\d|[01]?\d\d?)(?![\.\d])', str(ipjson)))) 
    public_ips = list(set(get_service_ips("php_frontend_public") + get_service_ips("java_connect-selector_public") + get_service_ips("java_connect-sh_public") + get_service_ips("eip")))
    ip_list.remove("127.0.0.1")
    for public_ip in public_ips:
        ip_list.remove(public_ip)   
    return ip_list

def open_ports(ip):
    ip_ports = []
    for port in ports:
        sk = socket.socket(socket.AF_INET, socket.SOCK_STREAM) 
        sk.settimeout(1) 
        try: 
            sk.connect((ip,port)) 
            ip_ports.append(port)
        except Exception: 
            print 'Server port' + str(port) + ' not open on ' + str(ip) 
        sk.close()
    return ip_ports 

def ip_port():
    all_ips = get_all_ips()
    ip_port_list = {}
    for i in all_ips:
        ip_port_list[i] = open_ports(i)
    return ip_port_list

def generate_ip_iptables():
    ip_iptables_list = {}
    ip_port_dict = ip_port()
    if USE_FIREWALL:
        for ip in ip_port_dict.keys():
            ip_iptables_list[ip] = copy.deepcopy(HEAD_FIREWALL) 
            for ips in ip_port_dict.keys():
                ip_iptables_list[ip]['rich rules'].append('rule family="ipv4" source address="' + ips + '" accept')
            for port in ip_port_dict[ip]:
                ip_iptables_list[ip]['port'].append(str(port) + '/tcp')
    else:       
        for ip in ip_port_dict.keys():
            ip_iptables_list[ip] = copy.deepcopy(HEAD_IPTABLES) 
            for ips in ip_port_dict.keys():
                #print ip_iptables_list[ip]
                ip_iptables_list[ip].append("-A INPUT -s " + str(ips) + "/32 -j ACCEPT")
            for port in ip_port_dict[ip]:
                 ip_iptables_list[ip].append("-A INPUT -p tcp -m tcp --dport " + str(port) + " -j ACCEPT")
            ip_iptables_list[ip].append(END_IPTABLES) 
    return ip_iptables_list

def get_dst_iptables(ip):
    if USE_FIREWALL:
        result = {}
        cmd_port = ''' firewall-cmd  --list-ports '''
        cmd_services = ''' firewall-cmd  --list-services '''
        cmd_rich_rules = ''' firewall-cmd   --list-rich-rules'''
        try:
            result['port'] = exec_ssh_cmd_withresult(ip, cmd_port).split()
            result['services'] = exec_ssh_cmd_withresult(ip, cmd_services).split()
            result['rich rules'] = [i for i in re.split('\r|\n',exec_ssh_cmd_withresult(ip, cmd_rich_rules)) if i != '']
        except Exception as e:
            print str(e)
            log_info('FirewallD is not running or Failed to execute command')
        return result
    else:
        result = []
        cmd = ''' iptables -t filter --list-rules INPUT '''
        result_cmd = exec_ssh_cmd_withresult(ip, cmd)
        for result_cmd_item in [i for i in re.split('\r|\n',result_cmd) if i != '']:
            result.append(result_cmd_item.strip())
        return result

def get_per_ip_iptables(all_ips):
    iptables_dict = {}
    for i in all_ips:
        iptables_dict[i] = get_dst_iptables(i)
    return iptables_dict

def diff_iptables(oldiptables,newiptables):
    if USE_FIREWALL:
        try:
            if sorted(oldiptables['services']) == sorted(newiptables['services']) and sorted(oldiptables['port']) == sorted(newiptables['port']) and  sorted(oldiptables['rich rules']) == sorted(newiptables['rich rules']):
                return True
            else:
                return False
        except Exception as e:
            print str(e)
            log_info('Key error or sorted iptables Failed')
            return False
    else:
        try:
            if sorted(oldiptables) == sorted(newiptables):
                return True
            else:
                return False
        except Exception as e:
            print str(e)
            log_info('Key error or sorted iptables Failed')
            return False 

def main():
    global USE_FIREWALL
    all_ips = get_all_ips()
    new_ip_iptables = get_per_ip_iptables(all_ips)

    f = open(FIREWALL_DIFFRESULT , "w+")
    #clean result file
    f.truncate()
    f.close()   
    if not os.path.isfile(OLD_IPTABLES_LIST_PATH):
        old_ip_iptables = generate_ip_iptables()
        f = open(OLD_IPTABLES_LIST_PATH , "w+")
        f.write(json.dumps(old_ip_iptables, indent = 4, sort_keys = True))
        f.close()
    else:
        old_ip_iptables = json.load(file(OLD_IPTABLES_LIST_PATH))
    for ip in old_ip_iptables.keys():
        if not diff_iptables(old_ip_iptables[ip],new_ip_iptables[ip]):
            f = open(FIREWALL_DIFFRESULT , "a+")
            f.write(json.dumps(ip, indent = 4, sort_keys = True))
            f.write(json.dumps(old_ip_iptables[ip], indent = 4, sort_keys = True))
            f.write(json.dumps(new_ip_iptables[ip], indent = 4, sort_keys = True))
            f.close()
    if os.path.getsize(FIREWALL_DIFFRESULT) != 0:
        sendmail(FIREWALL_DIFFRESULT)
if __name__ == "__main__":
    main()

