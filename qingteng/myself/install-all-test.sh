#!/bin/bash
# date 2022-8-29
# auth wuxiang

# 获取当前执行脚本的目录
file_root=`cd \`dirname $0\` && pwd`
default_path="/usr/local/src"
default_user="root"
default_port="22"
step="0"
base_config=${file_root}/service_ip.conf
#app_config=${install_path}/titan-app/ip_template.json
install_step=(decompress_all init_config  check_env install_base install_app)
upgrade_step=(decompress_all init_config  check_env install_base upgrade_app)


# 红色字体输出
echo_red(){
    echo -e "\033[31m $* \033[0m" 
}

# 检查是否安装完成
check(){
    if [ $? -eq 0 ]; then
        echo "$*, 检查正常"
    else
        echo "$*, 检查不正常, 退出安装" && exit 0
    fi 
}

# 获取role的所有ip, 用于生成base的配置文件
get_role_all_host(){
    local role=$1
    if [ ! -f ${app_config} ]; then
        echo "没有找到app的配置文件,请检查安装路径${file_root}下面是否存在${app_config}"
        exit 1
    fi
    cat ${app_config}|grep $role|grep -oP "(\d+\.){3}\d+"|sort -u
}


# 判断规则包和授权文件, 解压安装包文件
decompress_all(){
    echo "-------------------检查规则包和授权文件------------------"
    [ ! -f *-license*.zip ] && echo "不存在授权文件, 退出安装" && exit 0 
    [ ! -f *-rule*.zip ] && echo "不存在规则文件, 退出安装" && exit 0   
    echo "----------------------开始解压整包----------------------"
    echo_red "请输入安装路径, 类似/usr/local/src, 最后不要加/."
    
    # 写入配置信息
    echo "安装步骤：decompress_all=0 init_config=1  check_env=2 install_base=3  install_app=4  第5步就是执行完成" | sudo tee -a ${file_root}/step/config.conf 

    read -p "请输入安装路径, 默认路径为${default_path}:  "  install_path
    if [ ! ${install_path} ]; then
        install_path=${default_path}
    fi
    echo "path ${install_path}" | sudo tee ${file_root}/step/config.conf 

    read -p "请输入安装用户, 默认用户为${default_user}:  "  user
    if [ ! ${user} ]; then
        user=${default_user}
    fi
    echo "user ${user}" | sudo tee -a ${file_root}/step/config.conf 

    read -p "请输入ssh端口, 默认端口为${default_port}:  "  port
    if [ ! ${port} ]; then
        port=${default_port}
    fi
    echo "port ${port}" | sudo tee -a ${file_root}/step/config.conf 

    echo "开始解压安装包，请输入解压密码"
    sudo bash patch_all.sh ${install_path} && echo "解压整包成功"

    echo "--------------------开始解压base安装包-------------------"
    cd ${install_path} && sudo tar -zxf titan-base-* && echo "base包解压完成"
    [ ! -d ${install_path}/titan-base ] && echo "base包解压失败, 退出安装, 请检查原因" && exit 0

    echo "--------------------开始解压app安装包--------------------"
    cd ${install_path} && sudo tar -zxf titan-app-* && echo "app包解压完成"
    check 解压步骤
    [ ! -d ${install_path}/titan-app ] && echo "app包解压失败, 退出安装, 请检查原因" && exit 0
}


