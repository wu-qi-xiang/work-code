#!/bin/bash

DEFAULT_USER=root
DEFAULT_PORT=22

# the listening port used to check the connectivity of QT servers
TEMP_PORT=80
FILE_DIR=`cd \`dirname $0\` && /bin/pwd`
PORT_CHECK_RET=${FILE_DIR}/qt_stdalone_checker.log
TMP_SERVER=port_tool.py

ROLE_IP_CONF=`[ -f ${FILE_DIR}/service_ip.conf ] \
&& echo "${FILE_DIR}/service_ip.conf" \
|| echo "${FILE_DIR}/../service_ip.conf"`

PORTS_ERLANG="6677 7788 7789 8080 8443 8444 5672 15672" # beam
PORTS_PHP="80 443 81 8000 8001 8002"    # nginx
PORTS_JAVA="6000 1983 1984 2181 9092" # java
PORTS_MYSQL="3306"
PORTS_REDIS_ERLANG="6379"
PORTS_REDIS_PHP="6380"
PORTS_REDIS_JAVA="6381"
PORTS_MONGODB="27017"


set_np_authorized(){
    local ip=$1
    ${FILE_DIR}/setup_np_ssh.sh ${DEFAULT_USER}@${ip} ${DEFAULT_PORT}
}

# ports
get_ports(){
    local host=$1
    ssh -t -p ${DEFAULT_PORT} -oStrictHostKeyChecking=no ${DEFAULT_USER}@${host} "\
        (IFS=$'\n'; ports=''; for line in \`netstat -lnt|awk '{print \$4}'|sed '1,2d'\`; \
         do
            ports=\"\${ports}\n\${line##*:}\"
         done; echo -e \$ports|sort -n|uniq|tr \"\\\n\" \" \") || exit 1"
}

