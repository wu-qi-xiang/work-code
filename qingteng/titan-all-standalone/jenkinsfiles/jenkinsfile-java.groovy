import java.util.regex.Matcher

pipeline {
    agent {label 'master'}
    environment {
        GIT_URL = 'git@git.qingteng.cn:wisteria/wisteria.git'
        FRONTEND_GIT_URL = 'ssh://jitang.hu@gerrit.qingteng.cn:29418/titan-frontend'
        ARTFACTS_SERVER = "172.16.6.111"
        ARTFACTS_PATH = "/data/workspace/artifacts/${params.jobTag}/java/"
        ARTFACTS_URL = "jenkins@${ARTFACTS_SERVER}:${ARTFACTS_PATH}"
    }
    stages {
        stage('Prepare') {
            steps {
                echo "Parameters are ${params}"

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

                    git branch: branch, url: GIT_URL
                }

                dir("frontend") {
                    script{
                        String frontendBranch = params.frontendBranch

                        echo "Choose frontend branch $frontendBranch"

                        if (!frontendBranch) {
                            // just fetch remote to get lastest remote branches
                            git branch: "master", url: FRONTEND_GIT_URL, changelog: false

                            frontendBranch = getFrontendBranch(params.version, params.company)
                        }

                        // do the actual checkout
                        git branch: frontendBranch, url: FRONTEND_GIT_URL
                    }
                }
            }
        }
        stage('Build') {
            steps {
                sh """
                    pushd frontend/monitor
                    cnpm install && cnpm run standalone
                    popd

                    ./build-sa-dist.sh ${params.version}
                """
            }
        }
        stage('Upload') {
            steps {
                script {
                    File packageFile = findPackageFile()
                    echo "Found package file ${packageFile}" 
                                        
                    def uploadUrl = "jenkins@${ARTFACTS_SERVER}:${ARTFACTS_PATH}"
                    echo "Uploading ${packageFile.name} to $uploadUrl"
                    sh "scp build/${packageFile.name} $uploadUrl"

                    echo "Uploading sysinfo to $uploadUrl"
                    sh "scp build/dist/titan-connect-agent/sysinfo $uploadUrl"

                    echo "Record revision and upload"
                    sh "git rev-parse --short HEAD > ${WORKSPACE}/build/java-revision"
                    sh "scp build/java-revision $uploadUrl"
                }
            }
        }
    }
}

/*
 * Find generated package file in the 'build' directory
 */
@NonCPS
File findPackageFile() {
    File buildDir = new File("$WORKSPACE/build")
    File[] packageFiles = buildDir.listFiles((FilenameFilter){ File _, String name ->  name.endsWith(".zip") })
    
    if (packageFiles.length == 0) {
        error("No package file found")
    } else if (packageFiles.length > 1) {
        error("More than 1 package files has been found")
    }
    
    return packageFiles[0]
}

/*
 * Translate version and company name to branch name
 */
def getBranch(String version, String company) {
    Matcher matcher = version =~  /(\d+\.\d+\.\d+)(\.\d+)*/ 
    if (matcher) {
        String matchedVersion = matcher.group(0)
        if (company == 'common') {
            return "pre-release-${matchedVersion}"
        } else {
            return "${company}-${matchedVersion}"
        }
    }
    
    error("Wrong version format: $version")
}

/*
 * Translate version and company name to frontend branch name
 */
def getFrontendBranch(String version, String company) {
    if (company != "common") {
        return "custom-${company}-v${version}"
    }

    // try finding branch name like standalone-vx.x.x.x
    String standalonePrefixedName = "standalone-v${version}"
    output = sh(script: "git branch -a", returnStdout:true)
    branches = output.split("\n").collect({it =~ /\s+remotes\/origin\/(\S+)/}).findAll({it.matches()}).collect({it[0][1]})

    if (branches.contains(standalonePrefixedName)) {
        return standalonePrefixedName
    }

    // fallback to release-standalone-vx.x.x.x
    return "release-standalone-v${version}"
}
