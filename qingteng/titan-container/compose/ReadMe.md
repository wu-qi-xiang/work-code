# itan-compose-deploy 镜像说明

主要包含下面文件  
1、prepare.sh,用于常见目录并修改权限  
2、titan-dockerize， 用于容器启动时生成模板并等待依赖的服务启动完成  
3、mkcert，用于安装时随机生成证书  

### dockerize
使用的 https://github.com/powerman/dockerize/releases/tag/v0.13.1
https://github.com/jwilder/dockerize 已基本不维护，且无法从文件读取配置