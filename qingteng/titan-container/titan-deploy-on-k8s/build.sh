#!/bin/bash

# 此脚本多架构构建时，分别在 amd64 和 arm64 机器上执行

TAG=$1
if [ "x$TAG" == "x" ]; then
    echo "need tag"
    exit 1
fi

ARCH=$(uname -m)

REGISTRY=registry.qingteng.cn/titan-container
rootDir=$(cd `dirname $0`; /bin/pwd)

cd ${rootDir}
rm -rf build && mkdir -p build/dist

ruleImage=`grep rules_image ${rootDir}/var_file.yml | awk -F '}}/' '{print $2}'|tr -d '"' `
baseImages=`grep _image ${rootDir}/var_file.yml | grep -v rules_image | grep -v {{common_tag}} | awk -F '}}/' '{print $2}'|tr -d '"' `
appImages=`grep _image ${rootDir}/var_file.yml | grep {{common_tag}} | grep -oP 'titan-.*:'`

rBaseImages=""
rAppImages=""
for name in ${baseImages[@]} ; do rBaseImages="$rBaseImages $REGISTRY/$name"; done
for name in ${appImages[@]} ; do rAppImages="$rAppImages $REGISTRY/$name"${TAG}; done

# 构建 titan-deploy， 不push, 只保留在本地即可
# echo "build titan-deploy-onk8s image start"
# sed -i "s/^common_tag:.*/common_tag: $TAG/" var_file.yml
# if [ "${ARCH}" = "arm64" ] || [ "${ARCH}" = "aarch64" ]; then
#     docker build -t $REGISTRY/titan-deploy-onk8s:${TAG}-arm64 .
# else
#     docker build -t $REGISTRY/titan-deploy-onk8s:${TAG} .
# fi

# 检查ruleImage 的tar包是否存在，存在则直接复制过来，否则导出
ruleImageTar="titan-rules-${ruleImage#*:}.tar"
if [[ -f /data/qt-container/titan-container/baseimage/${ruleImageTar}-${ARCH} ]]; then
    echo "rule image tar already exists"
    cp /data/qt-container/titan-container/baseimage/${ruleImageTar}-${ARCH} build/dist/${ruleImageTar}
else
    docker pull $REGISTRY/$ruleImage
    echo "begin to export rule image"
    docker image save $REGISTRY/$ruleImage -o build/dist/${ruleImageTar}
    cp build/dist/${ruleImageTar} /data/qt-container/titan-container/baseimage/${ruleImageTar}-${ARCH}
fi
# 规则包镜像信息
echo $REGISTRY/$ruleImage >> build/dist/ruleimages;

#baseImages排序后计算md5
IFS=$'\n' sortedBaseImages=($(sort <<<"${baseImages[*]}"))
unset IFS
baseMd5=`echo "${sortedBaseImages[@]}"-${ARCH} | md5sum | cut -d ' ' -f 1`
# 根据baseMd5值到指定目录找 baseImages的tar包,找不到则重新生成
baseImageTar="titan-k8s-base-${baseMd5}.tar"
if [[ -f /data/qt-container/titan-container/baseimage/${baseImageTar}-${ARCH} ]]; then
    echo "base image tar already exists"
    cp /data/qt-container/titan-container/baseimage/${baseImageTar}-${ARCH} build/dist/${baseImageTar}
    cp /data/qt-container/titan-container/baseimage/${baseImageTar}.images-${ARCH} build/dist/baseimages
else
    for name in ${rBaseImages[@]}; do docker pull $name; done
    echo "begin to export base image"
    docker image save ${rBaseImages[@]} -o build/dist/${baseImageTar}
    for name in ${rBaseImages[@]}; do echo $name >> build/dist/baseimages; done
    # 复制到归档目录以便下次继续使用
    cp build/dist/${baseImageTar} /data/qt-container/titan-container/baseimage/${baseImageTar}-${ARCH}
    cp build/dist/baseimages /data/qt-container/titan-container/baseimage/${baseImageTar}.images-${ARCH}
fi

# pull all images, ensure exists
rAppImages="$rAppImages $REGISTRY/titan-deploy-onk8s:"${TAG}
echo $rAppImages
for name in ${rAppImages[@]}; do docker pull $name; done

# export app images and record image name to appimages
echo "begin to export app images, please wait"
docker image save ${rAppImages[@]} -o build/dist/titan-k8s-app-${TAG}.tar

for name in ${rAppImages[@]}; do echo $name >> build/dist/appimages; done

echo "change image tag in titan-deploy.yml"
cp -rf ./deploy/*  build/dist/ && mv build/dist/titan-env-release.yml build/dist/titan-env.yml
sed -i "s/COMMON_TAG/$TAG/" build/dist/titan-deploy.yml

echo "Set up the YQ file"
if [ "${ARCH}" == "x86_64" ];then
    rm -rf build/dist/yq_linux_arm64
    mv build/dist/yq_linux_amd64 build/dist/yq
elif [ "${ARCH}" == "aarch64" ];then
    rm -rf build/dist/yq_linux_amd64
    mv build/dist/yq_linux_arm64 build/dist/yq
else
    echo "This server architecture is not supported"
    exit 1
fi

echo "build standalone gzip package"
cd build/ && mv dist ${TAG} && tar --use-compress-program=pigz -cvpf titan-k8s-${TAG}-${ARCH}.tar.gz ${TAG}
echo "build/titan-k8s-${TAG}-${ARCH}.tar.gz"

cd ${rootDir} && rm -rf build/dist
