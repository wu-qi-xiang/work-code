import groovy.json.JsonSlurper

@NonCPS
String getBranch(String buildVariant, String artifact) {
    def versionJson
    if (env.VERSION_JSON){
        versionJson = "${env.VERSION_JSON}" 
    } else {
        versionJson = new File("${rootDir}/app-image/version.json").text
    }

    def jsonSlurper = new JsonSlurper()
    def versionJsonMap = jsonSlurper.parseText(versionJson)

    return versionJsonMap[buildVariant][artifact]
}

String getTag(){
    return (params.TAG) ? "${params.TAG}": "${params.version}-${params.company}-${BUILD_TIMESTAMP}"
}

boolean isARM64(){
    def arch = sh script: 'uname -m', returnStdout: true
    return arch.contains("aarch") || arch.contains("arm")
}

pipeline {
    agent {label "${JOB_NAME}".contains("arm") ? 'container-arm' : 'container'}
    environment {
        REGISTRYHOST = "registry.qingteng.cn/titan-container"
        CREDENTIALS_ID = "56ab2764-0e9c-40ef-b4aa-c16182485a84"
        TITAN_WISTERIA_GIT_URL = "git@git.qingteng.cn:wisteria/wisteria.git"
        AGENT_BUILD_SSH_URL = "qingteng@172.16.6.187:/data/thunderfire_full"
        TAG = getTag()
        ISARM64 = isARM64()
    }
    stages {
        stage('checkout') {
            steps {
                script {
                    String branch = getBranch(params.buildVariant,"java")
                    echo "Choose branch $branch"

                    git branch: branch, credentialsId: CREDENTIALS_ID, url: TITAN_WISTERIA_GIT_URL
                }
            }
        }
        stage('Prepare to rsync_cdc.sh build') {
            steps {
                script {
                    echo "$params"
                }
            }
        }
        //取消通过rsync_cdc.sh脚本同步cdc
        // stage('Prepare to rsync_cdc.sh build') {
        //     agent {label 'master'}
        //     steps {
        //         script {
        //             echo "$params"
        //             sh """ cp ${rootDir}/app-image/rsync_cdc.sh ./"""
        //             // stash(name: "rsync_cdc", includes: "rsync_cdc.sh")
        //         }
        //     }
        // }
        stage('Build titan-java-lib') {
            steps {
                sh """ cd ${WORKSPACE} && ./build-javalib-image.sh ${env.TAG} """
            }
        }

        stage('Build each service') {
            failFast true
            parallel {
                stage('java Build') {
                    steps {
                        script {
                            for (srvName in ["wisteria","gateway","user-srv","detect-srv",
                                        "job-srv","event-srv","anti-virus-srv","upload-srv","connect-dh","connect-sh",
                                        "connect-selector","connect-agent","ms-srv"]) {
                                String image_command = "cd ${WORKSPACE}/${srvName} && gradle --parallel dockerImageBuild -PproguardEnable=true -PTAG=${env.TAG}"
                                println(image_command)

                                sh """ ${image_command} """
                            }
                        }
                    }
                }

                // stage('upload and connect Build') {
                //     steps {
                //         script {
                //             for (srvName in ["upload-srv","connect-dh","connect-sh",
                //                         "connect-selector","connect-agent","ms-srv"]) {
                //                 String image_command = "cd ${WORKSPACE}/${srvName} && gradle dockerImageBuild -PproguardEnable=true -PTAG=${env.TAG}"
                //                 println(image_command)

                //                 sh """ ${image_command} """
                //             }
                //         }
                //     }
                // }

            }
        }

        stage('Build upload-ave/cdc, sysinfo and upgradetool') {
            steps {
                dir("${WORKSPACE}/sysinfo_build"){
                    script {
                        String image_command = "cd ${WORKSPACE}/sysinfo_build && docker build -t titan-sysinfo:${env.TAG} ."
                        println(image_command)

                        sh """
                            cp ${WORKSPACE}/buildscripts/sysinfo ${WORKSPACE}/sysinfo_build/
                            if [ "\$ISARM64" == "true" ]; then 
                                cp -f ${WORKSPACE}/buildscripts/sysinfo-arm64 ${WORKSPACE}/sysinfo_build/sysinfo
                            fi
                            cat > ${WORKSPACE}/sysinfo_build/Dockerfile <<EOF
FROM registry.qingteng.cn/titan-container/ubuntu:focal-20210827
COPY ./sysinfo /sysinfo
RUN groupadd -g 2020 titan && useradd -u 2020 -g titan -d /home/titan titan && chmod +x /sysinfo && chmod u+s /sysinfo
EOF
                            ${image_command}
                        """
                    }

                }

                script {
                    sh """
                        cd ${WORKSPACE}/tools && docker build -t titan-upgradetool:${env.TAG} .

                        cd ${WORKSPACE}/upload-srv && rm -rf build_cdc && mkdir build_cdc && cp Dockerfile_cdc build_cdc/Dockerfile
                        mkdir -p build_cdc/cdc/webshell_engine
                        cd build_cdc/
                        if [ "\$ISARM64" == "true" ]; then
                            rsync -rv --delete --exclude="php_cdc.tar.gz" ${AGENT_BUILD_SSH_URL}/* cdc/webshell_engine/
                            tar -zxf cdc/webshell_engine/php_cdc_arm.tar.gz -C cdc/webshell_engine/ && rm -rf cdc/webshell_engine/php_cdc_arm.tar.gz
                        else
                            rsync -rv --delete --exclude="php_cdc_arm.tar.gz" ${AGENT_BUILD_SSH_URL}/* cdc/webshell_engine/
                            tar -zxf cdc/webshell_engine/php_cdc.tar.gz -C cdc/webshell_engine/ && rm -rf cdc/webshell_engine/php_cdc.tar.gz
                        fi
                        docker build -t titan-java-upload-srv-cdc:${env.TAG} .

                        cd ${WORKSPACE}/upload-srv && rm -rf build_ave && mkdir build_ave &&  cp -r tav_file build_ave/ && cp -r titan_ave build_ave/ && cp Dockerfile_tav_ave build_ave/Dockerfile
                        if [ "\$ISARM64" == "true" ]; then 
                            cp -f arm64/savapi_file_scan build_ave/titan_ave/savapi_file_scan
                        fi
                        cd build_ave && docker build -t titan-java-upload-srv-tav-ave:${env.TAG} .

                    """
                }
            }
        }

        stage('Push titan-java-lib to registry') {
            steps {
                // docker tag titan-java-lib:${env.TAG} ${REGISTRYHOST}/titan-java-lib:${env.TAG}
                sh """
                    docker push ${REGISTRYHOST}/titan-java-lib:${env.TAG}
                """
            }
        }

        stage('Push service to registry') {
            failFast true
            parallel {
                stage('Push java and connect image') {
                    steps {
                        script {
                            for (srvName in ["wisteria","gateway","user-srv","detect-srv",
                                        "job-srv","connect-dh","connect-sh",
                                        "connect-selector","connect-agent","event-srv","ms-srv","anti-virus-srv"]) {
                                sh """
                                    docker tag titan-java-${srvName}:${env.TAG} ${REGISTRYHOST}/titan-java-${srvName}:${env.TAG}
                                    docker push ${REGISTRYHOST}/titan-java-${srvName}:${env.TAG}
                                """
                            }
                        }
                    }
                }

                stage('push uploadsrv, sysinfo, upgradetool Image') {
                    steps {
                        script {
                            for (srvName in ["upload-srv"]) {
                                sh """
                                    docker tag titan-java-${srvName}:${env.TAG} ${REGISTRYHOST}/titan-java-${srvName}:${env.TAG}
                                    docker push ${REGISTRYHOST}/titan-java-${srvName}:${env.TAG}
                                """
                            }

                            sh """
                                docker tag titan-sysinfo:${env.TAG} ${REGISTRYHOST}/titan-sysinfo:${env.TAG}
                                docker push ${REGISTRYHOST}/titan-sysinfo:${env.TAG}
                            """

                            sh """
                                docker tag titan-upgradetool:${env.TAG} ${REGISTRYHOST}/titan-upgradetool:${env.TAG}
                                docker push ${REGISTRYHOST}/titan-upgradetool:${env.TAG}
                            """

                            sh """
                                docker tag titan-java-upload-srv-cdc:${env.TAG} ${REGISTRYHOST}/titan-java-upload-srv-cdc:${env.TAG}
                                docker push ${REGISTRYHOST}/titan-java-upload-srv-cdc:${env.TAG}
                                docker tag titan-java-upload-srv-tav-ave:${env.TAG} ${REGISTRYHOST}/titan-java-upload-srv-tav-ave:${env.TAG}
                                docker push ${REGISTRYHOST}/titan-java-upload-srv-tav-ave:${env.TAG}
                            """
                        }
                    }
                }
            }
        }
    }
}