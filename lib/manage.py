#!/usr/bin/env python3
"""Small, transactional installer; runtime requires only Python's stdlib."""
import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import sys
import tempfile
import tomllib

HOME = Path.home()
ROOT = HOME / '.agentbell'
REPO = Path(__file__).resolve().parent.parent
FILES = {'settings.json': HOME / '.claude/settings.json',
         'config.toml': HOME / '.codex/config.toml'}
STATE = ROOT / 'install-state.json'
VIBE = HOME / '.vibe-island'
HOOK = '/bin/sh -c \'"$HOME/.agentbell/bin/agentbell-event" claude >/dev/null 2>&1; exit 0\''


def read_json(path):
    return json.loads(path.read_text(encoding='utf-8'))


def encoded(value):
    return (json.dumps(value, ensure_ascii=False, indent=2) + '\n').encode()


def atomic(path, content, metadata=None):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, name = tempfile.mkstemp(prefix='.agentbell-', dir=path.parent)
    try:
        with os.fdopen(fd, 'wb') as stream:
            stream.write(content)
        if metadata and metadata.exists():
            shutil.copystat(metadata, name)
        os.replace(name, path)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def digest(data):
    return hashlib.sha256(data).hexdigest()


def restore(backup, manifest):
    # Validate every backup before touching either live config.
    for name, info in manifest['files'].items():
        if info['exists'] and digest((backup / name).read_bytes()) != info['sha256']:
            raise RuntimeError('Backup checksum mismatch: ' + name)
    if manifest['vibe_archived'] and not (backup / 'vibe-island').exists():
        raise RuntimeError('Vibe Island backup missing')
    if manifest['vibe_archived'] and VIBE.exists():
        raise RuntimeError('Vibe Island directory recreated; refusing to overwrite it')
    for name, path in FILES.items():
        if manifest['files'][name]['exists']:
            atomic(path, (backup / name).read_bytes(), backup / name)
        else:
            path.unlink(missing_ok=True)
    if manifest['vibe_archived']:
        shutil.move(str(backup / 'vibe-island'), VIBE)


