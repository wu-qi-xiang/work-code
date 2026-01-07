from __future__ import (absolute_import, division, print_function)
__metaclass__ = type

DOCUMENTATION = '''
    name: ssh_live
    short_description: connect via SSH client binary and live output
    description:
        - same as ssh , can live output
    author: liangyong
    extends_documentation_fragment:
        - connection_pipelining
    version_added: historical
    notes:
        - Many options default to C(None) here but that only means we do not override the SSH tool's defaults and/or configuration.
          For example, if you specify the port in this plugin it will override any C(Port) entry in your C(.ssh/config).
    options:
      host:
          description: Hostname/IP to connect to.
          vars:
               - name: inventory_hostname
               - name: ansible_host
               - name: ansible_ssh_host
               - name: delegated_vars['ansible_host']
               - name: delegated_vars['ansible_ssh_host']
      host_key_checking:
          description: Determines if SSH should check host keys.
          default: True
          type: boolean
          ini:
              - section: defaults
                key: 'host_key_checking'
              - section: ssh_connection
                key: 'host_key_checking'
                version_added: '2.5'
          env:
              - name: ANSIBLE_HOST_KEY_CHECKING
              - name: ANSIBLE_SSH_HOST_KEY_CHECKING
                version_added: '2.5'
          vars:
              - name: ansible_host_key_checking
                version_added: '2.5'
              - name: ansible_ssh_host_key_checking
                version_added: '2.5'
      password:
          description: Authentication password for the C(remote_user). Can be supplied as CLI option.
          vars:
              - name: ansible_password
              - name: ansible_ssh_pass
              - name: ansible_ssh_password
      sshpass_prompt:
          description:
              - Password prompt that sshpass should search for. Supported by sshpass 1.06 and up.
              - Defaults to ``Enter PIN for`` when pkcs11_provider is set.
          default: ''
          ini:
              - section: 'ssh_connection'
                key: 'sshpass_prompt'
          env:
              - name: ANSIBLE_SSHPASS_PROMPT
          vars:
              - name: ansible_sshpass_prompt
          version_added: '2.10'
      ssh_args:
          description: Arguments to pass to all SSH CLI tools.
          default: '-C -o ControlMaster=auto -o ControlPersist=60s'
          ini:
              - section: 'ssh_connection'
                key: 'ssh_args'
          env:
              - name: ANSIBLE_SSH_ARGS
          vars:
              - name: ansible_ssh_args
                version_added: '2.7'
      ssh_common_args:
          description: Common extra args for all SSH CLI tools.
          ini:
              - section: 'ssh_connection'
                key: 'ssh_common_args'
                version_added: '2.7'
          env:
              - name: ANSIBLE_SSH_COMMON_ARGS
                version_added: '2.7'
          vars:
              - name: ansible_ssh_common_args
          cli:
              - name: ssh_common_args
          default: ''
      ssh_executable:
          default: ssh
          description:
            - This defines the location of the SSH binary. It defaults to C(ssh) which will use the first SSH binary available in $PATH.
            - This option is usually not required, it might be useful when access to system SSH is restricted,
              or when using SSH wrappers to connect to remote hosts.
          env: [{name: ANSIBLE_SSH_EXECUTABLE}]
          ini:
          - {key: ssh_executable, section: ssh_connection}
          #const: ANSIBLE_SSH_EXECUTABLE
          version_added: "2.2"
          vars:
              - name: ansible_ssh_executable
                version_added: '2.7'
      sftp_executable:
          default: sftp
          description:
            - This defines the location of the sftp binary. It defaults to C(sftp) which will use the first binary available in $PATH.
          env: [{name: ANSIBLE_SFTP_EXECUTABLE}]
          ini:
          - {key: sftp_executable, section: ssh_connection}
          version_added: "2.6"
          vars:
              - name: ansible_sftp_executable
                version_added: '2.7'
      scp_executable:
          default: scp
          description:
            - This defines the location of the scp binary. It defaults to C(scp) which will use the first binary available in $PATH.
          env: [{name: ANSIBLE_SCP_EXECUTABLE}]
          ini:
          - {key: scp_executable, section: ssh_connection}
          version_added: "2.6"
          vars:
              - name: ansible_scp_executable
                version_added: '2.7'
      scp_extra_args:
          description: Extra exclusive to the ``scp`` CLI
          vars:
              - name: ansible_scp_extra_args
          env:
            - name: ANSIBLE_SCP_EXTRA_ARGS
              version_added: '2.7'
          ini:
            - key: scp_extra_args
              section: ssh_connection
              version_added: '2.7'
          cli:
            - name: scp_extra_args
          default: ''
      sftp_extra_args:
          description: Extra exclusive to the ``sftp`` CLI
          vars:
              - name: ansible_sftp_extra_args
          env:
            - name: ANSIBLE_SFTP_EXTRA_ARGS
              version_added: '2.7'
          ini:
            - key: sftp_extra_args
              section: ssh_connection
              version_added: '2.7'
          cli:
            - name: sftp_extra_args
          default: ''
      ssh_extra_args:
          description: Extra exclusive to the SSH CLI.
          vars:
              - name: ansible_ssh_extra_args
          env:
            - name: ANSIBLE_SSH_EXTRA_ARGS
              version_added: '2.7'
          ini:
            - key: ssh_extra_args
              section: ssh_connection
              version_added: '2.7'
          cli:
            - name: ssh_extra_args
          default: ''
      reconnection_retries:
          description: Number of attempts to connect.
          default: 0
          type: integer
          env:
            - name: ANSIBLE_SSH_RETRIES
          ini:
            - section: connection
              key: retries
            - section: ssh_connection
              key: retries
          vars:
            - name: ansible_ssh_retries
              version_added: '2.7'
      port:
          description: Remote port to connect to.
          type: int
          ini:
            - section: defaults
              key: remote_port
          env:
            - name: ANSIBLE_REMOTE_PORT
          vars:
            - name: ansible_port
            - name: ansible_ssh_port
      remote_user:
          description:
              - User name with which to login to the remote server, normally set by the remote_user keyword.
              - If no user is supplied, Ansible will let the SSH client binary choose the user as it normally.
          ini:
            - section: defaults
              key: remote_user
          env:
            - name: ANSIBLE_REMOTE_USER
          vars:
            - name: ansible_user
            - name: ansible_ssh_user
          cli:
            - name: user
      pipelining:
          env:
            - name: ANSIBLE_PIPELINING
            - name: ANSIBLE_SSH_PIPELINING
          ini:
            - section: connection
              key: pipelining
            - section: ssh_connection
              key: pipelining
          vars:
            - name: ansible_pipelining
            - name: ansible_ssh_pipelining

      private_key_file:
          description:
              - Path to private key file to use for authentication.
          ini:
            - section: defaults
              key: private_key_file
          env:
            - name: ANSIBLE_PRIVATE_KEY_FILE
          vars:
            - name: ansible_private_key_file
            - name: ansible_ssh_private_key_file
          cli:
            - name: private_key_file
              option: '--private-key'

      control_path:
        description:
          - This is the location to save SSH's ControlPath sockets, it uses SSH's variable substitution.
          - Since 2.3, if null (default), ansible will generate a unique hash. Use `%(directory)s` to indicate where to use the control dir path setting.
          - Before 2.3 it defaulted to `control_path=%(directory)s/ansible-ssh-%%h-%%p-%%r`.
          - Be aware that this setting is ignored if `-o ControlPath` is set in ssh args.
        env:
          - name: ANSIBLE_SSH_CONTROL_PATH
        ini:
          - key: control_path
            section: ssh_connection
        vars:
          - name: ansible_control_path
            version_added: '2.7'
      control_path_dir:
        default: ~/.ansible/cp
        description:
          - This sets the directory to use for ssh control path if the control path setting is null.
          - Also, provides the `%(directory)s` variable for the control path setting.
        env:
          - name: ANSIBLE_SSH_CONTROL_PATH_DIR
        ini:
          - section: ssh_connection
            key: control_path_dir
        vars:
          - name: ansible_control_path_dir
            version_added: '2.7'
      sftp_batch_mode:
        default: 'yes'
        description: 'TODO: write it'
        env: [{name: ANSIBLE_SFTP_BATCH_MODE}]
        ini:
        - {key: sftp_batch_mode, section: ssh_connection}
        type: bool
        vars:
          - name: ansible_sftp_batch_mode
            version_added: '2.7'
      ssh_transfer_method:
        description:
            - "Preferred method to use when transferring files over ssh"
            - Setting to 'smart' (default) will try them in order, until one succeeds or they all fail
            - Using 'piped' creates an ssh pipe with ``dd`` on either side to copy the data
        choices: ['sftp', 'scp', 'piped', 'smart']
        env: [{name: ANSIBLE_SSH_TRANSFER_METHOD}]
        ini:
            - {key: transfer_method, section: ssh_connection}
        vars:
            - name: ansible_ssh_transfer_method
              version_added: '2.12'
      scp_if_ssh:
        default: smart
        description:
          - "Preferred method to use when transfering files over SSH."
          - When set to I(smart), Ansible will try them until one succeeds or they all fail.
          - If set to I(True), it will force 'scp', if I(False) it will use 'sftp'.
          - This setting will overridden by ssh_transfer_method if set.
        env: [{name: ANSIBLE_SCP_IF_SSH}]
        ini:
        - {key: scp_if_ssh, section: ssh_connection}
        vars:
          - name: ansible_scp_if_ssh
            version_added: '2.7'
      use_tty:
        version_added: '2.5'
        default: 'yes'
        description: add -tt to ssh commands to force tty allocation.
        env: [{name: ANSIBLE_SSH_USETTY}]
        ini:
        - {key: usetty, section: ssh_connection}
        type: bool
        vars:
          - name: ansible_ssh_use_tty
            version_added: '2.7'
      timeout:
        default: 10
        description:
            - This is the default ammount of time we will wait while establishing an SSH connection.
            - It also controls how long we can wait to access reading the connection once established (select on the socket).
        env:
            - name: ANSIBLE_TIMEOUT
            - name: ANSIBLE_SSH_TIMEOUT
              version_added: '2.11'
        ini:
            - key: timeout
              section: defaults
            - key: timeout
              section: ssh_connection
              version_added: '2.11'
        vars:
          - name: ansible_ssh_timeout
            version_added: '2.11'
        cli:
          - name: timeout
        type: integer
      pkcs11_provider:
        version_added: '2.12'
        default: ""
        description:
          - "PKCS11 SmartCard provider such as opensc, example: /usr/local/lib/opensc-pkcs11.so"
          - Requires sshpass version 1.06+, sshpass must support the -P option.
        env: [{name: ANSIBLE_PKCS11_PROVIDER}]
        ini:
          - {key: pkcs11_provider, section: ssh_connection}
        vars:
          - name: ansible_ssh_pkcs11_provider
'''

