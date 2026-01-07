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

# 保留老的properties不变
def merge_properties_keepold(new_properties,old_properties):
    try:
        new_properties_dict = {}
        for line in new_properties.splitlines():
            if not "=" in line:
                continue
            if line.strip().startswith("#"):
                continue

            line_data = line.strip()
            prop = line_data.split("=",1)[0]
            value = line_data.split("=",1)[1]

            new_properties_dict[prop] = value

        # 要保留老的配置，那么从新的里面删除老的已经存在的数据
        # 做不到十全十美，如果确实有配置要修改，那么另外的步骤里处理或人工处理
        for line in old_properties.splitlines():
            if not "=" in line:
                continue
            if line.strip().startswith("#"):
                continue

            line_data = line.strip()
            prop = line_data.split("=",1)[0]
            if prop in new_properties_dict:
                del new_properties_dict[prop]

        need_append_strs = []
        for prop, value in new_properties_dict.items():
            need_append_strs.append(prop+"="+value)

        merged_properties =  old_properties + "\n" + "\n".join(need_append_strs)
        return merged_properties

    except Exception as e:
        raise errors.AnsibleFilterError("merge_properties_keepold error: %s" % to_native(e))


class FilterModule(object):
    def filters(self):
        return {
          'merge_properties_keepold': merge_properties_keepold
        }