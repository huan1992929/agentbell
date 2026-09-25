import Foundation
import Darwin

struct CodexActivity {
    let session: String
    let turn: String
    let project: String
    let start: Date
    let client: String
}

// The desktop's private stdio server is not the CLI's shared daemon. Observe
// its persisted lifecycle records, not token traffic, file age, or chat text.
// lsof supplies ownership only: an open file is NOT proof of an active turn.
final class CodexRollout {
    private let url: URL
    private var inode: UInt64?
    private var headerReady = false
    private var offset: UInt64 = 0
    private var pending = Data()
    private var discarding = false
    private var session: String?
    private var client: String?
    private var project = "未知项目"
    private(set) var activity: CodexActivity?
    private let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()
    private let plain = ISO8601DateFormatter()

    init(url: URL) { self.url = url }

    func poll() throws {
        let info = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = (info[.size] as? NSNumber)?.uint64Value ?? 0
        let identity = (info[.systemFileNumber] as? NSNumber)?.uint64Value
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        if identity != inode || size < offset || !headerReady {
            inode = identity; offset = 0; pending.removeAll(); activity = nil
            session = nil; client = nil; discarding = false; headerReady = false
            // Read the metadata header and newest lifecycle marker once. Old,
            // still-loaded desktop sessions can be tens of MB; never replay them.
            let head = try file.read(upToCount: 65_536) ?? Data()
            guard let end = head.firstIndex(of: 10) else { return }
            headerReady = true
            metadata(Data(head.prefix(upTo: end)))
            guard session != nil, client != nil else { offset = size; return }
            var boundary = size
            var suffix = Data()
            var found = false
            while boundary > 0 && !found {
                let lower = boundary > 262_144 ? boundary - 262_144 : 0
                try file.seek(toOffset: lower)
                let chunk = try file.read(upToCount: Int(boundary - lower)) ?? Data()
                var block = chunk; block.append(suffix)
                let lines = block.split(separator: 10, omittingEmptySubsequences: false)
                // At EOF, ignore an unfinished record until its newline arrives.
                var usable = Array(lines.dropLast())
                if boundary == size { pending = Data(lines.last ?? Data.SubSequence()) }
                if lower > 0 { usable = Array(usable.dropFirst()) }
                for line in usable.reversed() {
                    if consume(Data(line)) { found = true; break }
                }
                suffix = Data(lines.first ?? Data.SubSequence())
                if lines.count > 1 { suffix.append(10) }
                if suffix.count > 8_388_608 { suffix.removeAll() }
                boundary = lower
            }
            offset = size
            if pending.count > 8_388_608 { pending.removeAll(); discarding = true }
            return
        }
        guard size > offset else { return }
        try file.seek(toOffset: offset)
        // Bound incremental work; catch up on the next tick if necessary.
        let chunk = try file.read(upToCount: 4_194_304) ?? Data()
        offset += UInt64(chunk.count); pending.append(chunk)
        while let end = pending.firstIndex(of: 10) {
            if !discarding { _ = consume(Data(pending.prefix(upTo: end))) }
            pending.removeSubrange(...end); discarding = false
        }
        if pending.count > 8_388_608 { pending.removeAll(); discarding = true }
    }

    private func metadata(_ data: Data) {
        guard let r = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              r["type"] as? String == "session_meta", let p = r["payload"] as? [String: Any],
              let id = p["id"] as? String, UUID(uuidString: id) != nil,
              let source = p["source"] as? String else { return }
        if source == "exec" || source == "cli" { client = "codex_exec" }
        else if source == "vscode", p["originator"] as? String == "Codex Desktop" { client = "Codex Desktop" }
        else { return } // Subagents and unknown clients are not user task rows.
        session = id
        if let cwd = p["cwd"] as? String { project = URL(fileURLWithPath: cwd).lastPathComponent }
    }

