# 一.kafka镜像包说明
##    1、kafka压缩包
        为了不把这个工程搞得非常庞大，因此kafka的安装包放在了nas上
        start-kafka.sh 里根据传入的环境变量做了一些简单配置工作
        特别说明：当有 EXTERNAL_KAFKA_HOSTS 环境变量时，会按照 EXTERNAL_KAFKA_HOSTS的配置对外暴露服务
        用于暴露kafka给大数据等场景

##    2、jenkins打包：
        jenkins groovy文件里wget从 nas 下载安装包并解压，然后打docker镜像    