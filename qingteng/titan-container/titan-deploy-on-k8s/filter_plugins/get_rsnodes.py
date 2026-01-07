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


'''
# mongoshard_nodes: 所有可用于部署mongo的节点 
[   node1,node2,node3 } 
] 
# shard_pods: 当前已部署的分片pod
[
    { "nodeName": "node1", "name": "mongoshard0-0" },
    { "nodeName": "node2", "name": "mongoshard0-1" },
    { "nodeName": "node3", "name": "mongoshard0-2" }
]
# rs_roles: 当前已部署的分片中的角色分布，primary，secondary等
[ 
    [ { "name": "mongoshard0-0.mongoshard0-hs:27019", "stateStr": "PRIMARY" },
      { "name": "mongoshard0-1.mongoshard0-hs:27019", "stateStr": "SECONDARY" },
      { "name": "mongoshard0-2.mongoshard0-hs:27019", "stateStr": "SECONDARY" }
    ]
]
# 统计每隔节点上 primary、secondary、arbiter 数量
# 从中选择没有master，且实例数量最少的作为新分片的 primary
# 从中选择剩余的节点上实例数量最少的作为新分片的 secondary
# 为了达到这个目的，简化算法，采用权重算法，按照权重算法来分配，权重分别为 4 2 1，按照总得分数最小的排序循环取即可

# 最终返回下一个 primary node , secondary node, arbiter node
'''
def get_rsnodes(mongoshard_nodes,shard_pods,rs_roles, shard_replicas=3):
    weight_dict = {'PRIMARY':4,'SECONDARY':2,'ARBITER':0}
    try:
        all_role_dict = {}
        for one_rs_role in rs_roles:
            one_rs_pri_count = 0
            for roleinfo in one_rs_role:
                name = roleinfo['name'].split('.')[0]
                role = roleinfo['stateStr']
                if role == 'PRIMARY':
                    one_rs_pri_count = one_rs_pri_count + 1
                all_role_dict[name] = role
            
            if one_rs_pri_count > 1:
                raise Exception(one_rs_role[0]['name'].split('-')[0] + " have more than one PRIMARY !")

        print(all_role_dict)
        #初始化所有mongo节点角色数量
        node_role_dict = {}
        for node in mongoshard_nodes:
            node_role_dict[node] = {'PRIMARY':0,'SECONDARY':0,'ARBITER':0,'score':0}
        print(node_role_dict)

        for pod in shard_pods:
            nodeName = pod['nodeName']
            podname = pod['name']
            role = all_role_dict[podname]

            # 异常状态按照 SECONDARY 来算
            if role not in weight_dict.keys():
                role = 'SECONDARY'
            # 当前已存在的pod所在节点不在mongo标签范围,忽略掉
            if  not nodeName in node_role_dict:
                continue

            node_role_dict[nodeName][role] = node_role_dict[nodeName][role] + 1
            node_role_dict[nodeName]['score'] = node_role_dict[nodeName]['score'] + weight_dict[role]
        print(node_role_dict)

        #统计完毕后排序(score和nodeName排序)然后按照顺序选取节点
        sorted_nodes = sorted(node_role_dict.items(), key=lambda kv: (kv[1]['score'],kv[0]))

        pri_node = sorted_nodes[0]
        sec_nodes = sorted_nodes[1:shard_replicas]
        print({"pri_node": pri_node, "sec_nodes": sec_nodes})

        #返回值只取node节点的名称即可
        return {"pri_node": pri_node[0],"sec_nodes":[node[0] for node in sec_nodes] }
    except Exception as e:
        raise errors.AnsibleFilterError("get_rsnodes error: %s" % to_native(e))

class FilterModule(object):
    def filters(self):
        return {
          'get_rsnodes': get_rsnodes
        }