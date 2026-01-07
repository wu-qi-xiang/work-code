#!/usr/bin/env bash

source /data/scripts/utils.sh

installed=false

# 检查环境是否已安装完成
function check_status(){
  (kubectl -n $NS get cm titan-system-status -o yaml | grep install_done) && installed=true
}

# 检查pod内titan-env的修改时间是否晚于容器启动时间，晚于容器启动时间则说明，容器启动后，titan-env又有了改动，需要重启
function check_titan_env(){
  pod=$1
  container_name=$2

  if [[ $1 == "" ]] || [[ $2 == "" ]]; then
    echo "false"
    return
  fi

  # 从pod内复制titan-env.yml出来
  kubectl -n $NS exec -i $pod -c $container_name -- cat /titan-env/titan-env.yml > /tmp/titan-env_$pod.yml
  # 对比
  diff_result=`diff -B -Z /tmp/old-titan-env.yml /tmp/titan-env_$pod.yml`
  if [ "$diff_result"x != ""x ]; then
    echo "true"
    return
  fi

  # 内容一样，ConfigMap可能已经更新到Pod内了，需要比较时间
  # https://stackoverflow.com/questions/5731234/how-to-get-the-start-time-of-a-long-running-linux-process
  # 使用这个主要是php内是busybox，这样也能兼容
  start_stamp=`kubectl -n $NS exec -ti $pod -c $container_name -- awk -v ticks="$(getconf CLK_TCK)" -v epoch="$(date +%s)" ' NR==1 { now=$1; next } END { printf "%9.0f\n", epoch - (now-($20/ticks)) }' /proc/uptime RS=')' /proc/1/stat | tr -d '\r'`
  titan_env_mtime=`kubectl -n $NS exec -ti $pod -c $container_name -- stat /titan-env/titan-env.yml | grep Modify: | awk -F 'Modify:' '{print $2}'`

  env_mtime_stamp=`date -d "$titan_env_mtime" +%s`

  if [[ $env_mtime_stamp -gt $start_stamp ]]; then
    echo "true"
  else
    echo "false"
  fi
}

function check_web(){
  web_pod=`kubectl get po -n $NS | grep titan-web.*Running | head -n 1 | awk '{print $1}'`
  result=`check_titan_env $web_pod titan-web`
  if [[ $result =~ "true" ]]; then
    kubectl -n $NS rollout restart daemonset titan-web
  fi
}

function check_java(){
  wisteria_pod=`kubectl get po -n $NS | grep titan-wisteria.*Running | head -n 1 | awk '{print $1}'`
  result=`check_titan_env $wisteria_pod titan-wisteria`
  if [[ $result =~ "true" ]]; then
    kubectl -n $NS rollout restart deployment titan-wisteria titan-gateway titan-detect-srv
  fi
}

function check_patrol(){
  patrol_pod=`kubectl get po -n $NS | grep titan-patrol.*Running | head -n 1 | awk '{print $1}'`
  result=`check_titan_env $patrol_pod titan-patrol`
  if [[ $result =~ "true" ]]; then
    kubectl -n $NS rollout restart deployment titan-patrol
  fi
}

function check_upgrade(){
  # 开始检查升级
  toVersion=`cat /data/var_file.yml | grep ^common_tag: | awk '{print $2}' | grep -v COMMON_TAG`
  if [[ $toVersion == "" ]]; then
    echo "false"
    return
  fi

  to_version_stamp=`echo $toVersion | awk -F '-' '{print $NF}'`
  
  php_version_stamp=`kubectl -n $NS get daemonset titan-web -o yaml | grep -E '[ ]+image:' | head -n 1 | awk -F '-' '{print $NF}'`
  wisteria_version_stamp=`kubectl -n $NS get deploy titan-wisteria -o yaml | grep -E '[ ]+image:' | head -n 1 | awk -F '-' '{print $NF}'`
  if [[ $php_version_stamp == "" ]] || [[ $wisteria_version_stamp == "" ]]; then
    echo "false"
    return
  fi

  # 判断版本大于wisteria或php的版本才升级
  if [[ $to_version_stamp -gt $php_version ]] || [[ $to_version_stamp -gt $wisteria_version ]]; then
    echo "true"
  else
    echo "false"
  fi
}