def install():
    if STATE.exists() and read_json(STATE).get('active'):
        state = read_json(STATE)
        for name, path in FILES.items():
            if not path.exists() or digest(path.read_bytes()) != state['installed_sha256'][name]:
                raise RuntimeError('Installed config changed; inspect before reinstalling: ' + str(path))
        print('Already installed; original backup retained: ' + state['backup'])
        return
    before = {name: path.read_bytes() if path.exists() else b'' for name, path in FILES.items()}
    settings = json.loads(before['settings.json'] or b'{}')
    text = before['config.toml'].decode('utf-8')
    original = tomllib.loads(text).get('notify', [])
    if not isinstance(original, list) or not all(isinstance(x, str) for x in original):
        raise RuntimeError('Expected notify to be an array of strings')
    if original and original[1:] != ['turn-ended']:
        raise RuntimeError('Unexpected original notify arguments; refusing to change its behavior')
    if original and 'agentbell-codex-notify' in original[0]:
        raise RuntimeError('Existing AgentBell notify without active backup; restore it first')

    # Detect a top-level, single-line notify; tomllib validates both versions.
    lines = text.splitlines(keepends=True)
    top_end = next((i for i, line in enumerate(lines) if line.lstrip().startswith('[')), len(lines))
    candidates = [i for i in range(top_end) if re.match(r'^\s*notify\s*=', lines[i])]
    replacement = 'notify = ' + json.dumps([str(ROOT / 'bin/agentbell-codex-notify'), 'turn-ended'])
    if original or candidates:
        if len(candidates) != 1:
            raise RuntimeError('Cannot locate a single top-level notify line')
        i = candidates[0]
        if tomllib.loads(lines[i]).get('notify') != original:
            raise RuntimeError('Multiline notify is unsupported; config left untouched')
        ending = '\r\n' if lines[i].endswith('\r\n') else '\n' if lines[i].endswith('\n') else ''
        indent = lines[i][:len(lines[i]) - len(lines[i].lstrip())]
        lines[i] = indent + replacement + ending
    else:
        lines.insert(0, replacement + '\n')
    updated_text = ''.join(lines)
    expected = tomllib.loads(text)
    expected['notify'] = [str(ROOT / 'bin/agentbell-codex-notify'), 'turn-ended']
    if tomllib.loads(updated_text) != expected:
        raise RuntimeError('TOML validation failed')

    hooks = settings.setdefault('hooks', {})
    removed = 0
    for event in list(hooks):
        remaining = []
        for group in hooks[event]:
            entries = group.get('hooks', [])
            keep = [h for h in entries if not any(s in h.get('command', '')
                    for s in ('vibe-island', '.agentbell/bin/agentbell-event'))]
            removed += sum('vibe-island' in h.get('command', '') for h in entries)
            if keep or not entries:
                remaining.append({**group, 'hooks': keep})
        if remaining:
            hooks[event] = remaining
        else:
            del hooks[event]
    if 'vibe-island' in json.dumps(settings.get('statusLine')):
        del settings['statusLine']
    for event in ('Stop', 'Notification', 'PermissionRequest'):
        hooks.setdefault(event, []).append({'hooks': [{'type': 'command', 'command': HOOK}]})

    config_path = ROOT / 'config.json'
    config = read_json(config_path) if config_path.exists() else {}
    config.setdefault('enabled', True)
    config.setdefault('sound_enabled', True)
    config.setdefault('notification_enabled', True)
    sounds = config.setdefault('sounds', {})
    for kind, name in [('codex_complete', 'Submarine'), ('claude_complete', 'Glass'), ('attention', 'Ping')]:
        sounds.setdefault(kind, '/System/Library/Sounds/' + name + '.aiff')
    config['original_notify'] = original
    after = {'settings.json': encoded(settings), 'config.toml': updated_text.encode()}
    backup = ROOT / 'backups' / datetime.datetime.now().strftime('%Y%m%d-%H%M%S-%f')
    backup.mkdir(parents=True, mode=0o700)
    manifest = {'files': {}, 'vibe_archived': False}
    for name, path in FILES.items():
        manifest['files'][name] = {'exists': path.exists(), 'sha256': digest(before[name])}
        if path.exists():
            shutil.copy2(path, backup / name)
    if config_path.exists():
        shutil.copy2(config_path, backup / 'agentbell-config.json')
    atomic(backup / 'manifest.json', encoded(manifest))
    try:
        (ROOT / 'bin').mkdir(exist_ok=True)
        (ROOT / 'logs').mkdir(exist_ok=True)
        for source in (REPO / 'bin').iterdir():
            if source.is_file() and source.name.startswith('agentbell-'):
                shutil.copy2(source, ROOT / 'bin' / source.name)
                (ROOT / 'bin' / source.name).chmod(0o700)
        atomic(config_path, encoded(config))
        if VIBE.exists():
            shutil.move(str(VIBE), backup / 'vibe-island')
            manifest['vibe_archived'] = True
            atomic(backup / 'manifest.json', encoded(manifest))
        for name, path in FILES.items():
            atomic(path, after[name], backup / name)
        atomic(STATE, encoded({'active': True, 'backup': str(backup),
                              'installed_sha256': {k: digest(v) for k, v in after.items()}}))
    except Exception:
        restore(backup, manifest)
        raise
    for path in FILES.values():
        print('Changed: ' + str(path))
    print('Runtime scripts/config: ' + str(ROOT))
    print('Removed Vibe Island hooks: ' + str(removed))
    print('Vibe Island directory archived: ' + str(manifest['vibe_archived']))
    print('Backup: ' + str(backup))


def uninstall():
    if not STATE.exists() or not read_json(STATE).get('active'):
        print('Not installed; logs and backups retained.')
        return
    state = read_json(STATE)
    backup = Path(state['backup'])
    # Do not silently discard edits made since installation.
    for name, path in FILES.items():
        if not path.exists() or digest(path.read_bytes()) != state['installed_sha256'][name]:
            raise RuntimeError('Config changed since installation; inspect before restoring: ' + str(path))
    restore(backup, read_json(backup / 'manifest.json'))
    state['active'] = False
    atomic(STATE, encoded(state))
    for path in FILES.values():
        print('Restored: ' + str(path))
    print('Backup: ' + str(backup))
    print('Logs retained: ' + str(ROOT / 'logs'))


if __name__ == '__main__':
    os.umask(0o077)
    try:
        {'install': install, 'uninstall': uninstall}[sys.argv[1]]()
    except Exception as exc:
        print('AgentBell: ' + str(exc), file=sys.stderr)
        sys.exit(1)