# ports & program name
get_ports_p(){
    local host=$1
    ssh -t -p ${DEFAULT_PORT} -oStrictHostKeyChecking=no ${DEFAULT_USER}@${host} "\
        (IFS=$'\n'; ret=''; for line in \`netstat -lntp|awk '{print \$4 \" \" \$7}'|sed '1,2d'\`; \
         do
             port=\`echo \${line} |awk '{print \$1}'\`
             prog=\`echo \${line} |awk '{print \$2}'\`
             ret=\"\${ret}\n\${port##*:} \${prog##*/}\"
         done; echo -e \${ret}|sort -uk 1,2n) || exit 1"
}

check_role_port_status(){
    local to_check_port=$1
    local query=$2

    for p in ${to_check_port};
    do
        local ret="`cat ${FILE_DIR}/tmp.log |grep ^${p} |grep ${query}|head -1`"
        [ ! -z "${ret}" ] && echo "${ret}" || echo "${p} wrong"
    done
}

after_deploy_check(){
    for ip in `cat ${ROLE_IP_CONF} |awk '{print $2}'|sort|uniq`;
    do
        echo "================== (${ip}) ======================"
        get_ports_p ${ip} > ${FILE_DIR}/tmp.log

        local roles=`grep ${ip} ${ROLE_IP_CONF}|awk '{print $1}'`
        for r in ${roles};
        do
            local ports=""
            local query=""
            case ${r} in
                erlang)
                    ports=${PORTS_ERLANG}
                    query=beam
                    ;;
                php)
                    ports=${PORTS_PHP}
                    query=nginx
                    ;;
                java)
                    ports=${PORTS_JAVA}
                    query=java
                    ;;
                redis_erlang|redis_php|redis_java)
                    local prefix=`echo ${r} | tr 'a-z' 'A-Z'`
                    local name="PORTS_${prefix}"
                    ports=${!name}
                    query=redis-server
                    ;;
                mysql|mysql_erlang|mysql_php)
                    ports=${PORTS_MYSQL}
                    query=mysqld
                    ;;
                mongo|mongo_erlang|mongo_java)
                    ports=${PORTS_MONGODB}
                    query=mongod
                    ;;
                *)
                    continue
                    ;;
            esac
            check_role_port_status "${ports}" ${query}
        done
    done

    [ -f ${FILE_DIR}/tmp.log ] && rm -f ${FILE_DIR}/tmp.log
}

hold_ports(){
    # the role that the server will be
    local roles=$1
    # server listening
    local sl_ports=$2
    # ports need to be check
    local check_port=""

    for r in ${roles};
    do
        case ${r} in
            erlang|php|java|redis_erlang|redis_php|redis_java)
                local prefix=`echo ${r} | tr 'a-z' 'A-Z'`
                local ports="PORTS_${prefix}"
                check_port="${check_port} ${!ports}"
                ;;
            mysql|mysql_erlang|mysql_php)
                check_port="${check_port} ${PORTS_MYSQL}"
                ;;
            mongo|mongo_erlang|mongo_java)
                check_port="${check_port} ${PORTS_MONGODB}"
                ;;
            *)
                ;;
        esac
    done

    local hold_ports=""
    for p in ${check_port};
    do
        if [ ! -z "`echo ${sl_ports}|grep ${p}`" ]; then
            hold_ports="${hold_ports}\n${p}"
        fi
    done

    echo -e ${hold_ports}|sort -n|tr "\n" " "
}

setup_server(){
    local host=$1
    scp ${FILE_DIR}/${TMP_SERVER} root@${host}:/root/

    # still run
    ssh -p ${DEFAULT_PORT} -oStrictHostKeyChecking=no ${DEFAULT_USER}@${host} "\
    python /root/${TMP_SERVER} -s -p ${TEMP_PORT} > /dev/null 2>&1 &
    "
}

stop_server(){
    echo "Are you sure to stop dummy server? default is N"
    read -p "Enter [Y/N]: " Enter
    case $Enter in
        Y | y)
            for ip in `cat ${ROLE_IP_CONF} |awk '{print $2}'|sort|uniq`;
            do
                echo "send exit signal to ( ${ip}:${TEMP_PORT} ) "
                ssh -t -p ${DEFAULT_PORT} -oStrictHostKeyChecking=no ${DEFAULT_USER}@${ip} "\
                python /root/${TMP_SERVER} -e -p ${TEMP_PORT}
                "
            done
            ;;
        *)
            ;;
     esac
}

# ping server
loop_ping(){
    local ips=`cat ${ROLE_IP_CONF} |awk '{print $2}'|sort|uniq`
    for from in ${ips};
    do
        echo "----------------- (${from}) ---> (Others) -----------------" >> ${PORT_CHECK_RET}
        for to in ${ips};
        do
            ssh -p ${DEFAULT_PORT} -oStrictHostKeyChecking=no ${DEFAULT_USER}@${from} "\
            python /root/${TMP_SERVER} -h ${to} -p ${TEMP_PORT}
            "
            [ $? -eq 0 ] && echo "${to}: pong" >> ${PORT_CHECK_RET} \
            || echo "${to}: pang" >> ${PORT_CHECK_RET}
        done
    done
}

format_str(){
    local ports=$1
    local line="    "
    local i=0
    for p in ${ports};
    do
        line="${line} ${p}"
        let i++
        [ $i -eq 10 ] && echo "${line}" >> ${PORT_CHECK_RET} && i=0 && line="    "
    done
    echo "${line}" >> ${PORT_CHECK_RET}
}

get_sys_info(){
    local ip=$1
    ssh -t -p ${DEFAULT_PORT} -oStrictHostKeyChecking=no ${DEFAULT_USER}@${ip} "\
        cpuinfo=\`cat /proc/cpuinfo |grep processor|wc -l\`; \
        meminfo=\`cat /proc/meminfo |grep MemTotal\`; \
        fsinfo=\`df -lh\`; \

        nslookup localhost -timeout=2 > /dev/null;
        dnsinfo=\`[ \$? -eq 0 ] && echo OK ||echo Failed\`; \
        ping www.baidu.com -c 1  > /dev/null; \
        outnet=\`[ \$? -eq 0 ] && echo OK ||echo Failed\`; \

        echo -e \"----------------- System Info ------------------------------------\n\
CPU: \${cpuinfo}\n\${meminfo}\n\n\${fsinfo}\n\n\
[Note]: please make sure the main disk is mounted on /data\n\n\
----------------- Network Info -----------------------------------\n\
DNS: \${dnsinfo}\nExternal-Network: \${outnet}\""
}

start(){
    for ip in `cat ${ROLE_IP_CONF} |awk '{print $2}'|sort|uniq`;
    do
        local roles=`grep ${ip} ${ROLE_IP_CONF}|awk '{print $1}'|tr "\n" " "`

        set_np_authorized ${ip}

        echo "================= Server (${ip}) ==========================" >> ${PORT_CHECK_RET}
        echo "Roles: ${roles}" >> ${PORT_CHECK_RET}
        get_sys_info ${ip} >> ${PORT_CHECK_RET}

        echo "----------------- Ports status -----------------------------------" >> ${PORT_CHECK_RET}
        local ports="$(get_ports ${ip})"
        local hold_rets=`hold_ports "${roles}" "${ports}"`

        echo "Ports Listening:" >> ${PORT_CHECK_RET}
        format_str "${ports}"
        echo -e "\nHeld up ports:" >> ${PORT_CHECK_RET}
        format_str "${hold_rets}"
        [ -z "`echo ${hold_rets}`" ] && echo -e "\nResult: OK" >> ${PORT_CHECK_RET} ||echo -e "\nResult: Failed" >> ${PORT_CHECK_RET}

        echo "----------------- Set up Server (${ip}:${TEMP_PORT}) ----------------"
        [ -z "`echo ${hold_rets}|grep ${TEMP_PORT}`" ] \
        || echo "${TEMP_PORT} is already listening, setting up temp server will be failed"

        # still upload port_tool.py to server, which used to ping other servers
        setup_server ${ip}
    done
    echo -e "\n================= Connectivity of Servers ===========================" >> ${PORT_CHECK_RET}
    # check the connectivity of servers before deploying QT services
    loop_ping
    # stop dummy server
    stop_server

    cat ${PORT_CHECK_RET}
}

[ $# -gt 0 ] || help $*

start_arg=$1

while [ $# -gt 0 ]; do
    case $1 in
        start)
            start
            shift
            ;;
        stop)
            stop_server
            shift
            ;;
        ping)
            loop_ping
            shift
            ;;
        qt_ports)
            after_deploy_check
            shift
            ;;
        *)
            echo "--------------- Usage ----------------"
            echo "portscan.sh [start|stop|ping|qt_ports]"
            exit 0
            ;;
    esac
done
exit 0