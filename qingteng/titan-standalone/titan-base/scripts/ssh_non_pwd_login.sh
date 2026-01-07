#/bin/bash
#
# Set Colors
#

bold=$(tput bold)
underline=$(tput sgr 0 1)
reset=$(tput sgr0)

red=$(tput setaf 1)
green=$(tput setaf 76)
white=$(tput setaf 7)
tan=$(tput setaf 202)
blue=$(tput setaf 25)

#
# Headers and Logging
#

underline() { printf "${underline}${bold}%s${reset}\n" "$@"
}
h1() { printf "\n${underline}${bold}${blue}%s${reset}\n" "$@"
}
h2() { printf "\n${underline}${bold}${white}%s${reset}\n" "$@"
}
debug() { printf "${white}%s${reset}\n" "$@"
}
info() { printf "${white}➜ %s${reset}\n" "$@"
}
success() { printf "${green}✔ %s${reset}\n" "$@"
}
error() { printf "${red}✖ %s${reset}\n" "$@"
}
warn() { printf "${tan}➜ %s${reset}\n" "$@"
}
bold() { printf "${bold}%s${reset}\n" "$@"
}
note() { printf "\n${underline}${bold}${blue}Note:${reset} ${blue}%s${reset}\n" "$@"
}

DIR="$(cd "$(dirname "$0")" && pwd)"
CONF="$DIR/../host.conf"
BAK_CONF="$DIR/host.conf"
#SYSTEM_VERSION=`cat /etc/redhat-release | tr -cd '[0-9,\.]'|cut -d "." -f 1`
SYSTEM_VERSION=$(cat /etc/redhat-release | tr -cd '[0-9,\.]')
USERNAME=$(cat $CONF |grep "no_pass_user"|awk -F "=" '{print $2}'|sed 's/\"//g')
PORT=$(cat $CONF |grep "no_paas_port"|awk -F "=" '{print $2}'|sed 's/\"//g')
PASSWD=$(cat $CONF |grep "no_pass_word"|awk -F "=" '{print $2}'|sed 's/\"//g')

check_system(){
     if [ ! -f /etc/redhat-release ];then error "The /etc/redhat-release does not exist";exit 1 ;fi
     if [ $(echo ${SYSTEM_VERSION}|cut -d "." -f 1) == 6 -o $(echo ${SYSTEM_VERSION}|cut -d "." -f 1) == 7 ];then 
	note "System version: $SYSTEM_VERSION"
     else
        error "The operating system is not supported"
        exit 1
     fi
}

check(){
    if [ $? -eq 0 ];then
        success "$* Successfully"
    else
        error "$* Failed"
	exit 1
    fi
}

check_ssh_login(){
    local php_host=$1
    local host=$2
    # 如果需要输入密码则会导致超时
    sudo ssh -t -oStrictHostKeyChecking=no -p $PORT $USERNAME@$php_host "timeout 3 sudo ssh -t -oStrictHostKeyChecking=no -p $PORT $USERNAME@$host "echo ok"" >/dev/null  2>&1
    check " root@${host_php} to ${USERNAME}@${host} SSH has passwordless"
}

get_ips_php(){
    php_arr=$(cat ${CONF}|grep -E $1|egrep -v "^#|^$"|awk '{print $2}')
    local ips=()
    # declare exists as a map
    declare -A exists
    for s in ${php_arr[@]} ; do
        tempip=${s%:*}
        [[ $tempip == '127.0.0.1' ]] && continue  # if 127.0.0.1, not add to ips
        [[ ${exists[$tempip]} ]] && continue  # if already in exists, not add to ips
        ips+=( "$tempip" )
        exists[$tempip]=1
    done
    echo ${ips[@]}
}

auto_gen_ssh_key() {
    local host=$1
    local passwd=$(get_host_pwd $host)
    note "$host server root ssh-key is being created"
    expect -c "set timeout -1;
    	spawn sudo ssh -t -p $PORT $USERNAME@$host \"sudo ssh-keygen \";
	expect {
                *(yes/no)*  {send -- yes\r;exp_continue;}
                *password:* {send -- $passwd\r;exp_continue;}
	        *(/root/.ssh/id_rsa)* {send -- \r;exp_continue;}
		*passphrase)* {send -- \r;exp_continue;}
		*again*	{send -- \r;exp_continue;}
		*(y/n)* {send -- y\r;exp_continue;}
		*password:* {send -- $passwd\r;exp_continue;}
		eof         
	}" >/dev/null  2>&1;
    check "$host server root ssh-key is being created"
}

auto_php_copy_id() {
    local host_php=$1
    local host_php_pwd=`get_host_pwd $host_php`
    note "Building root@${host_php} to ${USERNAME}@${host_php} without password"
    expect -c "set timeout -1;
    spawn sudo ssh -t -oStrictHostKeyChecking=no -p $PORT $USERNAME@$host_php \"sudo ssh-copy-id -oStrictHostKeyChecking=no -p $PORT $USERNAME@$host_php\";
    expect {
            *password:* {send -- $host_php_pwd\r;exp_continue;}  
            eof         
    }">/dev/null  2>&1;
    check_ssh_login $host_php $host_php
}

auto_ssh_copy_id() {
    local host_php=$1
    local host=$2
    local host_php_pwd=`get_host_pwd $host_php`
    local host_pwd=`get_host_pwd $host`
    if [ $host_php != $host ];then
        note "Building root@${host_php} to ${USERNAME}@${host} without password"
    	expect -c "set timeout -1;
    	spawn sudo ssh -t -oStrictHostKeyChecking=no -p $PORT $USERNAME@$host_php \"sudo ssh-copy-id -oStrictHostKeyChecking=no -p $PORT $USERNAME@$host\";
    	expect {
            	*password:* {send -- $host_pwd\r;exp_continue;}
                eof  
         }" >/dev/null  2>&1 ;
        check_ssh_login $host_php $host
    fi
}
get_host_pwd(){
    local host=$1
    if [ $PASSWD ];then
       local passwd=$PASSWD;
    else
       local passwd=$(cat ${CONF}|egrep -v "^#|^$|^php|^no"|grep $host|awk '{print $2}')
    fi
    echo $passwd
}



auto_copy_id_to_all() {
    local ips=`get_ips_php php`
    local ips_host=`get_ips_host`
    for ip in ${ips[@]};do
        auto_gen_ssh_key $ip
        auto_php_copy_id $ip
	for ip_host in ${ips_host[@]};do
            host_ip=$(echo $ip_host|awk '{print $1}')
            auto_ssh_copy_id $ip $host_ip 
        done
    done
}
get_ips_host(){
    host_arr=$(cat ${CONF}|egrep -v "^#|^$|^php|^no" |awk '{print $1}')  
    echo ${host_arr[@]}
}
install_expect(){
    info "Install tcl dependencies"
    rpm -ivh $DIR/expect/$(echo ${SYSTEM_VERSION}|cut -d "." -f 1)/*tcl*.rpm
#    check "Install tcl dependencies"
    info "Install expect dependencies" 
    rpm -ivh $DIR/expect/$(echo ${SYSTEM_VERSION}|cut -d "." -f 1)/*expect*.rpm  
#    check "Install expect dependencies"
}   


check_system
install_expect
set -e
auto_copy_id_to_all
if [ $? -eq 0 ]; then
    cp -f ${BAK_CONF} ${CONF}
else 
   info "免密失败, 请检查host.conf文件, 重新执行"
fi
