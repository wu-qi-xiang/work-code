import java.security.MessageDigest
import groovy.json.JsonOutput
import groovy.json.JsonSlurper

@NonCPS
buildOpenJDK(){
    echo "Parameters are $params"
    echo "buildOpenJDK: ${WORKSPACE}"

    def image_tag = "titan-openjdk:8u292-${DAY_STR}"

    sh """
        cd ${WORKSPACE}/base-image/openjdk
        docker buildx build --platform linux/amd64,linux/arm64 --push \
            -t ${REGISTRYHOST}/${image_tag} .
    """ 
}

@NonCPS
buildZookeeper(){
    echo "Parameters are $params"

    def image_tag = "titan-zookeeper:3.6.3-${DAY_STR}"
    def zk_filename = "apache-zookeeper-3.6.3-bin.tar.gz"

    sh """
        wget ${FILE_SERVER}/${zk_filename} && tar -zxvf ${zk_filename} \
            -C ${WORKSPACE}/base-image/zookeeper/ && rm ${zk_filename}

        cd ${WORKSPACE}/base-image/zookeeper 
        docker buildx build --platform linux/amd64,linux/arm64 --push \
            -t ${REGISTRYHOST}/${image_tag} .
    """ 
}

@NonCPS
buildKafka(){
    echo "Parameters are $params"

    def image_tag = "titan-kafka:2.3.1-${DAY_STR}"
    def kafka_filename = "kafka_2.12-2.3.1.tgz"

    sh """
        wget ${FILE_SERVER}/${kafka_filename} && tar -zxvf ${kafka_filename} \
            -C ${WORKSPACE}/base-image/kafka/ && rm ${kafka_filename}

        cd ${WORKSPACE}/base-image/kafka 
        docker buildx build --platform linux/amd64,linux/arm64 --push \
            -t ${REGISTRYHOST}/${image_tag} .
    """ 
}

@NonCPS
buildTitanGlusterfs(){
    echo "Parameters are $params"
    echo "buildTitanGlusterfs: ${WORKSPACE}"

    def image_tag = "titan-glusterfs:8.5-${DAY_STR}"

    sh """
        cd ${WORKSPACE}/base-image/glusterfs
        docker buildx build --platform linux/amd64,linux/arm64 --push \
            -t ${REGISTRYHOST}/${image_tag} .
    """ 
}

@NonCPS
buildTitanPxc(){
    echo "Parameters are $params"
    echo "buildTitanPxc: ${WORKSPACE}"

    def image_tag = "titan-pxc:5.7.31-${DAY_STR}"

    sh """
        cd ${WORKSPACE}/base-image/percona-xtradb-cluster
        docker build -t ${image_tag} .
        docker tag ${image_tag} ${REGISTRYHOST}/${image_tag}
        docker push ${REGISTRYHOST}/${image_tag}
    """ 
}

@NonCPS
buildTitanPercona(){
    echo "Parameters are $params"
    echo "buildTitanPercona: ${WORKSPACE}"

    def image_tag = "titan-percona:5.7.31-${DAY_STR}"

    sh """
        cd ${WORKSPACE}/base-image/percona
        docker build -t ${image_tag} .
        docker tag ${image_tag} ${REGISTRYHOST}/${image_tag}
        docker push ${REGISTRYHOST}/${image_tag}
    """ 
}

@NonCPS
buildTitanMongo(){
    echo "Parameters are $params"
    echo "buildTitanMongo: ${WORKSPACE}"

    def image_tag = "titan-mongo:4.4.6-${DAY_STR}"

    sh """
        cd ${WORKSPACE}/base-image/mongo
        docker buildx build --platform linux/amd64,linux/arm64 --push \
            -t ${REGISTRYHOST}/${image_tag} .
    """ 
}

@NonCPS
buildTitanMysqlrouter(){
    echo "Parameters are $params"
    echo "buildTitanMysqlrouter: ${WORKSPACE}"

    def image_tag = "titan-mysql-router:8.0.25-${DAY_STR}"

    sh """
        cd ${WORKSPACE}/base-image/mysql
        docker buildx build --platform linux/amd64,linux/arm64 --push \
            -t ${REGISTRYHOST}/${image_tag} -f Dockerfile-router .
    """ 
}

@NonCPS
buildTitanKeepalived(){
    echo "Parameters are $params"
    echo "buildTitanKeepalived: ${WORKSPACE}"

    def image_tag = "titan-keepalived:v2.2.1-${DAY_STR}"

    sh """
        cd ${WORKSPACE}/base-image/keepalived
        docker buildx build --platform linux/amd64,linux/arm64 --push \
            -t ${REGISTRYHOST}/${image_tag} .
    """ 
}

