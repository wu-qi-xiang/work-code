#!/bin/bash

export LANG="en_US.UTF-8"

COLOR_G="\x1b[0;32m"  # green
COLOR_R="\x1b[1;31m"  # red
COLOR_Y="\x1B[1;31m"  # yellow
#COLOR_Y="\033[31m \033[05m"
RESET="\x1b[0m"
echo "##########################################################################"
echo "#                                                                        #"
echo "#                        Qingteng health check script                    #"
echo "#                                                                        #"
echo "#警告:本脚本只是一个检查的操作,未对服务器做任何修改,管理员可以根据此报告       #"
echo "#进行相应的整改                                                           #"
echo "#下方会给出整改建议                                                       #"
echo "##########################################################################"
echo " "

# export PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin:/root/bin
# source /etc/profile

ROOT=`cd \`dirname $0\` && pwd`

DEFAULT_PORT=22
DEFAULT_USER=root

Default_Cpuinfo_Num=8
#Default_report_MemTotal=30720
Default_report_MemTotal=30720 #mb
Default_inodetotal=250 #M
Default_diskdata=450 #Gb
Default_diskinode=32 #M

[ $(id -u) -gt 0 ] && error_log "请用root或者sudo用户执行此脚本！" && exit 1
VERSION=`date +%F`

check_ip_host=`cat $ROOT/service_ip.conf |egrep -v "^$|vip" |awk '{print $2}'|sort | uniq`
function info_log(){
    if [ ! -z $2 ] ;then
        echo -e "${COLOR_G}$(date +"%Y-%m-%d %T")[Info][主机:$2] ${1}${RESET}"
    else
        echo -e "${COLOR_G}$(date +"%Y-%m-%d %T")[Info] ${1}${RESET}"
    fi
}

function error_log(){
    if [ ! -z $2 ] ;then
        echo -e "${COLOR_R}$(date +"%Y-%m-%d %T")[Error][主机:$2] ${1}${RESET}"
    else
        echo -e "${COLOR_R}$(date +"%Y-%m-%d %T")[Error] ${1}${RESET}"
    fi
    exit 1
}
function warn_log(){
    if [ ! -z $2 ] ;then 
        echo -e "${COLOR_Y}$(date +"%Y-%m-%d %T")[Warning][主机:$2] ${1}${RESET}"
    else
        echo -e "${COLOR_Y}$(date +"%Y-%m-%d %T")[Warning] ${1}${RESET}"
    fi
}
## $1实际主机指标。$2 预期主机指标。
function diff(){
    local host=$1
    local index_name=$2
    local Actual_index=$3
    local Expected_index=$4
    if [ $3 -lt $4 ];then
        warn_log "$index_name最低需要：$Expected_index,检测该主机实际为：$Actual_index,请检查处理" ${host}
    else
        info_log "$index_name最低需要：$Expected_index,检测该主机实际为：$Actual_index,满足安装条件，无需处理" $host
    fi
}

function diff_parameter(){
    local host=$1
    local index_name=$2
    local Actual_index=$3
    local Expected_index=$4
    if [ $3 -lt $4 ];then
        warn_log "$index_name最低需要：$Expected_index,检测该主机实际为：$Actual_index,请检查处理" ${host}
    else
        info_log "$index_name最低需要：$Expected_index,检测该主机实际为：$Actual_index,满足安装条件，无需处理" $host
    fi
}

check(){
    if [ $? -eq 0 ];then
        info_log "$* Successfully"
    else
        error_log "$* Failed"
        exit 1
    fi
}

function sq() { # single quote for Bourne shell evaluation
    # Change ' to '\'' and wrap in single quotes.
    # If original starts/ends with a single quote, creates useless
    # (but harmless) '' at beginning/end of result.
    printf '%s\n' "$*" | sed -e "s/'/'\\\\''/g" -e 1s/^/\'/ -e \$s/\$/\'/
}

