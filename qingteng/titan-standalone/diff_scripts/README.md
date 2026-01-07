# diff_scripts 
包括ci 打包脚本和生成base整包所需要使用的diff脚本和Patch脚本
+ build_package.sh
+ diff_base.sh
+ patch_base.sh

## build_package.sh ##
CI 构建整包脚本

os版本为el6和el7两个版本

### titan-base rpm构建管理方式 ###

rpm包会从mirror.qingteng.cn私有管理仓库平台中名为yum-standalone 的yum仓库中拉取离线rpm包。

rpm包会存放到titan-base/base/qingteng-{os}/

### titan-base pypi包构建管理方式 ###

pypi的下载会自动读取titan-base/java/pip_packages/requirements.txt中记录相关插件的版本号,从mirror.qingteng.cn私有管理仓库平台中名为qingteng-pip的pypi仓库中拉取离线pypi包.

Pypi离线包存放在titan-base/java/pip_packages/

### titan-base arthas构建管理方式 ###

通过读取titan-base/java/arthas_version 中记录的版本号，从https://mirror.qingteng.cn/repository/raw-qingteng-arthas/ 下载对应版本的包并解压到titan-base/java/到 然后拷贝到titan-base/connect下面

## diff_base.sh ##
构建base的patch包需要使用

```
./diff_base.sh old_titan_base_tar_gz new_titan_base_tar_gz the_floader_to_save_patch 
```

##patch_base.sh ##
从patch包生成完整的部署base包需要使用的脚本

```
./patch_base.sh old_titan_base_tar_gz patch_tar_file new_titan_base_floader

```
