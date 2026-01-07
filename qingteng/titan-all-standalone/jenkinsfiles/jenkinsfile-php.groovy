import java.util.regex.Matcher

/*
 * Translate version and company name to branch name
 */
def getBranch(String version, String company) {
    def final branchMap = [
        ["3.3.0.2", "common"]: "deploy_3302",
        ["3.3.0.1", "common"]: "deploy",
        ["3.2.0.2", "common"]: "deploy_320_2",
        ["3.2.0.2", "tencentcloud"]: "tencentcloud",
        ["3.3.0.3", "common"]: "deploy_3303",
        ["3.3.9", "common"]: "deploy_339",
        ["3.3.12", "common"]: "master",
        ["3.4.0", "common"]: "deploy_340"
    ]
    
    return branchMap.get([version, company], "rel")
}

pipeline {
    agent {label 'jenkins-slave-php'}
    environment {
        BUILD_OUT = "$WORKSPACE/deploy"
        ARTFACTS_SERVER = "172.16.6.111"
        ARTFACTS_PATH = "/data/workspace/artifacts/${params.jobTag}/php/"
        ARTFACTS_URL = "jenkins@${ARTFACTS_SERVER}:${ARTFACTS_PATH}"
    }
    stages {
        stage('Prepare') {
            steps {
                echo "Parameters are $params"
                
                echo "Cleanup previous build output directory"
                sh "rm -rf ${BUILD_OUT}/*"

                sh "ssh jenkins@${ARTFACTS_SERVER} 'mkdir -p ${ARTFACTS_PATH}'"
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
                    String packageFile = sh(script:"ls ${BUILD_OUT}/${company}/*.zip", returnStdout:true).trim()
                    echo "Found package file ${packageFile}" 
                    
                    echo "Uploading ${packageFile} to ${ARTFACTS_URL}"
                    sh "scp ${packageFile} ${ARTFACTS_URL}"

                    echo "Record revision and upload"
                    sh "cd titan-web && git rev-parse --short HEAD > ${BUILD_OUT}/php-revision"
                    sh "scp ${BUILD_OUT}/php-revision ${ARTFACTS_URL}"
                }
            }
        }
    }
}
