#!/usr/bin/env python3
"""Background-only event processing. The public sh entrypoints never wait."""
import datetime
import fcntl
import json
import os
from pathlib import Path
import select
import subprocess
import sys
import time

ROOT = Path.home() / '.agentbell'


def append(name, record):
    logs = ROOT / 'logs'
    logs.mkdir(parents=True, exist_ok=True, mode=0o700)
    with (logs / name).open('a', encoding='utf-8') as stream:
        fcntl.flock(stream, fcntl.LOCK_EX)
        stream.write(json.dumps(record, ensure_ascii=True) + '\n')


def error(stage, exc):
    append('errors.log', {'time': now(), 'stage': stage, 'error': str(exc)})


def now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def read_input():
    # Bound the whole read, including a writer that never closes its pipe.
    deadline = time.monotonic() + 0.15
    chunks = []
    while time.monotonic() < deadline:
        ready, _, _ = select.select([0], [], [], max(0, deadline - time.monotonic()))
        if not ready:
            break
        chunk = os.read(0, 65536)
        if not chunk:
            return b''.join(chunks).decode('utf-8', errors='replace'), False
        chunks.append(chunk)
    return b''.join(chunks).decode('utf-8', errors='replace'), True


def launch(command, inherit=False):
    # No shell parsing of payloads or original notify arguments.
    options = {} if inherit else dict(stdin=subprocess.DEVNULL,
                                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return subprocess.Popen(command, start_new_session=True, close_fds=True, **options)


def main():
    mode, *args = sys.argv[1:]
    config = {}
    try:
        config = json.loads((ROOT / 'config.json').read_text())
    except Exception as exc:
        error('config', exc)

    if mode == 'notify':
        source, argv = 'codex', args
        # Forward before doing any logging or notification work.
        original = config.get('original_notify', [])
        if original:
            try:
                launch([original[0], *args], inherit=True)
            except Exception as exc:
                error('original_notify', exc)
        raw, timed_out = (args[-1] if args else ''), False
    else:
        source = args[0] if args else 'unknown'
        argv = args
        raw, timed_out = read_input()

    try:
        payload = json.loads(raw)
    except (ValueError, TypeError):
        payload = None
    append('events.jsonl', {'timestamp': now(), 'source': source, 'argv': argv,
                           'raw_payload': raw, 'payload': payload,
                           'stdin_timed_out': timed_out})
    data = payload if isinstance(payload, dict) else {}
    event = data.get('hook_event_name')
    kind = None
    if source == 'codex' and data.get('type') == 'agent-turn-complete':
        kind = 'codex_complete'
    elif event == 'Stop':
        kind = 'claude_complete'
    elif event in ('Notification', 'PermissionRequest'):
        kind = 'attention'
    if not kind or not config.get('enabled', True):
        return
    sound = config.get('sounds', {}).get(kind)
    if sound and config.get('sound_enabled', True):
        try:
            launch(['/usr/bin/afplay', sound])
        except Exception as exc:
            error('sound', exc)
    if config.get('notification_enabled', True):
        # Only fixed strings enter AppleScript; raw user/agent text is never code.
        title = 'AgentBell · Codex' if source == 'codex' else 'AgentBell · Claude'
        message = '需要批准或回复' if kind == 'attention' else '任务已完成'
        script = 'display notification ' + json.dumps(message, ensure_ascii=False)
        script += ' with title ' + json.dumps(title, ensure_ascii=False)
        try:
            launch(['/usr/bin/osascript', '-e', script])
        except Exception as exc:
            error('notification', exc)


if __name__ == '__main__':
    os.umask(0o077)
    try:
        main()
    except Exception as exc:
        try:
            error('worker', exc)
        except Exception:
            pass