function ssh_t(){
    # 当用户不是root或者没有加sudo，才使用 sudo -n bash -c 'cmd', 主要处理web安装时 check hostname和path时的多个命令一起执行时的问题
    if [[ $DEFAULT_USER != "root" && !("$2" =~ .*sudo.*) ]]; then
        sudocmd="sudo -n bash -c $(sq "$2")"
        #echo "$sudocmd"
        ssh -p ${DEFAULT_PORT} -oStrictHostKeyChecking=no -o ConnectionAttempts=5 -o ConnectTimeout=3 ${DEFAULT_USER}@$1 "$sudocmd" >/dev/null 2>&1
    else
        ssh -p ${DEFAULT_PORT} -oStrictHostKeyChecking=no -o ConnectionAttempts=5 -o ConnectTimeout=3 ${DEFAULT_USER}@$1 $2 
    fi
}

function version(){
    echo ""
    echo ""
    echo -e "系统巡检脚本：Version $VERSION"
}

function getSSHStatus(){
    #SSHD服务状态，配置,受信任主机等
    echo ""
    echo -e "\033[33m*******************************************************SSH检查*******************************************************\033[0m"
    for host in ${check_ip_host[@]};do
        ssh_t ${host} "echo ok" >>/dev/null 2>&1
        if [ $? -eq 0 ];then
            info_log "本机远程登录到${host} 成功~" ${host}
        else
            error_log "本机远程登录到${host} 失败~ 请检查免密" ${host}
        fi
    done
}

function getCpuStatus(){
    echo ""
    echo -e "\033[33m*******************************************************CPU检查*******************************************************\033[0m"
    for host in ${check_ip_host[@]};do
        info_log "------------[$host]---------------"
        Cpuinfo_Num=$(ssh_t $host 'cat /proc/cpuinfo |grep ^processor|wc -l')        
        Physical_CPUs=$(ssh_t $host 'grep "physical id" /proc/cpuinfo| sort | uniq | wc -l')
        Virt_CPUs=$(ssh_t $host 'grep "processor" /proc/cpuinfo | wc -l') 
        CPU_Kernels=$(ssh_t $host "grep cores /proc/cpuinfo | uniq | awk -F ':' '{print $2}'" ) 
        CPU_Type=$(ssh_t $host "grep 'model name' /proc/cpuinfo | awk -F ':' '{print $2}' | sort | uniq") 
        CPU_Arch=$(ssh_t $host 'uname -m')
        diff ${host} "CPU线程总数" $Cpuinfo_Num $Default_Cpuinfo_Num
        info_log "CPU线程总数：$Cpuinfo_Num" ${host}
        info_log "物理CPU个数:$Physical_CPUs" ${host}
        info_log "逻辑CPU个数:$Virt_CPUs" ${host}
        info_log "每CPU核心数:$CPU_Kernels" ${host}
        info_log "CPU型号:$CPU_Type" ${host}
        info_log "CPU架构:$CPU_Arch" ${host}
    done 
}

function getMemStatus(){
    echo ""
    echo  -e "\033[33m*******************************************************内存检查*******************************************************\033[0m"
    for host in ${check_ip_host[@]};do
        info_log "------------[$host]---------------"
        centosVersion=$(ssh_t $host "awk '{print \$(NF-1)}' /etc/redhat-release")
        if [[ $centosVersion < 7 ]];then
            ssh_t $host free -mo
        else
            ssh_t $host free -h
        fi
        MemTotal=$(ssh_t $host "cat /proc/meminfo|grep MemTotal | awk '{print \$2}'")  #KB
        report_MemTotal=$(($MemTotal/1024))
        diff $host "内存总大小(MB)" ${report_MemTotal} ${Default_report_MemTotal}
        info_log "总内存大小(MB):$report_MemTotal" $host
    done

}



