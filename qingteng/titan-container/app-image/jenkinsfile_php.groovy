import groovy.json.JsonSlurper

@NonCPS
String getVersionJson() {
    if (env.VERSION_JSON){
        return "${env.VERSION_JSON}" 
    } else {
        return readFile("${rootDir}/app-image/version.json")
    }
}

@NonCPS
String getBranch(String buildVariant, String artifact) {
    
    def jsonSlurper = new JsonSlurper()
    def versionJsonMap = jsonSlurper.parseText(env.VERSION_JSON)

    return versionJsonMap[buildVariant][artifact]
}

String getTag(){
    return (params.TAG) ? "${params.TAG}": "${params.version}-${params.company}-${BUILD_TIMESTAMP}"
}

pipeline {
    agent {label 'container'}
    environment {
        REGISTRYHOST = "registry.qingteng.cn/titan-container"
        BUILD_DIR = "${rootDir}/build"
        DOCKER_SERVER = "172.16.17.193"
        DOCKER_PATH = "/data/build/container/docker-${BUILD_NUMBER}-php"
        AGENT_PATH = "/data/build/container/docker-${BUILD_NUMBER}-agent"
        DOCKER_URL = "root@${DOCKER_SERVER}:${DOCKER_PATH}"
        AGENT_URL = "root@${DOCKER_SERVER}:${AGENT_PATH}"
        TAG = getTag()
        VERSION_JSON = getVersionJson()
    }
    stages {
        stage('Prepare to build') {
            steps {
                script {
                    echo "$params"
                    sh """ mkdir -p ${DOCKER_PATH}/php && mkdir -p ${AGENT_PATH}"""
                    sh """ cp -arf ${rootDir}/app-image/rsync_agent*.sh ./"""
                    sh """ cp -arf ${rootDir}/app-image/rsync_bash.sh ./"""
                    sh """ cp -arf ${rootDir}/app-image/rsync_pre_virus.sh ./"""
                    stash(name: "rsync_agent", includes: "rsync*.sh")
                }
            }
        }

        stage('Prepare php and frontend and agent files') {
            //when { expression { return false } }
            failFast true
            parallel {
                stage('PHP Build') {
                    //when { expression { return false } }
                    agent {label 'jenkins-slave-php'}
                    environment {
                        // for php
                        PHP_ARTFACTS_URL = "${DOCKER_URL}"
                    }
                    stages {
                        stage('Prepare') {
                            steps {
                                echo "Parameters are $params"

                                echo "Cleanup previous build output directory"
                                sh "rm -rf ${WORKSPACE}/deploy/*"
                            }
                        }
                        stage('Checkout') {
                            steps {

                                script {
                                    String branch = getBranch(params.buildVariant, "php")
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
                                    cd ${WORKSPACE}/titan-web-builder
                                    composer update --no-dev
                                    php script/build_pack-code_new.php -p ${params.company} -v v${params.version} -s no
                                """
                            }
                        }
                        stage('Upload') {
                            steps {
                                script {
                                    String packageFile = sh(script:"ls ${WORKSPACE}/deploy/${company}/*.zip", returnStdout:true).trim()
                                    echo "Found package file ${packageFile}" 

                                    echo "Uploading ${packageFile} to ${PHP_ARTFACTS_URL}"
                                    sh "scp ${packageFile} ${PHP_ARTFACTS_URL}"

                                    echo "Record revision and upload"
                                    sh "cd titan-web && git rev-parse --short HEAD > ${WORKSPACE}/deploy/php-revision"
                                    sh "scp ${WORKSPACE}/deploy/php-revision ${PHP_ARTFACTS_URL}"
                                }
                            }
                        }
                    }
                }

                stage('Frontend Build') {
                    stages {
                        stage('Prepare') {
                            steps {
                                echo "Parameters are $params"
                                echo "${WORKSPACE}"
                            }
                        }
                        // 直接复用普通部署的前端打包任务，少维护点东西。。。
                        // 复用前端打包任务后，实际上容器化部署里不需要再维护前端打包分支？？，暂时保留吧，万一后面再变呢
                        stage('Frontend Build') {
                            steps{
                                build job: 'frontend-standalone', parameters: [
                                    string(name: 'version', value: params.version),
                                    string(name: 'company', value: params.company),
                                    string(name: 'titanAllStandalone', value: getBranch(params.buildVariant, "titanAllStandalone")),
                                    string(name: 'jobTag', value: "container-${BUILD_NUMBER}"),
                                    string(name: 'branch', value: getBranch(params.buildVariant, "frontend")),
                                    string(name: 'frontend_Micro_branch', value: getBranch(params.buildVariant, "frontend_Micro")),
                                    string(name: 'frontend_Virus_branch', value: getBranch(params.buildVariant, "frontend_Virus_branch")),
                                    string(name: 'frontend_Event_branch', value: getBranch(params.buildVariant, "frontend_Event_branch")),
                                    string(name: 'frontend_Unix_branch', value: getBranch(params.buildVariant, "frontend_Unix_branch")),
                                    // string(name: 'branch_hive', value: getBranch(params.buildVariant, "frontend-hive"))
                                ]
                            }
                        }

                        // 复用普通部署的前端打包任务后，得到的是在 jenkins服务器的 /data/workspace/artifacts/container-${BUILD_NUMBER}/frontend 下的压缩文件
                        stage('Scp frontend zip file from jenkins-server') {
                            steps {
                                script {
                                    sh """
                                    scp jenkins@172.16.6.111:/data/workspace/artifacts/container-${BUILD_NUMBER}/frontend/frontend-* ${DOCKER_PATH}
                                    """
                                }
                            }
                        }
                    }
                }
                
                stage('Agent RPM Rsync and transter to container slave') {
                    //when { expression { return false } }
                    agent {label 'master'}
                    steps {
                        script {
                            unstash(name: "rsync_agent")

                            String agent_pkg_vsn = (linux_agent_version =~ /.*v((\d\.*)+)/)[0][1]
                            String shell_audit_path = getBranch(params.buildVariant, "shell_audit_tag")
                            String dns_access_path = getBranch(params.buildVariant, "dns_access_tag")
                            String cmdaudit_path = getBranch(params.buildVariant, "cmdaudit_tag")
                            String psaudit_path = getBranch(params.buildVariant, "psaudit_tag")
                            String sysmon_path = getBranch(params.buildVariant, "sysmon_tag")

                            sh "mkdir -p ${BUILD_DIR} && rm -rf ${BUILD_DIR}/*"
                            dir ("${BUILD_DIR}") {
                                script {
                                    // 下面的代码和 titan-all-standalone 中的保持完全一致， 因前面unstash， 保证脚本路径位于${WORKSPACE}下
                                    sh "${WORKSPACE}/rsync_bash.sh ${params.buildVariant} ${shell_audit_path} ${dns_access_path} ${cmdaudit_path} ${psaudit_path} ${sysmon_path}"
                                    sh "chmod +x ${WORKSPACE}/rsync_pre_virus.sh && bash ${WORKSPACE}/rsync_pre_virus.sh ${params.company} ${params.version}"
                                    if (params.buildVariant == "test") {
                                        if (aix_agent_vsn?.trim() && solaris_x86_agent_vsn?.trim() && solaris_sparc_agent_vsn?.trim() && arm_aarch64_agent_vsn?.trim()) {
                                            sh "${WORKSPACE}/rsync_agent_test.sh v3 ${linux_agent_version} ${windows_agent_version} ${aix_agent_vsn} ${solaris_x86_agent_vsn} ${solaris_sparc_agent_vsn} aarch64/${arm_aarch64_agent_vsn}"
                                        } else if (aix_agent_vsn?.trim() && solaris_x86_agent_vsn?.trim() && solaris_sparc_agent_vsn?.trim()) {
                                            sh "${WORKSPACE}/rsync_agent_test.sh v3 ${linux_agent_version} ${windows_agent_version} ${aix_agent_vsn} ${solaris_x86_agent_vsn} ${solaris_sparc_agent_vsn}"
                                        } else if (arm_aarch64_agent_vsn?.trim()) {
                                            sh "${WORKSPACE}/rsync_agent_test.sh v3 ${linux_agent_version} ${windows_agent_version} aarch64/${arm_aarch64_agent_vsn}"
                                        } else {
                                            sh "${WORKSPACE}/rsync_agent_test.sh v3 ${linux_agent_version} ${windows_agent_version}"
                                        }

                                    } else {
                                        if (aix_agent_vsn?.trim() && solaris_x86_agent_vsn?.trim() && solaris_sparc_agent_vsn?.trim()&& arm_aarch64_agent_vsn?.trim()) {
                                            sh "${WORKSPACE}/rsync_agent.sh v3 ${linux_agent_version} ${windows_agent_version} ${aix_agent_vsn} ${solaris_x86_agent_vsn} ${solaris_sparc_agent_vsn} aarch64/${arm_aarch64_agent_vsn}"
                                        } else if (aix_agent_vsn?.trim() && solaris_x86_agent_vsn?.trim() && solaris_sparc_agent_vsn?.trim()) {
                                            sh "${WORKSPACE}/rsync_agent.sh v3 ${linux_agent_version} ${windows_agent_version} ${aix_agent_vsn} ${solaris_x86_agent_vsn} ${solaris_sparc_agent_vsn}"
                                        } else if (arm_aarch64_agent_vsn?.trim()) {
                                            sh "${WORKSPACE}/rsync_agent.sh v3 ${linux_agent_version} ${windows_agent_version} aarch64/${arm_aarch64_agent_vsn}"
                                        } else {
                                            sh "${WORKSPACE}/rsync_agent.sh v3 ${linux_agent_version} ${windows_agent_version}"
                                        }
                                    }
                                }
                            }

                            sh """
                                scp -r ${BUILD_DIR}/agent_files/www/* ${AGENT_URL}
                            """
                        }
                    }
                }
            }
        }

        stage('Get file from docker to build and push') {
            //when { expression { return false } }
            steps {
                script {
                    sh """
                    cp -r ${rootDir}/app-image/php/* ${DOCKER_PATH}/

                    cd ${DOCKER_PATH} && unzip frontend-standalone*.zip -d titan-frontend && unzip ${params.company}-v${params.version}*.zip && rm -f *.zip

                    rm -f web-ins/titan-web/vendor/composer/installed.json
                    mv web-ins/titan-web/conf web-ins/titan-web-conf && mv web-ins/titan-web/vendor web-ins/titan-web-vendor

                    cd ${DOCKER_PATH} && docker buildx build --platform ${params.platform} --push -t ${REGISTRYHOST}/titan-web-php:${env.TAG} .

                    cp -r ${rootDir}/app-image/agent/* ${AGENT_PATH}/
                    cd ${AGENT_PATH}
                    docker build -t ${REGISTRYHOST}/titan-agent:${env.TAG} .
                    docker push ${REGISTRYHOST}/titan-agent:${env.TAG}
                    docker -H 172.16.6.223 build -t ${REGISTRYHOST}/titan-agent:${env.TAG}-arm64 .
                    docker -H 172.16.6.223 push ${REGISTRYHOST}/titan-agent:${env.TAG}-arm64

                    docker pull ${REGISTRYHOST}/titan-agent:${env.TAG}
                    docker pull ${REGISTRYHOST}/titan-agent:${env.TAG}-arm64    
                    docker manifest create ${REGISTRYHOST}/titan-agent:${env.TAG} --amend ${REGISTRYHOST}/titan-agent:${env.TAG} --amend ${REGISTRYHOST}/titan-agent:${env.TAG}-arm64
                    docker manifest push ${REGISTRYHOST}/titan-agent:${env.TAG}
                    """
                }
            }
        }

    }
}
