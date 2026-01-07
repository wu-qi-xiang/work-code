#! /usr/bin/env python
# -*- coding: utf-8 -*-

import os
# import sys
# reload(sys)
# sys.setdefaultencoding('utf8')
import importlib,sys
importlib.reload(sys)
import collections
import copy
from ansible import errors
from ansible.module_utils._text import to_native

#按照mster_num，slave_num, nodes来排列组合redis实例，
#保证安装redis集群时，master节点不在一台，同时master所属的slave也不在一台
# hosts: 节点名称，例如 ['node1','node2','node3']
def combine_redis(args):
    try:
        hosts,master_num,slave_num = args[0],args[1],args[2]
        total = master_num + master_num * slave_num
        if len(hosts) < max(master_num, slave_num+1):
            raise Exception("hosts not enough", hosts)
    
        hosts_num = len(hosts)
        #对hosts排序并使用有序字典，保证多次执行的结果一致
        hosts.sort()
        host_dict = collections.OrderedDict()
        for host in hosts:
            host_dict[host] = []
        # 所有的redis实例的编号列表
        instances = list(range(total))

        # 下面这个循环是将 所有实例编号分布到所有host上比如0-5分配到node1,node2,node3
        # 循环后host_dict为 {'node1':[0,3],'node2':[1,4],'node3':[2,5]}
        end = False
        while True:
            for host, values in host_dict.items():
                if len(instances) <= 0:
                    end = True
                    break
                index = instances.pop(0)
                values.append(index)
        
            if end:
                break
    
        #print(host_dict)
        # host_dict转为host_instances，host_instances在此脚本中没什么用了，用于返回给playbook使用
        host_instances = []
        for host, instances in host_dict.items():
            for inst in instances:
                host_instances.append({'host':host,'inst': inst})

        # master与slave的组合结果
        master_slave_dict = collections.OrderedDict()
        #先取主机的第一个实例为master，来保证master不在一台机器上
        for host,instances in host_dict.items():
            master_slave_dict[instances[0]] = []
            if len(master_slave_dict) == master_num:
                break
        #针对每个master，从host中获取他的slave节点
        for master, slaves in master_slave_dict.items():
            for host,instances in host_dict.items():
                #说明当前master已经有足够的slave了，break
                if len(slaves) == slave_num:
                    break
                if len(instances) == 0:
                    continue
                #先从当前master后面的位置取值，如果从前面取，会出现部分master无满足要求的slave
                if master >= instances[0]:
                    continue
                if len(instances) == 0:
                    continue
                elif len(instances) == 1:
                    if instances[0] in master_slave_dict:
                        continue
                    else:
                        slaves.append(instances.pop(0))
                else:
                    slaves.append(instances.pop(1))
            
        
            for host,instances in host_dict.items():
                #说明当前master已经有足够的slave了，break
                if len(slaves) == slave_num:
                    break
                if master <= instances[0]:
                    break
                if len(instances) == 0:
                    continue
                elif len(instances) == 1:
                    if instances[0] in master_slave_dict:
                        continue
                    else:
                        slaves.append(instances.pop(0))
                else:
                    slaves.append(instances.pop(1))

        #print(master_slave_dict)
        return {"master_slave_dict":dict(master_slave_dict),"host_instances": host_instances}
    except Exception as e:
        raise errors.AnsibleFilterError("combine_redis error: %s" % to_native(e))

class FilterModule(object):
    def filters(self):
        return {
          'combine_redis': combine_redis
        }