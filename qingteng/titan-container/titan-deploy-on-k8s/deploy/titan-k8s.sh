#!/bin/bash

REGISTRY="registry.qingteng.cn/titan-container"
NAMESPACE=qtsa
# titan-deploy 改为 statefulset，以便可以常驻，同时用statefulset保证pod名字固定。之前的Pod方式挂了之后就没了。。
TITAN_DEPLOY_POD=titan-deploy-0

usage() {
    cat <<_EOF_
titan-k8s.sh <options>
Options:
  load_image           load image to localhost and push to registry      
  install              start titan-deploy to install
  install_from_docker  start titan-deploy to install in docker
  upgrade              upgrade java and php
  init_data            init data after install 
  help                 show this help
_EOF_
}

# 文档写了修改仓库地址，还是不按文档来或者修改错误，无奈，添加push镜像时尝试自动获取registry地址的功能
auto_getregistry(){
    # 如果不是默认值，则不自动获取仓库地址
    if [[ $REGISTRY != "registry.qingteng.cn/titan-container" ]]; then
        return
    fi
    # 依然是默认值的情况下，尝试自动获取仓库地址
    if [[ -f /etc/rancher/k3s/registries.yaml ]]; then
        addr=`cat /etc/rancher/k3s/registries.yaml | grep -A2 registry.qingteng.cn | tail -n 1 | tr -d ' "-'`
        if [[ $addr != "" ]]; then
            REGISTRY="${addr##*/}/titan-container"
            echo "auto get registry from k3s registries.yaml: $REGISTRY"
            return
        fi
    fi

    # 这里主要用于升级时如果使用了客户的registry，尝试自动获取配置
    pod_registry=`auto_get_registry_from_pod`
    if [[ $pod_registry != "" ]]; then
        REGISTRY="${pod_registry}"
        echo "auto get registry from old pod: $REGISTRY"
    fi
}

auto_get_registry_from_pod(){
    # 使用客户的镜像仓库升级时
    qtsapod=`kubectl get po -n ${NAMESPACE} | grep Running | head -n 1 | awk '{print $1}'`
    if [[ $qtsapod != "" ]]; then
        oldimage=`kubectl -n ${NAMESPACE} describe po ${qtsapod} | grep Image: | head -n 1 | awk '{print $2}'`
        echo ${oldimage%/*}
    fi
}

push_images(){
    images=("$*")
    for image in ${images[@]}
    do
        image_tag=${image##*/} 
        echo "$REGISTRY/$image_tag"
        docker tag $image "$REGISTRY/$image_tag"
        docker push "$REGISTRY/$image_tag"
    done
}

