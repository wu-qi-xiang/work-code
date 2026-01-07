# fluent-bit 镜像说明
arm64v8的官方的镜像是有问题的，报： <jemalloc>: Unsupported system page size  
在ARM64机器上安装 yum方式安装也报这个，经查是因为 使用了 jemalloc， 在pagesize=64KB的机器上会有这问题。  
因此 ARM64的镜像自己打。并和官方的 x86_64 架构下的镜像组合为 fluentbit-base:1.8.5, 然后在此基础上统一加上自己编写的out.go插件  

Dockerfile.arm64v8 相比官方所做的修改:  
1、src使用curl下载  
2、debian使用国内源  
3、最后的COPY直接从下载的src里copy，本地不需要存在src源代码


# go plugin: outfile_day

https://docs.fluentbit.io/manual/development/golang-output-plugins  
https://github.com/fluent/fluent-bit-go  

outfile_day 插件的功能是根据当前时间将上报的日志记录写入到按天确定的目录中
另外会有后台任务，定期检查，如果一个日志文件大于 200M，将会轮换新的  

