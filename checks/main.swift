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
