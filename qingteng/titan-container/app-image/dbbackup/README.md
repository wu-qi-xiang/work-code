#构建

```
docker build -t dbbackup:3.4.0-YYYYMMDD . && docker tag dbbackup:3.4.0-YYYYMMDD registry.qingteng.cn/titan-container/dbbackup:3.4.0-YYYYMMDD

#多架构构建
docker buildx build --platform linux/amd64,linux/arm64 --push -t registry.qingteng.cn/titan-container/titan-backup:3.4.0.2-YYYYMMDD .
```

#本地compose环境测试
```
docker run -ti -v /data/titan-backup:/data/titan-backup -v /data/code/titan-container/app-image/dbbackup/db_backup.py:/db_backup.py dbbackup:3.4.0-YYYYMMDD bash
进入容器后手工修改 /envconfig.json
```

#导出注意事项

脚本的导出有2种模式  
mode:0,备份核心数据模式，backup_config.json 是只导出配置文件里指定的表，用于只快速备份核心数据   
mode:1,完整数据迁移模式，export_config.json 导出所有表（排除 _EXCLUDE_ ）  

使用哪个配置文件可以 BACKUP_CONFIG 环境变量指定  

#导入注意事项
Mongo: python db_backup.py --mongo_restore
mongo的导入将备份文件放到 /data/titan-backup/mongo下，同时注意/data/titan-backup/mongo下不能有之前残留的done_colls文件  
因mongo的导入可能中断，所以用done_colls文件记录此次导入的进度，中断后可直接执行 python db_backup.py --mongo_restore 来继续导入

MySQL: python db_backup.py --mysql_restore

