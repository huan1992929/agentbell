"""Use Codex's own hook hashes and config API; never bypass hook trust."""
import json
import os
from pathlib import Path
import selectors
import shutil
import subprocess
import time


class CodexHooks:
    def __enter__(self):
        executable = shutil.which('codex')
        if not executable:
            raise RuntimeError('Codex CLI is required for hook discovery and trust')
        self.process = subprocess.Popen([executable, 'app-server', '--stdio'],
                                        stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                        stderr=subprocess.DEVNULL)
        self.selector = selectors.DefaultSelector()
        self.selector.register(self.process.stdout, selectors.EVENT_READ)
        self.pending = b''
        self.sequence = 0
        try:
            self.call('initialize', {'clientInfo': {'name': 'agentbell_installer', 'version': '0.2.0'},
                                    'capabilities': {'experimentalApi': True}})
        except Exception:
            self.__exit__(None, None, None)
            raise
        return self

    def call(self, method, params):
        self.sequence += 1
        self.process.stdin.write((json.dumps({'id': self.sequence, 'method': method,
                                              'params': params}) + '\n').encode())
        self.process.stdin.flush()
        deadline = time.monotonic() + 30
        while time.monotonic() < deadline:
            while b'\n' in self.pending:
                line, self.pending = self.pending.split(b'\n', 1)
                response = json.loads(line)
                if response.get('id') == self.sequence:
                    if 'error' in response:
                        raise RuntimeError('Codex ' + method + ': ' + str(response['error']))
                    return response['result']
            if self.selector.select(max(0, deadline - time.monotonic())):
                chunk = os.read(self.process.stdout.fileno(), 65536)
                if not chunk:
                    raise RuntimeError('Codex app-server exited during ' + method)
                self.pending += chunk
        raise RuntimeError('Codex app-server timed out during ' + method)

    def listed(self, cwd, path, command):
        data = self.call('hooks/list', {'cwds': [str(cwd)]})['data']
        if len(data) != 1 or data[0]['errors']:
            raise RuntimeError('Codex hook discovery failed: ' + str(data))
        return [h for h in data[0]['hooks']
                if Path(h['sourcePath']).resolve() == path.resolve()
                and h.get('command') == command]

    def trust(self, cwd, path, command, config_path):
        hooks = self.listed(cwd, path, command)
        expected = {'sessionStart', 'userPromptSubmit', 'sessionEnd', 'interrupt'}
        if len(hooks) != len(expected) or {h['eventName'] for h in hooks} != expected:
            raise RuntimeError('Installed Codex does not recognize all AgentBell hooks')
        if any(not h['enabled'] or h['isManaged'] or h['source'] != 'user' for h in hooks):
            raise RuntimeError('AgentBell hooks are disabled or not user hooks')
        # Only the four definitions just written and reviewed by this installer
        # are trusted. Hashes are computed by Codex, not guessed or synthesized.
        edits = [{'keyPath': 'hooks.state.' + json.dumps(h['key']) + '.trusted_hash',
                  'value': h['currentHash'], 'mergeStrategy': 'replace'} for h in hooks]
        self.call('config/batchWrite', {'edits': edits, 'filePath': str(config_path)})
        verified = self.listed(cwd, path, command)
        if len(verified) != len(expected) or any(h['trustStatus'] != 'trusted' for h in verified):
            raise RuntimeError('Codex did not persist hook trust')
        return hooks

    def __exit__(self, *_):
        self.selector.close()
        self.process.stdin.close()
        try:
            self.process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            self.process.terminate()
            try:
                self.process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.process.kill()
                self.process.wait()
        self.process.stdout.close()