# 生成初始配置文件
init_config(){
    local num=$1
    local ip_config=${install_path}/titan-app/ip-config.py
    echo_red "----------------开始生成配置文件-----------------"
    #修改安装用户,默认是root
    sudo sed -i  "s/DEFAULT_USER=.*/DEFAULT_USER=${user}/g" ${install_path}/titan-app/utils.sh
    sudo sed -i  "s/DEFAULT_SSH_USER = .*/DEFAULT_SSH_USER = \"${user}\"/g"  ${install_path}/titan-app/ip-config.py
    #修改ssh端口号，默认是22
    sudo sed -i  "s/ DEFAULT_SSH_PORT = .*/ DEFAULT_SSH_PORT = ${port}/g"  ${install_path}/titan-app/ip-config.py
    sudo sed -i  "s/DEFAULT_PORT=.*/DEFAULT_PORT=${port}/g" ${install_path}/titan-app/utils.sh

    # 安装unzip,解压规则包
    yum -y install  unzip
    # 复制授权和规则包到titan-app目录
    [ ! -f "${install_path}/titan-app/*zip" ] && sudo cp -af ${file_root}/*.zip  ${install_path}/titan-app
    cd ${file_root} && sudo /usr/bin/python $ip_config ${num}
    # 生成base的配置文件
    create_base_config
    sudo cp -af ${install_path}/titan-app/ip_template.json  ${file_root}
}


#生成base的配置文件
create_base_config(){
    # 存在问题的php,java,ms_srv
    base_middleware=(php_worker mysql redis_php redis_erlang redis_java zookeeper kafka rabbitmq mongo_java glusterfs java_detect-srv connect-dh ms-srv event-srv mongo_ms_srv)
    [ -f ${base_config} ] && rm -f ${base_config}
    for middleware in ${base_middleware[*]}
    do
        host=`get_role_all_host ${middleware}`
        if [[ -z ${host} || "${host}" = "127.0.0.1" ]]; then
            continue
        else
            for i in ${host}
            do
                if [[ -z ${i} || "${i}" = "127.0.0.1" ]]; then
                    continue
                elif [[ ${middleware} = "php_worker" ]]; then
                    echo "php                       ${i}" | sudo tee -a ${base_config}
                elif [[ ${middleware} = "event-srv" ]]; then
                    echo "event_srv                 ${i}" | sudo tee -a ${base_config}
                elif [[ ${middleware} = "ms-srv" ]]; then
                    echo "ms_srv                    ${i}" | sudo tee -a ${base_config}
                elif [[ ${middleware} = "connect-dh" ]]; then
                    echo "connect                   ${i}" | sudo tee -a ${base_config}
                elif [[ ${middleware} = "java_detect-srv" ]]; then
                    echo "java                      ${i}" | sudo tee -a ${base_config}
                else
                    echo "${middleware}             ${i}" | sudo tee -a ${base_config}
                fi
            done
        fi
    done
    check base配置文件
    echo_red "-------请仔细检查${base_config}文件-----------"
    [ ! -f ${base_config} ] && "不存在${base_config},请检查"
    read -p "按任意键继续，----检查不对的话, ctrl+c退出,然后再次执行安装命令。"
}


# 环境检查
check_env(){
    echo "-------------------开始环境检查------------------"
    check 环境检查步骤
}

# 安装base
install_base(){
    echo "------------------开始安装base包-----------------"
    sudo cp -f ${base_config}   ${install_path}/titan-base 
    cd ${install_path}/titan-base && sudo bash titan-base.sh all
    check base安装步骤 
}


# 安装app
install_app(){
    echo "------------------开始安装app包-----------------"
    sudo cp -f ${app_config}  ${install_path}/titan-app 
    cd ${install_path}/titan-app && sudo bash titan-app.sh install v3
    check app安装步骤
}


# 升级app
update_app(){
    echo "------------------开始升级app包-----------------"
    sudo cp -a ${file_root}/ip_template.json  ${install_path}/titan-app 
    #cd ${install_path}/titan-base && sudo bash titan-app.sh upgrade v3
    check app升级步骤
}


# 初始化用户, ssh端口, 安装路径
get_config(){
     if [ -f ${file_root}/step/config.conf ]; then
        install_path=`cat ${file_root}/step/config.conf|grep path|awk '{print $2}'`
        user=`cat ${file_root}/step/config.conf|grep user|awk '{print $2}'`
        port=`cat ${file_root}/step/config.conf|grep port|awk '{print $2}'`
        app_config=${install_path}/titan-app/ip_template.json
    fi
}


# 设置初始步骤, 获取当前步骤
init_step(){
    if [ -f ${file_root}/step/step.conf ]; then
        step=`cat ./step/step.conf`
    else 
        sudo mkdir -p ${file_root}/step
        echo ${step} | sudo tee ${file_root}/step/step.conf
    fi
}


# 更新当前步骤
update_step(){
    local now_step=$1
    [ ! -d ${file_root}/step ] && mkdir -p ${file_root}/step
    echo ${now_step} | sudo tee ${file_root}/step/step.conf
}


# 更新步骤拆分
upgrade(){
    local num=$1
    init_step

    case step in
        decompress_all)
            decompress_all
            ;;
        init_config)
            init_config $num
            ;;
        install_base)
            install_base
            ;;
        update_app)
            update_app
            ;;
    esac
}


install(){
    local num=$1
    # 安装之前先获取当前步骤
    init_step
    # 安装之前获取用户输入的配置
    get_config
    # 获取安装列表长度
    install_len=${#install_step[*]}
    if [ ${step} -lt ${install_len} ]; then
        len=`expr ${install_len} - 1`
        for i in `seq ${step} ${len}`
            do
                echo ${i}  ${install_step[${i}]} ${install_len}
                local now_step=${install_step[${i}]}
                if [ "${now_step}" = "init_config" ]; then
                    ${now_step} ${num}
                else
                    ${now_step}
                fi

                if [ $? -eq 0 ]; then
                    local new_step=`expr ${i} + 1`
                    update_step ${new_step}
                else 
                    echo "${now_step}这一步执行失败, 请检查"
                fi
            done
    else
        echo "已完成安装"
        exit 0
    fi
}


# 帮助提示
help(){
    echo "--------------------------------------------------------------------------"
    echo "                     执行必须带参数，参数提示如下                           "
    echo "--------------------------------------------------------------------------"
    echo "    install                                  #安装时使用的参数             "
    echo "    upgrade                                  #更新时使用的参数             "
    echo "--------------------------------------------------------------------------"
    echo "                              参考例子如下, 更新类似                        "
    echo "--------------------------------------------------------------------------"
    echo "    ./install-all.sh  install  --number=4    # 4台标准部署                 "
    echo "    ./install-all.sh  install  --cluster=6   # 6台高可用部署               "
} 


# 程序主方法
main(){
   if [ $# -gt 0 ];then
        case $1 in
            install)
                install $2 
                exit 0
                ;;
            upgrade)
                upgrade $2
                exit 0
                ;;
            *)
                help
                exit 0
                ;;
        esac
    else
        help
        exit 0
    fi 
}

# 执行main, 从这里开始
main $* 