//将所有打包流程串起来组成一个任务
import groovy.json.JsonSlurper

@NonCPS
String getVersionJson() {
    return readFile("${rootDir}/app-image/version.json")
}

pipeline {
    agent { label 'container' }
    environment {
        REGISTRYADDR = "registry.qingteng.cn/titan-container"
        TAG = "${params.version}-${params.company}-${BUILD_TIMESTAMP}"
        PWD_TAG = "release-${params.company}-${params.version}-${BUILD_TIMESTAMP}"
        VERSION_JSON = readFile("${rootDir}/app-image/version.json")
        PKG_ARCHIVE_PATH = "/data/qt-container/titan-container/release-nas"
    }
    stages {
        stage('Prepare to build') {
            steps {
                script {
                    echo "$params"
                    // 将titan-deploy-on-k8s 目录保存起来，分别在amd64机器和arm64机器上取出兵解压后为下面的k8s构建做准备
                    sh """
                    echo "tar gz titan-deploy-on-k8s for k8s package build"
                    cd ${rootDir} && tar czvf titan-deploy-on-k8s-${env.TAG}.tar.gz titan-deploy-on-k8s
                    """

                    sh """mv ${rootDir}/titan-deploy-on-k8s-${env.TAG}.tar.gz ./ """
                    stash(name: "titan-k8s", includes: "titan-deploy-on-k8s-${env.TAG}.tar.gz")

                    compose_download_url = ""
                    k8s_amd64_download_url = ""
                    k8s_arm64_download_url = ""

                    // 记录打包目录的绝对路径，用于打最终发布包时加密
                    k8s_amd64_build_dir = ""
                    k8s_arm64_build_dir = ""
                    password = randomPassword(8)
                    passwd_info = ""
                }
            }
        }
        stage ('Build JAVA and PHP image') {
            //when { expression { return false } }
            failFast true
            parallel {
                stage('PHP Image Build') {
                    steps{
                        echo "tag:${TAG}"
                        build job: 'titan-container-php', parameters: [
                            string(name: 'version', value: params.version),
                            string(name: 'company', value: params.company),
                            string(name: 'buildVariant', value: params.buildVariant),
                            string(name: 'scriptTag', value: params.scriptTag),
                            string(name: 'linux_agent_version', value: params.linux_agent_version),
                            string(name: 'windows_agent_version', value: params.windows_agent_version),
                            string(name: 'arm_aarch64_agent_vsn', value: params.arm_aarch64_agent_vsn),
                            string(name: 'aix_agent_vsn', value: params.aix_agent_vsn),
                            string(name: 'solaris_x86_agent_vsn', value: params.solaris_x86_agent_vsn),
                            string(name: 'solaris_sparc_agent_vsn', value: params.solaris_sparc_agent_vsn),
                            string(name: 'TAG', value: "${env.TAG}"),
                            string(name: 'platform', value: params.platform)
                        ]
                    }
                }

                stage('JAVA Image Build') {
                    when { expression { params.platform.contains("linux/amd64") } }
                    steps{
                        build job: 'titan-container-java', parameters: [
                            string(name: 'version', value: params.version),
                            string(name: 'company', value: params.company),
                            string(name: 'buildVariant', value: params.buildVariant),
                            string(name: 'TAG', value: "${env.TAG}")
                        ]
                    }
                }

                // 如果是多架构构建，则ARM64的镜像tag后增加-arm64,用于后面的manifest创建多架构镜像
                stage('JAVA ARM64 Image Build') {
                    when { expression { params.platform.contains("linux/arm64") } }
                    steps{
                        build job: 'titan-container-java-arm', parameters: [
                            string(name: 'version', value: params.version),
                            string(name: 'company', value: params.company),
                            string(name: 'buildVariant', value: params.buildVariant),
                            string(name: 'TAG', value: params.platform.contains(",") ? "${env.TAG}-arm64": "${env.TAG}")
                        ]
                    }
                }
                // 目前只有compose部署需要，后面修改
                stage('Go-patrol Image Build') {
                    // when { expression { params.package == "all" || params.package == "compose" } }
                    steps{
                        build job: 'titan-go-patrol', parameters: [
                            string(name: 'version', value: params.version),
                            string(name: 'company', value: params.company),
                            string(name: 'buildVariant', value: params.buildVariant),
                            string(name: 'TAG', value: "${env.TAG}")
                        ]
                    }
                }
            }
        }

        stage('manifest create multi arch images') {
            // 当同时打 amd64 和 arm64 的镜像时, 才需要。只有一种架构则无需处理
            when { expression { params.platform.contains(",") } }
            steps {
                script {
                    for (imageName in ["titan-sysinfo","titan-java-wisteria","titan-upgradetool","titan-java-gateway",
                                        "titan-java-user-srv","titan-java-connect-agent",
                                        "titan-java-connect-dh","titan-java-connect-selector","titan-java-connect-sh",
                                        "titan-java-detect-srv","titan-java-job-srv",
                                        "titan-java-upload-srv","titan-java-upload-srv-cdc",
                                        "titan-java-upload-srv-tav-ave",
                                        "titan-java-event-srv", "titan-java-ms-srv", "titan-java-anti-virus-srv"]) {
                        sh """
                        docker pull ${REGISTRYADDR}/${imageName}:${env.TAG}
                        docker pull ${REGISTRYADDR}/${imageName}:${env.TAG}-arm64
                        
                        docker manifest create ${REGISTRYADDR}/${imageName}:${env.TAG} --amend ${REGISTRYADDR}/${imageName}:${env.TAG} --amend ${REGISTRYADDR}/${imageName}:${env.TAG}-arm64

                        docker manifest push ${REGISTRYADDR}/${imageName}:${env.TAG}
                        """
                    }
                }
            }
        }

        stage('build multi arch titan-deploy-onk8s image') {
            when { expression { params.package == "all" || params.package == "k8s" } }
            steps {
                script {
                    sh """
                    echo "build titan-deploy-onk8s image start"
                    cd ${rootDir}/titan-deploy-on-k8s && rm -rf build
                    sed -i "s/^common_tag:.*/common_tag: ${env.TAG}/" var_file.yml
                    docker buildx build --platform ${params.platform} --push -t ${REGISTRYADDR}/titan-deploy-onk8s:${env.TAG} .
                    """
                }
            }
        }

        stage('Export all Image to build standalone targz package') {
            failFast true
            parallel {
                stage('Export and build package on X86_64') {
                    agent { label 'container' }
                    when { expression { params.platform.contains("linux/amd64") } }
                    steps{
                        script {
                            if (params.package == "all" || params.package == "compose" ){
                                sh """
                                    cd $rootDir/compose && ./build-sa.sh $TAG
                                    mv $rootDir/compose/build/titan-compose-all-${TAG}.tar.gz ${PKG_ARCHIVE_PATH}/
                                """
        
                                def size = sh(returnStdout: true, script: "du -sm ${PKG_ARCHIVE_PATH}/titan-compose-all-${TAG}.tar.gz | cut -f1")
                                composePkgSize = size + "M"
                                echo "${composePkgSize}"
                                compose_download_url = """<li>docker-compose单机部署X86_64架构安装包下载地址：${env.JENKINS_URL}release/titan-container/titan-compose-all-${TAG}.tar.gz （<font color='red'>${composePkgSize}</font>）"""
        
                            } 
                            if(params.package == "all" || params.package == "k8s" ) {
                                sh """ rm -rf titan-deploy-on-k8s* """
                                unstash(name: "titan-k8s")

                                def pkg = "titan-k8s-${TAG}-x86_64.tar.gz"
                                sh """
                                    tar zxvf titan-deploy-on-k8s-${env.TAG}.tar.gz
                                    if [[ $params.version =~ 3.4.0 ]];then
                                        sed -i '/^scansrv_image/d;/^clusterlinksrv_image/d' titan-deploy-on-k8s/var_file.yml
                                    fi
                                    cd titan-deploy-on-k8s && ./build.sh $TAG
                                    mv build/${pkg} ${PKG_ARCHIVE_PATH}/
                                """

                                k8s_amd64_build_dir = sh(returnStdout: true, script: "echo `pwd`/titan-deploy-on-k8s/build ")
        
                                def size = sh(returnStdout: true, script: "du -sm ${PKG_ARCHIVE_PATH}/${pkg} | cut -f1")
                                k8sPkgSize = size + "M"
                                echo "${k8sPkgSize}".replace('\n','')
                                k8s_amd64_download_url = """<li>K8S容器部署X86_64架构安装包下载地址：${env.JENKINS_URL}release/titan-container/${pkg} （<font color='red'>${k8sPkgSize}</font>）"""
                            
                            }

                        }
                    }
                }

                stage('Export and build package on ARM64') {
                    agent { label 'container-arm' }
                    when { expression { params.platform.contains("linux/arm64") } }
                    steps{
                        script {
                            
                            if(params.package == "all" || params.package == "k8s" ) {
                                sh """ rm -rf titan-deploy-on-k8s* """
                                unstash(name: "titan-k8s")

                                def pkg = "titan-k8s-${TAG}-aarch64.tar.gz"
                                sh """
                                    tar zxvf titan-deploy-on-k8s-${env.TAG}.tar.gz
                                    if [[ $params.version =~ 3.4.0 ]];then
                                        sed -i '/^scansrv_image/d;/^clusterlinksrv_image/d' titan-deploy-on-k8s/var_file.yml
                                    fi
                                    cd titan-deploy-on-k8s && ./build.sh $TAG
                                    mv build/${pkg} ${PKG_ARCHIVE_PATH}/
                                """

                                k8s_arm64_build_dir = sh(returnStdout: true, script: "echo `pwd`/titan-deploy-on-k8s/build ")
        
                                def size = sh(returnStdout: true, script: "du -sm ${PKG_ARCHIVE_PATH}/${pkg} | cut -f1")
                                k8sPkgSize = size + "M"
                                echo "${k8sPkgSize}".replace('\n','')
                                k8s_arm64_download_url = """<li>K8S容器部署ARM64架构安装包下载地址：${env.JENKINS_URL}release/titan-container/${pkg} （<font color='red'>${k8sPkgSize}</font>）"""
                            
                            }
                        }
                    }
                }
            }
        }


        stage('Encrypt install package and add docker-install or k3s-install to package') {
            // 是否是打最终发布包
            when { expression { params.final_release == "Yes" } }
            failFast true
            parallel {
                stage('encrypt and build release package on X86_64') {
                    agent { label 'container' }
                    when { expression { params.platform.contains("linux/amd64") } }
                    steps{
                        script {
                            if (params.package == "all" || params.package == "compose" ){
                                sh """
                                    echo ${password} > ${PKG_ARCHIVE_PATH}/package-ssl/${PWD_TAG}.pwd

                                    cd $rootDir/compose/build/$TAG  
                                    wget https://jenkins.qingteng.cn/release/titan-container/       docker-20.10.7-compose-1.29.2-install.tar.gz
                                    mv docker-20.10.7-compose-1.29.2-install.tar.gz docker-install.tar.gz
        
                                    cd $rootDir/compose/build/
                                    tar -zcvf - $TAG | openssl aes-128-cbc -e -pass pass:${password} -md md5 -out titan-compose-release-${TAG}.tar.gz
        
                                    mv titan-compose-release-${TAG}.tar.gz ${PKG_ARCHIVE_PATH}/
                                """
        
                                def size = sh(returnStdout: true, script: "du -sm ${PKG_ARCHIVE_PATH}/titan-compose-release-${TAG}.tar.gz | cut -f1")
                                composePkgSize = size + "M"
                                echo "${composePkgSize}"
                                compose_download_url = """<li>docker-compose单机部署安装包下载地址：${env.JENKINS_URL}release/      titan-container/titan-compose-release-${TAG}.tar.gz （<font color='red'>${composePkgSize}    </font>）"""
                                passwd_info = """<li>解密密码：<font color='red'>${password}</font>"""
        
                            }

                            if(params.package == "all" || params.package == "k8s" ) {
                                def pkg = "titan-k8s-release-${TAG}-x86_64.tar.gz"
                                sh """
                                    echo ${password} > ${PKG_ARCHIVE_PATH}/package-ssl/${PWD_TAG}.pwd
                                    cd  ${k8s_amd64_build_dir}
                                    tar -zcvf - $TAG | openssl aes-128-cbc -e -pass pass:${password} -md md5 -out ${pkg}
        
                                    mv ${pkg} ${PKG_ARCHIVE_PATH}/
                                """
        
                                def size = sh(returnStdout: true, script: "du -sm ${PKG_ARCHIVE_PATH}/${pkg} | cut -f1")
                                k8sPkgSize = size + "M"
                                echo "${k8sPkgSize}".replace('\n','')
                                k8s_amd64_download_url = """<li>K8S容器部署X86_64架构安装包下载地址：${env.JENKINS_URL}release/titan-container/${pkg} （<font color='red'>${k8sPkgSize}</font>）"""
                                passwd_info = """<li>解密密码：<font color='red'>${password}</font>"""
                            
                            }

                        }
                    }
                }

                stage('encrypt and build release package on ARM64') {
                    agent { label 'container-arm' }
                    when { expression { params.platform.contains("linux/arm64") } }
                    steps{
                        script {
                            
                            if(params.package == "all" || params.package == "k8s" ) {
                                def pkg = "titan-k8s-release-${TAG}-aarch64.tar.gz"
                                sh """
                                    echo ${password} > ${PKG_ARCHIVE_PATH}/package-ssl/${PWD_TAG}.pwd
                                    cd  ${k8s_arm64_build_dir}
                                    tar -zcvf - $TAG | openssl aes-128-cbc -e -pass pass:${password} -md md5 -out ${pkg}
                                    mv ${pkg} ${PKG_ARCHIVE_PATH}/
                                """
        
                                def size = sh(returnStdout: true, script: "du -sm ${PKG_ARCHIVE_PATH}/${pkg} | cut -f1")
                                k8sPkgSize = size + "M"
                                echo "${k8sPkgSize}".replace('\n','')
                                k8s_arm64_download_url = """<li>K8S容器部署ARM64架构安装包下载地址：${env.JENKINS_URL}release/titan-container/${pkg} （<font color='red'>${k8sPkgSize}</font>）"""
                                passwd_info = """<li>解密密码：<font color='red'>${password}</font>"""
                            
                            }
                        }
                    }
                }
            }
        }

    }

    post {
        success {
            emailext subject:"服务端容器化部署自动打包构建成功， TAG: ${TAG}，Build Number: ${BUILD_NUMBER}",
                to: env.NEW_STYLE_STANDALONE_BUILD_GROUP,
                mimeType: 'text/html',
                body: """
                    <h1 style="background:green;text-align:center">服务端容器化部署自动打包构建成功!</h1>
                    <h2>构建信息</h2>
                    <ul>
                        <li>项目名称: ${JOB_NAME}
                        <li>构建编号: ${BUILD_NUMBER}
                        <li>构建详情：${BUILD_URL}
                        <li>构建日志：${BUILD_URL}/console
                        <li>镜像仓库地址：https://registry.qingteng.cn/harbor/projects/22/repositories
                        <li>App Image Tag: ${env.TAG} 
                        ${compose_download_url}
                        ${k8s_amd64_download_url}
                        ${k8s_arm64_download_url}
                        ${passwd_info}
                    </ul>

                    <h2>构建参数</h2>
                    ${formatParams(params)}

                    <h2>构建分支</h2>
                    ${formatParams(getBranchMap(params.buildVariant))}
                """
        }
        failure {
            emailext subject:"服务端容器化部署自动打包构建失败 Build Number: ${BUILD_NUMBER}",
                to: env.NEW_STYLE_STANDALONE_BUILD_GROUP,
                mimeType: 'text/html',
                body: """
                    <h1 style="background:red;text-align:center">服务端容器化部署自动打包构建失败!</h1>
                    <h2>构建信息</h2>
                    <ul>
                        <li>项目名称: ${JOB_NAME}
                        <li>构建编号: ${BUILD_NUMBER}
                        <li>构建详情：${BUILD_URL}
                        <li>构建日志：${BUILD_URL}/console
                    </ul>

                    <h2>构建参数</h2>
                    ${formatParams(params)}

                    <h2>构建分支</h2>
                    ${formatParams(getBranchMap(params.buildVariant))}
                """
        }
    }
}

@NonCPS
String formatParams(def params) {
    StringBuilder sb = new StringBuilder()
    sb.append('<table style="border-collapse: collapse;border: 1px solid;">')

    params.each {key, value -> 
        sb.append("<tr><td style='border: 1px solid;'>${key}</td><td style='border: 1px solid;'>${value}</td></tr>")
    }

    sb.append('</table>')

    return sb.toString()
}

@NonCPS
Map<String, String> getBranchMap(String buildVariant) {
    def jsonSlurper = new JsonSlurper()
    def versionJsonMap = jsonSlurper.parseText(env.VERSION_JSON)
    return versionJsonMap[buildVariant]
}

@NonCPS
String randomPassword(int n) {
    def alphabet = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_%"
    int length = alphabet.length()
    StringBuilder sb = new StringBuilder()
    Random random=new Random();
    for(int i=0;i<n;i++){
       int number=random.nextInt(length);
       sb.append(alphabet.charAt(number));
    }

    return sb.toString()
}
