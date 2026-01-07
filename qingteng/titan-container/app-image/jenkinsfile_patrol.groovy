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

pipeline {
    agent {label 'container'}
    environment {
        REGISTRYHOST = "registry.qingteng.cn/titan-container"
        CREDENTIALS_ID = "56ab2764-0e9c-40ef-b4aa-c16182485a84"
        TITAN_WISTERIA_GIT_URL = "git@git.qingteng.cn:wisteria/go-patrol.git"
        TAG = getTag()
        GO_PATROL_FRONTEND_BRANCH = getBranch(params.buildVariant, "go-patrol-frontend")
    }
    stages {
        stage('Prepare') {
            steps {
                echo "Parameters are $params"
                echo "${WORKSPACE}"
            }
        }

        stage('checkout') {
            steps {
                script {
                    String branch = getBranch(params.buildVariant,"go-patrol")
                    echo "Choose branch $branch"

                    git branch: branch, credentialsId: CREDENTIALS_ID, url: TITAN_WISTERIA_GIT_URL
                }
            }
        }

        stage('Frontend Build Job') {
            steps{
                build job: 'titan-go-patrol-frontend', parameters: [
                    string(name: 'branch', value: "origin/${GO_PATROL_FRONTEND_BRANCH}")
                ]
            }
        }

        stage('Build titan-go-patrol') {
            steps {
                script {
                    sh """
                        echo "build titan-go-patrol image start"
                        cd ${WORKSPACE} && rm -rf static && mkdir -p static
                        tar zxvf /data/build/container/go-patrol/static-*.tar.gz -C static
                        ./build.sh ${env.TAG}
                    """
                }
            }
        }

    }
}