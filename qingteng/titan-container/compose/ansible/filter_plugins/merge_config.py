#! /usr/bin/env python
# -*- coding: utf-8 -*-

# import sys
# reload(sys)
# sys.setdefaultencoding('utf8')
import importlib,sys
importlib.reload(sys)
from ansible import errors
from ansible.module_utils._text import to_native
import re

'''
对比新老java.json,默认使用新的java.json, 根据 keepold_paths 获取老的java.json中的值，保留老配置
参数示例:
"keepold_paths": ["host.frontend", "host.backend"]
'''
def merge_json(new_dict,old_dict,keepold_paths):
    try:
        for jsonpath in keepold_paths:
            old_value = get_by_jsonpath(old_dict,jsonpath)
            if old_value is not None:
                set_by_jsonpath(new_dict,jsonpath,old_value)

        return new_dict
    except Exception as e:
        raise errors.AnsibleFilterError("merge_json error: %s" % to_native(e))

def get_by_jsonpath(jsondict,path):
    pahts = path.split(".")
    cur_dict=jsondict
    for p in pahts:
        if not p in cur_dict:
            return None
        cur_dict = cur_dict[p]

    #print("find " + mydict)
    return cur_dict

def set_by_jsonpath(jsondict,path,value):
    pahts = path.split(".")
    last_path = pahts.pop()
    cur_dict=jsondict
    for p in pahts:
        if not p in cur_dict:
            cur_dict[p] = {}
        cur_dict = cur_dict[p]
    
    cur_dict[last_path] = value

# ini 2种模式的需要保留，1: 相等 2:以.结尾
def merge_ini(new_ini,old_ini,keepold_props):
    try:
        merge_dict = {}
        for line in old_ini.splitlines():
            if not "=" in line:
                continue

            prop = line.split("=")[0]
            for keep_prop in keepold_props:
                if prop == keep_prop or (keep_prop.endswith(".") and prop.startswith(keep_prop)):
                    merge_dict[prop] = line

        for prop, line in merge_dict.items():
            #print(r'' + prop + r"=.*\n")
            #print(line)
            new_ini = re.sub(r'' + prop + r"=.*\n", line+"\n", new_ini)

        return new_ini
    except Exception as e:
        raise errors.AnsibleFilterError("merge_ini error: %s" % to_native(e))


class FilterModule(object):
    def filters(self):
        return {
          'merge_json': merge_json,
          'merge_ini': merge_ini
        }