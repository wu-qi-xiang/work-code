#!/bin/bash
# 该脚本更新后需要放到打包服务器的/data/patch/目录下



COLOR_G="\x1b[0;32m"  # green
COLOR_R="\x1b[1;31m"  # red
RESET="\x1b[0m"

info_log(){
    echo -e "${COLOR_G}[Info] ${1}${RESET}"
}

error_log(){
    echo -e "${COLOR_R}[Error] ${1}${RESET}"
    exit 1
}

error_log_no_exit(){
    echo -e "${COLOR_R}[Error] ${1}${RESET}"
}

check(){
    if [ $? -eq 0 ];then
        info_log "$1 Successfully"
    else
        error_log "$1 Failed"
    fi
}


help() {
    echo "--------------------------------------------------------------------------"
    echo "                             Usage information                            "
    echo "--------------------------------------------------------------------------"
    echo "                                                                          "
    echo "./patch_base.sh old_titan_base_tar_gz patch_tar_file new_titan_base_floader"
    echo "                                                                          "
    echo "  Example:                                                                "
    echo "    ./patch_base.sh titan-base-test-el6-v3.3.0.2-20190801192259.tar.gz patch.tar.gz /data/install/"
    echo "--------------------------------------------------------------------------"
    exit 1
}

function md5() {
    md5=$(md5sum $1)
    echo $md5 | awk -F' ' '{print$1}'
}

function patch() {
    #process add
    if [ -f $patchFloader"/"$addFiles ]; then
        while read line
        do
            local addIndex=`echo $line | awk -F'####' '{print $1}'`
            local addFile=`echo $line | awk -F'####' '{print $2}'`
            local targetFile=$oldFloader"/"$addFile
            mkdir -p $(dirname ${targetFile})
            cp $patchFloader"/"$addIndex".add" $targetFile
        done < $patchFloader"/"$addFiles
    fi


    #process delete
    if [ -f $patchFloader"/"$deleteFiles ]; then
        while read line
        do
            # avoid to delete the dirs which is used by system
            if [[ $line == titan-base* ]]; then
                rm -fr $oldFloader"/"$line
            fi
            ## 如果目录为空 就删除目录
            deleteFloader=`dirname $oldFloader"/"$line`
            res=`ls -A $deleteFloader`
            if [ -z "$res" ];then
                rm -rf $deleteFloader
            fi
        done < $patchFloader"/"$deleteFiles
    fi
}

function check_patch_available() {
    basicBaseName=`cat $patchFloader/basic_base_name`
    if [ $basicBaseName == $oldTarGzFileName ]; then
        return 0
    fi
    return 1
}

function get_version() {
    echo $1 | awk -F'-' '{print$7}'
}


if [ $# -ne 3 ]; then
help
exit 1
fi

addFiles="add.files"
deleteFiles="delete.files"
patchFiles="patch.files"
basicBaseDir="/data/basic_base/"
oldTarGz=$1
patchTarFile=$2
newTarGzFloader=$3
patchFloader="qingteng-base-patch"
patchTool=""
addFileIndex=0

# entry the patch.sh's dir
cd "$(dirname "$0")"

if [ ! -f $oldTarGz ]; then
    error_log "$oldTarGz is not exist"
fi

if [ ! -f $patchTarFile ]; then
    error_log "$patchTarFile is not exist"
fi

if [ ! -d $basicBaseDir ]; then
    mkdir -p $basicBaseDir
    check "mkdir $basicBaseDir"
fi

oldTarGzFileName=$(basename ${oldTarGz})
oldFloader=${oldTarGzFileName%.tar.gz}

# check if need to backup basic base package
if [ ! -f $basicBaseDir$oldTarGzFileName ]; then
    info_log "Copy $oldTarGz to $basicBaseDir for backup....."
    # clean other basic bases. only one basic base can exist
    rm -fr $basicBaseDir*
    cp $oldTarGz $basicBaseDir
fi


if [ -d $patchFloader ]; then
    rm -fr $patchFloader
fi
mkdir $patchFloader

info_log "Extracting $patchTarFile......"
tar -xvf $patchTarFile -C $patchFloader
check "Extracting $patchTarFile"


info_log "Checking If The Patch Is Available For $oldTarGz......"
check_patch_available
check "Checking Patch"

info_log "Extracting $oldTarGz......"
if [ -d $oldFloader ]; then
    rm -fr $oldFloader
fi
mkdir -p $oldFloader
tar -xvf $oldTarGz -C $oldFloader
check "Extracting $oldTarGz"




info_log "Applying Patch Files......"
patch
check "Applying Patch Files"


name=`cat $patchFloader/name`
info_log "Generate $name ..."
pushd . > /dev/null
cd $oldFloader && tar -zcvf $newTarGzFloader"/"$name *
info_log "[[[[${name%.tar.gz}]]]]"
popd > /dev/null
check "Generate $name"

info_log "Cleaning......"
rm -fr $patchFloader
rm -fr $oldFloader
check "Clean"