@NonCPS
buildTitanPhp(){
    echo "Parameters are $params"
    echo "buildTitanPhp: ${WORKSPACE}"

    def image_tag = "titan-php:7.4.30-${DAY_STR}"

    sh """
        cd ${WORKSPACE}/base-image/php
        docker buildx build --platform linux/amd64,linux/arm64 --push \
            -t ${REGISTRYHOST}/${image_tag} .
    """ 
}

@NonCPS
buildAnsible(){
    echo "Parameters are $params"
    echo "buildAnsible: ${WORKSPACE}"

    def image_tag = "titan-ansible:2.12.1-${DAY_STR}"

    sh """
        cd ${WORKSPACE}/titan-deploy-on-k8s/
        #docker buildx build --platform linux/amd64,linux/arm64 --push \
        #    -t ${REGISTRYHOST}/ansible-builder:3.13 -f Dockerfile-builder .
        docker buildx build --platform linux/amd64,linux/arm64 --push \
            -t ${REGISTRYHOST}/${image_tag} -f Dockerfile-ansible .
    """ 
}

@NonCPS
buildTitanFluentbit(){
    echo "Parameters are $params"
    echo "buildTitanFluentbit: ${WORKSPACE}"

    def image_tag = "titan-fluent-bit:v1.8.5-${DAY_STR}"

    sh """
        cd ${WORKSPACE}/base-image/fluent-bit
        docker pull fluent/fluent-bit:1.8.5-debug 
        docker tag fluent/fluent-bit:1.8.5-debug ${REGISTRYHOST}/fluentbit-base:1.8.5-amd64
        docker push ${REGISTRYHOST}/fluentbit-base:1.8.5-amd64
        docker build -t ${REGISTRYHOST}/fluentbit-base:1.8.5-arm64 -f Dockerfile.arm64v8 .
        docker push ${REGISTRYHOST}/fluentbit-base:1.8.5-arm64

        docker manifest create ${REGISTRYHOST}/fluentbit-base:1.8.5 \
            --amend ${REGISTRYHOST}/fluentbit-base:1.8.5-amd64 \
            --amend ${REGISTRYHOST}/fluentbit-base:1.8.5-arm64
        docker manifest push ${REGISTRYHOST}/fluentbit-base:1.8.5


        docker buildx build --platform linux/amd64,linux/arm64 --push \
            -t ${REGISTRYHOST}/${image_tag} .
    """ 
}

@NonCPS
buildTitanBackup(){
    echo "Parameters are $params"
    echo "buildDbbackup: ${WORKSPACE}"

    def image_tag = "titan-backup:3.4.1.28-${DAY_STR}"

    sh """
        cd ${WORKSPACE}/app-image/dbbackup
        docker buildx build --platform linux/amd64,linux/arm64 --push \
            -t ${REGISTRYHOST}/${image_tag} .
    """ 
}

pipeline {
    agent {label 'container'}
    environment {
        REGISTRYHOST = "registry.qingteng.cn/titan-container"
        FILE_SERVER = "https://jenkins.qingteng.cn/titan-container/base-package"
        CREDENTIALS_ID = "56ab2764-0e9c-40ef-b4aa-c16182485a84"
        TITAN_CONTAINER_GIT_URL = "git@git.qingteng.cn:build/titan-container.git"
        DAY_STR = "${BUILD_TIMESTAMP}".substring(0,8)
    }
    stages {
        stage('Checkout') {
            steps {
                script {
                    currentBuild.displayName = "${BUILD_NUMBER}-${params.version}-${params.company}-${params.component}"
                    String versionBranch = "${params.version}-${params.company}"
                    git branch: versionBranch, credentialsId: CREDENTIALS_ID, url: TITAN_CONTAINER_GIT_URL
                }
            }
        }

        stage('Build') {
            steps {
                script {
                    String component = "${params.component}"

                    switch (component) {
                        case "openjdk":
                            buildOpenJDK();
                            break;
                        case "zookeeper":
                            buildZookeeper();
                            break;
                        case "kafka":
                            buildKafka();
                            break;
                        case "glusterfs":
                            buildTitanGlusterfs();
                            break;
                        case "keepalived":
                            buildTitanKeepalived();
                            break;
                        case "mongo":
                            buildTitanMongo();
                            break;
                        case "mysql-router":
                            buildTitanMysqlrouter();
                            break;
                        case "pxc":
                            buildTitanPxc();
                            break;
                        case "percona":
                            buildTitanPercona();
                            break;
                        case "php":
                            buildTitanPhp();
                            break;
                        case "ansible":
                            buildAnsible();
                            break;
                        case "titan-backup":
                            buildTitanBackup();
                            break;
                        case "fluent-bit":
                            buildTitanFluentbit();
                            break;
                    }
                }
                
            }
        }

    }
}