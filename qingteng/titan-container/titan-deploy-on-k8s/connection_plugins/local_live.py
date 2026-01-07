# (c) 2012, Michael DeHaan <michael.dehaan@gmail.com>
# (c) 2015, 2017 Toshio Kuratomi <tkuratomi@ansible.com>
# GNU General Public License v3.0+ (see COPYING or https://www.gnu.org/licenses/gpl-3.0.txt)

from __future__ import (absolute_import, division, print_function)
__metaclass__ = type

DOCUMENTATION = '''
    name: local
    short_description: execute on controller
    description:
        - same as local, can live output
    author: liangyong
    version_added: historical
    notes:
        - The remote user is ignored, the user with which the ansible CLI was executed is used instead.
'''

import os
import pty
import shutil
import subprocess
import fcntl
import getpass

import ansible.constants as C
from ansible.errors import AnsibleError, AnsibleFileNotFound
from ansible.module_utils.compat import selectors
from ansible.module_utils.six import text_type, binary_type
from ansible.module_utils._text import to_bytes, to_native, to_text
from ansible.plugins.connection import ConnectionBase
from ansible.plugins.connection.local import Connection as LocalConnection
from ansible.utils.display import Display
from ansible.utils.path import unfrackpath

display = Display()

class Connection(LocalConnection):
    ''' Local based connections '''

    transport = 'local_live'
    has_pipelining = True

    def __init__(self, *args, **kwargs):

        super(Connection, self).__init__(*args, **kwargs)

    def _handle_live_output(self, data):
        if not data:
            return data

        if data[0] == "\n":
            data = data[1:]

        live_end = b'___live_end___'
        index = data.rfind(live_end)
        if index == -1:
            return data 
        else:
            live_log = to_text(data[:index]).lstrip("\n").replace("___live_end___\n","").replace("___live_end___","")
            display.display('[live]: %s' % (live_log), screen_only=False)
            return data[index+len(live_end):]       

    def exec_command(self, cmd, in_data=None, sudoable=True):
        ''' run a command on the local host '''

        display.debug("in local.exec_command()")

        executable = C.DEFAULT_EXECUTABLE.split()[0] if C.DEFAULT_EXECUTABLE else None

        if not os.path.exists(to_bytes(executable, errors='surrogate_or_strict')):
            raise AnsibleError("failed to find the executable specified %s."
                               " Please verify if the executable exists and re-try." % executable)

        display.vvv(u"EXEC {0}".format(to_text(cmd)), host=self._play_context.remote_addr)
        display.debug("opening command with Popen()")

        if isinstance(cmd, (text_type, binary_type)):
            cmd = to_bytes(cmd)
        else:
            cmd = map(to_bytes, cmd)

        master = None
        stdin = subprocess.PIPE
        if sudoable and self.become and self.become.expect_prompt() and not self.get_option('pipelining'):
            # Create a pty if sudoable for privlege escalation that needs it.
            # Falls back to using a standard pipe if this fails, which may
            # cause the command to fail in certain situations where we are escalating
            # privileges or the command otherwise needs a pty.
            try:
                master, stdin = pty.openpty()
            except (IOError, OSError) as e:
                display.debug("Unable to open pty: %s" % to_native(e))

        p = subprocess.Popen(
            cmd,
            shell=isinstance(cmd, (text_type, binary_type)),
            executable=executable,
            cwd=self.cwd,
            stdin=stdin,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )

        # if we created a master, we can close the other half of the pty now, otherwise master is stdin
        if master is not None:
            os.close(stdin)

        display.debug("done running command with Popen()")

        ###### change start #####
        selector = selectors.DefaultSelector()
        selector.register(p.stdout, selectors.EVENT_READ)
        selector.register(p.stderr, selectors.EVENT_READ)
        ###### change end #####

        if self.become and self.become.expect_prompt() and sudoable:
            fcntl.fcntl(p.stdout, fcntl.F_SETFL, fcntl.fcntl(p.stdout, fcntl.F_GETFL) | os.O_NONBLOCK)
            fcntl.fcntl(p.stderr, fcntl.F_SETFL, fcntl.fcntl(p.stderr, fcntl.F_GETFL) | os.O_NONBLOCK)
            ###### change start #####
            # selector = selectors.DefaultSelector()
            # selector.register(p.stdout, selectors.EVENT_READ)
            # selector.register(p.stderr, selectors.EVENT_READ)
            ###### change end  #####

            become_output = b''
            try:
                while not self.become.check_success(become_output) and not self.become.check_password_prompt(become_output):
                    events = selector.select(self._play_context.timeout)
                    if not events:
                        stdout, stderr = p.communicate()
                        raise AnsibleError('timeout waiting for privilege escalation password prompt:\n' + to_native(become_output))

                    for key, event in events:
                        if key.fileobj == p.stdout:
                            chunk = p.stdout.read()
                        elif key.fileobj == p.stderr:
                            chunk = p.stderr.read()

                    if not chunk:
                        stdout, stderr = p.communicate()
                        raise AnsibleError('privilege output closed while waiting for password prompt:\n' + to_native(become_output))
                    become_output += chunk
            except:
                selector.close()
                raise

            if not self.become.check_success(become_output):
                become_pass = self.become.get_option('become_pass', playcontext=self._play_context)
                if master is None:
                    p.stdin.write(to_bytes(become_pass, errors='surrogate_or_strict') + b'\n')
                else:
                    os.write(master, to_bytes(become_pass, errors='surrogate_or_strict') + b'\n')

            fcntl.fcntl(p.stdout, fcntl.F_SETFL, fcntl.fcntl(p.stdout, fcntl.F_GETFL) & ~os.O_NONBLOCK)
            fcntl.fcntl(p.stderr, fcntl.F_SETFL, fcntl.fcntl(p.stderr, fcntl.F_GETFL) & ~os.O_NONBLOCK)

        display.debug("starting update loop")

        p.stdin.flush()
        p.stdin.close()

        ###### change start #####
        display.debug("starting update live loop")
        stdout = b''
        stdout_done = False
        stderr = b''
        stderr_done = False

        while True:
            events = selector.select(1)
            for key, event in events:
                output = b''
                if key.fileobj == p.stdout:
                    output = os.read(p.stdout.fileno(), 9000)
                    if output == b'':
                        stdout_done = True
                        selector.unregister(p.stdout)
                    stdout += output
                    stdout = self._handle_live_output(stdout)
                elif key.fileobj == p.stderr:
                    output = os.read(p.stderr.fileno(), 9000)
                    if output == b'':
                        stderr_done = True
                        selector.unregister(p.stderr)
                    stderr += output
                    stderr = self._handle_live_output(stderr)
              

            # Exit if the process has closed both fds and the process has
            # finished
            if stdout_done and stderr_done and p.poll() is not None:
                break

        ###### change end #####

        display.debug("done communicating")
        #display.debug(stdout)

        # finally, close the other half of the pty, if it was created
        if master:
            os.close(master)

        display.debug("done with local.exec_command()")
        return (p.returncode, stdout, stderr)
