# .rpms

用于构建titan-base的离线镜像仓库所使用到的文件


# repolists.txt


 记录独立部署中构建rpm离线仓库时需要下载得安装包以及依赖包
```
 yumdownloader  --destdir=/tmp/qingteng/ --resolve openssl xxxx
```

# yumimport.sh


 批量上传rpm 到 nexus
```
cd qingteng-el7
bash yumimport.sh -e el7 -u user -p 'passwd' -r https://mirror.qingteng.cn/repository/yum-standalone/

-e 指定系统版本 el6/el7

-u 指定nexus 登录用户名

-p 指定nexus 登录密码

-r 指定nexus 私有镜像仓库url
```
# el6 el7

其中包含对应运行Gitlab-runner编译环境的centos7 centos6镜像

最好还是使用时间戳来控制版本。

构建命令如下

``` shell
cd el6

docker build -t registry.qingteng.cn/k8s/x86/gitlab/centos6:6.10-20220830 .

cd el7

docker build -t registry.qingteng.cn/k8s/x86/gitlab/centos7:7.9-20220830 .

docker push
