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
        APP_PACKAGE_NAME = "${params.name}-${params.buildVariant}-full-${params.company}-v${params.version}-${BUILD_TIMESTAMP}.tar.gz"
        SYSINFO_NAME = "sysinfo_${params.company}_v${params.version}"
        RELEASE_PATH = "/data/workspace/release/"
        PRE_RULE_PATH = "/data/qtrules/"
    }
    stages {
        stage('Checkout') {
            steps {
                dir ("titan-all-standalone"){
                    git branch: getBranch(params.buildVariant, "titanAllStandalone"), url: GIT_URL, credentialsId: '56ab2764-0e9c-40ef-b4aa-c16182485a84'
                    dir ("titan-standalone") {
                    git branch: getBranch(params.buildVariant, "app"), url: TITAN_STANDALONE_GIT_URL
		    // 下面checkout的方式可以设置timeout，git默认10分钟超时，有时候项目过大fetch时间有可能超过10分钟
		    //checkout([$class: 'GitSCM', branches: [[name: getBranch(params.buildVariant, "app")]], doGenerateSubmoduleConfigurations: false, extensions: [[$class: 'CheckoutOption', timeout: 120],[$class: 'CloneOption', timeout: 120]], submoduleCfg: [], userRemoteConfigs: [[url: TITAN_STANDALONE_GIT_URL]]])
                    }
                }
//                dir ("titan-standalone") {
//                    git branch: getBranch(params.buildVariant, "app"), url: TITAN_STANDALONE_GIT_URL
		    // 下面checkout的方式可以设置timeout，git默认10分钟超时，有时候项目过大fetch时间有可能超过10分钟
		    //checkout([$class: 'GitSCM', branches: [[name: getBranch(params.buildVariant, "app")]], doGenerateSubmoduleConfigurations: false, extensions: [[$class: 'CheckoutOption', timeout: 120],[$class: 'CloneOption', timeout: 120]], submoduleCfg: [], userRemoteConfigs: [[url: TITAN_STANDALONE_GIT_URL]]])
//                }
                script {
                    echo "${allInOnePatchTarByVersion(getBranch(params.buildVariant, 'appBasic'), 'el6', params)}"
                }
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
                stage('PHP Build') {
                    steps{
                        build job: 'php-standalone', parameters: [
                            string(name: 'version', value: params.version),
                            string(name: 'company', value: params.company),
                            string(name: 'titanAllStandalone', value: getBranch(params.buildVariant, "titanAllStandalone")),
                            string(name: 'jobTag', value: BUILD_NUMBER),
                            string(name: 'branch', value: getBranch(params.buildVariant, "php"))
                        ]
                    }
                }
		stage('images build'){
		    when {
                        expression {params.version =~ "3.4.1.1"}
                    }

		    steps{
                        build job: 'java-docker-standalone', parameters: [
                            string(name: 'version', value: params.version),
                            string(name: 'company', value: params.company),
                            string(name: 'titanAllStandalone', value: getBranch(params.buildVariant, "titanAllStandalone")),
                            string(name: 'jobTag', value: BUILD_NUMBER),
                            string(name: 'branch', value: getBranch(params.buildVariant, "scanner")),
			    string(name: 'hive_agent_tag', value: params.hive_agent_tag),
                            string(name: 'hive_agent_aarch64_tag', value: params.hive_agent_aarch64_tag),
                            string(name: 'scanner_worker_tag', value: getBranch(params.buildVariant, "scanner-worker")),
                            string(name: 'hiveaudit_tag', value: getBranch(params.buildVariant, "hiveaudit")),
                            string(name: 'cluster_link_tag', value: getBranch(params.buildVariant, "cluster-link")),
                            string(name: 'hivesec_proxy_tag', value: getBranch(params.buildVariant, "hivesec-proxy"))
                        ]
		    }
		}

                //stage('Frontend Build') {
                //    steps{
                //        build job: 'frontend-standalone', parameters: [
                //           string(name: 'version', value: params.version),
                //            string(name: 'company', value: params.company),
                //            string(name: 'titanAllStandalone', value: getBranch(params.buildVariant, "titanAllStandalone")),
                //           string(name: 'jobTag', value: BUILD_NUMBER),
                //            string(name: 'branch', value: getBranch(params.buildVariant, "frontend"))
                //        ]
                //    }
                //}
		stage('Frontend Build') {
                    agent { label 'jenkins-slave-frontend2' }
                    environment {
                        GIT_URL = "ssh://yan.zheng@gerrit.qingteng.cn:29418/titan-frontend"
                        ARTFACTS_SERVER = "172.16.6.111"
                        ARTFACTS_PATH = "/data/workspace/artifacts/${env.BUILD_NUMBER}/frontend/"
                        ARTFACTS_URL = "jenkins@${ARTFACTS_SERVER}:${ARTFACTS_PATH}"
                        OUTDIR = "frontend-standalone-v${version}-${BUILD_TAG}"
                        FRONTEND_BRANCH = getBranch(params.buildVariant, "frontend")
                    }
                    stages {
                        stage('Prepare Frontend') {
                            steps {
                                echo "Parameters are $params"

                                sh "ssh jenkins@${ARTFACTS_SERVER} mkdir -p ${ARTFACTS_PATH}"
                            }
                        }
                        stage('Frontend Build Job') {
                            steps{
                                build job: 'frontend-standalone-onlinux', parameters: [
                                string(name: 'type', value: "standalone"),
                                string(name: 'branch', value: "origin/${FRONTEND_BRANCH}"),
                                string(name: 'tag', value: params.company)
                                ]
                            }
                        }
                        stage('Upload Frontend') {
                            steps {
                                script {
                                    sh '''
                                        zipfile=`ls -t /data/frontend/workspace/frontend-standalone-onlinux/frontend*.zip | head -1`

                                        echo "Uploading ${zipfile} to $ARTFACTS_URL"
                                        scp \$zipfile $ARTFACTS_URL

                                        echo "Record revision and upload"
                                        cd /data/frontend/workspace/frontend-standalone-onlinux/
                                        git rev-parse --short HEAD > /data/frontend/workspace/frontend-standalone-onlinux/frontend-revision
                                        scp /data/frontend/workspace/frontend-standalone-onlinux/frontend-revision ${ARTFACTS_URL}
                                    '''
                                    }
                                }
                            }
                        }
                    }

                stage('Java Build') {
                    steps{
                        build job: 'java-standalone', parameters: [
                            string(name: 'version', value: params.version),
                            string(name: 'company', value: params.company),
                            string(name: 'titanAllStandalone', value: getBranch(params.buildVariant, "titanAllStandalone")),
                            string(name: 'jobTag', value: BUILD_NUMBER),
                            string(name: 'frontendBranch', value: getBranch(params.buildVariant, "frontend")),
                            string(name: 'branch', value: getBranch(params.buildVariant, "java"))
                        ]
                    }
                }

                stage('BigData Build') {
                    steps {
                        build job: 'bigdata-standalone', parameters: [
                            string(name: 'version', value: params.version),
                            string(name: 'company', value: params.company),
                            string(name: 'titanAllStandalone', value: getBranch(params.buildVariant, "titanAllStandalone")),
                            string(name: 'jobTag', value: BUILD_NUMBER),
                            string(name: 'branch', value: getBranch(params.buildVariant, "bigdata"))
                        ]
                    }
                }
            }
        }

        stage ('RPM Build') {
            failFast true
            parallel {
                stage("BigData RPM Build") {
                    steps {
                        script {
                            String artifactsDir = "$JOB_BUILD_BASE/artifacts/bigdata"
                            String rpmBuildDir = "$JOB_BUILD_BASE/rpmbuild/bigdata"
                            String specFileConsuemer = "$WORKSPACE/rpmspec/bigdata/qingteng-consumer.spec"
			                String specFileViewer = "$WORKSPACE/rpmspec/bigdata/qingteng-viewer.spec"

                            sh """
                                # pull artifaces from remote server
                                mkdir -p ${artifactsDir}
                                cp ${ARTIFACT_PATH}/bigdata/*.tgz ${artifactsDir}

                                # prepare rpm build ingredients
				# build consumer rpm
                                mkdir -p ${rpmBuildDir}/consumer/pkg
                                cd ${rpmBuildDir}/consumer
                                pushd pkg
                                mkdir -p BUILD SOURCES SPECS SRPMS RPMS
                                tar -I pigz -xvf ${artifactsDir}/qingteng-consumer*.tgz -C BUILD
                                cp ${specFileConsuemer} SPECS
                                cp ${WORKSPACE}/qingteng-consumer SOURCES
                                popd

                                rpmbuild \
                                    --define "_topdir ${rpmBuildDir}/consumer/pkg" \
                                    --define "upstream_version v${params.version}" \
                                    --define "upstream_release ${BUILD_TIMESTAMP}" \
                                    -bb pkg/SPECS/*.spec

			    #build viewer rpm
                                mkdir -p ${rpmBuildDir}/viewer/pkg
                                cd ${rpmBuildDir}/viewer
                                pushd pkg
                                mkdir -p BUILD SOURCES SPECS SRPMS RPMS
                                tar -I pigz -xvf ${artifactsDir}/qingteng-viewer*.tgz -C BUILD
                                cp ${specFileViewer} SPECS
                                cp ${WORKSPACE}/qingteng-viewer SOURCES
                                popd

                                rpmbuild \
                                    --define "_topdir ${rpmBuildDir}/viewer/pkg" \
                                    --define "upstream_version v${params.version}" \
                                    --define "upstream_release ${BUILD_TIMESTAMP}" \
                                    -bb pkg/SPECS/*.spec


                                # copy to rel folder
                                cp ${rpmBuildDir}/consumer/pkg/RPMS/x86_64/*.rpm ${JOB_OUT}
                                cp ${rpmBuildDir}/viewer/pkg/RPMS/x86_64/*.rpm ${JOB_OUT}
                                cp ${ARTIFACT_PATH}/bigdata/bigdata-revision ${JOB_OUT}/revisions/consumer-revision
								cp ${ARTIFACT_PATH}/bigdata/bigdata-revision ${JOB_OUT}/revisions/viewer-revision

				# append qingteng-consumer qingteng-viewer qingteng-bigdata.spec md5 to bigdata-revision
				                # consumer-revision
                                cd $WORKSPACE && md5sum qingteng-consumer rpmspec/bigdata/qingteng-consumer.spec | sed -r 's/(.{5}).*/\\1/g' >> $JOB_OUT/revisions/consumer-revision
								md5sum ${JOB_OUT}/revisions/consumer-revision | sed -r 's/(.{7}).*/\\1/g' > consumer-revision.tmp
								cat consumer-revision.tmp > ${JOB_OUT}/revisions/consumer-revision
								rm consumer-revision.tmp
								# viewer-revision
								cd $WORKSPACE && md5sum qingteng-viewer  rpmspec/bigdata/qingteng-viewer.spec | sed -r 's/(.{5}).*/\\1/g' >> $JOB_OUT/revisions/viewer-revision
								md5sum ${JOB_OUT}/revisions/viewer-revision | sed -r 's/(.{7}).*/\\1/g' > viewer-revision.tmp
								cat viewer-revision.tmp > ${JOB_OUT}/revisions/viewer-revision
								rm viewer-revision.tmp
                            """
                        }
                    }
                }

                stage('PHP & Frontend RPM Build') {
                    steps {
                        script {
                            String phpArtifactsDir = "$JOB_BUILD_BASE/artifacts/php"
                            String frontendArtifactsDir = "$JOB_BUILD_BASE/artifacts/frontend"
                            String rpmBuildDir = "$JOB_BUILD_BASE/rpmbuild/php"


                            File specFile = new File("$WORKSPACE/rpmspec/php/titan-web.spec")

                            sh """
                                mkdir -p $phpArtifactsDir
                                mkdir -p $frontendArtifactsDir

                                # pull artifacts from remote server
                                cp ${ARTIFACT_PATH}/php/*.zip $phpArtifactsDir
                                cp ${ARTIFACT_PATH}/frontend/*.zip $frontendArtifactsDir

                                # unzip php and frontend packages
                                pushd $phpArtifactsDir
                                unzip *.zip -d uncompressed
                                popd

                                pushd $frontendArtifactsDir
                                unzip *.zip -d uncompressed
                                popd

                                # create rpm build directory structure and prepare files
                                mkdir -p $rpmBuildDir/pkg
                                pushd $rpmBuildDir

                                pushd pkg
                                mkdir -p BUILD SOURCES SPECS SRPMS RPMS

                                cp -Rf $phpArtifactsDir/uncompressed/web-ins/titan-web BUILD/
                                cp -Rf $frontendArtifactsDir/uncompressed BUILD/titan-frontend

                                mkdir BUILD/titan-web/config_scripts
                                cp -Rf ${WORKSPACE}/titan-standalone/scripts/* BUILD/titan-web/config_scripts/
                                cp ${specFile} SPECS/

                                cat ${WORKSPACE}/supervisor.init > SOURCES/supervisor
                                popd  # back to $rpmBuildDir

                                rpmbuild \
                                    --define '_topdir $rpmBuildDir/pkg' \
                                    --define 'upstream_version v${params.version}' \
                                    --define 'upstream_release ${BUILD_TIMESTAMP}' \
                                    -bb $rpmBuildDir/pkg/SPECS/titan*.spec

                                # copy to rel folder
                                mkdir -p ${JOB_OUT}
                                cp $rpmBuildDir/pkg/RPMS/x86_64/*.rpm ${JOB_OUT}
				
                                # copy revisions
                                cp ${ARTIFACT_PATH}/php/php-revision ${JOB_OUT}/revisions
                                cp ${ARTIFACT_PATH}/frontend/frontend-revision ${JOB_OUT}/revisions

				# frontend and php are in one rpm, append frontend-revision to php-revesion
				cat ${ARTIFACT_PATH}/frontend/frontend-revision >> ${JOB_OUT}/revisions/php-revision

				# append titan-web.spec md5sum to php-revision
				md5sum ${specFile} | sed -r 's/(.{5}).*/\\1/g' >> ${JOB_OUT}/revisions/php-revision

				# append titan-standalone/scripts dir commit log to php-revision
				cd ${WORKSPACE}/titan-standalone && git log -n 1 --abbrev-commit scripts/ | head -n 1 | cut -d ' ' -f 2 >> $JOB_OUT/revisions/php-revision
				md5sum ${JOB_OUT}/revisions/php-revision | sed -r 's/(.{7}).*/\\1/g' > php-revision.tmp
                                cat php-revision.tmp > ${JOB_OUT}/revisions/php-revision
                                rm php-revision.tmp                            
			    """
                        }
                    }
                }

                stage('Agent RPM Build') {
                    steps {
                        script {
                            String rpmBuildDir = "$JOB_BUILD_BASE/rpmbuild/agent"
                            String agent_pkg_vsn = (linux_agent_version =~ /.*v((\d\.*)+)/)[0][1]
			    String specFile = "${WORKSPACE}/rpmspec/agent/titan-agent.spec"

                            sh "mkdir -p ${rpmBuildDir}"
                            dir (rpmBuildDir) {
                                 script {
                                    if (params.buildVariant == "test") {
                                        if (aix_agent_vsn?.trim() && solaris_x86_agent_vsn?.trim() && solaris_sparc_agent_vsn?.trim() && arm_aarch64_agent_vsn?.trim()) {
                                            sh "${WORKSPACE}/rsync_agent_test.sh v3 ${linux_agent_version} ${windows_agent_version} ${aix_agent_vsn} ${solaris_x86_agent_vsn} ${solaris_sparc_agent_vsn} aarch64/${arm_aarch64_agent_vsn}"
                                        } else if (aix_agent_vsn?.trim() && solaris_x86_agent_vsn?.trim() && solaris_sparc_agent_vsn?.trim()) {
                                            sh "${WORKSPACE}/rsync_agent_test.sh v3 ${linux_agent_version} ${windows_agent_version} ${aix_agent_vsn} ${solaris_x86_agent_vsn} ${solaris_sparc_agent_vsn}"
                                        } else if (arm_aarch64_agent_vsn?.trim()) {
                                            sh "${WORKSPACE}/rsync_agent_test.sh v3 ${linux_agent_version} ${windows_agent_version} aarch64/${arm_aarch64_agent_vsn}"
                                        } else {
                                            sh "${WORKSPACE}/rsync_agent_test.sh v3 ${linux_agent_version} ${windows_agent_version}"
                                        }

                                    } else {
                                        if (aix_agent_vsn?.trim() && solaris_x86_agent_vsn?.trim() && solaris_sparc_agent_vsn?.trim()&& arm_aarch64_agent_vsn?.trim()) {
                                            sh "${WORKSPACE}/rsync_agent.sh v3 ${linux_agent_version} ${windows_agent_version} ${aix_agent_vsn} ${solaris_x86_agent_vsn} ${solaris_sparc_agent_vsn} aarch64/${arm_aarch64_agent_vsn}"
                                        } else if (aix_agent_vsn?.trim() && solaris_x86_agent_vsn?.trim() && solaris_sparc_agent_vsn?.trim()) {
                                            sh "${WORKSPACE}/rsync_agent.sh v3 ${linux_agent_version} ${windows_agent_version} ${aix_agent_vsn} ${solaris_x86_agent_vsn} ${solaris_sparc_agent_vsn}"
                                        } else if (arm_aarch64_agent_vsn?.trim()) {
                                            sh "${WORKSPACE}/rsync_agent.sh v3 ${linux_agent_version} ${windows_agent_version} aarch64/${arm_aarch64_agent_vsn}"
                                        } else {
                                            sh "${WORKSPACE}/rsync_agent.sh v3 ${linux_agent_version} ${windows_agent_version}"
                                        }
                                    }

				
                                    sh """
                                        mkdir pkg

                                        pushd pkg
                                        mkdir -p BUILD SOURCES SPECS SRPMS RPMS
                                        mkdir BUILD/www
                                        popd

                                        cp -Rf ${rpmBuildDir}/agent_files/www/* ${rpmBuildDir}/pkg/BUILD/www
                                        cp ${specFile} ${rpmBuildDir}/pkg/SPECS/

                                        pushd ${rpmBuildDir}/pkg
                                        rpmbuild --define '_topdir ${rpmBuildDir}/pkg' \
                                                --define 'upstream_version ${agent_pkg_vsn}' \
                                                --define 'upstream_release ${BUILD_TIMESTAMP}' \
                                                -bb SPECS/titan-agent.spec

                                        popd

                                        mv ${rpmBuildDir}/pkg/RPMS/*/*.rpm ${JOB_OUT}

					# md5sum script.zip as revision
					find ${rpmBuildDir}/pkg | grep script | xargs md5sum | sed -r 's/(.....).*/\\1/g' >> ${JOB_OUT}/revisions/agent-revision
					# append titan-agent.spec md5sum to revision
					md5sum ${specFile} | sed -r 's/(.{5}).*/\\1/g' >> ${JOB_OUT}/revisions/agent-revision
					md5sum ${JOB_OUT}/revisions/agent-revision | sed -r 's/(.{7}).*/\\1/g' > agent-revision.tmp
                                	cat agent-revision.tmp > ${JOB_OUT}/revisions/agent-revision
                                	rm agent-revision.tmp
                                    """
                                }
                            }
                        }
                    }
                }

                stage("Java RPM Build") {
                    steps {
                        script {
                            String artifactsDir = "$JOB_BUILD_BASE/artifacts/java"
                            String rpmBuildDir = "$JOB_BUILD_BASE/rpmbuild/java"
                            String specFile = "${WORKSPACE}/rpmspec/java/titan-wisteria.spec"

                            sh """
                                # pull artifaces from remote server
                                mkdir -p $artifactsDir
                                cp $ARTIFACT_PATH/java/* $artifactsDir

                                # prepare rpm build ingredients
                                mkdir -p $rpmBuildDir/pkg
                                cd $rpmBuildDir
                                pushd pkg
                                mkdir -p BUILD SOURCES SPECS SRPMS RPMS
                                cp $artifactsDir/*.zip $rpmBuildDir/pkg/BUILD/titan-wisteria.zip
                                cp ${specFile} $rpmBuildDir/pkg/SPECS/
                                popd

                                # build rpm package
                                rpmbuild \
                                    --define '_topdir $rpmBuildDir/pkg' \
                                    --define 'upstream_version v${params.version}' \
                                    --define 'upstream_release ${BUILD_TIMESTAMP}' \
                                    -bb $rpmBuildDir/pkg/SPECS/titan*.spec

                                # copy to rel folder
                                cp $rpmBuildDir/pkg/RPMS/x86_64/*.rpm ${JOB_OUT}

                                #copy revisions
                                cp ${ARTIFACT_PATH}/java/java-revision ${JOB_OUT}/revisions
				
				# append titan-wisteria.spec md5sum to java-revision
				md5sum ${specFile} | sed -r 's/(.{5}).*/\\1/g' >> ${JOB_OUT}/revisions/java-revision
				md5sum ${JOB_OUT}/revisions/java-revision | sed -r 's/(.{7}).*/\\1/g' > java-revision.tmp
                                cat java-revision.tmp > ${JOB_OUT}/revisions/java-revision
                                rm java-revision.tmp

                                #copy sysinfo
                                cp ${ARTIFACT_PATH}/java/sysinfo ${JOB_OUT}/${SYSINFO_NAME}
                            """
                        }
                    }
                }
            }
        }

        stage('Build App Package') {
            steps {
                dir("${JOB_OUT}") {
                    sh "mkdir -p titan-app/common && mv *.rpm titan-app/common"
                            
                    dir ("titan-app") {
                        script {
                            File base = new File("${JOB_OUT}/titan-app")

                            def revisionMap = collectRevisions(new File ("${JOB_OUT}/revisions"))
                            new File(base, "version.json") << collectRpmVersions(new File(base, "common"), params.version, BUILD_TIMESTAMP, revisionMap)

                            sh "cp -r ${WORKSPACE}/titan-standalone/titan-app/* ${base}"
                        }
                    }

                    script {
                        String rulePackage = sh(script: "${WORKSPACE}/find_pre_rule.sh ${PRE_RULE_PATH} ${params.company} ${params.version}", returnStdout: true).trim()
                        if (rulePackage != null && !rulePackage.equals("")) {
                            sh "cp ${PRE_RULE_PATH}/${rulePackage} titan-app/common/"
                        }

                        sh "tar -I pigz -cvf ${APP_PACKAGE_NAME} titan-app"
                    }
                }
            }
        }

        stage('Build Final Package') {
            steps {
                dir("${JOB_OUT}") {
                    script {
                        File appPackage = new File("${JOB_OUT}/${APP_PACKAGE_NAME}")
                        String baseRecordFilename = "${getBranch(params.buildVariant, "appBasic")}-${params.buildVariant}"
			//if (params.company != "common" && new File("${RELEASE_PATH}/app_base_packages/${baseRecordFilename}-custom").exists()) {
			//	baseRecordFilename += "-custom"
			//}
                        File appBasePackage;
                        File appBaseRoot = new File("${RELEASE_PATH}/app_base_packages")

                        if (params.markAsBase) { // Create a new full package
                            // Copy to app base repository and write the name to the record file
                            sh "cp ${appPackage} ${appBaseRoot.path}"

                            appBasePackage = new File(appBaseRoot, appPackage.name)

                            String appBaseRecord = "${baseRecordFilename}"
                            sh "echo ${appBasePackage.name} > ${RELEASE_PATH}/app_base_packages/${appBaseRecord}"
                        } else { // Create a package with patch
                            appBasePackage = new File(appBaseRoot, new File("${RELEASE_PATH}/app_base_packages/${baseRecordFilename}").text.trim())
                        }

                        // Make app patch
                        sh """
                            mkdir app_patch
                            pushd /data/diff
                            /data/diff/parallel_diff_app.sh ${appBasePackage.path} ${appPackage.path} ${JOB_OUT}/app_patch
                            popd
                            mv app_patch/*_${appPackage.name} app_patch/patch_app.tar.gz
                        """

                        // trim version from form a.b.c.d to a.b.c
       
                        String basicEl6 = findBaseBasicPackage(getBranch(params.buildVariant, "baseVersion"), 'el6')
                        String basicEl7 = findBaseBasicPackage(getBranch(params.buildVariant, "baseVersion"), 'el7')
                        echo "Find el6 base package: ${basicEl6}"
                        echo "Find el7 base package: ${basicEl7}"

                        def basePackageMap = [el6: basicEl6, el7: basicEl7]

                        // Make final packages for el6 and el7
                        basePackageMap.each{el, base ->
                            String packagePath = "${JOB_OUT}/${allInOneTar(el, params)}"
                            String patchPath = "${JOB_OUT}/${allInOnePatchTar(appBasePackage.name, el, params)}"

                            sh """
                                mkdir ${JOB_OUT}/${el}

                                tar -I pigz -xvf ${base} -C ${JOB_OUT}/${el}
				if [ -f ${JOB_OUT}/app_patch/${appBasePackage.name} ]; then
                                	ls ${JOB_OUT}/${el} | tr '\n' ' ' | xargs tar -I pigz -cvf ${packagePath} -C ${JOB_OUT}/app_patch/ patch_app.tar.gz ${appBasePackage.name} -C /data/patch/ patch_all.sh patch_app.sh xdelta3 -C ${JOB_OUT}/${el}/
				else
                                	ls ${JOB_OUT}/${el} | tr '\n' ' ' | xargs tar -I pigz -cvf ${packagePath} -C ${appBaseRoot.path} ${appBasePackage.name} -C ${JOB_OUT}/app_patch/ patch_app.tar.gz -C /data/patch/ patch_all.sh patch_app.sh xdelta3 -C ${JOB_OUT}/${el}/
				fi
                                tar -I pigz -cvf ${patchPath} -C ${JOB_OUT}/app_patch/ patch_app.tar.gz -C /data/patch/ patch_all.sh patch_app.sh xdelta3 -C ${JOB_OUT}/${el}/ patch_base.tar.gz patch_base.sh
                                if [[ \$? -eq 0 ]]; then
                                    mv ${packagePath} /data/workspace/release_package/
                                    mv ${patchPath} /data/workspace/release_package/
                                fi
                            """
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
                        allInOneTar('el6', params),
                        allInOneTar('el7', params),
                        allInOnePatchTarByVersion(getBranch(params.buildVariant, 'appBasic'), 'el6', params),
                        allInOnePatchTarByVersion(getBranch(params.buildVariant, 'appBasic'), 'el7', params)
                    ]

                    packagesToPush.each {pkg -> 
                        sh "cd /data/workspace/release_package/ && scp -P 22 ${pkg} huaqiao.long@123.59.41.43:/data/build/"
                    }
                }             
            }
        }
        
        stage("upload sysinfo via ftp") {
            steps {
                dir("${JOB_OUT}") {
                ftpPublisher alwaysPublishFromMaster: false, continueOnError: false, failOnError: false, masterNodeName: '', paramPublish: null, publishers: [
    [configName: 'upload agent gate srv(123.59.54.87)', transfers: [
        [asciiMode: false, cleanRemote: false, excludes: '', flatten: false, makeEmptyDirs: false, noDefaultExcludes: false, patternSeparator: '[, ]+', remoteDirectory: '/titan-agent/tools/sysinfo/x86_64', remoteDirectorySDF: false, removePrefix: '', sourceFiles: 'sysinfo_*']
    ], usePromotionTimestamp: false, useWorkspaceInPromotion: false, verbose: false]
]
                }
            }

        }    

        stage("Deploy") {
            when {
                expression {return params.auto_deploy}
            }

            steps {
                build job: 'deploy_standalone_test', parameters: [
                    string(name: 'standalone_package', value: allInOneTar('el7', params)),
                ]
            }
        }
    }

    post {
        success {
            emailext subject:"独立部署自动打包构建成功 Build Number: ${BUILD_NUMBER}",
                to: env.NEW_STYLE_STANDALONE_BUILD_GROUP,
                mimeType: 'text/html',
                body: """
                    <h1 style="background:green;text-align:center">独立部署自动打包构建成功!</h1>
                    <h2>构建信息</h2>
                    <ul>
                        <li>项目名称: ${JOB_NAME}
                        <li>构建编号: ${BUILD_NUMBER}
                        <li>构建详情：${BUILD_URL}
                        <li>构建日志：${BUILD_URL}/console
                        <li>el6构建包下载地址：${env.JENKINS_URL}release/${allInOneTar('el6', params)} （<font color='red'>${getFileSize('/data/workspace/release_package/' + allInOneTar('el6', params))}</font>）
                        <li>el7构建包下载地址：${env.JENKINS_URL}release/${allInOneTar('el7', params)} （<font color='red'>${getFileSize('/data/workspace/release_package/' + allInOneTar('el7', params))}</font>）
                        <li>el6补丁包下载地址：${env.JENKINS_URL}release/${allInOnePatchTarByVersion(getBranch(params.buildVariant, 'appBasic'), 'el6', params)} （<font color='red'>${getFileSize('/data/workspace/release_package/' + allInOnePatchTarByVersion(getBranch(params.buildVariant, 'appBasic'), 'el6', params))}</font>）
                        <li>el7补丁包下载地址：${env.JENKINS_URL}release/${allInOnePatchTarByVersion(getBranch(params.buildVariant, 'appBasic'), 'el7', params)} （<font color='red'>${getFileSize('/data/workspace/release_package/' + allInOnePatchTarByVersion(getBranch(params.buildVariant, 'appBasic'), 'el7', params))}</font>）
                    </ul>

                    <h2>构建参数</h2>
                    ${formatParams(params)}

                    <h2>构建分支</h2>
                    ${formatParams(chooseBranchMap(params.buildVariant))}
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
String allInOneTar(String el, def params) {
    return "${el}-${params.buildVariant}-${params.company}-v${params.version}-${BUILD_TIMESTAMP}.tar.gz"
}

@NonCPS
String allInOnePatchTar(String basicApp, String el, def params) {
    return basicApp.replace(".tar.gz", "").replace("titan-app-rhel", el).replace("-full", "") + "_" + allInOneTar(el, params)
}

@NonCPS
String allInOnePatchTarByVersion(String appBasicVersion, String el, def params) {
    if (params.markAsBase) {
        return ""
    }
    File appPackage = new File("${JOB_OUT}/${APP_PACKAGE_NAME}")
    String baseRecordFilename = "${appBasicVersion}-${params.buildVariant}"
    File appBaseRoot = new File("${RELEASE_PATH}/app_base_packages")
    String basicApp = new File(appBaseRoot, new File("${RELEASE_PATH}/app_base_packages/${baseRecordFilename}").text.trim()).getName()
    return allInOnePatchTar(basicApp, el, params)
}

String findBaseBasicPackage(String baseVersion, String osVersion) {
    println "Base version is ${baseVersion}"
    result = sh(script: "${WORKSPACE}/find_base_pkg.sh ${RELEASE_PATH} ${buildVariant} ${osVersion} ${baseVersion}", returnStdout: true).trim()
    return result
}

@NonCPS
String getFileSize(String file) {
    File f = new File(file)
    long size = f.length()
    return (int)(size / 1024 / 1024) + "M"
}


@NonCPS
Map<String, String> collectRevisions(File revisionDir) {
    Map<String, String> revisionMap = [:]

    File[] revisionFiles = revisionDir.listFiles((FilenameFilter){File _, String name -> name.endsWith("-revision")})

    def pattern = ~/(?<name>\w+)-revision/

    revisionFiles.each {
        def m = it.name =~ pattern

        if (m.find()) {
            revisionMap[m.group("name")] = it.text.trim()
        }
    }

    // some of these rpms are parts of java, use the same version
    revisionMap['patrol-srv'] = revisionMap['java']
    revisionMap['scan-srv'] = revisionMap['java']
    revisionMap['connect-agent'] = revisionMap['java']
    revisionMap['connect-sh'] = revisionMap['java']
    revisionMap['connect-dh'] = revisionMap['java']
    revisionMap['connect-selector'] = revisionMap['java']
    revisionMap['agent'] = revisionMap['agent']

    return revisionMap
}

/**
 * Collect all the rpm files and parse name and version from them
 */
@NonCPS
String collectRpmVersions(File rpmDir, String version, String buildTs, Map<String, String> revisionMap) {
    Map<String, String> rpmPatterns = [
        /(?<name>titan-wisteria)-v?(?<version>(\d+\.)+\d+)/: 'java',
        /(?<name>titan-patrol-srv)-v?(?<version>(\d+\.)+\d+)/: 'patrol-srv',
        /(?<name>titan-scan-srv)-v?(?<version>(\d+\.)+\d+)/: 'scan-srv',
        /(?<name>titan-web)-v?(?<version>(\d+\.)+\d+)/: 'php',
        /(?<name>titan-agent)-v?(?<version>(\d+\.)+\d+)/: 'agent',
        /(?<name>titan-connect-sh)-v?(?<version>(\d+\.)+\d+)/: 'connect-sh',
        /(?<name>titan-connect-dh)-v?(?<version>(\d+\.)+\d+)/: 'connect-dh',
        /(?<name>titan-connect-agent)-v?(?<version>(\d+\.)+\d+)/: 'connect-agent',
        /(?<name>titan-connect-selector)-v?(?<version>(\d+\.)+\d+)/: 'connect-selector',
        /(?<name>qingteng-consumer)-v?(?<version>(\d+\.)+\d+)/: 'consumer',
		/(?<name>qingteng-viewer)-v?(?<version>(\d+\.)+\d+)/: 'viewer',
    ]

    def rpmVersionMap = [version: "v${version}_${buildTs}"]

    String[] rpmFiles = rpmDir.list((FilenameFilter){File dir, String name -> name.endsWith(".rpm")})
    rpmFiles.each { rpmFile ->
        rpmPatterns.each {key, value ->
            def m = rpmFile =~ key
            if (m) {
                String revision = revisionMap[value]
		if (!revision?.trim()) {
                    rpmVersionMap[m.group("name")] = m.group("version")
		} else {
                    rpmVersionMap[m.group("name")] = m.group("version") + "-${revision}"
		}
            }
        }
    }

    return JsonOutput.toJson(rpmVersionMap)

}

String titanStandaloneBranch(String baseDir, String version, String company) {
    String branch = "master-v${version}"
    if (company == "common") {
        return branch
    }

    String companyBranch = "${company}-${version}"
    result = sh(script: "cd ${WORKSPACE}/${baseDir} && git branch -a", returnStdout: true)

    if (result == null || !result.contains(companyBranch)) {
        companyBranch = branch
    }
    

    return companyBranch
}

/**
 * Convert version to a normalized format, e.g 3.2.0.2 goes to 003.002.000.002.000
 */
@NonCPS
String normalizeVersion(String version) {
    final int NORMALIZED_VERSION_PARTS = 5;

    if (version.startsWith("v")) {
        version = version[1..-1]
    }

    String[] parts = version.split(/\./)

    parts.eachWithIndex { String entry, int i ->
        if (entry.size() > 3) {
            throw new RuntimeException("Invalid version $version, one of the parts is longer than 3")
        }

        if (entry.size() < 3) {
            entry = "0" * (3 - entry.size()) + entry
        }

        parts[i] = entry
    }

    String[] newParts = new String[NORMALIZED_VERSION_PARTS]

    newParts.eachWithIndex { String entry, int i ->
        newParts[i] = i < parts.size() ? parts[i] : "000"
    }


    return newParts.join(".")
}
