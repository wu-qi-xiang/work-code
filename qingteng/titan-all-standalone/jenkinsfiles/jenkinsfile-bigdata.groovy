pipeline {
    agent {label 'master'}
    environment {
        ARTFACTS_SERVER = "127.0.0.1"
        ARTFACTS_PATH = "/data/workspace/artifacts/${params.jobTag}/bigdata/"
        ARTFACTS_URL = "jenkins@${ARTFACTS_SERVER}:${ARTFACTS_PATH}"
        GIT_DATAMANAGER_URL = 'ssh://zi.tan@gerrit.qingteng.cn:29418/insight_datamanager/'
        GIT_ANALYSISMANAGER_URL = 'ssh://zi.tan@gerrit.qingteng.cn:29418/insight_analysismanager/'
    }
    stages {
        stage('Prepare') {
            steps {
                echo "Parameters are $params"

                sh "ssh jenkins@${ARTFACTS_SERVER} 'mkdir -p ${ARTFACTS_PATH}'"

                echo "Cleanup previous build packages"
                sh "if [[ -d '.git' ]]; then git clean -fdx; fi" 
            }
        }
        stage('Checkout') {
            steps {
                script {
                    String branch = params.branch

                    if (!branch) {
                        branch = getBranch(params.version, params.company)
                    }

                    echo "Choose branch $branch"

                    git branch: "${branch}", url: GIT_DATAMANAGER_URL, credentialsId: 'zi.tan-gerrit'

                    dir("viewer") {
                        git branch: "${branch}", url: GIT_ANALYSISMANAGER_URL, credentialsId: 'zi.tan-gerrit'
                    }
                }
            }
        }
        stage('Build') {
            steps {
                sh """
                    echo "使用独立部署版本的配置文件"
                    mv -f qt_consumer/conf/consumer_standalone.yml qt_consumer/conf/consumer.yml

                    mv viewer/qt_viewer qt_viewer

                    echo "将py文件编译为pyc和pyo"
                    python2.7.9 -m compileall qt_* bin
                    python2.7.9 -O -m compileall qt_* bin

                    # 删除py源文件
                    find qt_* -name "*.py" -type f -not -path "**/run.py" -print -exec rm -rf {} \\;
                    rm -rf bin/*.py

                    rm -rf viewer* doc

                    chmod +x bin/*
                    mv other/*.conf .
		    tar -I pigz -cvf qingteng-consumer-v1.0.0-`date +%Y%m%d%H%M%S`.tgz bin qt_consumer qt_monitor bin other

                    rm -rf other/*.conf
		    mv *.conf other/

                    tar -I pigz -cvf qingteng-viewer-V1.0.0-`date +%Y%m%d%H%M%S`.tgz qt_viewer other

                    echo "编译为pyc和pyo文件，打包工程完成"
                """
            }
        }
        stage('Upload') {
            steps {
                script {
                    File[] packageFiles = findPackageFile()
                    for (packageFile in packageFiles){
                      echo "Found package file ${packageFile}"

                      echo "Uploading ${packageFile.absolutePath} to $ARTFACTS_URL"
                      sh "scp ${packageFile.absolutePath} $ARTFACTS_URL"
                    }

                    echo "Record revision and upload"
                    sh "git rev-parse --short HEAD > ${WORKSPACE}/bigdata-revision"
                    sh "scp ${WORKSPACE}/bigdata-revision ${ARTFACTS_URL}"  
                    
                    
                }
            }
        }
    }
}

@NonCPS
String getBranch(String version, String company) {
    return "${version.replaceAll(/\./, '')}_${company}"
}

/*
 * Find generated package file in the  directory
 */
@NonCPS
File[] findPackageFile() {
    File buildDir = new File(WORKSPACE)
    File[] packageFiles = buildDir.listFiles((FilenameFilter){ File _, String name ->  name.endsWith(".tgz") })
    
    if (packageFiles.length == 0) {
        error("No package file found")
    } else if (packageFiles.length > 2) {
        error("More than 2 package files have been found")
    }
    
    return packageFiles
}
