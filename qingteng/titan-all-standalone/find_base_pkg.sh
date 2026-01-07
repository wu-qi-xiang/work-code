#!/bin/bash

if [[ $# -lt 4 ]]; then
    echo "Usage $0 <release dir> <build variant> <el> <base version>"
fi

releaseDir=$1
buildVariant=$2
el=$3
baseVersion=$4

ls -r ${releaseDir}/titan-base-${buildVariant}-${el}*${baseVersion}-*-withpatch*tar.gz | head -n 1
