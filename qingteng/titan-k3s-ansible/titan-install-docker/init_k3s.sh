#!/bin/bash

set -o pipefail
FILE_ROOT=`cd \`dirname $0\` && pwd`
INI_PATH="$FILE_ROOT/../titan-install-k3s/inventory/hosts.ini"
K3S_DATA_PATH="$FILE_ROOT/../titan-install-k3s"
liunx_machine=$(uname -m)


\cp $FILE_ROOT/hosts.ini $INI_PATH

install_docker(){
    if [ ! -f "/data/qt-docker" ];then
        mkdir -p /data/qt-docker
    fi
	if [ ! -f "/usr/bin/docker" ];then
        cd $FILE_ROOT/docker-package && tar zxvf docker*${liunx_machine}.tar.gz && cd docker-install && bash install.sh docker
    fi
}

update_docker(){
    systemctl stop docker
    cd $FILE_ROOT/docker-package && tar zxvf docker*${liunx_machine}.tar.gz && cd docker-install && bash uninstall.sh && bash install.sh docker
    echo "docker update done"
}

load_images(){
            cd $FILE_ROOT/docker-package && docker load -i titan-ansible-${liunx_machine}.tar
}

set_ansible_env(){
        local images_tag=$(docker images|grep titan-ansible|awk '{print $2}'|uniq|sort -V|tail -n1)
        if [ ! -f ~/.bashrc ];then
            touch ~/.bashrc
        fi
        
        if [ ! -z "$(cat ~/.bashrc |grep docker-ansible-cli)" ];then
            sed -i "/docker-ansible-cli/d" ~/.bashrc
        fi
        
        if [ ! -z "$(cat ~/.bashrc |grep docker-ansible-cmd)" ];then
            sed -i "/docker-ansible-cmd/d" ~/.bashrc
        fi
        echo "alias docker-ansible-cli=\"docker run --rm -it -v $K3S_DATA_PATH:/data  -v ~/.ssh/id_rsa:/root/.ssh/id_rsa --workdir=/data registry.qingteng.cn/titan-container/titan-ansible:$images_tag /bin/sh\" " >> ~/.bashrc
        echo "alias docker-ansible-cmd=\"docker run --rm -it -v $K3S_DATA_PATH:/data  -v ~/.ssh/id_rsa:/root/.ssh/id_rsa --workdir=/data registry.qingteng.cn/titan-container/titan-ansible:$images_tag \" " >> ~/.bashrc
        source ~/.bashrc 
}

install_k3s(){
        local images_tag=$(docker images|grep titan-ansible|awk '{print $2}'|uniq|sort -V|tail -n1)
        docker run --rm -it -v $K3S_DATA_PATH:/data  -v ~/.ssh/id_rsa:/root/.ssh/id_rsa --workdir=/data registry.qingteng.cn/titan-container/titan-ansible:$images_tag ansible-playbook -i inventory/hosts.ini site.yml
}

extend_k3s_cluster(){
        local images_tag=$(docker images|grep titan-ansible|awk '{print $2}'|uniq|sort -V|tail -n1)
        docker run --rm -it -v $K3S_DATA_PATH:/data  -v ~/.ssh/id_rsa:/root/.ssh/id_rsa --workdir=/data registry.qingteng.cn/titan-container/titan-ansible:$images_tag ansible-playbook -i inventory/hosts.ini site.yml -v -e cluster_extend=true

}
usage() {
    cat <<_EOF_
install_k3s.sh <options>
Options:
    registry           install docker and registry and load image to localhost
    all                execute all step,install docker,registry and k3s cluster 
    install_k3s        install k3s cluster
    extend_k3s_cluster extend k3s cluster 
    help               show this help
_EOF_
}

action=$1
#echo "Action is $action"
case $action in
    load_image)
        load_images | tee -a install.log
        exit 0
        ;;
    install_docker)
        install_docker | tee -a install.log
        exit 0
        ;;
    update_docker)
        update_docker | tee -a update_docker
        exit 0
        ;;
    install_k3s)
        install_k3s | tee -a install.log
        exit 0
        ;;
    set_ansible_env)
        exit 0
        ;;
    all)
        (install_docker && load_images && set_ansible_env && install_k3s)  | tee -a install.log
        #(install_docker && load_images && set_ansible_env )  | tee -a install.log
        exit 0
        ;;
    extend_k3s_cluster)
        (load_images && extend_k3s_cluster) | tee -a extend_k3s_cluster.log
        exit 0
        ;;
    help)
        usage && exit 0
        ;;
    *)
        printf "Wrong option or empty option...!" 1>&2
        usage && exit 1
        ;;
esac
