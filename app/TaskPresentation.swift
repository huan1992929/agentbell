import Foundation

// Only user-submitted text is accepted here; assistant output is never a fallback.
enum TaskText {
    static let missing = "未记录任务提示词"
    static func title(_ prompt: String?) -> String? {
        guard let prompt else { return nil }
        if prompt.hasPrefix("# Overview\n\nGenerate 0 to 3 hyperpersonalized suggestions") {
            return "Codex 自动生成任务建议"
        }
        // Claude wraps pasted user input; the wrapper itself is not a title.
        let unwrapped = prompt.replacingOccurrences(of: "</?pasted_content(?:\\s[^>]*)?>", with: "", options: .regularExpression)
        guard let line = unwrapped.split(whereSeparator: \.isNewline).first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) else { return nil }
        var value = line.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        if value.hasPrefix("/"), !value.contains(" ") {
            value = URL(fileURLWithPath: value).lastPathComponent
        }
        value = value.replacingOccurrences(of: "^(?:#{1,6} |[-*] )", with: "", options: .regularExpression)
            .replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "`", with: "")
        guard !value.isEmpty, !isHeartbeat(value),
              value.range(of: "^</?[A-Za-z][A-Za-z0-9_-]*(?:\\s[^>]*)?>", options: .regularExpression) == nil else { return nil }
        return String(value.prefix(100)) + (value.count > 100 ? "…" : "")
    }
    static func isHeartbeat(_ prompt: String) -> Bool {
        prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            .range(of: "^<heartbeat(?:\\s[^>]*)?>", options: .regularExpression) != nil
    }
    static func isHeartbeatTurn(_ inputs: [String]) -> Bool {
        inputs.last(where: { submitted($0) || isHeartbeat($0) }).map(isHeartbeat) ?? false
    }
    static func submitted(_ prompt: String) -> Bool {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        return !text.isEmpty && !isHeartbeat(text) && !["Files mentioned by the user:", "<in-app-browser-context", "<task-notification>", "<environment_context>", "<recommended_plugins>", "<send_user_message_question_reply>", "<permissions instructions>", "# AGENTS.md instructions"].contains { text.hasPrefix($0) }
    }
}

enum TaskTime {
    static func duration(_ seconds: TimeInterval) -> String {
        let n = max(0, Int(seconds))
        if n >= 86400 { return "\(n / 86400)天" }
        if n >= 3600 { return "\(n / 3600)小时" }
        if n >= 60 { return "\(n / 60)分钟" }
        return "\(n)秒"
    }
    static func completed(_ date: Date, now: Date = Date()) -> String {
        let seconds = now.timeIntervalSince(date)
        if Calendar.current.isDate(date, inSameDayAs: now.addingTimeInterval(-86400)), seconds >= 3600 { return "昨天" }
        return seconds < 60 ? "刚刚" : duration(seconds) + "前"
    }
    static func elapsed(_ date: Date, now: Date = Date()) -> String {
        "已运行 " + duration(now.timeIntervalSince(date))
    }
}

struct CodexUsage {
    struct Window {
        let percent: Double
        let minutes: Int
        let reset: Date
        var name: String {
            if minutes % 1440 == 0 { return "\(minutes / 1440)天" }
            if minutes % 60 == 0 { return "\(minutes / 60)小时" }
            return "\(minutes)分钟"
        }
        var used: String {
            if percent > 0 && percent < 1 { return "<1%" }
            return (percent == percent.rounded() ? String(format: "%.0f", percent) : String(format: "%.1f", percent)) + "%"
        }
        func resetLabel(now: Date = Date()) -> String {
            let seconds = reset.timeIntervalSince(now)
            return seconds > 0 ? TaskTime.duration(seconds) + "后重置" : "等待新额度"
        }
        func label(now: Date) -> String {
            let remaining = reset.timeIntervalSince(now)
            let resetText = remaining > 0 ? TaskTime.duration(remaining) + "后重置" : "待刷新"
            return "\(name) 已用\(used) · \(resetText)"
        }
    }
    let time: Date
    let windows: [Window]
    init?(payload: [String: Any], time: Date) {
        guard payload["limit_id"] == nil || payload["limit_id"] is NSNull || payload["limit_id"] as? String == "codex" else { return nil }
        self.time = time
        windows = ["primary", "secondary"].compactMap { key in
            guard let value = payload[key] as? [String: Any],
                  let percent = value["used_percent"] as? Double, percent.isFinite, percent >= 0,
                  let minutes = value["window_minutes"] as? Int, minutes > 0,
                  let epoch = value["resets_at"] as? Double, epoch.isFinite else { return nil }
            return Window(percent: percent, minutes: minutes, reset: Date(timeIntervalSince1970: epoch))
        }
    }
    func freshness(now: Date = Date()) -> String {
        if windows.contains(where: { $0.reset <= now }) { return "等待更新 · 上次 " + TaskTime.completed(time, now: now) }
        return now.timeIntervalSince(time) > 900 ? "缓存 · " + TaskTime.completed(time, now: now) : "更新于 " + TaskTime.completed(time, now: now)
    }
    func label(now: Date = Date()) -> String {
        windows.isEmpty ? "Codex 用量不可用" : "Codex  " + windows.map { $0.label(now: now) }.joined(separator: "  /  ")
    }
}
