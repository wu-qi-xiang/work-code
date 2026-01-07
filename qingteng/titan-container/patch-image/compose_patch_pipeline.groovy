
pipeline {
    agent { label 'container' }
    environment {
        REGISTRYHOST = "registry.qingteng.cn/titan-container"
        fromtag = "${params.fromtag}"
        totag = "${params.totag}"
        PKG_ARCHIVE_PATH = "/data/qt-container/titan-container/release-nas"
    }
    stages {
        stage('Prepare to build patch') {
            steps {
                script {
                    echo "params: ${params}"

                    if (fromtag == totag){
                        echo "tag must not same"
                    }

                    currentBuild.displayName = "${BUILD_NUMBER}-${fromtag}-${totag}"

                    echo "begin: ${WORKSPACE}"
                    sh '''
                        rm -rf build/dist && mkdir -p build/dist
                    '''

                    sh  """
                        echo ${fromtag}/base_tar_info 
                        echo ${fromtag}/app_tar_info
                        if [[ -f ${fromtag}/base_tar_info ]] && [[ -f ${fromtag}/app_tar_info ]]; then
                            echo "already have old info, no need extract again"
                        else
                            tar zxvf /data/qt-container/titan-container/release-nas/titan-compose-all-${fromtag}.tar.gz
                            tar -tf ${fromtag}/titan-*-base-*.tar > ${fromtag}/base_tar_info
                            tar -tf ${fromtag}/titan-*-app-${fromtag}.tar > ${fromtag}/app_tar_info
                            tar -tf ${fromtag}/titan-sysinfo-${fromtag}.tar > ${fromtag}/sysinfo_tar_info
                        fi

                        tar zxvf /data/qt-container/titan-container/release-nas/titan-compose-all-${totag}.tar.gz -C build/dist/ 
                        tar -tf build/dist/${totag}/titan-*-base-*.tar > build/dist/${totag}/base_tar_info
                        tar -tf build/dist/${totag}/titan-*-app-${totag}.tar > build/dist/${totag}/app_tar_info
                        tar -tf build/dist/${totag}/titan-sysinfo-${totag}.tar > build/dist/${totag}/sysinfo_tar_info
                        rm -f build/dist/${totag}/titan-rules-*.tar
                    """
                }
            }
        }

        stage('Compare and build patch') {
            steps {
                script {
                    def fromBaseFiles = getFilesFromTarInfo("${fromtag}/base_tar_info")
                    def toBaseFiles = getFilesFromTarInfo("build/dist/${totag}/base_tar_info")
                    def fromAppFiles = getFilesFromTarInfo("${fromtag}/app_tar_info")
                    def toAppFiles = getFilesFromTarInfo("build/dist/${totag}/app_tar_info")
                    def fromSysinfoFiles = getFilesFromTarInfo("${fromtag}/sysinfo_tar_info")
                    def toSysinfoFiles = getFilesFromTarInfo("build/dist/${totag}/sysinfo_tar_info")

                    // begin compare, only compare layers
                    echo "fromBaseFiles:"
                    echo fromBaseFiles.join(" ")
                    echo "toBaseFiles:"
                    echo toBaseFiles.join(" ")
                    def oldBaseFiles = []
                    def newBaseFiles = []
                    compareFiles(fromBaseFiles,toBaseFiles,oldBaseFiles,newBaseFiles)
                    echo "base compare result:"
                    echo oldBaseFiles.join(" ")
                    echo newBaseFiles.join(" ")

                    echo "fromAppFiles:"
                    echo fromAppFiles.join(" ")
                    echo "toAppFiles:"
                    echo toAppFiles.join(" ")
                    def oldAppFiles = []
                    def newAppFiles = []
                    compareFiles(fromAppFiles,toAppFiles,oldAppFiles,newAppFiles)
                    echo "app compare result:"
                    echo oldAppFiles.join(" ")
                    echo newAppFiles.join(" ")

                    echo "fromSysinfoFiles:"
                    echo fromSysinfoFiles.join(" ")
                    echo "toSysinfoFiles:"
                    echo toSysinfoFiles.join(" ")
                    def oldSysinfoFiles = []
                    def newSysinfoFiles = []
                    compareFiles(fromSysinfoFiles,toSysinfoFiles,oldSysinfoFiles,newSysinfoFiles)
                    echo "sysinfo compare result:"
                    echo oldSysinfoFiles.join(" ")
                    echo newSysinfoFiles.join(" ")

                    if (newBaseFiles.size() > 0) {
                        echo "begin create base patch"
                        def delBaseFiles = oldBaseFiles.join(" ") 
                        sh  """ 
                            cd build/dist/${totag}
                            mkdir -p base_patch/ && tar xvf titan-compose-base-*.tar -C base_patch/
                            cd base_patch/ && rm -rf ${delBaseFiles}
                            tar -cvf ../titan-compose-patch-base-${fromtag}-${totag}.tar *
                        """ 
                    }
                
                    if (newAppFiles.size() > 0) {
                        echo "begin create app patch"
                        def delAppFiles = oldAppFiles.join(" ") 
                        sh  """
                            cd build/dist/${totag}
                            mkdir -p app_patch/ && tar xvf titan-compose-app-*.tar -C app_patch/
                            cd app_patch/ && rm -rf ${delAppFiles}
                            tar -cvf ../titan-compose-patch-app-${fromtag}-${totag}.tar *
                        """
                    }

                    echo "begin create sysinfo patch"
                    def delSysinfoFiles = oldSysinfoFiles.join(" ") 
                    echo delSysinfoFiles 
                    sh  """
                        cd build/dist/${totag}
                        mkdir -p sysinfo_patch/ && tar xvf titan-sysinfo-*.tar -C sysinfo_patch/
                        cd sysinfo_patch/ && rm -rf ${delSysinfoFiles}
                        tar -cvf ../titan-sysinfo-${fromtag}-${totag}.tar *
                    """

                    sh """
                        cd build/dist/${totag}
                        rm -rf base_tar_info app_tar_info sysinfo_tar_info base_patch app_patch sysinfo_patch titan-compose-base-*.tar titan-compose-app-*.tar titan-sysinfo-${totag}.tar
                        cd ../ && tar --use-compress-program=pigz -cvpf titan-compose-patch-${fromtag}-${totag}.tar.gz ${totag}
                    """
                
                    sh """
                        rm -rf ${fromtag}/*.tar
                        mv build/dist/titan-compose-patch-${fromtag}-${totag}.tar.gz ${PKG_ARCHIVE_PATH}/
                    """
                }
            }
        }

        stage('Build Email text') {
            //when { expression { return false } }
            steps {
                script {
                    compose_download_url = ""

                    def size = sh(returnStdout: true, script: "du -sm ${PKG_ARCHIVE_PATH}/titan-compose-patch-${fromtag}-${totag}.tar.gz | cut -f1")
                    composePkgSize = size + "M"
                    echo "${composePkgSize}"
                    compose_download_url = """<li>docker-compose单机部署Patch补丁包下载地址：${env.JENKINS_URL}release/titan-container/titan-compose-patch-${fromtag}-${totag}.tar.gz （<font color='red'>${composePkgSize}</font>）""" 
                    
                }
            }
        }
    }

    post {
        success {
            emailext subject:"服务端容器化部署Patch包构建成功， Build Number: ${BUILD_NUMBER}",
                to: env.NEW_STYLE_STANDALONE_BUILD_GROUP,
                mimeType: 'text/html',
                body: """
                    <h1 style="background:green;text-align:center">服务端容器化部署Patch包构建成功!</h1>
                    <h2>构建信息</h2>
                    <ul>
                        <li>项目名称: ${JOB_NAME}
                        <li>构建编号: ${BUILD_NUMBER}
                        <li>构建详情：${BUILD_URL}
                        <li>构建日志：${BUILD_URL}/console
                        ${compose_download_url}
                    </ul>

                    <h2>构建参数</h2>
                    ${formatParams(params)}
                """
        }
        failure {
            emailext subject:"服务端容器化部署Patch包构建失败 Build Number: ${BUILD_NUMBER}",
                to: env.NEW_STYLE_STANDALONE_BUILD_GROUP,
                mimeType: 'text/html',
                body: """
                    <h1 style="background:red;text-align:center">服务端容器化部署Patch包构建失败!</h1>
                    <h2>构建信息</h2>
                    <ul>
                        <li>项目名称: ${JOB_NAME}
                        <li>构建编号: ${BUILD_NUMBER}
                        <li>构建详情：${BUILD_URL}
                        <li>构建日志：${BUILD_URL}/console
                    </ul>

                    <h2>构建参数</h2>
                    ${formatParams(params)}

                """
        }
    }    
}

// 返回docker导出的镜像包第一级的文件和目录
def getFilesFromTarInfo(def tarInfoPath) {
    tarInfoLines = readFile(tarInfoPath).split("\n")     
    def tarFiles = []

    for(file in tarInfoLines){
        if (file.contains("/") && !file.endsWith("/")){
            continue
        }
        tarFiles.add(file)
    }

    echo "getFilesFromTarInfo:"
    echo tarFiles.join(" ")
    return tarFiles
}


@NonCPS
def compareFiles(def fromFiles, def toFiles, def oldFiles, def newFiles) {
    for(file in toFiles){
        if (file == "repositories" || file == "manifest.json" || file.endsWith(".json")){
            continue
        }
        if (fromFiles.contains(file)){
            oldFiles.add(file) 
        } else {
            newFiles.add(file) 
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
