#!/usr/bin/env bash

source /data/scripts/utils.sh

if [[ $1 == "--config" ]] ; then
  cat <<EOF
{
  "configVersion": "v1",
  "kubernetes": [
    {
      "name":"OnCreateTitanSystemStatus",
      "apiVersion": "v1",
      "kind": "ConfigMap",
      "executeHookOnEvent":["Added","Modified"],
      "namespace": {"nameSelector":{"matchNames": ["$NS"]}},
      "nameSelector": {"matchNames": ["titan-system-status"]}
    }
  ],
  "settings": {
    "executionMinInterval": 10s,
    "executionBurst": 1
  }
}
EOF
else
  # 还未安装完成，那么无需注册帐号，直接退出即可
  (kubectl -n $NS get cm titan-system-status -o yaml | grep install_done) || exit 0

  # check if already register account
  (kubectl -n $NS get cm titan-system-status -o yaml | grep register_done) && exit 0

  # 检查这几个Pod状态正常则注册帐号
  check_pod=`kubectl -n $NS get po |grep -E "(wisteria|titan-web|titan-patrol|titan-gateway)" | grep Running`
  if [[ "$check_pod" =~ "wisteria" && "$check_pod" =~ "titan-web" && "$check_pod" =~ "titan-patrol"  && "$check_pod" =~ "titan-gateway" ]]; then
      # 注册帐号，日志在 /logs/register.log
      register_auto > /logs/register.log
      kubectl -n $NS patch configmap/titan-system-status --type merge -p '{"data":{"register_done":"true"}}'
  else
      # 不成功会自动重试此hook, 默认重试是5秒，此处主动sleep 30秒，避免太频繁
      echo "部分服务未安装成功，无法注册帐号"  
      sleep 30 && exit 1
  fi
fi
