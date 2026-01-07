#! /usr/bin/env python
# -*- coding: utf-8 -*-

import os
# import sys
# reload(sys)
# sys.setdefaultencoding('utf8')
import importlib,sys
importlib.reload(sys)
from ansible import errors
from ansible.module_utils._text import to_native

# 检查是否都ready，数量是否正确
# {'changed': False, 'resources': [{'kind': 'DaemonSet',....}]}
def daemonset_check(ansibleDaemonsetObj, replicas=None):
    if ansibleDaemonsetObj is None or len(ansibleDaemonsetObj.get("resources",[])) == 0:
        return False
    daemonsetObj = ansibleDaemonsetObj["resources"]
    if isinstance(daemonsetObj, list):
        daemonSet = daemonsetObj[0]
    else:
        daemonSet = daemonsetObj

    desiredNumberScheduled = daemonSet.get("status",{}).get("desiredNumberScheduled",0)
    numberReady = daemonSet.get("status",{}).get("numberReady",0)
    if replicas is not None:
        return (desiredNumberScheduled == replicas) and (numberReady == replicas)
    else:
        return numberReady != 0 and desiredNumberScheduled == numberReady 

def statefulset_check(ansibleStatefulsetObj, replicas=None):
    if ansibleStatefulsetObj is None or len(ansibleStatefulsetObj.get("resources",[])) == 0:
        return False
    statefulObj = ansibleStatefulsetObj["resources"]
    if isinstance(statefulObj, list):
        statefulset = statefulObj[0]
    else:
        statefulset = statefulObj

    curReplicas = statefulset.get("status",{}).get("replicas",0)
    numberReady = statefulset.get("status",{}).get("readyReplicas",0)
    currentRevision = statefulset.get("status",{}).get("currentRevision","")
    updateRevision = statefulset.get("status",{}).get("updateRevision","")
    if currentRevision == updateRevision:
        if replicas is not None:
            return (curReplicas == replicas) and (numberReady == replicas)
        else:
            return numberReady != 0 and curReplicas == numberReady
    else:
        # 说明在更新中
        return False

def deployment_check(ansibleDeploymentObj):
    if ansibleDeploymentObj is None or len(ansibleDeploymentObj.get("resources",[])) == 0:
        return False
    deployObj = ansibleDeploymentObj["resources"]
    if isinstance(deployObj, list):
        deployment = deployObj[0]
    else:
        deployment = deployObj

    replicas = deployment.get("status",{}).get("replicas",0)
    numberReady = deployment.get("status",{}).get("readyReplicas",0)
    return replicas == numberReady

# 检查pod的image符合版本，主要用于升级时判断pod已更新完成，以便继续下面的步骤
def pods_check(data, targetTag=None, replicas=None):
    pods = []
    if isinstance(data,list):
        pods = data
    else:
        pods = [pods]

    # 数量不一致
    if replicas != None and len(pods) != int(replicas):
        return False

    pod_tags = set()
    for pod in pods:
        image = pod["spec"]["containers"][0]["image"]
        tag = image.split(":")[1]
        pod_tags.add(tag)

        phase = pod.get("status",{}).get("phase","")
        if phase != "Running":
            return False

    #print(pod_tags)
    if targetTag == None:
        # 所有pod的tag一样
        return len(pod_tags) == 1
    else:
        # 所有pod的tag一样，且等于目标版本
        return len(pod_tags) == 1 and pod_tags.pop() == targetTag


def resource_exist(data):
    return data and len(data['resources']) > 0


class FilterModule(object):
    def filters(self):
        return {
          'daemonset_check': daemonset_check,
          'statefulset_check': statefulset_check,
          'deployment_check': deployment_check,
          'pods_check': pods_check,
          'resource_exist': resource_exist
        }