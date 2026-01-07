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

# 统计labels
def labels_stat(all_nodelabels, namespace):
    label_nodes_dict = {}
    for item in all_nodelabels:
        node = item['name']
        labels = item['labels']
        for label in labels:
            if  not label.startswith(namespace + "-"):
                continue
            label_nodes_dict.setdefault(label,[])
            label_nodes_dict[label].append(node)

    return label_nodes_dict;

class FilterModule(object):
    def filters(self):
        return {
          'labels_stat': labels_stat
        }