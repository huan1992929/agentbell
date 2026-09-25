// Focused regression checks; no test framework or external dependencies.
import AppKit

let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: folder) }
let file = folder.appendingPathComponent("rollout.jsonl")
let session = "11111111-1111-4111-8111-111111111111"
func json(_ value: [String: Any]) -> Data {
    var result = try! JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    result.append(10); return result
}
let meta = json(["type": "session_meta", "payload": ["id": session, "source": "vscode", "originator": "Codex Desktop", "cwd": "/fixture/desktop"]])
func event(_ type: String, _ turn: String) -> Data {
    json(["timestamp": "2026-09-25T09:00:00.000Z", "type": "event_msg", "payload": ["type": type, "turn_id": turn]])
}
func append(_ data: Data) throws {
    let handle = try FileHandle(forWritingTo: file); defer { try? handle.close() }
    try handle.seekToEnd(); try handle.write(contentsOf: data)
}
try Data().write(to: file)
let reader = CodexRollout(url: file)
try reader.poll()
try append(meta + event("task_started", "first"))
try reader.poll()
precondition(reader.activity?.turn == "first")
try append(event("task_started", "second"))
try append(event("task_complete", "first"))
try reader.poll()
precondition(reader.activity?.turn == "second", "Late completion must not clear a newer turn")
let complete = event("task_complete", "second")
try append(Data(complete.dropLast(5))); try reader.poll()
precondition(reader.activity?.turn == "second", "Partial records must wait for their newline")
try append(Data(complete.suffix(5))); try reader.poll()
precondition(reader.activity == nil, "Completion clears without SessionEnd")
let reopened = CodexRollout(url: file); try reopened.poll()
precondition(reopened.activity == nil, "Restart must not resurrect a completed, still-open session")
// A lifecycle record split across the 256 KiB reverse-scan boundary must survive.
let start = event("task_started", "boundary")
let emptyFiller = json(["type": "response_item", "payload": ["text": ""]])
let filler = json(["type": "response_item", "payload": ["text": String(repeating: "x", count: 262_144 - start.count / 2 - emptyFiller.count)]])
try (meta + start + filler).write(to: file)
let boundary = CodexRollout(url: file); try boundary.poll()
precondition(boundary.activity?.turn == "boundary", "Reverse-scan boundary lost an event")
try append(json(["type": "response_item", "payload": ["type": "task_complete", "turn_id": "boundary"]]))
try boundary.poll()
precondition(boundary.activity?.turn == "boundary", "Message text must not masquerade as lifecycle")
try append(event("turn_aborted", "boundary")); try boundary.poll()
precondition(boundary.activity == nil)
let store = EventStore(url: folder.appendingPathComponent("events.jsonl"))
let a = CodexActivity(session: session, turn: "desktop", project: "desktop", start: Date(), client: "Codex Desktop")
let b = CodexActivity(session: "22222222-2222-4222-8222-222222222222", turn: "cli", project: "cli", start: Date(), client: "codex_exec")
store.reconcileCodex([a,b], problem: nil); precondition(store.running.count == 2)
store.reconcileCodex([b], problem: nil); precondition(store.running.count == 1)
store.reconcileCodex([], problem: nil); precondition(store.running.isEmpty)
let live = CodexActivityMonitor().sample()
precondition(live.1 == nil, "Local ownership probe failed")
print("PASS: lifecycle parsing, reverse boundary, partial append, abort, no-SessionEnd recovery, 2→1→0 reconciliation")
print("Live owned active sessions:", live.0.count)

// D008: only input records supply titles; quota must survive a later terminal.
func record(_ type: String, _ payload: [String: Any], _ stamp: String = "2026-09-25T09:00:01.000Z") -> Data {
    json(["timestamp": stamp, "type": type, "payload": payload])
}
let input = record("response_item", ["type": "message", "role": "user", "content": [["type": "input_text", "text": "核对订单金额\n请检查合计"]]])
let limit = record("event_msg", ["type": "token_count", "rate_limits": [
    "primary": ["used_percent": 11.0, "window_minutes": 10080, "resets_at": 1790832478],
    "secondary": ["used_percent": 23.5, "window_minutes": 300, "resets_at": 1790832478]]])