import errno
import fcntl
import hashlib
import os
import pty
import re
import subprocess
import time

from functools import wraps
from ansible import constants as C
from ansible.errors import (
    AnsibleAuthenticationFailure,
    AnsibleConnectionFailure,
    AnsibleError,
    AnsibleFileNotFound,
)
from ansible.errors import AnsibleOptionsError
from ansible.module_utils.compat import selectors
from ansible.module_utils.six import PY3, text_type, binary_type
from ansible.module_utils.six.moves import shlex_quote
from ansible.module_utils._text import to_bytes, to_native, to_text
from ansible.module_utils.parsing.convert_bool import BOOLEANS, boolean
from ansible.plugins.connection import ConnectionBase, BUFSIZE
from ansible.plugins.connection.ssh import Connection as SSHConnection
from ansible.plugins.shell.powershell import _parse_clixml
from ansible.utils.display import Display
from ansible.utils.path import unfrackpath, makedirs_safe

display = Display()

class Connection(SSHConnection):
    ''' ssh based connections '''

    transport = 'ssh_live'
    has_pipelining = True

    def __init__(self, *args, **kwargs):
        super(Connection, self).__init__(*args, **kwargs)

    def _handle_live_output(self, data):
        if not data:
            return data

        live_end = b'___live_end___'
        index = data.rfind(live_end)
        if index == -1:
            return data 
        else:
            live_log = to_text(data[:index]).replace("___live_end___\n","").replace("___live_end___","")
            display.display('[live]: <%s> %s' % (self._play_context.remote_addr, live_log), screen_only=False) 
            return data[index+len(live_end):]

    def _bare_run(self, cmd, in_data, sudoable=True, checkrc=True):
        '''
        Starts the command and communicates with it until it ends.
        '''

        # We don't use _shell.quote as this is run on the controller and independent from the shell plugin chosen
        display_cmd = u' '.join(shlex_quote(to_text(c)) for c in cmd)
        display.vvv(u'SSH: EXEC {0}'.format(display_cmd), host=self.host)

        # Start the given command. If we don't need to pipeline data, we can try
        # to use a pseudo-tty (ssh will have been invoked with -tt). If we are
        # pipelining data, or can't create a pty, we fall back to using plain
        # old pipes.

        p = None

        if isinstance(cmd, (text_type, binary_type)):
            cmd = to_bytes(cmd)
        else:
            cmd = list(map(to_bytes, cmd))

        conn_password = self.get_option('password') or self._play_context.password

        if not in_data:
            try:
                # Make sure stdin is a proper pty to avoid tcgetattr errors
                master, slave = pty.openpty()
                if PY3 and conn_password:
                    # pylint: disable=unexpected-keyword-arg
                    p = subprocess.Popen(cmd, stdin=slave, stdout=subprocess.PIPE, stderr=subprocess.PIPE, pass_fds=self.sshpass_pipe)
                else:
                    p = subprocess.Popen(cmd, stdin=slave, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                stdin = os.fdopen(master, 'wb', 0)
                os.close(slave)
            except (OSError, IOError):
                p = None

        if not p:
            try:
                if PY3 and conn_password:
                    # pylint: disable=unexpected-keyword-arg
                    p = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                         stderr=subprocess.PIPE, pass_fds=self.sshpass_pipe)
                else:
                    p = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                         stderr=subprocess.PIPE)
                stdin = p.stdin
            except (OSError, IOError) as e:
                raise AnsibleError('Unable to execute ssh command line on a controller due to: %s' % to_native(e))

        # If we are using SSH password authentication, write the password into
        # the pipe we opened in _build_command.

        if conn_password:
            os.close(self.sshpass_pipe[0])
            try:
                os.write(self.sshpass_pipe[1], to_bytes(conn_password) + b'\n')
            except OSError as e:
                # Ignore broken pipe errors if the sshpass process has exited.
                if e.errno != errno.EPIPE or p.poll() is None:
                    raise
            os.close(self.sshpass_pipe[1])

        #
        # SSH state machine
        #

        # Now we read and accumulate output from the running process until it
        # exits. Depending on the circumstances, we may also need to write an
        # escalation password and/or pipelined input to the process.

        states = [
            'awaiting_prompt', 'awaiting_escalation', 'ready_to_send', 'awaiting_exit'
        ]

        # Are we requesting privilege escalation? Right now, we may be invoked
        # to execute sftp/scp with sudoable=True, but we can request escalation
        # only when using ssh. Otherwise we can send initial data straightaway.

        state = states.index('ready_to_send')
        if to_bytes(self.get_option('ssh_executable')) in cmd and sudoable:
            prompt = getattr(self.become, 'prompt', None)
            if prompt:
                # We're requesting escalation with a password, so we have to
                # wait for a password prompt.
                state = states.index('awaiting_prompt')
                display.debug(u'Initial state: %s: %s' % (states[state], to_text(prompt)))
            elif self.become and self.become.success:
                # We're requesting escalation without a password, so we have to
                # detect success/failure before sending any initial data.
                state = states.index('awaiting_escalation')
                display.debug(u'Initial state: %s: %s' % (states[state], to_text(self.become.success)))

        # We store accumulated stdout and stderr output from the process here,
        # but strip any privilege escalation prompt/confirmation lines first.
        # Output is accumulated into tmp_*, complete lines are extracted into
        # an array, then checked and removed or copied to stdout or stderr. We
        # set any flags based on examining the output in self._flags.

        b_stdout = b_stderr = b''
        b_tmp_stdout = b_tmp_stderr = b''

        self._flags = dict(
            become_prompt=False, become_success=False,
            become_error=False, become_nopasswd_error=False
        )

        # select timeout should be longer than the connect timeout, otherwise
        # they will race each other when we can't connect, and the connect
        # timeout usually fails
        timeout = 2 + self.get_option('timeout')
        for fd in (p.stdout, p.stderr):
            fcntl.fcntl(fd, fcntl.F_SETFL, fcntl.fcntl(fd, fcntl.F_GETFL) | os.O_NONBLOCK)

        # TODO: bcoca would like to use SelectSelector() when open
        # select is faster when filehandles is low and we only ever handle 1.
        selector = selectors.DefaultSelector()
        selector.register(p.stdout, selectors.EVENT_READ)
        selector.register(p.stderr, selectors.EVENT_READ)

        # If we can send initial data without waiting for anything, we do so
        # before we start polling
        if states[state] == 'ready_to_send' and in_data:
            self._send_initial_data(stdin, in_data, p)
            state += 1

        try:
            while True:
                poll = p.poll()
                events = selector.select(timeout)

                # We pay attention to timeouts only while negotiating a prompt.

                if not events:
                    # We timed out
                    if state <= states.index('awaiting_escalation'):
                        # If the process has already exited, then it's not really a
                        # timeout; we'll let the normal error handling deal with it.
                        if poll is not None:
                            break
                        self._terminate_process(p)
                        raise AnsibleError('Timeout (%ds) waiting for privilege escalation prompt: %s' % (timeout, to_native(b_stdout)))

                # Read whatever output is available on stdout and stderr, and stop
                # listening to the pipe if it's been closed.

                for key, event in events:
                    if key.fileobj == p.stdout:
                        b_chunk = p.stdout.read()
                        if b_chunk == b'':
                            # stdout has been closed, stop watching it
                            selector.unregister(p.stdout)
                            # When ssh has ControlMaster (+ControlPath/Persist) enabled, the
                            # first connection goes into the background and we never see EOF
                            # on stderr. If we see EOF on stdout, lower the select timeout
                            # to reduce the time wasted selecting on stderr if we observe
                            # that the process has not yet existed after this EOF. Otherwise
                            # we may spend a long timeout period waiting for an EOF that is
                            # not going to arrive until the persisted connection closes.
                            timeout = 1
                        b_tmp_stdout += b_chunk
                        display.debug(u"stdout chunk (state=%s):\n>>>%s<<<\n" % (state, to_text(b_chunk)))
                        stdout = self._handle_live_output(b_tmp_stdout)
                    elif key.fileobj == p.stderr:
                        b_chunk = p.stderr.read()
                        if b_chunk == b'':
                            # stderr has been closed, stop watching it
                            selector.unregister(p.stderr)
                        b_tmp_stderr += b_chunk
                        display.debug("stderr chunk (state=%s):\n>>>%s<<<\n" % (state, to_text(b_chunk)))
                        stdout = self._handle_live_output(b_tmp_stderr)

                # We examine the output line-by-line until we have negotiated any
                # privilege escalation prompt and subsequent success/error message.
                # Afterwards, we can accumulate output without looking at it.

                if state < states.index('ready_to_send'):
                    if b_tmp_stdout:
                        b_output, b_unprocessed = self._examine_output('stdout', states[state], b_tmp_stdout, sudoable)
                        b_stdout += b_output
                        b_tmp_stdout = b_unprocessed

                    if b_tmp_stderr:
                        b_output, b_unprocessed = self._examine_output('stderr', states[state], b_tmp_stderr, sudoable)
                        b_stderr += b_output
                        b_tmp_stderr = b_unprocessed
                else:
                    b_stdout += b_tmp_stdout
                    b_stderr += b_tmp_stderr
                    b_tmp_stdout = b_tmp_stderr = b''

                # If we see a privilege escalation prompt, we send the password.
                # (If we're expecting a prompt but the escalation succeeds, we
                # didn't need the password and can carry on regardless.)

                if states[state] == 'awaiting_prompt':
                    if self._flags['become_prompt']:
                        display.debug(u'Sending become_password in response to prompt')
                        become_pass = self.become.get_option('become_pass', playcontext=self._play_context)
                        stdin.write(to_bytes(become_pass, errors='surrogate_or_strict') + b'\n')
                        # On python3 stdin is a BufferedWriter, and we don't have a guarantee
                        # that the write will happen without a flush
                        stdin.flush()
                        self._flags['become_prompt'] = False
                        state += 1
                    elif self._flags['become_success']:
                        state += 1

                # We've requested escalation (with or without a password), now we
                # wait for an error message or a successful escalation.

                if states[state] == 'awaiting_escalation':
                    if self._flags['become_success']:
                        display.vvv(u'Escalation succeeded')
                        self._flags['become_success'] = False
                        state += 1
                    elif self._flags['become_error']:
                        display.vvv(u'Escalation failed')
                        self._terminate_process(p)
                        self._flags['become_error'] = False
                        raise AnsibleError('Incorrect %s password' % self.become.name)
                    elif self._flags['become_nopasswd_error']:
                        display.vvv(u'Escalation requires password')
                        self._terminate_process(p)
                        self._flags['become_nopasswd_error'] = False
                        raise AnsibleError('Missing %s password' % self.become.name)
                    elif self._flags['become_prompt']:
                        # This shouldn't happen, because we should see the "Sorry,
                        # try again" message first.
                        display.vvv(u'Escalation prompt repeated')
                        self._terminate_process(p)
                        self._flags['become_prompt'] = False
                        raise AnsibleError('Incorrect %s password' % self.become.name)

                # Once we're sure that the privilege escalation prompt, if any, has
                # been dealt with, we can send any initial data and start waiting
                # for output.

                if states[state] == 'ready_to_send':
                    if in_data:
                        self._send_initial_data(stdin, in_data, p)
                    state += 1

                # Now we're awaiting_exit: has the child process exited? If it has,
                # and we've read all available output from it, we're done.

                if poll is not None:
                    if not selector.get_map() or not events:
                        break
                    # We should not see further writes to the stdout/stderr file
                    # descriptors after the process has closed, set the select
                    # timeout to gather any last writes we may have missed.
                    timeout = 0
                    continue

                # If the process has not yet exited, but we've already read EOF from
                # its stdout and stderr (and thus no longer watching any file
                # descriptors), we can just wait for it to exit.

                elif not selector.get_map():
                    p.wait()
                    break

                # Otherwise there may still be outstanding data to read.
        finally:
            selector.close()
            # close stdin, stdout, and stderr after process is terminated and
            # stdout/stderr are read completely (see also issues #848, #64768).
            stdin.close()
            p.stdout.close()
            p.stderr.close()

        if self.get_option('host_key_checking'):
            if cmd[0] == b"sshpass" and p.returncode == 6:
                raise AnsibleError('Using a SSH password instead of a key is not possible because Host Key checking is enabled and sshpass does not support '
                                   'this.  Please add this host\'s fingerprint to your known_hosts file to manage this host.')

        controlpersisterror = b'Bad configuration option: ControlPersist' in b_stderr or b'unknown configuration option: ControlPersist' in b_stderr
        if p.returncode != 0 and controlpersisterror:
            raise AnsibleError('using -c ssh on certain older ssh versions may not support ControlPersist, set ANSIBLE_SSH_ARGS="" '
                               '(or ssh_args in [ssh_connection] section of the config file) before running again')

        # If we find a broken pipe because of ControlPersist timeout expiring (see #16731),
        # we raise a special exception so that we can retry a connection.
        controlpersist_broken_pipe = b'mux_client_hello_exchange: write packet: Broken pipe' in b_stderr
        if p.returncode == 255:

            additional = to_native(b_stderr)
            if controlpersist_broken_pipe:
                raise AnsibleControlPersistBrokenPipeError('Data could not be sent because of ControlPersist broken pipe: %s' % additional)

            elif in_data and checkrc:
                raise AnsibleConnectionFailure('Data could not be sent to remote host "%s". Make sure this host can be reached over ssh: %s'
                                               % (self.host, additional))

        return (p.returncode, b_stdout, b_stderr)
