import AppKit

struct Running {
    let source: String
    let session: String?
    let project: String
    let start: Date
    let prompt: String?
    let background: Bool
}

struct Completion {
    let source: String
    let session: String?
    let project: String
    let time: Date
    let summary: String
}

// Reads only the event script's append-only log. No notifications, subprocesses,
// terminal inspection or network access belong in the presentation process.
// Routing reads only identifier metadata, never transcript messages.
final class EventStore {
    let url: URL
    var running: [String: Running] = [:]
    var recent: [Completion] = []
    var problem: String?
    var clients: [String: String] = [:]
    private var offset: UInt64 = 0
    private var identity: UInt64?
    private var pending = Data()
    private var discarding = false
    private let fractional = ISO8601DateFormatter()
    private let plain = ISO8601DateFormatter()
    private var finishedTurns: [String: Date] = [:]

    init(url: URL) {
        self.url = url
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    func poll() {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let size = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
            let inode = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value
            if identity != inode || size < offset {
                offset = 0
                pending.removeAll()
                discarding = false
                running.removeAll()
                recent.removeAll()
                finishedTurns.removeAll()
                clients.removeAll()
            }
            identity = inode
            problem = nil
            guard size > offset else { return }
            let file = try FileHandle(forReadingFrom: url)
            defer { try? file.close() }
            try file.seek(toOffset: offset)
            // Bound work per tick even when opening a large historical log.
            let chunk = try file.read(upToCount: 1_048_576) ?? Data()
            offset += UInt64(chunk.count)
            pending.append(chunk)
            while let end = pending.firstIndex(of: 10) {
                let line = pending.prefix(upTo: end)
                if !discarding { consume(Data(line)) }
                pending.removeSubrange(...end)
                discarding = false
            }
            if pending.count > 8_388_608 {
                pending.removeAll()
                discarding = true
            }
        } catch {
            problem = FileManager.default.fileExists(atPath: url.path)
                ? "暂时无法读取事件日志" : "等待首条事件"
        }
    }

    func reconcileClaudeApp() {
        // Desktop local agents have no TTY. Never infer their lifetime from
        // terminal processes, lsof, or the absence of per-tool events.
        let applications = NSWorkspace.shared.runningApplications.filter {
            $0.bundleIdentifier == "com.anthropic.claudefordesktop" && !$0.isTerminated
        }
        running = running.filter { _, value in
            guard value.source == "Claude" else { return true }
            return applications.contains { app in
                app.launchDate.map { value.start >= $0 } ?? true
            }
        }
    }

    private func consume(_ line: Data) {
        guard let record = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
              let source = record["source"] as? String,
              let payload = record["payload"] as? [String: Any],
              let stamp = record["timestamp"] as? String,
              let time = fractional.date(from: stamp) ?? plain.date(from: stamp) else { return }
        let cwd = payload["cwd"] as? String ?? ""
        let project = cwd.isEmpty ? "未知项目" : URL(fileURLWithPath: cwd).lastPathComponent
        let event = payload["hook_event_name"] as? String
        let isClaude = source == "claude" && event == "Stop"
        let isCodex = source == "codex" && payload["type"] as? String == "agent-turn-complete"
        guard source == "claude" || source == "codex" else { return }
        let label = source == "claude" ? "Claude" : "Codex"
        let session = payload["session_id"] as? String ?? payload["thread-id"] as? String
        let turn = payload[source == "claude" ? "prompt_id" : "turn_id"] as? String
            ?? payload["turn-id"] as? String
        let key = session.map { source + ":" + $0 }
        let turnKey = key.flatMap { k in turn.map { k + ":" + $0 } }
        if let key {
            if source == "codex" {
                if let client = payload["client"] as? String { clients[key] = client }
                if clients[key] == nil, let path = payload["transcript_path"] as? String {
                    clients[key] = SessionNavigation.codexClient(path: path, session: session)
                }
            }
            if event == "UserPromptSubmit" {
                // Steering can submit again inside the same prompt/turn.
                if let turn, running[key]?.prompt == turn { return }
                // Ignore late starts for a turn already completed by notify.
                if turnKey.flatMap({ finishedTurns[$0] }) == nil,
                   running[key].map({ time >= $0.start }) ?? true {
                    let start = running[key].flatMap { $0.background ? $0.start : nil } ?? time
                    running[key] = Running(source: label, session: session, project: project, start: start,
                                           prompt: turn, background: false)
                }
                return
            }
            // A desktop Stop can arrive while its own background shell is still
            // running. Preserve the session until the later completion turn.
            let tasks = payload["background_tasks"] as? [[String: Any]] ?? []
            if isClaude && tasks.contains(where: { $0["status"] as? String == "running" }) {
                if running[key]?.prompt == nil || turn == nil || running[key]?.prompt == turn {
                    running[key] = Running(source: label, session: session, project: project,
                                           start: running[key]?.start ?? time,
                                           prompt: turn, background: true)
                }
                return
            }
            // SessionStart is lifecycle metadata, not proof that a turn is running.
            if event == "SessionEnd" {
                if running[key].map({ time >= $0.start }) ?? false { running.removeValue(forKey: key) }
                return
            }
            if isClaude || isCodex || event == "Interrupt" {
                if let turnKey { finishedTurns[turnKey] = time }
                if finishedTurns.count > 512 {
                    let oldest = finishedTurns.min { $0.value < $1.value }!.key
                    finishedTurns.removeValue(forKey: oldest)
                }
                if let start = running[key], time >= start.start,
                   start.prompt == nil || turn == nil || start.prompt == turn {
                    running.removeValue(forKey: key)
                }
            }
        }
        guard isClaude || isCodex else { return }
        let message = payload[isClaude ? "last_assistant_message" : "last-assistant-message"] as? String ?? ""
        let lastLine = message.split(whereSeparator: \.isNewline).last.map(String.init) ?? "（无回复摘要）"
        let compact = lastLine.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let summary = String(compact.prefix(100)) + (compact.count > 100 ? "…" : "")
        recent.append(Completion(source: isClaude ? "Claude" : "Codex", session: session, project: project,
                                 time: time, summary: summary))
        recent.sort { $0.time > $1.time }
        recent = Array(recent.prefix(10))
    }
}
