#!/bin/bash

TAG=$1
if [ "x$TAG" == "x" ]; then
    echo "need tag"
    exit 1
fi

REGISTRY=registry.qingteng.cn/titan-container
rootDir=$(cd `dirname $0`; /bin/pwd)

cd ${rootDir}
rm -rf build && mkdir -p build/dist

echo "begin build titan-compose-deploy"
cd ../titan-dockerize && CGO_ENABLED=0 go build -o ${rootDir}/script/dockerize
cd ${rootDir}
docker build -t titan-compose-deploy:${TAG} .
docker tag titan-compose-deploy:${TAG} "$REGISTRY"/titan-compose-deploy:${TAG}
#docker push "$REGISTRY"/titan-compose-deploy:${TAG}

ruleImage=`grep rules_image ${rootDir}/env_template | awk -F '}}/' '{print $2}'|tr -d '"' `
baseImages=`grep _image ${rootDir}/env_template | grep -v {{common_tag}} |grep -v rules_image | awk -F '}}/' '{print $2}'|tr -d '"' `
appImages=`grep _image ${rootDir}/env_template | grep {{common_tag}} | grep -oP 'titan-.*:'`
rBaseImages=""
rAppImages=""
for name in ${baseImages[@]} ; do rBaseImages="$rBaseImages $REGISTRY/$name"; done
for name in ${appImages[@]} ; do rAppImages="$rAppImages $REGISTRY/$name"${TAG}; done

# 检查ruleImage 的tar包是否存在，存在则直接复制过来，否则导出
ruleImageTar="titan-rules-${ruleImage#*:}.tar"
if [[ -f /data/qt-container/titan-container/baseimage/${ruleImageTar} ]]; then
    echo "rule image tar already exists"
    cp /data/qt-container/titan-container/baseimage/${ruleImageTar} build/dist/
else
    docker pull $REGISTRY/$ruleImage
    echo "begin to export rule image"
    docker image save $REGISTRY/$ruleImage -o build/dist/${ruleImageTar}
    cp build/dist/${ruleImageTar} /data/qt-container/titan-container/baseimage/
fi

#baseImages排序后计算md5
IFS=$'\n' sortedBaseImages=($(sort <<<"${baseImages[*]}"))
unset IFS
baseMd5=`echo "${sortedBaseImages[@]}" | md5sum | cut -d ' ' -f 1`
# 根据baseMd5值到指定目录找 baseImages的tar包,找不到则重新生成
baseImageTar="titan-compose-base-${baseMd5}.tar"
if [[ -f /data/qt-container/titan-container/baseimage/${baseImageTar} ]]; then
    echo "base image tar already exists"
    cp /data/qt-container/titan-container/baseimage/${baseImageTar} build/dist/
    cp /data/qt-container/titan-container/baseimage/${baseImageTar}.images build/dist/baseimages
else
    for name in ${rBaseImages[@]}; do docker pull $name; done
    echo "begin to export base image"
    docker image save ${rBaseImages[@]} -o build/dist/${baseImageTar}
    for name in ${rBaseImages[@]}; do echo $name >> build/dist/baseimages; done
    cp build/dist/${baseImageTar} /data/qt-container/titan-container/baseimage/
    cp build/dist/baseimages /data/qt-container/titan-container/baseimage/${baseImageTar}.images
fi

# pull all images, ensure exists
echo $rAppImages
for name in ${rAppImages[@]}; do docker pull $name; done

# export app images and record image name to appimages
echo "begin to export images, please wait"
docker image save $rAppImages -o build/dist/titan-compose-app-${TAG}.tar
docker image save "${REGISTRY}/titan-sysinfo:${TAG}" -o build/dist/titan-sysinfo-${TAG}.tar
for name in ${rAppImages[@]}; do echo $name >> build/dist/appimages; done

echo "build docker compose standalone gzip package"
cp -rf ./{env_template,docker-compose.yml,utils.sh,compose.sh,config.sh,titan.env_template} build/dist/
sed -i "s#{{registry}}#$REGISTRY#g" build/dist/env_template
sed -i "/deploy_image/,/php_image/ s/:.*$/:${TAG}/g" build/dist/env_template
cd build/ && mv dist ${TAG} && tar --use-compress-program=pigz -cvpf titan-compose-all-${TAG}.tar.gz ${TAG}

echo "build/titan-compose-all-${TAG}.tar.gz"