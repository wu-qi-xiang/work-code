# (c) 2012-2014, Michael DeHaan <michael.dehaan@gmail.com>
#
# This file is part of Ansible
#
# Ansible is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# Ansible is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with Ansible.  If not, see <http://www.gnu.org/licenses/>.
# Make coding more python3-ish
from __future__ import (absolute_import, division, print_function)
__metaclass__ = type

DOCUMENTATION = '''
    strategy: parallel
    short_description: Executes tasks in a linear fashion,support parallel
    description:
        - Task execution is extedn from linear, can execute task parallelly. for operate k8s
    version_added: "2.9"
    notes:
     - This was the  Ansible parallel plugins which can execute parallel ansible job.
    author: yong.liang@qingteng.cn
'''
import os
import shutil
import errno
import sys
import time
import threading 
from multiprocessing import Manager

from ansible import constants as C
from ansible.errors import AnsibleError, AnsibleAssertionError
from ansible.executor import action_write_locks
from ansible.executor.task_queue_manager import FinalQueue
from ansible.executor.task_result import TaskResult
from ansible.module_utils.six.moves import queue as Queue
from ansible.module_utils.six import iteritems, itervalues, string_types
from ansible.executor.play_iterator import PlayIterator
from ansible.module_utils.six import iteritems
from ansible.module_utils._text import to_text
from ansible.parsing.yaml.loader import AnsibleLoader
from ansible.playbook.block import Block
from ansible.playbook.handler import Handler
from ansible.playbook.included_file import IncludedFile
from ansible.playbook.task import Task
from ansible.plugins import AnsiblePlugin, get_plugin_class
from ansible.plugins import loader as plugin_loader
from ansible.plugins.loader import action_loader
from ansible.plugins.strategy import StrategyBase,StrategySentinel,results_thread_main
from ansible.plugins.strategy.linear import StrategyModule as LinearStrategy
from ansible.template import Templar
from ansible.utils.display import Display
from ansible.utils.multiprocessing import context as multiprocessing_context

display = Display()

class ParallelStrategySentinel:
    def __init__(self, *args, **kwargs):
        self.pid = os.getpid()

def parallel_results_thread_main(strategy):
    while True:
        try:
            time.sleep(0.05)
            result = strategy._parallel_child_queue.get_nowait()
            display.debug("[parallel_results_thread_main] wait child")

            if isinstance(result, ParallelStrategySentinel):
                child_pid = result.pid
                display.debug("[parallel_results_thread_main] main got ParallelStrategySentinel of %d" % child_pid)
                parallel_name = strategy._parallel_child_map.pop(child_pid)
                display.banner(u"PARALLEL JOB [%s %d] end" % (parallel_name, child_pid), color=C.COLOR_CHANGED)
                
                # waitpid of child process to avoid zombie process
                display.debug("[parallel_results_thread_main] Start watching %s " % (child_pid))
                count=2
                while os.waitpid(child_pid, os.WNOHANG) == (0, 0):
                    display.debug("[parallel_results_thread_main] %s still running" % child_pid)
                    time.sleep(0.2)
                    count = count -1

                    if count <= 0:
                        # actually kill it
                        display.debug("[parallel_results_thread_main] Timeout reached, now killing %s" % (child_pid))
                        os.killpg(child_pid, signal.SIGKILL)
                        display.debug("[parallel_results_thread_main] Sent kill to group %s " % child_pid)
                # waitpid end

                # 释放子任务信号量
                strategy._parallel_semaphore.release()
                # 获取并展示子进程的最后一个task的结果
                status, last_msg = strategy.get_parallel_child_result(parallel_name)
                display.banner("PARALLEL JOB [ %s ] last task result:" % (parallel_name))
                display.display(last_msg + "\n\n")

                if len(strategy._parallel_child_map) == 0:
                    display.debug("[parallel_results_thread_main] all child exited")
                    break
            else:
                display.debug("[parallel_results_thread_main] unknow message, %s" % result._task)
        except (IOError, EOFError) as e:
            display.debug("[parallel_results_thread_main] got error %s" % e)
            break
        except Queue.Empty:
            pass
        except Exception as e:
            display.debug("[parallel_results_thread_main] exception: %s" % e)
            #raise