function getDiskStatus(){
    echo ""
    echo -e "\033[33m*******************************************************磁盘检查*******************************************************\033[0m"
    for host in ${check_ip_host[@]};do
        info_log "------------[$host]---------------"
        ssh_t $host "df -hiP | sed 's/Mounted on/Mounted/' > /tmp/inode; \
        df -hTP | sed 's/Mounted on/Mounted/'> /tmp/disk; \
        join /tmp/disk /tmp/inode | awk '{print \$1,\$2,\"|\",\$3,\$4,\$5,\$6,\"|\",\$8,\$9,\$10,\$11,\"|\",\$12}'| column -t"
        echo "-----------------------"
        # diskdata=$(df -TP|sed '1d'|sed "/^tmp/d" |sort -k 3n|tail -1)
        disk_data=$(ssh_t $host "df -TP|grep -Ew '/data$'| awk {'print \$3'}")
        if [ ! -z ${disk_data} ];then
            diff $host "/data目录可用容量(GB)" $((disk_data/1024/1024)) ${Default_diskdata}
        else
            disk_data=$(ssh_t $host "df -TP|grep -Ew '/$'| awk {'print \$3'}")
            if [ $((disk_data/1024/1024)) -ge ${Default_diskdata} ];then
                warn_log "发现/目录总空间大于${Default_diskdata}GB,安装将使用/目录,请确认！！！" $host
            else
                warn_log "未发现/目录或者/data空间大小超过${Default_diskdata}GB，请检查磁盘是否挂载，磁盘空间是否充足" $host
            fi
        fi
        #diskinode=$(df -TP|sed '1d'|sed "/^tmp/d" |sort -k 3n|tail -1)
        disk_inode=$(ssh_t $host "df -iTP | grep -Ew '/data$' | awk {'print \$3'}")
        if [ ! -z ${disk_inode} ];then
            diff $host "/data目录可用容量(M)" $((disk_inode/1024/1000)) ${Default_diskinode}
        else
            disk_inode=$(ssh_t $host "df -iTP|grep -Ew '/$'| awk {'print \$3'}")
            if [ $((disk_inode/1024/1000)) -ge ${Default_diskinode} ];then
                info_log "发现/目录inode大于${Default_diskinode}M,安装会使用/目录,请确认！！！" $host
            else
                warn_log "未发现/目录或者/data目录inode大小超过${Default_diskinode}M，请检查/磁盘初始化状态" $host
            fi
        fi
    done

    # inodedata=$(df -iTP | sed '1d' | awk '$2!="tmpfs"{print}')
    # inodetotal=$(echo "$inodedata" | awk '{total+=$3}END{print total}')
    # inodeused=$(echo "$inodedata" | awk '{total+=$4}END{print total}')
    # inodefree=$((inodetotal-inodeused))
    # inodeusedpercent=$(echo $inodetotal $inodeused | awk '{if($1==0){printf 100}else{printf "%.2f",$2*100/$1}}')
    # report_DiskTotal=$((disktotal/1024/1024))"GB" 
    # report_DiskFree=$((diskfree/1024/1024))"GB"   
    # report_DiskUsedPercent="$diskusedpercent""%"   
    # report_InodeTotal=$((inodetotal/1000))"K"     
    # report_InodeFree=$((inodefree/1000))"K"       
    # report_InodeUsedPercent="$inodeusedpercent""%" 
}



