#! /usr/bin/python

from bcrypt import gensalt,hashpw
from config_helper import *

java_ip = get_service_ips("java")[0]
print "get java.json from Java Server...\n"
java_config_directory = "/data/app/titan-config/java.json"
scp_from_remote(java_config_directory, java_ip, "/data/app/www/titan-web/config_scripts/java.json")
    
# load the current configuration
java_config = json.load(file("/data/app/www/titan-web/config_scripts/java.json"))
pbeconfig = java_config["base"]["pbeconfig"]
pbepwd,pbesalt = pbeconfig[:16],pbeconfig[16:]
mysql_pwd = java_config["mysql"]["password"]

dbpasswd = decrypt_string(pbepwd,pbesalt,mysql_pwd)

mysql_ips = get_service_ips("db_mysql_php")
mysql_ip = mysql_ips[0]
if len(mysql_ips) > 1:
	mysql_path = CLUSTER_MYSQL
else:
	mysql_path = "/usr/local/sbin/mysql"

update_console_cmd= mysql_path + ''' -uroot -p'{dbpasswd}' -h 127.0.0.1 -e 'update qt_titan_user.v3_user set password="{enc_passwd}" where username="{username}";' '''
update_backend_cmd= mysql_path + ''' -uroot -p'{dbpasswd}' -h 127.0.0.1 -e 'update qt_titan_back.tb_user set password="{enc_passwd}" where username="{username}";' '''


print "Do you want to reset consonle(80) user's password? default is Y"
print "Enter [Y/N]: "
v = get_input("Y")
if v == "y" or v == "Y" or v == "Yes" or v == "YES":
	username = get_input("admin@sec.com","Please input console username to reset,(default is admin@sec.com):")
	random_pwd = randomString(13)
	new_pwd = get_input(random_pwd,"Please input console account's password,(default is {random_pwd}):".format(random_pwd=random_pwd))
	new_pwd = new_pwd.strip()
	if new_pwd == '':
		print("password input worng, will not reset")
	else:
		print("Please wait to encrypt password")
		enc_passwd=hashpw(new_pwd, gensalt(10))
		exec_ssh_cmd(mysql_ip, update_console_cmd.format(dbpasswd=dbpasswd,enc_passwd=enc_passwd,username=username))


print "Do you want to reset backend(81) user's password? default is Y"
print "Enter [Y/N]: "
v = get_input("Y")
if v == "y" or v == "Y" or v == "Yes" or v == "YES":
	username = get_input("admin@sec.com","Please input backend username to reset,(default is admin@sec.com):")
	random_pwd = randomString(13)
	new_pwd = get_input(random_pwd,"Please input backend account's password,(default is {random_pwd}):".format(random_pwd=random_pwd))

	if new_pwd == '':
		print("password input worng, will not reset")
	else:
		print("Please wait to encrypt password")
		enc_passwd=hashpw(new_pwd, gensalt(10))
		exec_ssh_cmd(mysql_ip, update_backend_cmd.format(dbpasswd=dbpasswd,enc_passwd=enc_passwd,username=username))

