// Offline layout fixtures only. Never writes events or feeds the installed app.
import AppKit
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let folder = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
let now = Date()
func render(_ name: String, notch: CGFloat, active: Bool, unavailable: Bool = false) throws {
    let store = EventStore(url: folder.appendingPathComponent("not-an-event-log"), codexOnly: true)
    store.recent = [
        Completion(source: "Codex", session: "fixture-one", project: "产品网站", time: now.addingTimeInterval(-86400), summary: "调整首页信息顺序与导航入口"),
        Completion(source: "Codex", session: "fixture-two", project: "知识库", time: now.addingTimeInterval(-7200), summary: "核对导入文档的标题与目录"),
        Completion(source: "Codex", session: "fixture-three", project: "知识库", time: now.addingTimeInterval(-90000), summary: "另一会话：整理检索提示词")]
    if active {
        store.running["fixture-running"] = Running(source: "Codex", session: "fixture-running", project: "工作台", start: now.addingTimeInterval(-161), prompt: "fixture", background: false, title: "检查移动端信息层级，保留长任务说明在两行内可读，并能进入对应会话")
    }
    if !unavailable {
        store.usage = CodexUsage(payload: [
            "primary": ["used_percent": 0.04, "window_minutes": 300, "resets_at": now.addingTimeInterval(7200).timeIntervalSince1970] as [String: Any],
            "secondary": ["used_percent": 0.0, "window_minutes": 10080, "resets_at": now.addingTimeInterval(5 * 86400).timeIntervalSince1970] as [String: Any]], time: now.addingTimeInterval(-1800))
    }
    if !unavailable { precondition(store.usage?.windows.count == 2) }
    let view = IslandView(frame: NSRect(x: 0, y: 0, width: 420, height: 400))
    view.appearance = NSAppearance(named: .darkAqua)
    view.expanded = true; view.notch = notch; view.notchWidth = notch > 0 ? 185 : 0
    view.count = active ? 1 : 0; view.message = unavailable ? "暂时无法读取任务状态，请打开 Codex 查看" : nil
    view.quota.refresh(store.usage)
    view.rebuild(store: store, navigation: SessionNavigation(), open: { _ in })
    view.setFrameSize(NSSize(width: 420, height: view.preferredHeight + notch))
    view.layoutSubtreeIfNeeded()
    let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
    view.cacheDisplay(in: view.bounds, to: rep)
    try rep.representation(using: .png, properties: [:])!.write(to: folder.appendingPathComponent(name + ".png"))
    print(name, view.frame.size)
}
try render("fixture-idle", notch: 0, active: false)
try render("fixture-notch-running", notch: 32, active: true)
try render("fixture-unavailable", notch: 0, active: false, unavailable: true)