# 生成Patch时，为了避免之前的镜像不在这一台上，需要先 pull 老的镜像
pull_images(){
    images=("$*")
    for image in ${images[@]}
    do
        image_tag=${image##*/} 
        echo "$REGISTRY/$image_tag"
        docker pull "$REGISTRY/$image_tag"
    done
}

load_image(){

    auto_getregistry

    test -f old_baseimages && ( echo "pull old base images for patch" &&  pull_images `cat old_baseimages` )
    test -f old_appimages && ( echo "pull old app images for patch" &&  pull_images `cat old_appimages` )   

    # 检查base镜像是否存在，存在则Load，不存在则不加载
    baseimages=(`cat baseimages`)
    echo "load base image to localhost start, please wait"
    test -f titan-k8s-*base-*.tar && docker load -i titan-k8s-*base-*.tar
    echo "begin load base image to registry, please wait"
    push_images ${baseimages[@]}

    if [ -f titan-rules-*.tar ]; then
        ruleimages=(`cat ruleimages`)
        echo "load rule image to localhost start, please wait"
        test -f titan-rules-*.tar && docker load -i titan-rules-*.tar
        echo "begin load rule image to registry, please wait"
        push_images ${ruleimages[@]}
    fi

    appimages=(`cat appimages`)
    last_app_image=`cat appimages | tail -1`
    pull_result=`docker pull "$REGISTRY/${last_app_image##*/}" 2>&1 | grep 'Error response'`
    if [[ -z $pull_result ]]; then
        echo "app image already loaded to registry"
        return
    else
        echo "load app image to localhost start, please wait"
        docker load -i titan-k8s-*app-*.tar
        echo "begin load app image to registry, please wait"
        push_images  ${appimages[@]}
    fi
}

label_help(){
    lable_info=`cat titan-env.yml | grep -A6 ^label_nodes: | grep -v label_nodes: | grep -E '^ .+' | tr -d ' []"'`

    echo "lable nodes command:"
    for line in $lable_info
    do
      label=`echo "$line" | awk -F ":" '{print $1}'`
      nodes=`echo "$line" | awk -F ":" '{print $2}' | tr -s ',' ' '`
      nodeArray=("$nodes")
      for node in ${nodeArray[@]}
      do
        echo "kubectl label node $node $label=true"
      done
    done
}

# 用于修改titan-env这个configMap, 因为直接 kubectl edit cm titan-env 可能内容是没换行的，非常难改
vienv(){
    # 保存vi之前的数据
    mkdir tmp
    kubectl -n $NAMESPACE get cm titan-env -o jsonpath='{.data.titan-env\.yml}' > tmp/old-titan-env.yml
    cp tmp/old-titan-env.yml titan-env.yml
    # vi 修改 titan-env
    vi titan-env.yml
    # 保存vi之后的数据
    
    # 对比，如果没变化，则提示无变化
    diff_result=`diff -B tmp/old-titan-env.yml titan-env.yml`
    if [ "$diff_result"x != ""x ]; then
        # 创建 titan-env.yml，先删除再创建
        kubectl -n $NAMESPACE delete --ignore-not-found=true configmap titan-env && sleep 1
        kubectl -n $NAMESPACE create configmap titan-env --from-file=titan-env.yml
    else
        echo "titan-env no changes"
    fi
    rm -rf tmp
}

create_titan_deploy(){
    # 没有先删除是为了某些情况下，可能deploy-0 还在继续执行
    cp -f titan-deploy.yml titan-deploy-tmp.yml

    # 根据 titan-env  configmap 里的配置修改 titan-deploy.yml 里的 仓库地址
    # 不跟据 titan-env是为了也用于升级
    kubectl -n $NAMESPACE get cm titan-env -o jsonpath='{.data.titan-env\.yml}' > /tmp/titan-env.yml
    env_registry=`cat /tmp/titan-env.yml |grep ^registry: | awk '{print $2}'`
    sed -i -r "s#image: .*(/titan-deploy-onk8s:.*)#image: ${env_registry}\1#" titan-deploy-tmp.yml
    
    # 根据 titan-env.yml 里的配置修改titan-deploy.yml 里的 imagePullSecrets 配置
    env_user_registry_key=`cat /tmp/titan-env.yml |grep '^use_registry_key: .*true' | awk '{print $2}'`
    if [[ "$env_user_registry_key" == "true" ]]; then
        sed -i -r "/imagePullSecrets/s/#//" titan-deploy-tmp.yml
        sed -i -r "/registry-key/s/#//" titan-deploy-tmp.yml
        kubectl -n $NAMESPACE get secret registry-key || exit 1 
    fi

    kubectl apply -f titan-deploy-tmp.yml && rm -f titan-deploy-tmp.yml 
}

# check if need cluster role 
check_apply_clusterrole(){
    kubectl apply -f namespace_rbac.yml

    dfs_need=Y
    (kubectl -n $NAMESPACE get pvc titan-dfs || cat titan-env.yml | grep -E "^titan_dfs_storageclass: .+") && dfs_need=N
    localpv_need=Y
    (cat titan-env.yml | grep -E "^storageName: .+") && localpv_need=N
    if [[ $dfs_need == "N" && $localpv_need == "N" ]]; then
        echo "no need use cluster role"
    else
        kubectl apply -f rbac_cluster.yml
    fi

    (cat titan-env.yml | grep "not_label_nodes: Y" && echo "node rbac not need" ) || kubectl apply -f rbac_nodes.yml
}

install_from_docker(){
    # create namespace and role rolebinding
    kubectl apply -f namespace_rbac.yml
    check_apply_clusterrole

    # 创建 titan-env.yml，先删除再创建
    kubectl -n $NAMESPACE delete --ignore-not-found=true configmap titan-env && sleep 1
    kubectl -n $NAMESPACE create configmap titan-env --from-file=titan-env.yml

    mkdir -p $HOME/logs
    test -f $HOME/.kube/config || (mkdir -p $HOME/.kube && cp -f /etc/rancher/k3s/k3s.yaml $HOME/.kube/config)
    
    create_titan_deploy

    deploy_image=`grep titan-deploy-onk8s appimages`
    docker run -ti --rm --net=host --name="titan-deploy" -v $HOME/.kube:/root/.kube -v $HOME/logs:/logs $deploy_image titan_install
}

install_from_k8s(){
    # create namespace and role rolebinding
    kubectl apply -f namespace_rbac.yml
    check_apply_clusterrole
    
    # 创建 titan-env.yml，先删除再创建
    kubectl -n $NAMESPACE delete --ignore-not-found=true configmap titan-env && sleep 1
    kubectl -n $NAMESPACE create configmap titan-env --from-file=titan-env.yml

    create_titan_deploy
}


upgrade(){
    # create namespace and role rolebinding, maybe need new permission??
    kubectl apply -f namespace_rbac.yml

    #升级前先删除老的 titan-deploy
    kubectl -n $NAMESPACE delete --ignore-not-found=true StatefulSet titan-deploy && sleep 3 
    
    #获取旧的titan_env
    kubectl -n $NAMESPACE get cm titan-env  -o jsonpath='{.data.titan-env\.yml}' > /tmp/titan-env-old.yml
    if [ $? != 0 ];then
        echo "Failed to export configMap titan-env. Please check"
        exit 1
    fi
    #拷贝新的titan_env
    cp -f titan-env.yml /tmp/titan-env-new.yml
    #merge
    chmod +x yq 
    ./yq ea '. as $item ireduce ({}; . * $item )' /tmp/titan-env-new.yml /tmp/titan-env-old.yml > ./titan-env.yml
    kubectl -n $NAMESPACE create configmap titan-env-$(date +%Y%m%d%H%M%S) --from-file=/tmp/titan-env-old.yml
    kubectl -n $NAMESPACE delete --ignore-not-found=true configmap titan-env && sleep 1
    kubectl -n $NAMESPACE create configmap titan-env --from-file=titan-env.yml
    rm -rf /tmp/titan-env-*.yml
    
    #升级前检查是否存在titan-system-status.不存在就创建。
    kubectl -n $NAMESPACE get ConfigMap "titan-system-status" >/dev/null 2>&1 
    if [ $? != 0 ];then
        echo "titan-system-status cm not found,Upgrade Create "
        kubectl apply -f titan-system-status.yml 
    fi

    # 会自动触发upgrade,不再需要手工执行
    create_titan_deploy
}

init_data(){
    echo "copy license zip file to pod"
    license_zipfile=`ls -t *-license*.zip | head -1`
    [ -z "${license_zipfile}" ] && exit 1
    kubectl -n $NAMESPACE cp ${license_zipfile} $TITAN_DEPLOY_POD:/data/ 
    
    echo "copy rule zip file to pod"
    rule_zipfile=`ls -t *-rule-*.zip | head -1`
    [ -z "${rule_zipfile}" ] && exit 1
    kubectl -n $NAMESPACE cp ${rule_zipfile} $TITAN_DEPLOY_POD:/data/

    kubectl exec -ti $TITAN_DEPLOY_POD -n $NAMESPACE -- init_data
}

uninstall(){
    echo "begin uninstall"
    kubectl -n $NAMESPACE --ignore-not-found=true delete statefulset titan-deploy
    kubectl -n $NAMESPACE --ignore-not-found=true --cascade='foreground' delete deploy titan-anti-virus-srv titan-wisteria titan-detect-srv titan-scan-srv titan-upload-srv titan-ms-srv titan-backup
    kubectl -n $NAMESPACE --ignore-not-found=true delete daemonset titan-web
    kubectl -n $NAMESPACE get po | grep -E 'titan-(upload-srv|wisteria|scan-srv|ms-srv|detect-srv|web|backup)' | awk '{print $1}' | xargs kubectl -n $NAMESPACE delete po

    kubectl delete ns $NAMESPACE
    
    kubectl get pv | grep ^$NAMESPACE"-pvc" | awk '{print $1}' | xargs kubectl delete pv
    kubectl delete pv titan-dfs
    echo "end uninstall"
}

action=$1
#echo "Action is $action"
case $action in
    init_data)
        init_data
        exit 0
        ;;
    install)
        install_from_k8s
        exit 0
        ;;
    install_from_docker)
        install_from_docker
        exit 0
        ;;
    upgrade)
        upgrade
        exit 0
        ;;
    load_image)
        load_image
        exit 0
        ;;
    vienv)
        vienv
        exit 0
        ;;
    uninstall)
        uninstall
        exit 0
        ;;
    help)
        usage
        exit 0
        ;;
    label_help)
        label_help
        exit 0
        ;;
    *)
        echo "Wrong option or empty option..." 1>&2
        usage
        ;;
esac
