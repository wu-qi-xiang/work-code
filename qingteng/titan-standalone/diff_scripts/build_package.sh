#!/bin/bash
set -xe

info_log() {
    echo -e "${COLOR_G}[Info] ${1}${RESET}"
}

error_log() {
    echo -e "${COLOR_R}[Error] ${1}${RESET}"
    exit 1
}

info_log2() {
    echo -e "${COLOR_L}[Info] ${1}${RESET}"
}

check() {
    if [ $? -eq 0 ]; then
        info_log "$* Successfully"
    else
        error_log "$* Failed"
        exit 1
    fi
}

source_dir="/tmp/rpms/qingteng-${os}"
target_dir="${CI_PROJECT_DIR}/titan-base/base"
rpmlistfile_dir="${CI_PROJECT_DIR}/rpms_scripts/${os}/repolists.txt"
qt_package_dir="${target_dir}/qingteng/qt_base_${os}"
qt_java_dir="${CI_PROJECT_DIR}/titan-base/java"
version_dir="${CI_PROJECT_DIR}/titan-base/version.json"
SCP_CMD="scp -P 22 -oStrictHostKeyChecking=no -o ConnectionAttempts=5 -o ConnectTimeout=3"
RMOTE_HOST="172.16.17.164"
NAS_DIR="/data/packages/packages/packages/"
RELEASE_NAS_DIR="/data/packages/release/"


#build download rpms
echo "${source_dir}" "${target_dir}"
mkdir -p "${source_dir}"/qt_base_"${os}" "${target_dir}"
yum clean all
yum makecache
grep -Ev "^#|^$" "${rpmlistfile_dir}" | xargs yumdownloader \*i686 --archlist=x86_64 --destdir="${source_dir}" --resolve
mv "${source_dir}"/qingteng* "${source_dir}"/titan-rabbitmq* "${source_dir}"/qt_base_"${os}"/
createrepo --update "${source_dir}"
mv "${source_dir}" "${target_dir}"/qingteng

##build download expect rpm
yumdownloader \*i686 --archlist=x86_64 --destdir="${CI_PROJECT_DIR}/titan-base/scripts/expect/${os#*l}" --resolve expect

##build python module 
pip2.7 download -d "${qt_java_dir}/pip_packages" -i https://mirror.qingteng.cn/repository/qingteng-pip/simple -r "${qt_java_dir}"/pip_packages/requirements.txt

##build download arthas_version
arthas_ver=$(cat "${qt_java_dir}"/arthas_version)
arthas_packname="arthas-packaging-${arthas_ver}-bin"
arthas_download_url="https://mirror.qingteng.cn/repository/raw-qingteng-arthas/arthas/arthas-packaging/${arthas_ver}/${arthas_packname}.zip"
mkdir -p  "${qt_java_dir}/${arthas_packname}" && \
cd "${qt_java_dir}/${arthas_packname}" && \
wget "${arthas_download_url}" && \
[ ! -f "${arthas_packname}.zip" ] && echo download arthas fail && exit 1
unzip "${arthas_packname}.zip" && rm -rf "${arthas_packname}.zip"
cp -rf "${qt_java_dir}/${arthas_packname}" "${qt_java_dir}/../connect/"

##build create version
len=$(cd "${qt_package_dir}" && ls *.rpm | wc -l)
rpm_list=$(cd "${qt_package_dir}" && ls *.rpm)
index=0
echo "{" >"${version_dir}"
echo "  \"version\":\"${version}_$(date '+%Y%m%d%H%M%S')\"," >>${version_dir}
for i in ${rpm_list}; do
    rpm_name=$(echo "${i}" | cut -d "-" -f1-2)
    base_version=$(echo "${i}" | cut -d "-" -f3)
    base_release=$(echo "${i}" | cut -d "-" -f4)
    (( a++ )) || true
    if [ ${index} -ne "${len}" ]; then
        echo "  \"${rpm_name}\"":"\"${base_version##v}-${base_release%%.*}\"," >>"${version_dir}"
    else
        echo "  \"${rpm_name}\"":"\"${base_version##v}-${base_release%%.*}\"" >>"${version_dir}"
    fi
done
echo "}" >>"${version_dir}"

##build_package
package_name="${name}-${os}-${version}-${BUILD_TIME}.tar.gz"
cd "${CI_PROJECT_DIR}" || exit
chmod 755 -R titan-base
tar -I pigz -cvf "${package_name}" titan-base

###build_diff_package
SSH_CMD="ssh -oStrictHostKeyChecking=no -o ConnectionAttempts=5 -o ConnectTimeout=3"
if ${SSH_CMD} ${RMOTE_HOST} test -e ${NAS_DIR}/basic_"${name}"_"${os}"_"${version}" ;then
  echo "$NAS_DIR/basic_${name}_${os}_${version} 存在"
  exit_code=0
else
  echo "$NAS_DIR/basic_${name}_${os}_${version} 不存在"
  exit_code=1
fi

${SSH_CMD} ${RMOTE_HOST} "echo basic_${name}_${os}_${version}"

if [ ! -z "${basic_version}" ]; then
    basic_base=$($SSH_CMD $RMOTE_HOST "cat $NAS_DIR/basic_${name}_${os}_${basic_version}")
elif [ "$exit_code" -eq 0 ]; then
    basic_base=$(${SSH_CMD} ${RMOTE_HOST} "cat ${NAS_DIR}/basic_${name}_${os}_${version}")
fi

if [ -z "${basic_base}" ]; then
    basic_base=${package_name}
    ##记录当前版本的基准包##
    ${SSH_CMD} ${RMOTE_HOST} "echo ${basic_base} > /data/packages/packages/packages/basic_${name}_${os}_${version}"
else
    #拷贝基准包到/tmp
    ${SCP_CMD} ${RMOTE_HOST}:${NAS_DIR}/${basic_base} /tmp/
fi

old=${basic_base%.tar.gz}
new=${package_name%.tar.gz}
patchTar=${old}_${new}.tar.gz

if [ "${basic_base}" == "${package_name}" ]; then
    cp "${CI_PROJECT_DIR}"/"${package_name}" /tmp/
    ${SCP_CMD} "${package_name}" ${RMOTE_HOST}:${NAS_DIR}
fi
cd "${CI_PROJECT_DIR}"/diff_scripts/ && bash ./diff_base.sh /tmp/"${basic_base}" "${CI_PROJECT_DIR}"/"${package_name}" "${CI_PROJECT_DIR}"/patch
mv "${CI_PROJECT_DIR}"/patch/"${patchTar}" "${CI_PROJECT_DIR}"/patch/patch_base.tar.gz
cd "${CI_PROJECT_DIR}" || exit
tar -zcvf "${new}"-withpatch.tar.gz -C /tmp/ "$basic_base" -C "$CI_PROJECT_DIR"/patch/ patch_base.tar.gz -C "$CI_PROJECT_DIR"/diff_scripts/ patch_base.sh
$SCP_CMD "$CI_PROJECT_DIR"/"$new"-withpatch.tar.gz $RMOTE_HOST:$RELEASE_NAS_DIR
