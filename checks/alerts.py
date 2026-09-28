"""Focused worker check: notify forwarding survives heartbeat suppression."""
import importlib.util
import json
from pathlib import Path
import sys
import tempfile

spec = importlib.util.spec_from_file_location('worker', Path(__file__).resolve().parents[1] / 'bin/agentbell-worker.py')
worker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(worker)
with tempfile.TemporaryDirectory() as folder:
    worker.ROOT = Path(folder)
    (worker.ROOT / 'config.json').write_text(json.dumps({
        'original_notify': ['/fixture/original', 'turn-ended'],
        'sounds': {'codex_complete': '/fixture/sound.aiff'},
    }))
    calls = []
    worker.launch = lambda command, inherit=False: calls.append((command, inherit))
    for prompt, expected in [('<heartbeat>\ncheck\n</heartbeat>', 1),
                             ('<heartbeat mode="timer">\ncheck', 1),
                             ('解释 <heartbeat> 标记', 3), ('普通任务', 3)]:
        calls.clear()
        payload = json.dumps({'type': 'agent-turn-complete', 'input-messages': ['上一个用户任务', prompt]})
        sys.argv = ['worker', 'notify', 'turn-ended', payload]
        worker.main()
        assert len(calls) == expected, calls
        assert calls[0] == (['/fixture/original', 'turn-ended', payload], True)
    assert len((worker.ROOT / 'logs/events.jsonl').read_text().splitlines()) == 4
print('PASS: heartbeats log and forward unchanged without sound/notification; ordinary tasks still alert')
