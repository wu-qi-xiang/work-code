from __future__ import (absolute_import, division, print_function)
__metaclass__ = type

import os
import time
from ansible.plugins.action import ActionBase


class ActionModule(ActionBase):
    ''' Fail with custom message '''

    TRANSFERS_FILES = False
    _VALID_ARGS = frozenset(('parallel_names',))

    def run(self, tmp=None, task_vars=None):
        if task_vars is None:
            task_vars = dict()

        result = super(ActionModule, self).run(tmp, task_vars)
        del tmp  # tmp no longer has any effect

        parallel_names = self._task.args.get('parallel_names')
        parallel_parent_dir = os.path.expanduser("~/.ansible_parallel")

        end_parallel_names = []
        while True:
            time.sleep(0.3)
            for parallel_name in parallel_names:
                parallel_dir = os.path.join(parallel_parent_dir, parallel_name)
                parallel_result = os.path.join(parallel_dir, "result")
                # 如果子进程目录不存在，则不处理这个
                if not os.path.exists(parallel_dir):
                    parallel_names.remove(parallel_name)
                    continue

                # 如果已经出现 result 文件，说明结束了
                if os.path.exists(parallel_result):
                    parallel_names.remove(parallel_name)
                    end_parallel_names.append(parallel_name)
                    continue

            if len(parallel_names) == 0:
                break

        result['failed'] = False
        result['msg'] = "parallel jobs [ %s ] end" % " ".join(end_parallel_names)
        return result
