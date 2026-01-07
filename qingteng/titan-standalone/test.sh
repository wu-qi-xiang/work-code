#!/bin/bash
source_dir="/tmp/rpms/qingteng-${os}"
target_dir="${CI_PROJECT_DIR}/titan-base/base"
rpmlistfile_dir="${CI_PROJECT_DIR}/rpms_scripts/repolists.txt"
qt_package_dir="${target_dir}/qingteng/qt_base_${os}"
version_dir="${CI_PROJECT_DIR}/titan-base/version.json"
SCP_CMD="scp -P 22 -oStrictHostKeyChecking=no -o ConnectionAttempts=5 -o ConnectTimeout=3"
RMOTE_HOST="172.16.17.164"
NAS_DIR="/data/packages/packages/packages/"
RELEASE_NAS_DIR="/data/packages/release/"


echo $source_dir
echo $target_dir
echo $rpmlistfile_dir
echo $qt_package_dir
echo "basic_version:$basic_version"
echo "version: $version"