function getSystemStatus(){
    echo ""
    echo -e "\033[33m*******************************************************系统检查 *******************************************************\033[0m"
    centosVersion_list=(6 7)
    SELINUX_list=(enforcing permissive)
    for host in ${check_ip_host[@]};do
        info_log "------------[$host]---------------"
        #default_LANG="$(ssh_t $host "grep 'LANG=' /etc/sysconfig/i18n | grep -v '^#' | awk -F '\"' '{print \$2}'")"
        default_LANG="$(ssh_t $host "/usr/bin/locale |grep \"LANG\"|awk -F \"=\" '{print \$2}'")"
        #export LANG="en_US.UTF-8"
        Release=$(ssh_t $host "cat /etc/redhat-release 2>/dev/null")
        Kernel=$(ssh_t $host "uname -r")
        OS=$(ssh_t $host "uname -o")
        Hostname=$(ssh_t $host "uname -n")
        SELinux=$(ssh_t $host "/usr/sbin/sestatus | grep 'SELinux status: ' | awk '{print \$3}'")
        LastReboot=$(ssh_t $host "who -b | awk '{print \$3,\$4}'")
        uptime=$(ssh_t $host "uptime | sed 's/.*up \([^,]*\), .*/\1/'")
        ssl_version=$(ssh_t $host "openssl version | awk '{print \$2}' ")
        path=$(ssh_t $host "echo \$PATH")
        local_umask=$(ssh_t $host "umask")
        local_java_home="$(ssh_t $host "echo \$JAVA_HOME")"
        echo "     系统：$OS"
        echo " 发行版本：$Release"
        echo "     内核：$Kernel"
        echo "   主机名：$Hostname"
        echo "  SELinux：$SELinux"
        echo "语言/编码：$default_LANG"
        echo " 当前时间：$(ssh_t $host "date")"
        echo " 最后启动：$LastReboot"
        echo " 运行时间：$uptime"
        echo " openssl版本：$ssl_version"
        echo " umask: $local_umask"
        #check os
        centosVersion=$(ssh_t $host "awk '{print \$(NF-1)}' /etc/redhat-release| cut -d\".\" -f1")
        result=$(echo ${centosVersion_list[@]} | grep "$centosVersion")
        [[ "$result" == "" ]] && warn_log "操作系统不匹配" $host
        #check iptables/firewalld
        if [ "$centosVersion" == "6" ];then
            [ "$(ssh_t $host "/sbin/service iptables status 1>/dev/null 2>\&1 ; echo \$?")" != "3" ] && warn_log "iptables 开启中，请关闭！" $host
        elif [ "$centosVersion" == "7" ];then
            [ "$(ssh_t $host "systemctl status firewalld >/dev/null  2>\&1 ; echo \$?")" != "3" ] && warn_log "Firewalld 开启中，请关闭！" $host
        fi
        #check hostname
        #is localhost
        if [[ ${Hostname} =~ "localhost" ]];then
            warn_log "主机名：${Hostname} 不符合要求，不能是localhost，请检查并修改" $host
        fi
        #is number
        if [ -n "$(echo $Hostname| sed -n "/^[0-9]\+$/p")" ];then
            warn_log "主机名：${Hostname} 不符合要求,不可以是纯数字，请检查并修改" $host
        fi
        #is "^."
        if [[ ${Hostname} =~ "^." ]];then
            warn_log "主机名：${Hostname} 不符合要求,不可以以.开头，请检查并修改" $host
        fi
        #check SELINUX

        [[ "${SELINUX_list[@]}" =~ "$SELinux" ]] && warn_log "SELINUX:$SELinux 不符合要求,请修改后并重启机器" $host
        #check lang        
        if [ "${default_LANG}" != "en_US.UTF-8" ];then
            warn_log " 语言/编码：$default_LANG 不符合要求,应该为：en_US.UTF-8,请修改" $host
        fi
        #check server time 
        if [[ $(ssh_t $host "date") =~ "CST" ]];then
            local_time=$(date --date="$(date +'%Y-%m-%d %H:%M:%S')" +%s)
            remote_time=$(ssh_t $host "date --date=\"\$(date +'%Y-%m-%d %H:%M:%S')\" +%s")
            diff_time=$(($local_time-$remote_time))
            if (($diff_time<0));then
                diff_time=$((-$diff_time))
            fi
            if (($diff_time>600));then
                warn_log "ip为：$host 主机时间与控制机时间相差 $diff_time S,超过10分钟以上，请检查并调整"
            fi
        else
            warn_log "主机时间不是CST时间，请检查并修改" $host            
        fi

        ! if [[ $(echo $ssl_version | awk '{print $2}') =~ "^1.0.2" ]];then
            warn_log "openssl版本为：$ssl_version,与要求版本不符合,请检查" $host
        fi

        [ -z "$(echo ${path} | grep "/usr/local/bin")" ] && warn_log "系统加载路径未包含/usr/local/bin ,请检查！！" $host
        
        if [ ! -z "$(ssh_t ${host} "grep 'reposdir' /etc/yum.conf")" ];then
            local local_repo_dir=$(ssh_t ${host} "grep 'reposdir' /etc/yum.conf | awk -F '=' '{print \$2}'")
            if [ -z "$(echo '/etc/yum.repos.d/' | grep "$local_repo_dir")" ];then 
                warn_log "yum仓库路径指向不是/etc/yum.repos.d,请检查确认" $host
            fi
        fi
        [ "${local_umask}" != "0022" ] && warn_log "umask等于$local_umask,与要求的的0022不符合，请检查" $host
        [ ! -z "${local_java_home}" ] && warn_log "环境中存在JAVA_HOME:${local_java_home}" $host
    done
}