function do_upgrade(){
  cd /data/ && ansible-playbook upgrade.yml -v
  # 如果自动升级执行成功，则更新 titan-system-status 里的 upgrade_retry 为0
  if [ $? -eq 0 ]; then
    install_date=`date +'%Y%m%d%H%M%S'`
    kubectl -n $NS patch configmap/titan-system-status --type merge -p "{\"data\":{\"upgrade_retry\":\"0\"}}"
  else
    # 获取之前的retry
    retry_times=`kubectl -n $NS get cm titan-system-status -o jsonpath='{.data.upgrade_retry}'`
    retry_times=$((retry_times+1))
    kubectl -n $NS patch configmap/titan-system-status --type merge -p "{\"data\":{\"upgrade_retry\":\"$retry_times\"}}"
      
    if [[ $retry_times -lt 3 ]]; then
      # 失败，因为会自动重试，则主动sleep 30s
      sleep 30 && exit 1
    else 
      # retry达到3次则exit 0,
      echo "Maximum number of retries reached" && exit 0
    fi
  fi
}

function do_update_env(){
    # 检查配置，看是否需要自动重启以应用配置
    echo "check titan-env updated and if need restart service"
    kubectl -n $NS get cm titan-env -o jsonpath='{.data.titan-env\.yml}' > /tmp/old-titan-env.yml
  
    check_web
    check_java
    check_patrol

    # todo 检查 8002 的地址和配置是否一致，不一样则自动执行 update_agent_config
}

function do_install(){
    kubectl -n $NS get configmap titan-system-status || kubectl -n $NS create configmap titan-system-status --from-literal=created_at=`date +'%Y%m%d%H%M%S'`
    # 自动安装
    /data/scripts/titan_install_auto
    # 如果自动安装执行成功，则更新 titan-system-status 里的 install_done
    if [ $? -eq 0 ]; then
      install_date=`date +'%Y%m%d%H%M%S'`
      kubectl -n $NS patch configmap/titan-system-status --type merge -p "{\"data\":{\"install_done\":\"$install_date\"}}"
    else
      # 获取之前的retry
      retry_times=`kubectl -n $NS get cm titan-system-status -o jsonpath='{.data.install_retry}'`
      retry_times=$((retry_times+1))
      kubectl -n $NS patch configmap/titan-system-status --type merge -p "{\"data\":{\"install_retry\":\"$retry_times\"}}"
      
      if [[ $retry_times -lt 3 ]]; then
        # 失败，因为会自动重试，则主动sleep 30s
        sleep 30 && exit 1
      else 
        # retry达到3次则exit 0,
        echo "Maximum number of retries reached" && exit 0
      fi
    fi
}


if [[ $1 == "--config" ]] ; then
  cat <<EOF
{
  "configVersion": "v1",
  "kubernetes": [
    {
      "name":"OnCreateTitanEnv",
      "apiVersion": "v1",
      "kind": "ConfigMap",
      "executeHookOnEvent":["Added", "Modified"],
      "namespace": {"nameSelector":{"matchNames": ["$NS"]}},
      "nameSelector": {"matchNames": ["titan-env"]}
    }
  ],
  "settings": {
    "executionMinInterval": 15s,
    "executionBurst": 1
  }
}
EOF
else
  # 还没有titan-env 则直接退出
  kubectl -n $NS get cm titan-env -o yaml || exit 0

  check_status
  if [[ $installed == "true" ]]; then
    # 已安装完成，则检查是否需要upgrade/或者是否需要更新env配置
    echo "check for upgrade"
    upgrade_flag=`check_upgrade`
    if [[ $upgrade_flag =~ "true" ]]; then
      # 执行自动升级
      do_upgrade >> /logs/upgrade.log 2>&1
    else
      do_update_env
    fi

  else
    do_install >> /logs/install.log 2>&1
  fi
fi
