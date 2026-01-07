#!/bin/bash
# ------------------------------------------------------------------------------
# @author:  jiang.wu
# @email:   jiang.wu@qingteng.cn
#-------------------------------------------------------------------------------

CERT_PATH=/data/app/conf/cert

NGINX_CONF=${CERT_PATH}/nginx.conf.ssl

IP_TEMPLATE=/data/app/www/titan-web/config_scripts/ip.json

console_domain=''
backend_domain=''
api_domain=''
innerapi_domain=''
agent_domain=''
download_domain=''

ENABLE_SSL=$1

PORT=$2


get_value(){
    grep \"$1\" ${IP_TEMPLATE} |awk -F ":*" '{print $2}' |awk -F ",*" '{print $1}' | awk -F "\"*" '{print $2}'
}

# replace the n-th match
chg_server_name(){
    domain_name=$1
    order=$2
    sed_cmd=":a;N;\$!ba;s/server_name[^;]+/server_name ${domain_name}/${order}"
    sed -i -r "${sed_cmd}" /data/app/conf/nginx.servers.conf
}

chg_server_port(){
    port=$1
    order=$2
    sed_cmd=":a;N;\$!ba;s/listen [^;]+/listen ${port}/${order}"
    sed -i -r "${sed_cmd}" /data/app/conf/nginx.servers.conf
}

chg_server_ssl(){
    stat=$1
    order=$2
    sed_cmd=":a;N;\$!ba;s/ssl [^;]+/ssl ${stat}/${order}"
    sed -i -r "${sed_cmd}" /data/app/conf/nginx.servers.conf
}

chg_cluster_srvname(){
    domain_name=$1
    order=$2
    sed_cmd=":a;N;\$!ba;s/server_name[^;]+/server_name ${domain_name}/${order}"
    sed -i -r "${sed_cmd}" /data/app/conf/cluster/nginx.cluster.conf 
}

chg_cluster_port(){
    port=$1
    order=$2
    sed_cmd=":a;N;\$!ba;s/listen [^;]+/listen ${port}/${order}"
    sed -i -r "${sed_cmd}" /data/app/conf/cluster/nginx.cluster.conf 
}

chg_cluster_ssl(){
    stat=$1
    order=$2
    sed_cmd=":a;N;\$!ba;s/ssl [^;]+/ssl ${stat}/${order}"
    sed -i -r "${sed_cmd}" /data/app/conf/cluster/nginx.cluster.conf
}

#######################################################################

ssl_pem=`ls -t ${CERT_PATH}/*.pem|head -1`
ssl_key=`ls -t ${CERT_PATH}/*.key|head -1`

#if [ -f /etc/nginx/nginx.conf.ssl ]; then
#    NGINX_CONF=/etc/nginx/nginx.conf.ssl
#fi

cp -f ${NGINX_CONF} /etc/nginx/nginx.conf

## update cert files
if [ -n "${ssl_pem}" -a -n "${ssl_key}" ]; then
    sed -i "s:sl_certificate .*:sl_certificate  ${ssl_pem};:g" /etc/nginx/nginx.conf
    sed -i "s:sl_certificate_key.*:sl_certificate_key  ${ssl_key};:g" /etc/nginx/nginx.conf
fi

#######################################################################
if [ -f ${IP_TEMPLATE} ]; then
    console_domain=`get_value php_frontend_domain`
    backend_domain=`get_value php_backend_domain`
    api_domain=`get_value php_api_domain`
    innerapi_domain=`get_value php_inner_api_domain`
    agent_domain=`get_value php_agent_domain`
    download_domain=`get_value php_download_domain`

    # upgrade
    #cp -f ${CERT_PATH}/nginx.servers.conf /data/app/conf/nginx.servers.conf

    [ -n "${console_domain}" ] && chg_server_name ${console_domain} 1
    [ -n "${backend_domain}" ] && chg_server_name ${backend_domain} 2
    [ -n "${innerapi_domain}" ] && chg_server_name ${innerapi_domain} 4
    [ -n "${api_domain}" ] && chg_server_name ${api_domain} 3

    # nginx.cluster.conf have 3 server_name config, if add, need change here
    if [ -f "/data/app/conf/cluster/nginx.cluster.conf" ]; then
      [ -n "${backend_domain}" ] && chg_cluster_srvname ${backend_domain} 1
      [ -n "${innerapi_domain}" ] && chg_cluster_srvname ${innerapi_domain} 2
      [ -n "${api_domain}" ] && chg_cluster_srvname ${api_domain} 3
    fi

    if [ -n "${agent_domain}" ];then
        if [ -n "${download_domain}" ];then
            if [ "$agent_domain" != "$download_domain" ];then
              chg_server_name "${agent_domain} ${download_domain}" 5
            else
              chg_server_name ${agent_domain} 5
            fi
        else 
           chg_server_name ${agent_domain} 5
        fi
    else
        if [ -n "${download_domain}" ];then
          chg_server_name ${download_domain} 5
        fi
    fi

else
    echo "File ${IP_TEMPLATE} not found"
fi

if [[ ${ENABLE_SSL:=""} = "enable_console_https" ]]; then
        [ "${PORT}" != "None" ] && chg_server_port ${PORT} 1
        chg_server_ssl "on" 1
elif [[ ${ENABLE_SSL:=""} = "disable_console_https" ]]; then
        [ "${PORT}" != "None" ] && chg_server_port ${PORT} 1
        chg_server_ssl "off" 1
elif [[ ${ENABLE_SSL:=""} = "enable_backend_https" ]]; then
    if [ -f "/data/app/conf/cluster/nginx.cluster.conf" ]; then
        [ "${PORT}" != "None" ] && chg_cluster_port ${PORT} 3
        chg_cluster_ssl "on" 3
    else
        [ "${PORT}" != "None" ] && chg_server_port ${PORT} 2
        chg_server_ssl "on" 2
    fi
elif [[ ${ENABLE_SSL:=""} = "disable_backend_https" ]]; then
    if [ -f "/data/app/conf/cluster/nginx.cluster.conf" ]; then
        [ "${PORT}" != "None" ] && chg_cluster_port ${PORT} 3
        chg_cluster_ssl "off" 3
    else
        [ "${PORT}" != "None" ] && chg_server_port ${PORT} 2
        chg_server_ssl "off" 2
    fi
elif [[ ${ENABLE_SSL:=""} = "enable_api_https" ]]; then
    if [ -f "/data/app/conf/cluster/nginx.cluster.conf" ]; then
        [ "${PORT}" != "None" ] && chg_cluster_port ${PORT} 5
        chg_cluster_ssl "on" 5
    else
        [ "${PORT}" != "None" ] && chg_server_port ${PORT} 3
        chg_server_ssl "on" 3
    fi
elif [[ ${ENABLE_SSL:=""} = "disable_api_https" ]]; then
    if [ -f "/data/app/conf/cluster/nginx.cluster.conf" ]; then
        [ "${PORT}" != "None" ] && chg_cluster_port ${PORT} 5
        chg_cluster_ssl "off" 5
    else
        [ "${PORT}" != "None" ] && chg_server_port ${PORT} 3
        chg_server_ssl "off" 3
    fi
elif [[ ${ENABLE_SSL:=""} = "enable_agent_download_https" ]]; then
        [ "${PORT}" != "None" ] && chg_server_port ${PORT} 5
        chg_server_ssl "on" 5
elif [[ ${ENABLE_SSL:=""} = "disable_agent_download_https" ]]; then
        [ "${PORT}" != "None" ] && chg_server_port ${PORT} 5
        chg_server_ssl "off" 5

else
    echo "None of ENABLE_SSL"
fi
