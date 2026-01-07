#!/bin/bash

#用于diff比对base包，如果有修改需要放到打包服务器上
#base打包服务器：/data/diff/

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

check(){
    if [ $? -eq 0 ];then
        info_log "$1 Successfully"
    else
        error_log "$1 Failed"
    fi
}


help() {
    echo "--------------------------------------------------------------------------"
    echo "          Generate Patch Files Between Two Titan-Base Packages             "
    echo "--------------------------------------------------------------------------"
    echo "                             Usage information                            "
    echo "--------------------------------------------------------------------------"
    echo "                                                                          "
    echo "./diff_base.sh old_titan_base_tar_gz new_titan_base_tar_gz the_floader_to_save_patch"
    echo "                                                                          "
    echo "  Example:                                                                "
    echo "    ./diff_base.sh /usr/local/src/titan-base-test-el6-v3.3.0.2-20190801192259.tar.gz /usr/local/src/titan-base-test-el6-v3.3.0.2-20190810192259.tar.gz /patch"
    echo "--------------------------------------------------------------------------"
    exit 1
}

function md5() {
	md5=$(md5sum $1)
	echo $md5 | awk -F' ' '{print$1}'
}


function loop_old_dir() {
	local floader=$1
	for file in `ls $1`
	do
		local floaderFile=$floader"/"$file
		if [ -d $floaderFile ]; then
			loop_old_dir $floaderFile
		else
			# target_file is new file
			for exclude in ${excludeFilePrefixs[@]}; do
				if [[ $file == $exclude* ]]; then
					continue 2
				fi
			done
			local targetFloader=$newFloader${floader#*$oldFloader}
			local targetFloaderFile=$targetFloader"/"$file
			# if new file is exist. diff is needed
			if [ -f $targetFloaderFile ]; then
				local oldMd5=`md5 $floaderFile`
                local newMd5=`md5 $targetFloaderFile`
                if [ "$oldMd5" != "$newMd5" ]; then
                    cp $targetFloaderFile $patchFloader"/"$addFileIndex".add"
                    echo $addFileIndex"####"${floaderFile#*/} >> $patchFloader/add.files
                    let 'addFileIndex+=1'
                fi
			else
				# if new file is not exist, it must be deleted
                echo ${floaderFile#*/} >> $patchFloader/delete.files
			fi
		fi
	done
}

function loop_new_dir() {
	local floader=$1
	for file in `ls $1`
	do
		local floaderFile=$floader"/"$file
		if [ -d $floaderFile ]; then
			loop_new_dir $floaderFile
		else
			# target_file is new file
			local targetFloader=$oldFloader${floader#*$newFloader}
			local targetFloaderFile=$targetFloader"/"$file
			# if old file is not exist. add is needed
			if [ ! -f $targetFloaderFile ]; then
                cp $floaderFile $patchFloader"/"$addFileIndex".add"
                echo $addFileIndex"####"${floaderFile#*/} >> $patchFloader/add.files
                let 'addFileIndex+=1'
			fi
		fi
	done
}


function get_version() {
	echo $1 | awk -F'-' '{print$7}'
}

##############################START##############################


if [ $# -ne 3 ]; then
help
exit 1
fi

oldFile=$1
newFile=$2
patchTarGzSaveFloader=$3
patchFloader="qingteng-base-patch"
diffTool=""
addFileIndex=0
patchFileIndex=0


#do not need to process file prefix, this is an array. (eg: ("titan-channel" "titan-patrol"))
excludeFilePrefixs=()

if [ ! -f $oldFile ]; then
	error_log "$oldFile is not exist"
fi

if [ ! -f $newFile ]; then
	error_log "$newFile is not exist"
fi

oldFileName=$(basename ${oldFile})
newFileName=$(basename ${newFile})

info_log "old file:"$oldFileName
info_log "new file:"$newFileName

oldFloader=${oldFileName%.tar.gz}
newFloader=${newFileName%.tar.gz}

if [ ! -d $patchTarGzSaveFloader ]; then
	mkdir -p $patchTarGzSaveFloader
fi
# Check whether patch files have been generated 
patchTar=$patchTarGzSaveFloader"/"$oldFloader"_"$newFloader".tar.gz"
if [ -f $patchTar ]; then
	info_log "$patchTar is already exist"
	exit 0
fi


info_log "Extracting $oldFile to $oldFloader......"
if [ -d $oldFloader ]; then
	rm -fr $oldFloader
fi
mkdir $oldFloader
tar -xvf $oldFile -C $oldFloader
check "Extracting $oldFile to $oldFloader"

if [ -d $newFloader ]; then
	rm -fr $newFloader
fi
mkdir $newFloader
info_log "Extracting $newFile to $newFloader......"
tar -xvf $newFile -C $newFloader
check "Extracting $newFile to $newFloader"

if [ -d $patchFloader ]; then
	rm -fr $patchFloader
fi
mkdir $patchFloader

info_log "Generating Patch Files......"
# loop old dir to find the files which need to be delete and replace
loop_old_dir $oldFloader

# loop new dir to find the files which need to add
loop_new_dir $newFloader

echo $newFileName > $patchFloader/name
echo $oldFileName > $patchFloader/basic_base_name
check "Generating Patch Files"


info_log "Compressing Patch Files......"
pushd . > /dev/null
cd $patchFloader && tar -zcvf $patchTar *
popd > /dev/null
check "Compressing Patch Files"

info_log "Clean......"
rm -fr $patchFloader
rm -fr $oldFloader
rm -fr $newFloader
check "Clean"
