#!/bin/bash
# define variable
BACKUP_PATH=/data/saas-backup
BACKUP_PATH_DATA=$BACKUP_PATH/yaml/`date +%Y%m%d%H%M%S`
BACKUP_PATH_LOG=$BACKUP_PATH/log
BACKUP_LOG_FILE=$BACKUP_PATH_LOG/k8s-backup-`date +%Y%m%d%H%M%S`.log
# base function
function printlog(){
 echo "`date +'%Y-%m-%d %H:%M:%S'` $1"
 echo "`date +'%Y-%m-%d %H:%M:%S'` $1" >> $BACKUP_LOG_FILE 2>&1 
}
function printlogonly(){
 echo "`date +'%Y-%m-%d %H:%M:%S'` $1" >> $BACKUP_LOG_FILE 2>&1 
}
# set K8s type（此处可根据集群资源自行修改）
CONFIG_TYPE="service deploy ingress configmap secret job cronjob daemonset statefulset"
# make dir
mkdir -p $BACKUP_PATH_DATA
mkdir -p $BACKUP_PATH_LOG
cd $BACKUP_PATH_DATA
# set namespace list
ns_list=`kubectl get ns | awk '{print $1}' | grep -v NAME`
if [ $# -ge 1 ]; then
ns_list="$@"
fi
# define counters
COUNT_NS=0
COUNT_ITEM_IN_NS=0
COUNT_ITEM_IN_TYPE=0
COUNT_ITEM_ALL=0
# print hint
printlog "Backup kubernetes config in namespaces: ${ns_list}"
printlog "Backup kubernetes config for [type: ${CONFIG_TYPE}]."
printlog "If you want to read the record of backup, please input command ' tail -100f ${BACKUP_LOG_FILE} '"
# ask and answer
message="This will backup resources of kubernetes cluster to yaml files."
printlog ${message}
# loop for namespaces
for ns in $ns_list;
do
COUNT_NS=`expr $COUNT_NS + 1`
printlog "Backup No.${COUNT_NS} namespace [namespace: ${ns}]."
COUNT_ITEM_IN_NS=0

## loop for types
for type in $CONFIG_TYPE; 
do
printlogonly "Backup type [namespace: ${ns}, type: ${type}]."
item_list=`kubectl -n $ns get $type | awk '{print $1}' | grep -v NAME | grep -v "No "`
COUNT_ITEM_IN_TYPE=0

## loop for items
for item in $item_list; 
do 
file_name=$BACKUP_PATH_DATA/${ns}_${type}_${item}.yaml
printlogonly "Backup kubernetes config yaml [namespace: ${ns}, type: ${type}, item: ${item}] to file: ${file_name}"
kubectl -n $ns get $type $item -o yaml > $file_name
COUNT_ITEM_IN_NS=`expr $COUNT_ITEM_IN_NS + 1`
COUNT_ITEM_IN_TYPE=`expr $COUNT_ITEM_IN_TYPE + 1`
COUNT_ITEM_ALL=`expr $COUNT_ITEM_ALL + 1`
printlogonly "Backup No.$COUNT_ITEM_ALL file done."
done;

done;
printlogonly "Backup $COUNT_ITEM_IN_TYPE files in [namespace: ${ns}, type: ${type}]."

printlog "Backup ${COUNT_ITEM_IN_NS} files done in [namespace: ${ns}]."
done;

# show stats
printlog "Backup ${COUNT_ITEM_ALL} yaml files in all."
printlog "kubernetes Backup completed, all done."
exit 0
