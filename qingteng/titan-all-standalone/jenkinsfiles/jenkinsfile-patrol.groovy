import java.security.MessageDigest
import groovy.json.JsonOutput
import groovy.json.JsonSlurper

@NonCPS
Map<String, String> chooseBranchMap(String buildVariant) {
    def jsonSlurper = new JsonSlurper()
    def object = jsonSlurper.parseText(versionJson)
    String branchVariant = buildVariant == "release" ? "branchMap" : "testBranchMap"
    return object.get(branchVariant)
}

@NonCPS
String getBranch(String buildVariant, String artifact) {
    return chooseBranchMap(buildVariant)[artifact]
}

pipeline {
    agent any
    environment {
        ARTIFACT_PATH = "/data/workspace/artifacts/${BUILD_NUMBER}"
        JOB_BUILD_BASE = "${WORKSPACE}/build/job-${BUILD_NUMBER}"
        JOB_OUT = "${JOB_BUILD_BASE}/rel"
        GIT_URL = 'git@git.qingteng.cn:build/titan-all-standalone.git'
        TITAN_STANDALONE_GIT_URL = "ssh://jitang.hu@gerrit.qingteng.cn:29418/titan-standalone"
        RELEASE_PATH = "/data/workspace/release_package/"
    }
    stages {
        stage('Checkout') {
            steps {
                git branch: getBranch(params.buildVariant, "titanAllStandalone"), url: GIT_URL, credentialsId: '56ab2764-0e9c-40ef-b4aa-c16182485a84'
            }
        }
        stage('Prepare') {
            steps {
                echo "Parameters are $params"
                sh """
                    mkdir -p ${JOB_BUILD_BASE}/artifacts
                    mkdir -p ${JOB_OUT}
                    mkdir -p ${JOB_OUT}/revisions
                    mkdir -p ${JOB_BUILD_BASE}/rpmbuild
                """
            }
        }

        stage ('Build') {
            failFast true
	    parallel {
                stage('Patrol Build') {
                    steps{
                        build job: 'patrol-standalone-internal', parameters: [
                            string(name: 'version', value: params.version),
                            string(name: 'company', value: params.company),
                            string(name: 'titanAllStandalone', value: getBranch(params.buildVariant, "titanAllStandalone")),
                            string(name: 'jobTag', value: BUILD_NUMBER),
			    string(name: 'frontendBranch', value: getBranch(params.buildVariant, "frontend")),
                            string(name: 'branch', value: getBranch(params.buildVariant, "java"))
                        ]
                    }
                }
	    }
        }

	stage ('RPM Build') {
            failFast true
            parallel {
                stage("Patrol RPM Build") {
                    steps {
                        script {
                            String rpmBuildDir = "$JOB_BUILD_BASE/rpmbuild/patrol"
                            String specFile = "$WORKSPACE/rpmspec/patrol/qingteng-patrol.spec"

                            sh """
                                # prepare rpm build ingredients
                                mkdir -p ${rpmBuildDir}/pkg
                                cd ${rpmBuildDir}
                                pushd pkg
                                mkdir -p BUILD SOURCES SPECS SRPMS RPMS
                                cp ${ARTIFACT_PATH}/patrol/*.zip $rpmBuildDir/pkg/BUILD/patrol-srv.zip
                                cp ${specFile} SPECS
                                popd
                                
				rpmbuild \
				    --define "_topdir ${rpmBuildDir}/pkg" \
				    --define "_binary_payload w9.gzdio" \
                                    --define "upstream_version v${params.version}" \
                                    --define "upstream_release ${BUILD_TIMESTAMP}" \
                                    -bb pkg/SPECS/*.spec

                            """
                            // copy to rel folder
			    copyToReleaseDir(params)
                        }
                    }
                }
	    }
 	}

        stage("Push To VPN") {
            when {
                expression {return params.pushToVPN && params.buildVariant == "release"}
            }

            steps {
                script {
                    def packagesToPush = [
			patrolRpmPackage(params)
                    ]

                    packagesToPush.each {pkg -> 
                        sh "scp -P 22 ${pkg} huaqiao.long@123.59.41.43:/data/build/"
                    }
                }             
            }
        }
    }

    post {
        success {
            emailext subject:"Patrol自动打包构建成功 Build Number: ${BUILD_NUMBER}",
                to: env.NEW_STYLE_STANDALONE_BUILD_GROUP,
                mimeType: 'text/html',
                body: """
                    <h1 style="background:green;text-align:center">Patrol自动打包构建成功!</h1>
                    <h2>构建信息</h2>
                    <ul>
                        <li>项目名称: ${JOB_NAME}
                        <li>构建编号: ${BUILD_NUMBER}
                        <li>构建详情：${BUILD_URL}
                        <li>构建日志：${BUILD_URL}/console
                        <li>Patrol包下载地址：${env.JENKINS_URL}release/${getPatrolRpmNewFileName(params)}
                    </ul>

                    <h2>构建参数</h2>
                    ${formatParams(params)}

                    <h2>构建分支</h2>
                    ${formatParams(chooseBranchMap(params.buildVariant))}
                """
        }
        failure {
            emailext subject:"Patrol自动打包构建失败 Build Number: ${BUILD_NUMBER}",
                to: env.NEW_STYLE_STANDALONE_BUILD_GROUP,
                mimeType: 'text/html',
                body: """
                    <h1 style="background:red;text-align:center">Patrol自动打包构建失败!</h1>
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
                    ${formatParams(chooseBranchMap(params.buildVariant))}
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
String getPatrolRpmNewFileName(def params) {
	return "titan-patrol-srv-${params.company}-v${params.version}-${BUILD_TIMESTAMP}.x86_64.rpm"
}

@NonCPS
void copyToReleaseDir(def params) {
	println "copy patrol rpm to ${RELEASE_PATH}"
	sh(script: "cp ${JOB_BUILD_BASE}/rpmbuild/patrol/pkg/RPMS/x86_64/titan-patrol-srv-v${params.version}-${BUILD_TIMESTAMP}.x86_64.rpm ${RELEASE_PATH}${getPatrolRpmNewFileName(params)}")
}

@NonCPS
String patrolRpmPackage(def params) {
	return "${RELEASE_PATH}${getPatrolRpmNewFileName(params)}"
}
