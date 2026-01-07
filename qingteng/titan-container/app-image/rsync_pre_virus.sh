#!/bin/bash
##用于同步预制的杀毒引擎文件

if [[ $# -lt 2 ]]; then
    echo "Usage $0 <company> <version>"
fi

dir="/data/qt-virusengine/"
company=$1
version=$2

pre_virusengine_package=$(ls -r ${dir} | grep -w qingteng-virusengine-${company}-${version} | head -n 1)

if [ "${pre_virusengine_package}" != "" ] && [ -e "${dir}${pre_virusengine_package}" ];then
    echo "rsync package: $pre_virusengine_package"
    cp -r ${dir}${pre_virusengine_package} agent_files/www/agent-update/
    tar -xzf agent_files/www/agent-update/${pre_virusengine_package} -C agent_files/www/agent-update/
    rm -rf agent_files/www/agent-update/${pre_virusengine_package}
else
    echo "no found pre virus package"
fi
