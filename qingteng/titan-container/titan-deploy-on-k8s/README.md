# 服务端容器化相关安装部署代码和脚本

## ansible打包流程
参考 https://github.com/cytopia/docker-ansible/blob/master/Dockerfiles/Dockerfile


多架构构建是：  
```bash
docker buildx build --platform linux/amd64,linux/arm64 --push -t ${REGISTRYHOST}/ansible-builder:3.13 -f Dockerfile-builder .
docker buildx build --platform linux/amd64,linux/arm64 --push -t ${REGISTRYHOST}/${image_tag} -f Dockerfile-ansible .
```

然后使用上面打出来的titan-ansible来继续构建titan-deploy-onk8s  
```bash
docker buildx build --platform linux/amd64,linux/arm64 --push -t registry.qingteng.cn/titan-container/titan-deploy-onk8s:develop .
```  

或者单独构建一个架构下的  
```bash
docker build -t registry.qingteng.cn/titan-container/ansible-builder:3.13 -f Dockerfile-builder .
docker build -t registry.qingteng.cn/titan-container/titan-ansible:2.12.1 -f Dockerfile-ansible .
docker build -t registry.qingteng.cn/titan-container/titan-deploy-onk8s:develop .
```

## K8S本地开发流程
1、获取到开发环境的 master节点的.kube目录，放到自己的 ～/.kube下  

2、拉取开发镜像  
```bash
docker pull registry.qingteng.cn/titan-container/titan-deploy-onk8s:3.4.0.7-common-20211110201607
```

3、可以有两种开发模式  

(1) 启动shell-operator,测试 hook相关功能  
docker run --name=deploy-on-k8s -d -v /home-path/.kube:/root/.kube -v /code-path/titan-deploy-on-k8s/:/data titan-deploy-onk8s:3.4.0.7-common-20211110201607 /usr/bin/tini -- /shell-operator start  

注意替换自己的.kube所存放的目录home-path，以及code-path代码路径  
```bash
docker run --name=deploy-on-k8s -d -v /home/yongliang/.kube:/root/.kube -v /data/code/titan-container/titan-deploy-on-k8s/:/data registry.qingteng.cn/titan-container/titan-deploy-onk8s:develop-20220305 /usr/bin/tini -- /shell-operator start
```

(2) 不启动shell-operator，手工执行ansible-playbook的模式  

docker run -ti -v /home-path/.kube:/root/.kube -v /code-path/titan-deploy-on-k8s/:/data titan-deploy-onk8s:3.4.0.7-common-20211110201607 bash  

注意替换自己的.kube所存放的目录home-path，以及code-path代码路径  
 
```bash
docker run -ti -v /home/yongliang/.kube:/root/.kube -v /data/code/titan-container/titan-deploy-on-k8s/:/data registry.qingteng.cn/titan-container/titan-deploy-onk8s:develop-20220108 bash
```

4、 需要在 deploy 目录执行下面命令创建namespace 及 titan-env  

```bash
kubectl apply -f deploy/namespace_rbac.yml  
kubectl -n qtsa create configmap titan-env --from-file=deploy/titan-env.yml --dry-run=client -o yaml | kubectl -n qtsa apply -f -
```

5、 之后可在外面修改代码并在docker容器内执行 ansible-playbook 了

    
