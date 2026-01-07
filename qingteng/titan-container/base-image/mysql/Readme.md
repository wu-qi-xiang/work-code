# mysql8.0 镜像说明

# 2021-10-12最新改动， 由于 Mysql Group Replication使用过程中发现2个问题 1、大事物下集群卡死 2、k3s下宕机coredns所在的机器将崩溃无法恢复。  决定改用 MariaDB Galera Cluster  
https://hub.docker.com/_/mariadb?tab=tags


mysql在 dockerhub上有下面几个
https://registry.hub.docker.com/r/mysql/mysql-server （oracle维护的，支持ARM64）
https://registry.hub.docker.com/_/mysql （docker官方维护的，debian为基础，不支持ARM64，因为mysql8.0 arm包没发布到debian上去）  
https://registry.hub.docker.com/r/ubuntu/mysql （ubuntu官方维护的，但是还是beta，使用很少）  

https://ubuntu.pkgs.org/20.04/ubuntu-main-arm64/mysql-client-8.0_8.0.19-0ubuntu5_arm64.deb.html  
http://repo.mysql.com/apt/ubuntu/  （mysql官方发布的ubuntu的包，只有amd64的）
ubuntu官方仓库里mysql支持arm64，是ubuntu官方维护的，而mysql官方发布的arm64的包支持 RHEL-7 & 8/Oracle-Linux-7 & 8  

但是ubuntu的这些都没有ARM64的 MysqlShell 。。。

# 如果自己打mysql镜像说明  
参考以下2个地方:  
https://registry.hub.docker.com/layers/ubuntu/mysql/8.0-20.04_beta/images/sha256-a9a6ee3370be4919d993d425b155b01316aa0169f816194de31514e2a196321d?context=explore
https://github.com/docker-library/mysql/blob/master/8.0/Dockerfile.debian  

# 最终决定  
直接使用 https://registry.hub.docker.com/r/mysql/mysql-server ， 这个镜像打得很好，支持ARM64,且自带 MysqlShell 完美支持 InnoDB Cluster 

mysql-router oracle官方也没有打ARM的，参考官方自己写的，
需要提供 $MYSQL_HOST || -z $MYSQL_PORT || -z $MYSQL_USER || -z $MYSQL_PASSWORD_FILE 