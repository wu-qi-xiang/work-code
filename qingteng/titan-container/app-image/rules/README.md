# 容器化预置规则包镜像打包步骤

# 2021-10-12最新改动， 由于 Mysql Group Replication使用过程中发现2个问题 1、大事物下集群卡死 2、k3s下宕机coredns所在的机器将崩溃无法恢复。  决定改用 MariaDB Galera Cluster  
最新的普通部署打包出来的预制规则包已经直接包含了qt_titan_connect，MariaDB Galera Cluster 可以直接用。修改Dockerfile里的文件名为普通部署打出来的预制规则包名即可。


普通部署打出来的预制规则包不包含qt_titan_connect, 而且是5.7的

## 初始化步骤
```bash
rm -rf /data/titan-container/rules/mysql /data/titan-logs/rules/
mkdir -p /data/titan-container/rules/mysql && chown -R 999:999 /data/titan-container/rules/mysql
mkdir -p /data/titan-logs/rules/ && chown -R 999:999  /data/titan-logs/rules/
```

## 下载最新的普通的预制规则包并解压  
```bash
tar zxvf qingteng-rules-common-3.4.0.2-20210322.tar.gz -C /data/titan-container/rules/  && chown -R 999:999 /data/titan-container/rules/mysql

docker run -d --name=mysql-rules -v $(pwd)/my.cnf:/etc/my.cnf -v $(pwd)/init.sql:/tmp/init.sql -v /data/titan-container/rules/mysql:/var/lib/mysql -v /data/titan-logs/rules/:/data/titan-logs/mysql registry.qingteng.cn/titan-container/mariadb:10.5.12-focal

# 查看日志等待启动并升级完成，等待出现 ready for connections
tail -f /data/titan-logs/rules/error.log  
```

## 执行 titan-web 对应分支的 qt_titan_connect.sql 生成最新的完整预制规则库
```bash
docker exec -i mysql-rules mysql -uroot -p9pbsoq6hoNhhTzl < /data/code/titan-web/db/titan-connect.sql
```

## 停止mysql容器， 删除部分文件，打包成预制规则 root用户执行  
  
```bash
docker container stop mysql-rules && docker container rm mysql-rules
cd /data/titan-container/rules/mysql && rm -rf auto.cnf ca-key.pem  ca.pem  client-cert.pem  client-key.pem  private_key.pem  public_key.pem  server-cert.pem  server-key.pem mysql-bin.*
cd /data/titan-container/rules/ && tar czvf titan-rules-3.4.0.2-20210322.tar.gz mysql
```

# 打镜像
docker buildx build --platform linux/amd64,linux/arm64 --push -t registry.qingteng.cn/titan-container/titan-rules:3.4.0.2-20210322 .


打成的titan-rules-3.4.0.2-20210322.tar.gz的文件结构需要如下所示
/ # tar -tvf mysql.tar.gz 
-rw-r--r-- yongliang/yongliang     25650 2020-08-05 09:54:58 mysql/agent_monitor_db/agent_monitor.frm
-rw-r--r-- yongliang/yongliang    147456 2020-08-05 09:54:58 mysql/agent_monitor_db/agent_monitor.ibd
-rw-r--r-- yongliang/yongliang        61 2020-08-05 09:54:58 mysql/agent_monitor_db/db.opt
-rw-r--r-- yongliang/yongliang        61 2020-08-05 09:54:58 mysql/base/db.opt
-rw-r--r-- yongliang/yongliang        61 2020-08-05 09:54:58 mysql/core/db.opt
-rw-r--r-- yongliang/yongliang    114688 2020-08-05 09:55:52 mysql/qt_titan/t_update.ibd
-rw-r--r-- yongliang/yongliang     13874 2020-08-05 09:55:52 mysql/qt_titan/t_update2_account.frm
-rw-r--r-- yongliang/yongliang    131072 2020-08-05 09:55:52 mysql/qt_titan/t_update2_account.ibd
-rw-r--r-- yongliang/yongliang      8926 2020-08-05 09:55:52 mysql/qt_titan/t_update2_client.frm
-rw-r--r-- yongliang/yongliang    114688 2020-08-05 09:55:52 mysql/qt_titan/t_update2_client.ibd
-rw-r--r-- yongliang/yongliang      8900 2020-08-05 09:55:52 mysql/qt_titan/t_update2_client_detail.frm
-rw-r--r-- yongliang/yongliang     98304 2020-08-05 09:55:52 mysql/qt_titan/t_update2_client_detail.ibd
-rw-r--r-- yongliang/yongliang      9027 2020-08-05 09:55:52 mysql/qt_titan/t_update2_pack.frm
-rw-r--r-- yongliang/yongliang    131072 2020-08-05 09:55:52 mysql/qt_titan/t_update2_pack.ibd