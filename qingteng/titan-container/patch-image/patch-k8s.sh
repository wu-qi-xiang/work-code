#!/bin/bash

REGISTRY="registry.qingteng.cn/titan-container"
NS=qtsa

push_images(){
    images=("$*")
    for image in ${images[@]}
    do
        image_tag=${image##*/} 
        echo "$REGISTRY/$image_tag"
        docker tag $image "$REGISTRY/$image_tag"
        docker push "$REGISTRY/$image_tag"
    done
}

load_image(){
    patchimages=(`cat patchimages`)
    last_patch_image=`cat patchimages | tail -1`
    pull_result=`docker pull "$REGISTRY/${last_patch_image##*/}" 2>&1 | grep 'Error response'`
    if [[ -z $pull_result ]]; then
        echo "patch image already loaded to registry"
        return
    else
        patchimage_tarfile=`ls -t titan-container-patch-*.tar | head -1`
        [ -z "${patchimage_tarfile}" ] && exit 1
        echo "load patch image to localhost start, please wait"
        docker load -i ${patchimage_tarfile}
        echo "begin load patch image to registry, please wait"
        push_images  ${patchimages[@]}
    fi
}

patch_k8s(){
    patchimages=(`cat patchimages`)
    for image in ${patchimages[@]}
    do
        image_tag=${image##*/} 
        echo "$image_tag"
        image_name=${image_tag##*:}
        case $image_name in
            titan-java-wisteria)
                kubectl -n $NS set image deployment titan-wisteria titan-wisteria="$REGISTRY/${image_tag}"
                ;;
            titan-java-connect-agent)
                kubectl -n $NS set image deployment titan-connectagent titan-connectagent="$REGISTRY/${image_tag}"
                ;;
            titan-java-connect-dh)
                kubectl -n $NS set image deployment titan-connectdh titan-connectdh="$REGISTRY/${image_tag}"
                ;;
            titan-java-connect-selector)
                kubectl -n $NS set image deployment titan-connectselector titan-connectselector="$REGISTRY/${image_tag}"
                ;;
            titan-java-connect-sh)
                kubectl -n $NS get deployment | grep connectsh | awk '{print $1}' | xargs -i kubectl -n $NS set image deployment {} titan-connectsh="$REGISTRY/${image_tag}"
                ;;
            titan-java-detect-srv)
                kubectl -n $NS set image deployment titan-detect-srv titan-detect-srv="$REGISTRY/${image_tag}"
                ;;
            titan-java-gateway)
                kubectl -n $NS set image deployment titan-gateway titan-gateway="$REGISTRY/${image_tag}"
                ;;
            titan-java-scan-srv)
                kubectl -n $NS set image deployment titan-scansrv titan-scansrv="$REGISTRY/${image_tag}"
                ;;
            titan-java-upload-srv)
                kubectl -n $NS set image deployment titan-upload-srv titan-upload-srv="$REGISTRY/${image_tag}"
                ;;
            titan-java-user-srv)
                kubectl -n $NS set image deployment titan-usersrv titan-usersrv="$REGISTRY/${image_tag}"
                ;;
            titan-web-php)
                kubectl -n $NS get deployment | grep titan-web- | awk '{print $1}' | xargs -i kubectl -n $NS set image deployment {} titan-web="$REGISTRY/${image_tag}"
                ;;
            titan-java-job-srv)
                kubectl -n $NS get statefulset | grep titan-job-srv | awk '{print $1}' | xargs -i kubectl -n $NS set image statefulset {} titan-job-srv="$REGISTRY/${image_tag}"
                ;;
            upgradetool)
                kubectl -n $NS set image deployment titan-wisteria upgradetool="$REGISTRY/${image_tag}"
                ;;
            *)
                echo "Unknow image..." 1>&2
                exit 1
                ;;
        esac
    done

    echo "patch done. current images are:"
    (kubectl -n $NS get statefulset -o wide && kubectl -n $NS get deployment -o wide | awk {'print $1"\t" $2"\t" $5"\t" $6"\t" $7'} | column -t ) | sed -r 's#[^, ]+/[^, ]+/##g' | column -t

}

load_image
patch_k8s