    @discardableResult private func consume(_ data: Data) -> Bool {
        // Cheap byte filter before parsing; never interpret messages mentioning
        // these names as events. They must be top-level event_msg records.
        guard let raw = String(data: data, encoding: .utf8),
              raw.contains("\"task_started\"") || raw.contains("\"task_complete\"") || raw.contains("\"turn_aborted\""),
              let r = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              r["type"] as? String == "event_msg", let p = r["payload"] as? [String: Any],
              let kind = p["type"] as? String,
              ["task_started", "task_complete", "turn_aborted"].contains(kind),
              let turn = p["turn_id"] as? String,
              let session, let client else { return false }
        if kind == "task_started" {
            guard let stamp = r["timestamp"] as? String,
                  let date = fractional.date(from: stamp) ?? plain.date(from: stamp) else { return false }
            if activity?.turn != turn {
                activity = CodexActivity(session: session, turn: turn, project: project, start: date, client: client)
            }
        } else if activity == nil || activity?.turn == turn { activity = nil }
        return true
    }
}

final class CodexActivityMonitor {
    private let queue = DispatchQueue(label: "local.agentbell.codex-activity", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var readers: [String: CodexRollout] = [:]
    private var lastGood: [CodexActivity] = []
    private var failedSince: Date?
    private let home = FileManager.default.homeDirectoryForCurrentUser

    func start(deliver: @escaping ([CodexActivity], String?) -> Void) {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: 2)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let result = self.sample()
            DispatchQueue.main.async { deliver(result.0, result.1) }
        }
        self.timer = timer; timer.resume()
    }
    func stop() { timer?.cancel(); timer = nil }

    // Internal for the standalone smoke check; never invoked on the UI thread.
    func sample() -> ([CodexActivity], String?) {
        do {
            let paths = try writerPaths()
            readers = readers.filter { paths[$0.key] != nil }
            var result: [String: CodexActivity] = [:]
            var unreadable = false
            for (path, ownerStarted) in paths {
                let reader = readers[path] ?? CodexRollout(url: URL(fileURLWithPath: path))
                readers[path] = reader
                do { try reader.poll() } catch { unreadable = true; continue }
                if let value = reader.activity, value.start >= ownerStarted {
                    result[value.session] = value
                }
            }
            lastGood = Array(result.values); failedSince = nil
            return (lastGood, unreadable ? "部分 Codex 状态暂不可读" : nil)
        } catch {
            // Brief discovery failure must not make a live task blink out. A
            // sustained failure expires the evidence instead of keeping ghosts.
            if failedSince == nil { failedSince = Date() }
            if Date().timeIntervalSince(failedSince!) >= 10 { lastGood.removeAll() }
            return (lastGood, "Codex 状态暂不可确认")
        }
    }

    private func writerPaths() throws -> [String: Date] {
        let process = Process(), output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-n", "-P", "-c", "codex", "-Fpfan"]
        process.standardOutput = output; process.standardError = FileHandle.nullDevice
        try process.run()
        let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 3, execute: timeout)
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit(); timeout.cancel()
        guard process.terminationReason == .exit,
              process.terminationStatus == 0 || (process.terminationStatus == 1 && data.isEmpty),
              let text = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "AgentBell.CodexDiscovery", code: 1)
        }
        let root = home.appendingPathComponent(".codex/sessions").resolvingSymlinksInPath().path + "/"
        var access = ""
        var ownerStarted: Date?
        var paths: [String: Date] = [:]
        for line in text.split(separator: "\n") {
            if line.hasPrefix("p") {
                access = ""; ownerStarted = nil
                if let pid = Int32(line.dropFirst()) {
                    var info = proc_bsdinfo()
                    let size = Int32(MemoryLayout<proc_bsdinfo>.size)
                    if proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size {
                        ownerStarted = Date(timeIntervalSince1970: Double(info.pbi_start_tvsec) + Double(info.pbi_start_tvusec) / 1_000_000)
                    }
                }
            } else if line.hasPrefix("f") { access = "" }
            else if line.hasPrefix("a") { access = String(line.dropFirst()) }
            else if line.hasPrefix("n"), access == "w" || access == "u" {
                let path = String(line.dropFirst())
                if path.hasPrefix(root), path.hasSuffix(".jsonl"),
                   URL(fileURLWithPath: path).resolvingSymlinksInPath().path.hasPrefix(root), let ownerStarted {
                    // A new process reopening a crashed rollout must not resurrect
                    // a task_started left behind by its previous owner.
                    paths[path] = min(paths[path] ?? ownerStarted, ownerStarted)
                }
            }
        }
        return paths
    }
}