class StrategyModule(LinearStrategy):

    def __init__(self, *args, **kwargs):
        super(LinearStrategy, self).__init__(*args, **kwargs)

        self._parallel_results_thread = threading.Thread(target=parallel_results_thread_main, args=(self,))
        self._parallel_results_thread.daemon = True
        self._parallel_results_thread.start()
        self._parallel_main = True
        self._parallel_child_map = {}
        self._parallel_child_queue = Manager().Queue()

        semaphore_num = self.get_semaphore_num_config()
        # 并发子任务添加信号量控制，控制最大并发数量
        self._parallel_semaphore = threading.Semaphore(semaphore_num)

    def get_semaphore_num_config(self):
        try:
            defs={"semaphore_num": {
                'description': 'strategy_parallel semaphore_num',
                'ini': [
                    {
                        'section': 'strategy.parallel',
                        'key': "semaphore_num",
                    }
                ],
                'env': [
                    {'name': 'ANSIBLE_STRATEGY_PARALLEL_SEMAPHORE_NUM'},
                ],
                'required': False,
            }}
            C.config.initialize_plugin_configuration_definitions('strategy', "parallel", defs)
            config_values = C.config.get_plugin_options("strategy","parallel")
            return int(config_values.get("semaphore_num",1))
        except AnsibleError as e:
            print(e)
            return 1

    def _try_parallel_child_semaphore(self):
        count=0
        while True:
            if self._parallel_semaphore.acquire(timeout=3):
                display.debug("[_try_parallel_child_semaphore] get parallel_child_semaphore success")
                break
            else:
                if count % 20 == 0:
                    display.banner(u"parallel job number reach limit, now wait some child job end")
                count = count + 1

    def cleanup(self):
        # close active persistent connections
        for sock in itervalues(self._active_connections):
            try:
                conn = Connection(sock)
                conn.reset()
            except ConnectionError as e:
                # most likely socket is already closed
                display.debug("got an error while closing persistent connection: %s" % e)
        display.debug("cleanup of %d" % (os.getpid()))
        self._final_q.put(StrategySentinel())
        self._results_thread.join()

        if not self._parallel_main:
            # notify main process: this child end
            self._parallel_child_queue.put(ParallelStrategySentinel())
            display.debug("exit %d" % (os.getpid()))
            os._exit(0)
        else:
            if len(self._parallel_child_map) > 0:
                for pid, parallel_name in self._parallel_child_map.items():
                    display.banner(u"PARALLEL JOB [%s %d] still running" % (parallel_name, pid), color=C.COLOR_CHANGED)
                self._parallel_results_thread.join()

    def wait_parallel_child(self, parallel_names):
        '''
            等待子进程结束
        '''
        while True:
            time.sleep(0.05)
            for parallel_name in parallel_names:
                if not parallel_name in self._parallel_child_map:
                    parallel_names.remove(parallel_name)

            if len(parallel_names) == 0:
                break

    def _get_parallel_dir(self, parallel_name):
        parallel_parent_dir = os.path.expanduser("~/.ansible_parallel")
        parallel_dir = os.path.join(parallel_parent_dir, parallel_name)
        return parallel_dir

    def get_parallel_dir(self, parallel_name):
        '''
            获取子进程输出目录
        '''
        parallel_dir = self._get_parallel_dir(parallel_name)
        try:
            if os.path.exists(parallel_dir):
                shutil.rmtree(parallel_dir)
            os.makedirs(parallel_dir)
        except OSError as exc: 
            if exc.errno == errno.EEXIST and os.path.isdir(parallel_dir):
                pass
        return parallel_dir

    def get_parallel_child_result(self, parallel_name):
        '''
            获取子进程执行的最后一个Task
        '''
        parallel_dir = self._get_parallel_dir(parallel_name)
        # 读取 parallel_dir/result
        result = self._tqm.RUN_OK
        with open(os.path.join(parallel_dir, "result"), 'r') as f_result:
            result = int(f_result.readline().strip())

        # 解析 parallel_dir/output,获取最后一个 TASK [ 直到末尾之间的内容， 很不优雅
        with open(os.path.join(parallel_dir, "output.log"), 'r') as f_output:
            lines = f_output.readlines()

            last_task_index = 0
            for i,line in enumerate(lines):
                if line.startswith("TASK ["):
                    last_task_index = i

            return result, "\n".join(lines[last_task_index:])

    def write_parallel_child_result(self, result):
        '''
            写入子进程执行结果
        '''
        if self._parallel_main:
            return

        parallel_dir = self._get_parallel_dir(self.parallel_name)
        # 读取 parallel_dir/result
        result = self._tqm.RUN_OK
        with open(os.path.join(parallel_dir, "result"), 'w') as f_result:
            f_result.write(str(result))

    def cleanup_child_result(self, parallel_name):
        '''
            主进程清理子进程的输出日志等信息，避免影响下次任务
        '''
        # 暂不处理
        pass


    def run(self, iterator, play_context):
        '''
        ## modify start
        大部分逻辑继承自 linear, 判断有 ansible_parallel 时才走自定义的 parallel 流程
        ## modify end
        '''

        # iterate over each task, while there is one left to run
        result = self._tqm.RUN_OK
        work_to_do = True

        self._set_hosts_cache(iterator._play)

        while work_to_do and not self._tqm._terminated:

            try:
                display.debug("getting the remaining hosts for this loop")
                hosts_left = self.get_hosts_left(iterator)
                display.debug("done getting the remaining hosts for this loop")

                # queue up this task for each host in the inventory
                callback_sent = False
                work_to_do = False

                host_results = []
                host_tasks = self._get_next_task_lockstep(hosts_left, iterator)

                ## modify start
                for host_task in host_tasks:
                    display.debug("check task name:" + str(host_task[1]))

                ## todo 判断是否 parallel 类型的 Task
                host_task = host_tasks[0]
                task = host_task[1]
                if task and "ansible_parallel" in task.get_vars():
                    task_vars = task.get_vars()
                    # 开始并行执行
                    parallel_name=task_vars["ansible_parallel"]
                    if not self._parallel_main:
                        if parallel_name == self.parallel_name:
                            display.debug("continue executed in this child process")
                        else:
                            display.debug("this child process end, %s, %s" % (parallel_name, self.parallel_name))
                            work_to_do = False
                            continue
                    else:
                        # 判断已启动并发子进程，则主进程不处理此任务并继续. 对应的场景是连续的两个task的ansible_parallel名称相同
                        # 注意ansible_parallel相同的task必须是连续的
                        if parallel_name in self._parallel_child_map.values():
                            display.debug("this task will executed in exist child process,continue next task")
                            ## 需要修改 work_to_do 状态，否则都block，无法继续执行下面的任务
                            work_to_do = True
                            continue

                        # 需要启动并发子任务的，尝试获取信号量
                        self._try_parallel_child_semaphore()

                        pid = os.fork()
                        #根据 pid 值，分别为子进程和父进程布置任务
                        if pid == 0:
                            display.debug('child process, ID=' + str(os.getpid()) + ", ppid="+ str(os.getppid()))
                            self._parallel_main = False
                            
                            # 不支持交互
                            parallel_dir = self.get_parallel_dir(parallel_name)
                            child_log = open(os.path.join(parallel_dir, "output.log"), "a")
                            sys.stdout = child_log
                            sys.stderr = child_log
                            
                            child_queue = FinalQueue() 
                            self._final_q = child_queue
                            # create the result processing thread for reading results in the background
                            self._results_thread = threading.Thread(target=results_thread_main, args=(self,))
                            self._results_thread.daemon = True
                            self._results_thread.start()
                            self.parallel_name = parallel_name

                            num = len(self._workers)
                            display.debug('reinit _workers %d' % num)
                            self._workers = []
                            for i in range(num):
                                self._workers.append(None)

                        else:
                            self._parallel_child_map[pid] = parallel_name
                            display.banner(u"PARALLEL JOB [%s %d] start" % (parallel_name, pid), color=C.COLOR_CHANGED)
                            ## 需要处理状态，否则都block，无法继续执行下面的任务??
                            work_to_do = True
                            continue
                elif task and not "ansible_parallel" in task.get_vars():
                    task_vars = task.get_vars()
                    if not self._parallel_main:
                         work_to_do = False
                         continue
                ## modify end

                # skip control
                skip_rest = False
                choose_step = True

                # flag set if task is set to any_errors_fatal
                any_errors_fatal = False

                results = []
                for (host, task) in host_tasks:
                    if not task:
                        continue

                    if self._tqm._terminated:
                        break

                    run_once = False
                    work_to_do = True

                    # check to see if this task should be skipped, due to it being a member of a
                    # role which has already run (and whether that role allows duplicate execution)
                    if task._role and task._role.has_run(host):
                        # If there is no metadata, the default behavior is to not allow duplicates,
                        # if there is metadata, check to see if the allow_duplicates flag was set to true
                        if task._role._metadata is None or task._role._metadata and not task._role._metadata.allow_duplicates:
                            display.debug("'%s' skipped because role has already run" % task)
                            continue

                    display.debug("getting variables")
                    task_vars = self._variable_manager.get_vars(play=iterator._play, host=host, task=task,
                                                                _hosts=self._hosts_cache, _hosts_all=self._hosts_cache_all)
                    self.add_tqm_variables(task_vars, play=iterator._play)
                    templar = Templar(loader=self._loader, variables=task_vars)
                    display.debug("done getting variables")

                    # test to see if the task across all hosts points to an action plugin which
                    # sets BYPASS_HOST_LOOP to true, or if it has run_once enabled. If so, we
                    # will only send this task to the first host in the list.

                    task_action = templar.template(task.action)

                    try:
                        action = action_loader.get(task_action, class_only=True, collection_list=task.collections)
                    except KeyError:
                        # we don't care here, because the action may simply not have a
                        # corresponding action plugin
                        action = None

                    if task_action in C._ACTION_META:
                        # for the linear strategy, we run meta tasks just once and for
                        # all hosts currently being iterated over rather than one host
                        results.extend(self._execute_meta(task, play_context, iterator, host))
                        if task.args.get('_raw_params', None) not in ('noop', 'reset_connection', 'end_host', 'role_complete'):
                            run_once = True
                        if (task.any_errors_fatal or run_once) and not task.ignore_errors:
                            any_errors_fatal = True
                    else:
                        # handle step if needed, skip meta actions as they are used internally
                        if self._step and choose_step:
                            if self._take_step(task):
                                choose_step = False
                            else:
                                skip_rest = True
                                break

                        run_once = templar.template(task.run_once) or action and getattr(action, 'BYPASS_HOST_LOOP', False)

                        if (task.any_errors_fatal or run_once) and not task.ignore_errors:
                            any_errors_fatal = True

                        if not callback_sent:
                            display.debug("sending task start callback, copying the task so we can template it temporarily")
                            saved_name = task.name
                            display.debug("done copying, going to template now")
                            try:
                                task.name = to_text(templar.template(task.name, fail_on_undefined=False), nonstring='empty')
                                display.debug("done templating")
                            except Exception:
                                # just ignore any errors during task name templating,
                                # we don't care if it just shows the raw name
                                display.debug("templating failed for some reason")
                            display.debug("here goes the callback...")
                            self._tqm.send_callback('v2_playbook_on_task_start', task, is_conditional=False)
                            task.name = saved_name
                            callback_sent = True
                            display.debug("sending task start callback")

                        self._blocked_hosts[host.get_name()] = True
                        self._queue_task(host, task, task_vars, play_context)
                        del task_vars

                    # if we're bypassing the host loop, break out now
                    if run_once:
                        break

                    results += self._process_pending_results(iterator, max_passes=max(1, int(len(self._tqm._workers) * 0.1)))

                # go to next host/task group
                if skip_rest:
                    continue

                display.debug("done queuing things up, now waiting for results queue to drain")
                if self._pending_results > 0:
                    results += self._wait_on_pending_results(iterator)

                host_results.extend(results)

                self.update_active_connections(results)

                included_files = IncludedFile.process_include_results(
                    host_results,
                    iterator=iterator,
                    loader=self._loader,
                    variable_manager=self._variable_manager
                )

                include_failure = False
                if len(included_files) > 0:
                    display.debug("we have included files to process")

                    display.debug("generating all_blocks data")
                    all_blocks = dict((host, []) for host in hosts_left)
                    display.debug("done generating all_blocks data")
                    for included_file in included_files:
                        display.debug("processing included file: %s" % included_file._filename)
                        # included hosts get the task list while those excluded get an equal-length
                        # list of noop tasks, to make sure that they continue running in lock-step
                        try:
                            if included_file._is_role:
                                new_ir = self._copy_included_file(included_file)

                                new_blocks, handler_blocks = new_ir.get_block_list(
                                    play=iterator._play,
                                    variable_manager=self._variable_manager,
                                    loader=self._loader,
                                )
                            else:
                                new_blocks = self._load_included_file(included_file, iterator=iterator)

                            display.debug("iterating over new_blocks loaded from include file")
                            for new_block in new_blocks:
                                task_vars = self._variable_manager.get_vars(
                                    play=iterator._play,
                                    task=new_block.get_first_parent_include(),
                                    _hosts=self._hosts_cache,
                                    _hosts_all=self._hosts_cache_all,
                                )
                                display.debug("filtering new block on tags")
                                final_block = new_block.filter_tagged_tasks(task_vars)
                                display.debug("done filtering new block on tags")

                                noop_block = self._prepare_and_create_noop_block_from(final_block, task._parent, iterator)

                                for host in hosts_left:
                                    if host in included_file._hosts:
                                        all_blocks[host].append(final_block)
                                    else:
                                        all_blocks[host].append(noop_block)
                            display.debug("done iterating over new_blocks loaded from include file")

                        except AnsibleError as e:
                            for host in included_file._hosts:
                                self._tqm._failed_hosts[host.name] = True
                                iterator.mark_host_failed(host)
                            display.error(to_text(e), wrap_text=False)
                            include_failure = True
                            continue

                    # finally go through all of the hosts and append the
                    # accumulated blocks to their list of tasks
                    display.debug("extending task lists for all hosts with included blocks")

                    for host in hosts_left:
                        iterator.add_tasks(host, all_blocks[host])

                    display.debug("done extending task lists")
                    display.debug("done processing included files")

                display.debug("results queue empty")

                display.debug("checking for any_errors_fatal")
                failed_hosts = []
                unreachable_hosts = []
                for res in results:
                    # execute_meta() does not set 'failed' in the TaskResult
                    # so we skip checking it with the meta tasks and look just at the iterator
                    if (res.is_failed() or res._task.action in C._ACTION_META) and iterator.is_failed(res._host):
                        failed_hosts.append(res._host.name)
                    elif res.is_unreachable():
                        unreachable_hosts.append(res._host.name)

                # if any_errors_fatal and we had an error, mark all hosts as failed
                if any_errors_fatal and (len(failed_hosts) > 0 or len(unreachable_hosts) > 0):
                    dont_fail_states = frozenset([iterator.ITERATING_RESCUE, iterator.ITERATING_ALWAYS])
                    for host in hosts_left:
                        (s, _) = iterator.get_next_task_for_host(host, peek=True)
                        # the state may actually be in a child state, use the get_active_state()
                        # method in the iterator to figure out the true active state
                        s = iterator.get_active_state(s)
                        if s.run_state not in dont_fail_states or \
                           s.run_state == iterator.ITERATING_RESCUE and s.fail_state & iterator.FAILED_RESCUE != 0:
                            self._tqm._failed_hosts[host.name] = True
                            result |= self._tqm.RUN_FAILED_BREAK_PLAY
                ## modify start
                display.debug("result:" + str(result))
                ## modify end
                display.debug("done checking for any_errors_fatal")

                display.debug("checking for max_fail_percentage")
                if iterator._play.max_fail_percentage is not None and len(results) > 0:
                    percentage = iterator._play.max_fail_percentage / 100.0

                    if (len(self._tqm._failed_hosts) / iterator.batch_size) > percentage:
                        for host in hosts_left:
                            # don't double-mark hosts, or the iterator will potentially
                            # fail them out of the rescue/always states
                            if host.name not in failed_hosts:
                                self._tqm._failed_hosts[host.name] = True
                                iterator.mark_host_failed(host)
                        self._tqm.send_callback('v2_playbook_on_no_hosts_remaining')
                        result |= self._tqm.RUN_FAILED_BREAK_PLAY
                    display.debug('(%s failed / %s total )> %s max fail' % (len(self._tqm._failed_hosts), iterator.batch_size, percentage))
                display.debug("done checking for max_fail_percentage")

                display.debug("checking to see if all hosts have failed and the running result is not ok")
                if result != self._tqm.RUN_OK and len(self._tqm._failed_hosts) >= len(hosts_left):
                    display.debug("^ not ok, so returning result now")
                    self._tqm.send_callback('v2_playbook_on_no_hosts_remaining')
                    ## modify start
                    self.write_parallel_child_result(result)
                    ## modify end
                    return result
                display.debug("done checking to see if all hosts have failed")

            except (IOError, EOFError) as e:
                display.debug("got IOError/EOFError in task loop: %s" % e)
                # most likely an abort, return failed
                self.write_parallel_child_result(self._tqm.RUN_UNKNOWN_ERROR)
                ## modify start
                self.write_parallel_child_result(result)
                ## modify end
                return self._tqm.RUN_UNKNOWN_ERROR

        # run the base class run() method, which executes the cleanup function
        # and runs any outstanding handlers which have been triggered
        ## modify start
        if self._parallel_main:
            display.debug("run super to run handlers and cleanup ")
            return super(LinearStrategy, self).run(iterator, play_context, result)
        else:
            self.write_parallel_child_result(result)
            return result
        ## modify end