function getFilestatus(){
    echo ""
    echo -e "\033[33m*******************************************************文件检查 *******************************************************\033[0m"
    for host in ${check_ip_host[@]};do
        [ ! -z "$(ssh_t $host 'grep "^auth[[:space:]]*required" /etc/pam.d/su')" ] && warn_log "/etc/pam.d/su中未注释auth required行" $host
        [ ! -z "$(ssh_t $host 'grep "^Default[[:space:]]*requiretty" /etc/sudoers')" ] && warn_log "/etc/sudoers中未注释auth requiretty行" $host
        [ "$(ssh_t $host "[ -w /etc/passwd ] && echo 1 ||echo 2")" == "2" ] && warn_log "/etc/passwd 不可读，请检查" $host
        [ "$(ssh_t $host "[ -w /etc/sudoers ] && echo 1 ||echo 2")" == "2" ] && warn_log "/etc/passwd 不可读，请检查" $host
        [ "$(ssh_t $host "[ -w /etc/group ] && echo 1 ||echo 2")" == "2" ] && warn_log "/etc/passwd 不可读，请检查" $host        
    done
}

function getPortstatus(){
    echo ""
    echo -e "\033[33m*******************************************************端口检查 *******************************************************\033[0m"
    local ignore_port_list="25|10050|10051|$DEFAULT_PORT"
    for host in ${check_ip_host[@]};do
        port_list=$(ssh_t ${host} "ss -ntul |grep LISTEN|awk '{print \$5}'|cut -d":" -f2|egrep -v \"^\$|${ignore_port_list}\"|sort|uniq|xargs")
        [ ! -z "$port_list" ] && warn_log "服务器上存在相关端口$port_list,请检查" $host
    done
}

function getServicestatus(){
    echo ""
    echo -e "\033[33m*******************************************************服务检查 *******************************************************\033[0m"
    local ignore_server_list="mariadb-libs|mysql-libs"
    local check_server_list="nginx|mysql|mongodb|percona|jdk|kafka|zookeeper|wisteria|php|redis|mariadb-libs|percona|gnome|xorg|elasticsearch|logstash|viewer"
    for host in ${check_ip_host[@]};do
        server_list=$(ssh_t ${host} "rpm -aq|egrep  \"${check_server_list}\"|egrep -v \"${ignore_server_list}\"")
        [ ! -z "$server_list" ] && warn_log "服务器上安装了影响服务端部署冲突的安装包：\n$server_list \n请检查!!!" $host
    done

}


#getSSHStatus && sleep 3s
#getCpuStatus && sleep 3s
#getMemStatus && sleep 3s
#getDiskStatus && sleep 3s
#getSystemStatus && sleep 3s
#getFilestatus && sleep 3s
#getPortstatus && sleep 3s
#getServerstatus && sleep 3s


function help() {
    echo "-------------------------------------------------------------------------------"
    echo "                        Usage information"
    echo "-------------------------------------------------------------------------------"
    echo ""
    echo -e "./check_system.sh [<all | check_ssh | check_cpu | check_mem | check_disk |check_system| check_file |check_port |check_service]"
    echo "Options:"
    echo "  all                         check all environments                  "
    echo "  check_ssh                   SSH检查                                 "
    echo "  check_cpu                   CPU检查                                 "
    echo "  check_mem                   内存检查                                "
    echo "  check_disk                  磁盘检查                                "
    echo "  check_system                系统检查                                "
    echo "  check_file                  文件检查                                "
    echo "  check_port                  端口检查                                "
    echo "  check_service               服务检查                                "
    echo ""
    echo "  One-key install:"
    echo "    ./check_system.sh all"
    echo "  Install for specific server:"
    echo "    ./check_system.sh check_ssh"
    echo "-------------------------------------------------------------------"
    exit 1
}
#------------------start------------------------------
if [ $# == "0" ];then
    help 
    exit 1
fi
version
while [ $# -gt 0 ]; do
    case $1 in
        all)
            getSSHStatus
            getCpuStatus
            getMemStatus
            getDiskStatus
        getSystemStatus
            getFilestatus
            getPortstatus
            getServicestatus
            exit 0
            ;;
        check_ssh)
            getSSHStatus
            exit 0
            ;;
        check_cpu)
            getCpuStatus
            exit 0
            ;;
        check_mem)
            getMemStatus
            exit 0
            ;;
        check_disk)
            getDiskStatu
            exit 0
            ;;
        check_system)
            getSystemStatus
            exit 0
            ;;
        check_file)
            getFilestatus
            exit 0
            ;;
        check_port)
            getPortstatus
            exit 0
            ;;
        check_service)
            getServicestatus
            exit 0
            ;;
        *)
            help $*
            exit 0
            ;;
    esac
done

