
node('container') {
    def version = params.tag.split("-")[0]
    def company = params.tag.split("-")[1]

    currentBuild.displayName = "${BUILD_NUMBER}-${version}-${company}"
    
    String CREDENTIALS_ID = '56ab2764-0e9c-40ef-b4aa-c16182485a84'
    String TITAN_CONTAINER_GIT_URL = 'git@git.qingteng.cn:build/titan-container.git'

    String REGISTRY = 'registry.qingteng.cn/titan-container'

    echo "begin: ${WORKSPACE}"
    sh '''
        rm -rf build/dist && mkdir -p build/dist
    '''

    echo "params: ${params}"
    String versionBranch = "${version}-${company}"
    git branch: versionBranch, credentialsId: CREDENTIALS_ID, url: TITAN_CONTAINER_GIT_URL

    def services = params.services.split(",")
    def patchImages = []
    for(srv in services) {
        def rImage = "${REGISTRY}/${srv}:${params.tag}"
        patchImages.add(rImage) 
        sh  """ 
            docker pull ${rImage}
            echo ${rImage} >> build/dist/patchImages; 
        """
    }

    

    def imageStr = patchImages.join(" ")
    sh """
        docker image save ${imageStr} > build/dist/titan-container-patch-${TAG}-${BUILD_NUMBER}.tar
        cp patch-image/patch-k8s.sh build/dist/
        cd build/dist && tar --use-compress-program=pigz -cvpf ../titan-container-patch-${TAG}-${BUILD_NUMBER}.tar.gz *
    """

    echo "build/titan-container-patch-${TAG}-${BUILD_NUMBER}.tar.gz"

}