try (meta + event("task_started", "title") + input + limit).write(to: file)
let titled = CodexRollout(url: file); try titled.poll()
precondition(titled.activity?.title == "核对订单金额")
precondition(titled.usage?.windows.map(\.name) == ["7天", "5小时"])
precondition(titled.usage?.windows.map(\.percent) == [11, 23.5])
try append(event("task_complete", "title")); try titled.poll()
let idle = CodexRollout(url: file); try idle.poll()
precondition(idle.activity == nil && idle.usage?.windows.count == 2)
try append(event("task_started", "new")); try titled.poll()
precondition(titled.activity?.title == TaskText.missing)
try append(input); try titled.poll(); precondition(titled.activity?.title == "核对订单金额")
try append(record("event_msg", ["type": "token_count", "rate_limits": ["primary": ["used_percent": 12, "window_minutes": 90, "resets_at": 1790832478], "secondary": NSNull()]], "2026-09-25T09:00:02.000Z"))
try titled.poll(); precondition(titled.usage?.windows.map(\.name) == ["90分钟"])
let eventsFile = folder.appendingPathComponent("titles.jsonl")
var records = Data()
for i in 0..<6 {
    records.append(json(["timestamp": "2026-09-25T09:00:0\(i)Z", "source": "codex", "payload": ["type": "agent-turn-complete", "input-messages": ["以前的任务", "任务\(i)\n第二行"], "last-assistant-message": "disposition: ship"]]))
}
records.append(json(["timestamp": "2026-09-25T09:00:07Z", "source": "claude", "payload": ["hook_event_name": "UserPromptSubmit", "session_id": "fixture", "prompt_id": "one", "prompt": "整理演示文稿\n第二行"]]))
try records.write(to: eventsFile)
let titleStore = EventStore(url: eventsFile); titleStore.poll()
precondition(titleStore.recent.count == 5 && titleStore.recent.first?.summary == "任务5")
precondition(titleStore.running["claude:fixture"]?.title == "整理演示文稿")
let stop = json(["timestamp": "2026-09-25T09:00:08Z", "source": "claude", "payload": ["hook_event_name": "Stop", "session_id": "fixture", "prompt_id": "one", "last_assistant_message": "{bad summary}"]])
let handle = try FileHandle(forWritingTo: eventsFile); try handle.seekToEnd(); try handle.write(contentsOf: stop); try handle.close()
titleStore.poll()
precondition(titleStore.recent.count == 5 && titleStore.recent.first?.summary == "整理演示文稿" && titleStore.running.isEmpty)
precondition(TaskTime.completed(Date(timeIntervalSince1970: 0), now: Date(timeIntervalSince1970: 1620)) == "27分钟前")
precondition(TaskTime.elapsed(Date(timeIntervalSince1970: 0), now: Date(timeIntervalSince1970: 70)) == "已运行 1分钟")
print("PASS: prompt titles, two quota windows, latest/null window, idle recovery, five completions, relative/elapsed time")
precondition(TaskText.title("<pasted_content id=\"example\">\n核对数据\n</pasted_content>") == "核对数据")
precondition(TaskText.title("/fixture/任务要求.md") == "任务要求.md")
precondition(!TaskText.submitted("<task-notification>\nbackground task done"))
let background = json(["timestamp": "2026-09-25T09:00:09Z", "source": "claude", "payload": ["hook_event_name": "UserPromptSubmit", "session_id": "fixture", "prompt_id": "background", "prompt": "<task-notification>\nbackground task done"]])
let backgroundHandle = try FileHandle(forWritingTo: eventsFile); try backgroundHandle.seekToEnd(); try backgroundHandle.write(contentsOf: background); try backgroundHandle.close()
titleStore.poll(); precondition(titleStore.running["claude:fixture"]?.title == "整理演示文稿")
print("PASS: pasted prompt wrapper, file prompt title, background completion keeps user title")
let quotaOnlyMeta = json(["type": "session_meta", "payload": ["id": session, "source": ["subagent": "fixture"]]])
try (quotaOnlyMeta + event("task_started", "hidden") + limit).write(to: file)
let quotaOnly = CodexRollout(url: file); try quotaOnly.poll()
precondition(quotaOnly.activity == nil && quotaOnly.usage?.windows.count == 2)
print("PASS: quota-only sources do not add running rows")
