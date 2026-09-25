import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = EventStore(url: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".agentbell/logs/events.jsonl"))
    private var item: NSStatusItem!
    private var island: IslandController!
    private var timer: Timer?
    private let codex = CodexActivityMonitor()
    func applicationDidFinishLaunching(_ notification: Notification) {
        let identifier = Bundle.main.bundleIdentifier ?? "local.agentbell.menubar"
        if NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
            .contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            NSApp.terminate(nil); return
        }
        store.poll(); store.reconcileClaudeApp()
        island = IslandController(store: store)
        codex.start { [weak self] activities, problem, usage in
            guard let self else { return }
            self.store.reconcileCodex(activities, problem: problem)
            self.store.usage = usage
            self.island.refresh()
            self.item.button?.title = self.store.running.isEmpty ? "" : " \(self.store.running.count)"
        }
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "bell", accessibilityDescription: "AgentBell")
        item.button?.image?.isTemplate = true
        item.button?.toolTip = "AgentBell · 显示灵动岛 / 退出"
        let menu = NSMenu()
        let show = NSMenuItem(title: "显示灵动岛", action: #selector(showIsland), keyEquivalent: "")
        show.target = self; menu.addItem(show); menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出 AgentBell", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self; menu.addItem(quit); item.menu = menu
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.store.poll(); self.store.reconcileClaudeApp(); self.island.refresh()
            self.item.button?.title = self.store.running.isEmpty ? "" : " \(self.store.running.count)"
        }
        self.timer = timer; RunLoop.main.add(timer, forMode: .common)
    }
    func applicationWillTerminate(_ notification: Notification) { codex.stop() }
    @objc private func showIsland() { island.show() }
    @objc private func quitApp() { NSApp.terminate(nil) }
}
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
