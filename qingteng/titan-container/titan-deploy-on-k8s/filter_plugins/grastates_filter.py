#! /usr/bin/env python
# -*- coding: utf-8 -*-

# import sys
# reload(sys)
# sys.setdefaultencoding('utf8')
import importlib,sys
importlib.reload(sys)
from ansible import errors
from ansible.module_utils._text import to_native


'''
参数示例:
"grastate_list": ["mysql-0 seqno:2199 safe_to_bootstrap:0", "mysql-1 seqno:2199 safe_to_bootstrap:0"]
'''
def get_need_recovery(grastate_list):
    result = []
    try:
        for grastate in grastate_list:
            tmp_strs = grastate.split()
            podname,seqno,safe_to_bootstrap = tmp_strs[0],tmp_strs[1].split(":")[1],tmp_strs[2].split(":")[1]
            if "seqno:-1" in grastate:
                result.append(podname)

        return result
    except Exception as e:
        raise errors.AnsibleFilterError("get_need_recovery error: %s" % to_native(e))

# 获取seqno 最大的，用于 bootstrap
def grastates_filter(grastate_list):
    try:
        bootstrap_pod = "" 
        max_seqno = -99999

        for grastate in grastate_list:
            tmp_strs = grastate.split()
            podname,seqno,safe_to_bootstrap = tmp_strs[0],tmp_strs[1].split(":")[1],tmp_strs[2].split(":")[1]
            if safe_to_bootstrap == "1":
                seqno = int(seqno) + 1

            if int(seqno) > max_seqno:
                max_seqno = int(seqno)
                bootstrap_pod = podname

        return bootstrap_pod
    except Exception as e:
        raise errors.AnsibleFilterError("grastates_filter error: %s" % to_native(e))

class FilterModule(object):
    def filters(self):
        return {
          'grastates_filter': grastates_filter,
          'get_need_recovery': get_need_recovery
        }