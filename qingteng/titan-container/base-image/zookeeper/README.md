参考 https://github.com/kubernetes-retired/contrib/tree/master/statefulsets
和 https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/


# zk更新
## 下载-bin包到slave下  
## 修改Dockerfile
COPY --chown=zookeeper:zookeeper ./  apache-zookeeper-3.6.3-bin /usr/local/qingteng/zookeeper/
## 修改jenkinsfile_base.groovy
def zk_filename = "apache-zookeeper-3.6.3-bin.tar.gz"  

## 四字命令
需要单独放开ruok zoo.cfg  
4lw.commands.whitelist=ruok

