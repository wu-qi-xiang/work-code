#!/bin/bash

## define the script directorys
channel_bin=/data/app/titan-channel/bin/channel
titan_server_bin=/data/app/titan-servers/bin/titan-server
selector_bin=/data/app/titan-selector/bin/selector


restart_php_server() {
    echo "reloading nginx conf"
    nginx -s reload
    check_result nginx reload

    echo "restarting php-fpm"
    service php-fpm restart
    check_result php-fpm restart

    echo "restarting gearmand"
    service gearmand restart
    check_result gearman restart

    echo "reloading supervisor conf"
    supervisorctl reload
    check_result supervisorctl reload
}

stop_erlang_server() {
    echo "......channel stopping......"
    ch_ip=`get_ch_ip`
    ssh root@$ch_ip "$channel_bin stop"
    check_result channel stop

    echo "......selector stopping......"
    sl_ip=`get_sl_ip`
    ssh root@$sl_ip "$selector_bin stop"
    check_result selector stop


    echo "......sh stopping......"
    sh_ip=`get_sh_ip`
    ssh root@$sh_ip "$titan_server_bin stop"
    check_result sh stop


    echo "......dh stopping......"
    dh_ip=`get_dh_ip`
    ssh root@$dh_ip "$titan_server_bin stop"
    check_result dh stop


    echo "......om stopping......"
    om_ip=`get_om_ip`
    ssh root@$om_ip "$titan_server_bin stop"
    check_result om stop

}

start_erlang_server() {
    echo "......start channel......"
    ch_ip=`get_ch_ip`
    ssh root@$ch_ip "$channel_bin hp"
    check_result channel start


    echo "......start om......"
    om_ip=`get_om_ip`
    ssh root@$om_ip "$titan_server_bin -r om_node hp"
    check_result om start


    echo "......start dh......"
    dh_ip=`get_dh_ip`
    ssh root@$dh_ip "$titan_server_bin -r dh_node hp"
    check_result dh start

    echo "......start sh......"
    sh_ip=`get_sh_ip`
    ssh root@$sh_ip "$titan_server_bin -r sh_node hp"
    check_result sh start

    echo "......start selector......"
    sl_ip=`get_sl_ip`
    ssh root@$sl_ip "$selector_bin hp"
    check_result selector start
}

restart_java_server() {
    echo "......restart java......"
    java_ip=`get_java_ip`
    if [ "$java_ip" == "" ]; then
        echo "no java server exist"
    else
        ssh root@$java_ip "/etc/init.d/wisteria restart"
        check_result java restart
    fi
}

## check_result
## example: check_resutl channel stop
##    $1: server name, titan-server | channel | selector | php...
##    $2: action, start | stop
check_result() {
    if [ $? -eq 0 ]; then
        echo "#########$1 $2 success###########"
        echo ""
    else
        echo "#########$1 $2 fail##############"
        echo ""
        exit 1
    fi
}

get_om_ip(){
    path="$SCRIPT_DIR/ip.json"
    grep "om_1" $path |  awk -F ":*" '{print $2}' | awk -F ",*" '{print $1}' | awk -F "\"*" '{print $2}'
}

get_dh_ip(){
    path="$SCRIPT_DIR/ip.json"
    grep "dh_1" $path |  awk -F ":*" '{print $2}' | awk -F ",*" '{print $1}' | awk -F "\"*" '{print $2}'
}

get_sh_ip(){
    path="$SCRIPT_DIR/ip.json"
    grep "sh_pri_1" $path |  awk -F ":*" '{print $2}' | awk -F ",*" '{print $1}' | awk -F "\"*" '{print $2}'
}

## get channel ip
get_ch_ip(){
    path="$SCRIPT_DIR/ip.json"
    grep "channel_private_ip" $path |  awk -F ":*" '{print $2}' | awk -F ",*" '{print $1}' | awk -F "\"*" '{print $2}'
}


## get selector ip
get_sl_ip(){
    path="$SCRIPT_DIR/ip.json"
    grep "selector_pri" $path |  awk -F ":*" '{print $2}' | awk -F ",*" '{print $1}' | awk -F "\"*" '{print $2}'
}


## get java server ip
get_java_ip() {
    path="$SCRIPT_DIR/ip.json"
    grep "java_ip" $path |  awk -F ":*" '{print $2}' | awk -F ",*" '{print $1}' | awk -F "\"*" '{print $2}'
}


### -----------------------start---------------------------
SCRIPT_DIR=`cd \`dirname $0\` && /bin/pwd`

echo "om_ip:" `get_om_ip`
echo "dh_ip:" `get_dh_ip`
echo "sh_ip:" `get_sh_ip`
echo "ch_ip:" `get_ch_ip`
echo "sl_ip:" `get_sl_ip`
echo "java_ip:" `get_java_ip`

restart_php_server
echo "after restart_php_server, sleep for 3 seconds"
sleep 3

stop_erlang_server
echo "after stop_erlang_server, sleep for 3 seconds"
sleep 3

start_erlang_server
echo "after start_erlang_server, sleep for 3 seconds"
sleep 3

restart_java_server

