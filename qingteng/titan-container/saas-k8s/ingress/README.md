# ingress

## k8s选择
>=1.18 使用1.22ingress-deployment.yml
<1.18 使用ingress-deployment.yml
## Ingress安装部署说明
ingress安装对于下载下来的ingress部署文件的改动

    namespace修改为qtsa
    image镜像修改为内部仓库地址
    
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
deployment声明增加
      nodeSelector:
        "qtsa-ingress": "true"
      hostNetwork: true
      dnsPolicy: ClusterFirstWithHostNet
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
 
    args增加
            - --watch-namespace=qtsa
            - --tcp-services-configmap=$(POD_NAMESPACE)/tcp-services



## SAAS线上Ingress暴露服务说明
### 大数据
为了对接大数据，需要暴露 kafka 9092/ mongodb 27017/ gateway 6000/ wisteria 6100 / job-srv 6170 给大数据  
Kafka比较特殊，为了暴露给大数据，需要 配置2个listener，增加一个EXTERNAL:9093  
然后每个Kafka的Pod创建一个Service，共3个Service，再通过ingress将3个Service对外暴露出去

### PHP
Php的8002(包含download，dump)仍然在K8S外，需要暴露mysql
