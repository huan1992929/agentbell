import AppKit

struct Destination {
    let label: String
    let bundle: String
    let url: URL?
}

// All paths are resolved locally. Never infer a desktop id from a CLI id.
final class SessionNavigation {
    private var claudeIDs: [String: String] = [:]
    private var lastScan = Date.distantPast
    private let home = FileManager.default.homeDirectoryForCurrentUser

    func refresh() {
        guard Date().timeIntervalSince(lastScan) > 5 else { return }
        lastScan = Date()
        var matches: [String: Set<String>] = [:]
        let base = home.appendingPathComponent("Library/Application Support/Claude/claude-code-sessions")
        let fm = FileManager.default
        // The desktop stores metadata exactly two account directories below this root.
        // Do not recursively traverse transcript/attachment directories.
        for account in (try? fm.contentsOfDirectory(at: base, includingPropertiesForKeys: nil)) ?? [] {
            for org in (try? fm.contentsOfDirectory(at: account, includingPropertiesForKeys: nil)) ?? [] {
                for file in (try? fm.contentsOfDirectory(at: org, includingPropertiesForKeys: [.fileSizeKey])) ?? [] {
                    guard file.lastPathComponent.hasPrefix("local_"), file.pathExtension == "json",
                          (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize).map({ $0 < 2_097_152 }) == true,
                          let bytes = try? Data(contentsOf: file),
                          let data = (try? JSONSerialization.jsonObject(with: bytes)) as? [String: Any],
                          data["isArchived"] as? Bool != true,
                          let cli = data["cliSessionId"] as? String,
                          let desktop = data["sessionId"] as? String,
                          desktop == file.deletingPathExtension().lastPathComponent,
                          UUID(uuidString: cli) != nil,
                          desktop.range(of: "^local_[A-Za-z0-9-]{1,64}$", options: .regularExpression) != nil
                    else { continue }
                    matches[cli, default: []].insert(desktop)
                }
            }
        }
        // Ambiguous mappings must fall back rather than open a different conversation.
        claudeIDs = matches.compactMapValues { $0.count == 1 ? $0.first : nil }
    }

    static func codexClient(path: String, session: String?) -> String? {
        let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/sessions").resolvingSymlinksInPath().path + "/"
        let fileURL = URL(fileURLWithPath: path).resolvingSymlinksInPath()
        guard fileURL.path.hasPrefix(root), let file = try? FileHandle(forReadingFrom: fileURL) else { return nil }
        defer { try? file.close() }
        // Only the bounded session_meta header, never subsequent chat/tool records.
        guard let data = try? file.read(upToCount: 65_536), let end = data.firstIndex(of: 10),
              let record = (try? JSONSerialization.jsonObject(with: data.prefix(upTo: end))) as? [String: Any],
              record["type"] as? String == "session_meta",
              let meta = record["payload"] as? [String: Any], meta["id"] as? String == session,
              let source = meta["source"] as? String else { return nil }
        if source == "exec" || source == "cli" { return "codex_exec" }
        if source == "vscode", meta["originator"] as? String == "Codex Desktop" { return "Codex Desktop" }
        return nil
    }

    func destination(source: String, session: String?, client: String?) -> Destination {
        if source == "Claude" {
            if let session, let desktop = claudeIDs[session] {
                var url = URLComponents()
                url.scheme = "claude"; url.host = "code"; url.path = "/continue"
                url.queryItems = [URLQueryItem(name: "session", value: desktop)]
                return Destination(label: "打开会话", bundle: "com.anthropic.claudefordesktop", url: url.url)
            }
            return Destination(label: "打开 Claude · 无法定位会话", bundle: "com.anthropic.claudefordesktop", url: nil)
        }
        if client == "codex_exec" || client == "codex_cli_rs" {
            let terminal = ["com.googlecode.iterm2", "com.apple.Terminal"].first {
                !NSRunningApplication.runningApplications(withBundleIdentifier: $0).isEmpty
            } ?? "com.apple.Terminal"
            return Destination(label: "打开终端 · 不定位会话", bundle: terminal, url: nil)
        }
        if client == "Codex Desktop", let session, UUID(uuidString: session) != nil {
            return Destination(label: "打开会话", bundle: "com.openai.codex", url: URL(string: "codex://threads/" + session))
        }
        return Destination(label: "打开 Codex · 来源未确认", bundle: "com.openai.codex", url: nil)
    }

    func open(_ destination: Destination, feedback: @escaping (String) -> Void) {
        let workspace = NSWorkspace.shared
        guard let app = workspace.urlForApplication(withBundleIdentifier: destination.bundle) else {
            feedback("未找到对应 App"); return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        func activate() {
            workspace.openApplication(at: app, configuration: configuration) { _, error in
                DispatchQueue.main.async {
                    if error != nil { feedback("无法打开对应 App") }
                    else if destination.url != nil { feedback("已打开 App，无法定位到具体会话") }
                }
            }
        }
        guard let url = destination.url else { activate(); return }
        workspace.open([url], withApplicationAt: app, configuration: configuration) { _, error in
            // OS delivery alone is not confirmation that the app navigated.
            if error != nil { activate() }
        }
    }
}
