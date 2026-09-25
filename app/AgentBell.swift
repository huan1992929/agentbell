import AppKit

struct Running {
    let project: String
    let start: Date
    let prompt: String?
}

struct Completion {
    let source: String
    let project: String
    let time: Date
    let summary: String
}

// Reads only the event script's append-only log. No notifications, subprocesses,
// terminal inspection or network access belong in the presentation process.
final class EventStore {
    let url: URL
    var running: [String: Running] = [:]
    var recent: [Completion] = []
    var problem: String?
    private var offset: UInt64 = 0
    private var identity: UInt64?
    private var pending = Data()
    private var discarding = false
    private let fractional = ISO8601DateFormatter()
    private let plain = ISO8601DateFormatter()

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

    private func consume(_ line: Data) {
        guard let record = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
              let source = record["source"] as? String,
              let payload = record["payload"] as? [String: Any],
              let stamp = record["timestamp"] as? String,
              let time = fractional.date(from: stamp) ?? plain.date(from: stamp) else { return }
        let cwd = payload["cwd"] as? String ?? ""
        let project = cwd.isEmpty ? "未知项目" : URL(fileURLWithPath: cwd).lastPathComponent
        let event = payload["hook_event_name"] as? String
        if source == "claude", let session = payload["session_id"] as? String {
            if event == "UserPromptSubmit" {
                running[session] = Running(project: project, start: time,
                                           prompt: payload["prompt_id"] as? String)
                return
            }
            if event == "Stop" {
                let start = running[session]
                let prompt = payload["prompt_id"] as? String
                // A delayed Stop from a previous turn must not clear a newer turn.
                if let start, time >= start.start,
                   start.prompt == nil || prompt == nil || start.prompt == prompt {
                    running.removeValue(forKey: session)
                }
            }
        }
        let isClaude = source == "claude" && event == "Stop"
        let isCodex = source == "codex" && payload["type"] as? String == "agent-turn-complete"
        guard isClaude || isCodex else { return }
        let message = payload[isClaude ? "last_assistant_message" : "last-assistant-message"] as? String ?? ""
        let lastLine = message.split(whereSeparator: \.isNewline).last.map(String.init) ?? "（无回复摘要）"
        let compact = lastLine.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let summary = String(compact.prefix(100)) + (compact.count > 100 ? "…" : "")
        recent.append(Completion(source: isClaude ? "Claude" : "Codex", project: project,
                                 time: time, summary: summary))
        recent.sort { $0.time > $1.time }
        recent = Array(recent.prefix(10))
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let store = EventStore(url: FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".agentbell/logs/events.jsonl"))
    private var item: NSStatusItem!
    private let menu = NSMenu()
    private var timer: Timer?
    private var signature = ""
    private var runningItems: [(NSMenuItem, Running)] = []
    private let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm:ss"
        return formatter
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // LaunchAgent and a manual open should share one menu bar instance.
        let identifier = Bundle.main.bundleIdentifier ?? "local.agentbell.menubar"
        if NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
            .contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            NSApp.terminate(nil)
            return
        }
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "bell", accessibilityDescription: "AgentBell")
        item.button?.image?.isTemplate = true
        item.button?.toolTip = "AgentBell · 任务状态"
        menu.autoenablesItems = false
        menu.delegate = self
        item.menu = menu
        refresh()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.refresh() }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func menuWillOpen(_ menu: NSMenu) { refresh() }

    private func row(_ title: String, header: Bool = false) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        entry.isEnabled = !header
        menu.addItem(entry)
        return entry
    }

    private func runningTitle(_ value: Running) -> String {
        let seconds = max(0, Int(Date().timeIntervalSince(value.start)))
        let elapsed = seconds >= 3600
            ? String(format: "%d小时%02d分%02d秒", seconds / 3600, seconds / 60 % 60, seconds % 60)
            : String(format: "%d分%02d秒", seconds / 60, seconds % 60)
        return "Claude · \(value.project) · \(elapsed)"
    }

    private func refresh() {
        store.poll()
        item.button?.title = store.running.isEmpty ? "" : " \(store.running.count)"
        let running = store.running.sorted { $0.key < $1.key }
        let next = running.map { "\($0.key):\($0.value.start.timeIntervalSince1970)" }.joined()
            + store.recent.map { "\($0.source)\($0.project)\($0.time)\($0.summary)" }.joined()
            + (store.problem ?? "")
        if next != signature || menu.items.isEmpty {
            signature = next
            menu.removeAllItems()
            runningItems.removeAll()
            _ = row("Claude 运行中", header: true)
            if running.isEmpty { _ = row("暂无运行中的 Claude 会话") }
            for (_, value) in running {
                runningItems.append((row(runningTitle(value)), value))
            }
            menu.addItem(.separator())
            _ = row("最近完成 · Claude / Codex", header: true)
            if store.recent.isEmpty { _ = row("暂无完成记录") }
            for value in store.recent {
                _ = row("\(value.source) · \(value.project) · \(clock.string(from: value.time))")
                let summary = row(value.summary)
                summary.indentationLevel = 1
                summary.toolTip = value.summary
            }
            if let problem = store.problem { _ = row(problem, header: true) }
            menu.addItem(.separator())
            let quit = NSMenuItem(title: "退出 AgentBell", action: #selector(quitApp), keyEquivalent: "q")
            quit.target = self
            menu.addItem(quit)
        }
        for (entry, value) in runningItems { entry.title = runningTitle(value) }
    }

    @objc private func quitApp() { NSApp.terminate(nil) }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
