
pipeline {
    agent { label 'container' }
    environment {
        REGISTRYHOST = "registry.qingteng.cn/titan-container"
        PKG_ARCHIVE_PATH = "/data/qt-container/titan-container/release-nas"
    }
    stages {
        stage('Prepare to build patch') {
            steps {
                script {
                    currentBuild.displayName = "${BUILD_NUMBER}-${fromtag}-${totag}"

                    if (fromtag == totag){
                        error "tag must not same"
                    }

                    k8s_download_url_x8664 = ""
                    k8s_download_url_arm64 = ""

                    echo "params: ${params}"
                }
            }
        }

        stage('Prepare to build patch for platforms') {
            steps {
                script {

                for (_platform in params.platform.split(",") ) {
                    if (_platform == "linux/amd64"){
                        arch = "x86_64"
                    }else {
                        arch = "aarch64"
                    }

                    echo "begin: ${WORKSPACE}"
                    sh '''
                        rm -rf build/dist && mkdir -p build/dist
                    '''

                    sh  """
                        echo ${fromtag}-${arch}/base_tar_info 
                        echo ${fromtag}-${arch}/app_tar_info

                        rm -rf ${fromtag} 

                        if [[ -f ${fromtag}-${arch}/base_tar_info ]] && [[ -f ${fromtag}-${arch}/app_tar_info ]]; then
                            echo "already have old info, no need extract again"
                            cp -r ${fromtag}-${arch} ${fromtag}
                        else
                            tar zxvf /data/qt-container/titan-container/release-nas/titan-k8s-${fromtag}-${arch}.tar.gz
                            tar -tf ${fromtag}/titan-*-base-*.tar > ${fromtag}/base_tar_info
                            tar -tf ${fromtag}/titan-*-app-*.tar > ${fromtag}/app_tar_info

                            rm -rf ${fromtag}/*.tar
                            cp -r ${fromtag} ${fromtag}-${arch}
                        fi

                        tar zxvf /data/qt-container/titan-container/release-nas/titan-k8s-${totag}-${arch}.tar.gz -C build/dist/
                        tar -tf build/dist/${totag}/titan-*-base-*.tar > build/dist/${totag}/base_tar_info
                        tar -tf build/dist/${totag}/titan-*-app-*.tar > build/dist/${totag}/app_tar_info
                        rm -f build/dist/${totag}/titan-rules-*.tar
                        cp ${fromtag}/baseimages build/dist/${totag}/old_baseimages && cp ${fromtag}/appimages build/dist/${totag}/old_appimages
                    """

                    echo "begin compare and build patch for ${arch}"

                    def fromBaseFiles = getFilesFromTarInfo("${fromtag}/base_tar_info")
                    def toBaseFiles = getFilesFromTarInfo("build/dist/${totag}/base_tar_info")
                    def fromAppFiles = getFilesFromTarInfo("${fromtag}/app_tar_info")
                    def toAppFiles = getFilesFromTarInfo("build/dist/${totag}/app_tar_info")

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

                    if (newBaseFiles.size() > 0) {
                        echo "begin create base patch"
                        def delBaseFiles = oldBaseFiles.join(" ") 
                        sh  """ 
                            cd build/dist/${totag}
                            mkdir -p base_patch/ && tar xvf titan-k8s-base-*.tar -C base_patch/
                            cd base_patch/ && rm -rf ${delBaseFiles}
                            tar -cvf ../titan-k8s-patch-base-${fromtag}-${totag}.tar *
                        """ 
                    }
                
                    if (newAppFiles.size() > 0) {
                        echo "begin create app patch"
                        def delAppFiles = oldAppFiles.join(" ") 
                        sh  """
                            cd build/dist/${totag}
                            mkdir -p app_patch/ && tar xvf titan-k8s-app-*.tar -C app_patch/
                            cd app_patch/ && rm -rf ${delAppFiles}
                            tar -cvf ../titan-k8s-patch-app-${fromtag}-${totag}.tar *
                        """
                    }

                    sh """
                        cd build/dist/${totag}
                        rm -rf base_tar_info app_tar_info base_patch app_patch titan-k8s-base-*.tar titan-k8s-app-*.tar
                        cd ../ && tar --use-compress-program=pigz -cvpf titan-k8s-patch-${fromtag}-${totag}-${arch}.tar.gz ${totag}

                        mv titan-k8s-patch-${fromtag}-${totag}-${arch}.tar.gz ${PKG_ARCHIVE_PATH}/
                    """

                    echo 'Build Email text for ${arch}'

                    def size = sh(returnStdout: true, script: "du -sm ${PKG_ARCHIVE_PATH}/titan-k8s-patch-${fromtag}-${totag}-${arch}.tar.gz | cut -f1")
                    k8sPkgSize = size + "M"
                    echo "${k8sPkgSize}"
                    if ("$arch" == "x86_64" ){
                        k8s_download_url_x8664 = """<li>K8S部署X86_64架构Patch补丁包下载地址：${env.JENKINS_URL}release/titan-container/titan-k8s-patch-${fromtag}-${totag}-${arch}.tar.gz （<font color='red'>${k8sPkgSize}</font>）"""  
                    } else {
                        k8s_download_url_arm64 = """<li>K8S部署ARM64架构Patch补丁包下载地址：${env.JENKINS_URL}release/titan-container/titan-k8s-patch-${fromtag}-${totag}-${arch}.tar.gz （<font color='red'>${k8sPkgSize}</font>）"""  
                    }
                     
                }    
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
                        ${k8s_download_url_x8664}
                        ${k8s_download_url_arm64}
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
