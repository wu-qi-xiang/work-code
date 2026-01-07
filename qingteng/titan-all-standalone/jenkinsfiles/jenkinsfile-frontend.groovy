import java.util.regex.Matcher

pipeline {
    agent { label 'jenkins-slave-frontend2' }
    environment {
        GIT_URL = "ssh://yan.zheng@gerrit.qingteng.cn:29418/titan-frontend"
        ARTFACTS_SERVER = "172.16.6.111"
        ARTFACTS_PATH = "/data/workspace/artifacts/${params.jobTag}/frontend/"
        ARTFACTS_URL = "jenkins@${ARTFACTS_SERVER}:${ARTFACTS_PATH}"
        OUTDIR = "frontend-standalone-v${version}-${BUILD_TAG}"
    }
    stages {
        stage('Prepare') {
            steps {
                echo "Parameters are $params"

                sh "ssh jenkins@${ARTFACTS_SERVER} mkdir -p ${ARTFACTS_PATH}"
            }
        }
        stage('Checkout') {
            steps {
                script {
                    String branch = params.branch

                    if (!branch) {
                       // just fetch remote to get lastest remote branches
                        git branch: "master", url: GIT_URL, credentialsId: 'b0263eb3-f05f-4f2e-94ab-c50415215508', changelog: false

                        branch = getBranch(params.version, params.company)
                    }
                    
                    echo "Choose branch $branch"

                    // do the actual checkout
                    git branch: "${branch}", url: GIT_URL, credentialsId: 'b0263eb3-f05f-4f2e-94ab-c50415215508'
                }
            }
        }
        stage('Build') {
            steps {
                    nodejs(nodeJSInstallationName: 'nodejs9.5.0', configId: '55c12f7a-04b6-479d-b3a3-2a9a2dc7ed37') {
                        sh '''
                            cd v3
                            grunt standalone
                            #grunt pure


                            cd ../next
                            npm install
                            npm run standalone
                            #npm run build

                            cd ../screen
                            npm install
                            npm run build
                    '''
                    }
                }
        }
        stage('Upload') {
            steps {
                script {
                    sh """
                            zipDir=frontend-standalone-${BUILD_TIMESTAMP}
                            echo "\${zipDir}"
                            cd ${WORKSPACE}
                                mkdir -p \${zipDir}
                                cp -r -f ./v3/rel/* ./\${zipDir}/
                                cp -r -f ./next/dist ./\${zipDir}/next
                                cp -r -f ./screen/dist ./\${zipDir}/screen
                            cd \${zipDir} && zip -q -r ../\${zipDir} ./
                            zipfile=`ls -t /data/frontend/workspace/frontend-standalone/frontend*.zip | head -1`
                            echo "Uploading \${zipfile} to ${ARTFACTS_URL}"
                            scp \$zipfile ${ARTFACTS_URL}
                            echo "Record revision and upload"
                            cd ${WORKSPACE}
                            git rev-parse --short HEAD > ${WORKSPACE}/frontend-revision
                            scp ${WORKSPACE}/frontend-revision ${ARTFACTS_URL}
                            echo "clean frontend dir"
                            rm -rf ${WORKSPACE}/\${zipDir}
                            """

                }
            }
        }
    }
}

/*
 * Translate version and company name to branch name
 */
def getBranch(String version, String company) {
    if (company != "common") {
        return "custom-${company}-v${version}"
    }

    // try finding branch name like standalone-vx.x.x.x
    String standalonePrefixedName = "standalone-v${version}"
    output = bat(script: "git branch -a", returnStdout:true)
    branches = output.split("\n").collect({it =~ /\s+remotes\/origin\/(\S+)/}).findAll({it.matches()}).collect({it[0][1]})

    if (branches.contains(standalonePrefixedName)) {
        return standalonePrefixedName
    }

    // fallback to release-standalone-vx.x.x.x
    return "release-standalone-v${version}"
}
