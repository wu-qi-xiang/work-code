import java.util.regex.Matcher

pipeline {
    agent {label 'slave-container'}
    environment {
        GIT_SCANNER_URL = 'git@git.qingteng.cn:wisteria/scanner.git'
        ARTFACTS_PATH = "/data/qt-container/qt-image"
        ARTFACTS_PATH_SCANNER = "/data/qt-container/qt-image/${params.jobTag}/scanner"
        ARTFACTS_PATH_HIVE = "/data/qt-container/qt-image/${params.jobTag}/hive"
        ARTFACTS_PATH_AGENT = "/data/qt-container/qt-image/${params.jobTag}/agent"
	DOWNLOAD_URL = "http://172.16.17.164/qt-image/package"
    }
    stages {
        stage('Prepare') {
            steps {
                echo "Parameters are ${params}"

                sh "mkdir -p ${ARTFACTS_PATH_SCANNER} ${ARTFACTS_PATH_HIVE} ${ARTFACTS_PATH_AGENT}"
            }
        }
        stage('Checkout') {
            steps {
	        dir("scanner") {
                    script {
                        String branch = params.branch

                        if (!branch) {
                            branch = getBranch(params.version, params.company)
                        }

                        echo "Choose branch $branch"

                        git branch: branch, url: GIT_SCANNER_URL, credentialsId: '56ab2764-0e9c-40ef-b4aa-c16182485a84'
                    }
                }
            }
	}
        stage('Build') {
	    parallel {
	        stage ('copy config file') {
                    steps {
	                script {
                            sh """
                                pushd scanner/scanner-worker
                                cp docker-compose.yml ${ARTFACTS_PATH_SCANNER}
                                cp /data/common.sh ${ARTFACTS_PATH_SCANNER} 
                                cp /data/install.sh ${ARTFACTS_PATH_SCANNER}
                                popd
                            """
                        }
		    }
		}
		stage ('build scanner images') {
		    steps {
		        dir("scanner") {
                            script {
                                sh """
                                    gradle6 dockerImageBuild -x test
                                    tag_version=\$(cat build.gradle|grep -w version |cut -d "=" -f2| awk \'\$1=\$1\'|sed \$\'s/\\'//g\')
                                    docker save -o ${ARTFACTS_PATH_SCANNER}/scanner-worker.tar.gz scanner-worker:\${tag_version}
                                """
                            }
                        }
		    }
		}
		stage ('load other images') {
	            steps {
		        script {
	                    sh """
		                docker pull registry.qingteng.cn/hivesec/hiveaudit:${params.hiveaudit_tag}
		                docker pull registry.qingteng.cn/hivesec/cluster-link:${params.cluster_link_tag}
		                docker pull registry.qingteng.cn/hivesec/hivesec-proxy:${params.hivesec_proxy_tag}
		                docker pull registry.qingteng.cn/hivesec/hive_agent_aarch64:${params.hive_agent_aarch64_tag}
		                docker pull registry.qingteng.cn/hivesec/hive_agent:${params.hive_agent_tag}
 
		                docker save -o ${ARTFACTS_PATH_HIVE}/hiveaudit.tar.gz registry.qingteng.cn/hivesec/hiveaudit:${params.hiveaudit_tag}
		                docker save -o ${ARTFACTS_PATH_HIVE}/cluster-link.tar.gz registry.qingteng.cn/hivesec/cluster-link:${params.cluster_link_tag}
		                docker save -o ${ARTFACTS_PATH_HIVE}/hivesec-proxy.tar.gz registry.qingteng.cn/hivesec/hivesec-proxy:${params.hivesec_proxy_tag}
		                docker save -o ${ARTFACTS_PATH_AGENT}/hive_agent_aarch64.tar.gz registry.qingteng.cn/hivesec/hive_agent_aarch64:${params.hive_agent_aarch64_tag}
		                docker save -o ${ARTFACTS_PATH_AGENT}/hive_agent.tar.gz registry.qingteng.cn/hivesec/hive_agent:${params.hive_agent_tag}
		            """
	                }
		    }
	        }
            }
	}
        stage('Upload') {
            steps {
                script {
		String packagename = "${ARTFACTS_PATH}/package/hive-images-${params.company}-v${params.version}-${BUILD_TIMESTAMP}.tar.gz"
                sh """
		   mkdir -p $ARTFACTS_PATH/package
		   cd  ${ARTFACTS_PATH}/${params.jobTag}
		   ls ${ARTFACTS_PATH}/${params.jobTag} | xargs tar -I pigz -cvf ${packagename}
                """
		}
            }
        }
    }
    post {
        success {
            emailext subject:"容器镜像自动打包构建成功 Build Number: ${BUILD_NUMBER}",
                to: env.NEW_STYLE_STANDALONE_BUILD_GROUP,
                mimeType: 'text/html',
                body: """
                    <h1 style="background:green;text-align:center">容器镜像自动打包构建成功!</h1>
                    <h2>构建信息</h2>
                    <ul>
                        <li>项目名称: ${JOB_NAME}
                        <li>构建编号: ${BUILD_NUMBER}
                        <li>构建详情：${BUILD_URL}
                        <li>构建日志：${BUILD_URL}/console
                        <li>构建包下载地址：${env.DOWNLOAD_URL}/hive-images-${params.company}-v${params.version}-${BUILD_TIMESTAMP}.tar.gz
                    </ul>

                    <h2>构建参数</h2>
		    ${formatParams(params)}
                """
        }
        failure {
            emailext subject:"独立部署自动打包构建失败 Build Number: ${BUILD_NUMBER}",
                to: env.NEW_STYLE_STANDALONE_BUILD_GROUP,
                mimeType: 'text/html',
                body: """
                    <h1 style="background:red;text-align:center">独立部署自动打包构建失败!</h1>
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
                """
        }
    }
}

/*
 * Find generated package file in the 'build' directory
 */
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
String allInOneTar(def params) {
    return "v${params.version}-${BUILD_TIMESTAMP}.tar.gz"
}
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
