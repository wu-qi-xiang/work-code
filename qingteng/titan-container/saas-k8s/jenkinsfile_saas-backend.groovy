import groovy.json.JsonSlurper

String getTag(){
    return (params.TAG) ? "${params.TAG}": "${params.version}-${BUILD_TIMESTAMP}"
}

pipeline {
    agent {label 'container'}
    environment {
        REGISTRYHOST = "registry.qingteng.cn/titan-container"
        BUILD_DIR = "${rootDir}/build"
        TAG = getTag()
    }
    stages {

        stage('SAAS 81 Build') {
            //when { expression { return false } }
            agent {label 'jenkins-slave-php'}
            // environment {
            //     // for saas build
            // }
            stages {
                stage('Checkout') {
                    steps {
                        script {
                            String branch = "master"
                            echo "Choose branch $branch"
                            dir("titan-web") {
                                git branch: "${branch}", url: 'ssh://jitang.hu@gerrit.qingteng.cn:29418/titan-web'
                            }
                            dir("titan-web-builder") {
                                git branch: "master", url: 'ssh://jitang.hu@gerrit.qingteng.cn:29418/titan-web-builder'
                            }
                        }
                    }
                }
                stage('Build') {
                    steps {
                        sh """
                            cd ${WORKSPACE}/titan-web-builder && composer up
                            php script/build_release.php --version=v${params.version} --msg="jenkins build: ${BUILD_NUMBER}, version: v${params.version}"
                            cd ${WORKSPACE} && tar -czvf saas81-v${TAG}.tar.gz web/*
                        """
                    }
                }
            }
        }

        stage('download php file to build image and push') {
            //when { expression { return false } }
            steps {
                script {
                    echo "$params"
                    echo "${rootDir}"

                    sh """
                    cd ${rootDir}
                    rm -rf build/ && mkdir -p build/
                    scp -r root@172.16.6.39:/data/php/workspace/titan-container-k8s-saas81/saas81-v${TAG}.tar.gz build/

                    tar -zxvf build/saas81-v${TAG}.tar.gz -C build
                    cp -rf saas-k8s/backend/* build/
                    docker build -t saas-backend:${env.TAG} build && docker tag saas-backend:${env.TAG} ${REGISTRYHOST}/saas-backend:${env.TAG} && docker push ${REGISTRYHOST}/saas-backend:${env.TAG}
                    """
                }
            }
        }

    }
}