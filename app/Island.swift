import AppKit
import QuartzCore

private let ink = NSColor(calibratedWhite: 0.94, alpha: 1)
private let quiet = NSColor(calibratedWhite: 0.62, alpha: 1)
private let activeColor = NSColor(calibratedRed: 0.49, green: 0.88, blue: 0.72, alpha: 1)
private let attentionColor = NSColor(calibratedRed: 0.96, green: 0.72, blue: 0.40, alpha: 1)

private func text(_ value: String, in rect: NSRect, size: CGFloat, color: NSColor = ink,
                  weight: NSFont.Weight = .regular, mono: Bool = false, wrap: Bool = false) {
    let style = NSMutableParagraphStyle()
    style.lineBreakMode = wrap ? .byWordWrapping : .byTruncatingTail
    (value as NSString).draw(in: rect, withAttributes: [
        .font: mono ? NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight) : NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: color, .paragraphStyle: style
    ])
}

private func symbol(_ name: String, in rect: NSRect, color: NSColor) {
    guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
        .withSymbolConfiguration(.init(pointSize: rect.height, weight: .regular)) else { return }
    let tinted = NSImage(size: image.size)
    tinted.lockFocus(); color.setFill(); NSRect(origin: .zero, size: image.size).fill()
    image.draw(at: .zero, from: .zero, operation: .destinationIn, fraction: 1)
    tinted.unlockFocus()
    tinted.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
}

final class IslandPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
final class FlippedView: NSView { override var isFlipped: Bool { true } }

final class TaskRow: NSButton {
    var project = "", detail = "", stamp = ""
    var active = false
    var destination: Destination!
    var start: Date?
    var completed: Date?
    var invoke: ((Destination) -> Void)?
    private var hovered = false
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isBordered = false; target = self; action = #selector(openRow)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }
    override func mouseEntered(with event: NSEvent) { hovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
    @objc private func openRow() { invoke?(destination) }
    func updateElapsed() {
        if let start { stamp = TaskTime.elapsed(start) }
        else if let completed { stamp = TaskTime.completed(completed) }
        setAccessibilityLabel("\(project) · \(detail) · \(stamp) · \(destination.label)")
        needsDisplay = true
    }
    override func draw(_ dirtyRect: NSRect) {
        if hovered || isHighlighted {
            NSColor.white.withAlphaComponent(isHighlighted ? 0.10 : 0.055).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 1), xRadius: 10, yRadius: 10).fill()
        }
        text(project, in: NSRect(x: 14, y: 8, width: bounds.width - 152, height: 19), size: 13, weight: active ? .semibold : .medium)
        text(stamp, in: NSRect(x: bounds.width - 132, y: 10, width: 106, height: 17), size: 11, color: active ? activeColor : quiet, mono: true)
        // The prompt remains legible on hover; the affordance doesn't replace it.
        text(detail, in: NSRect(x: 14, y: 29, width: bounds.width - 44, height: 17), size: 12, color: quiet)
        if hovered { symbol("arrow.up.right", in: NSRect(x: bounds.width - 23, y: 10, width: 11, height: 11), color: ink) }
    }
}

final class QuotaView: NSView {
    var usage: CodexUsage?
    override var isFlipped: Bool { true }
    var preferredHeight: CGFloat { 30 + CGFloat(max(1, usage?.windows.count ?? 0)) * 24 }
    override init(frame: NSRect) {
        super.init(frame: frame); setAccessibilityElement(true); setAccessibilityRole(.group)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func refresh(_ value: CodexUsage?) {
        usage = value
        let summary = (value?.label() ?? "Codex 用量暂不可用") + " · " + (value?.freshness() ?? "尚未获取到额度记录")
        setAccessibilityLabel(summary); toolTip = summary; needsDisplay = true
    }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.withAlphaComponent(0.07).setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: 0.5).fill()
        text("Codex 用量", in: NSRect(x: 0, y: 13, width: 100, height: 17), size: 11, color: quiet, weight: .medium)
        text(usage?.freshness() ?? "暂无数据", in: NSRect(x: 124, y: 13, width: bounds.width - 124, height: 17), size: 10, color: quiet)
        guard let usage, !usage.windows.isEmpty else {
            text("暂不可用", in: NSRect(x: 0, y: 32, width: bounds.width, height: 17), size: 12, color: quiet)
            return
        }
        for (index, window) in usage.windows.enumerated() {
            let y = 32 + CGFloat(index) * 24
            text(window.name, in: NSRect(x: 0, y: y, width: 66, height: 16), size: 11, color: quiet)
            text(window.used, in: NSRect(x: 69, y: y - 1, width: 52, height: 18), size: 12, weight: .medium, mono: true)
            text(window.resetLabel(), in: NSRect(x: bounds.width - 110, y: y, width: 110, height: 16), size: 11, color: quiet)
            let track = NSRect(x: 128, y: y + 7, width: max(20, bounds.width - 252), height: 2)
            NSColor.white.withAlphaComponent(0.10).setFill(); NSBezierPath(roundedRect: track, xRadius: 1, yRadius: 1).fill()
            // No fill for 0%; unavailable data has no track at all.
            if window.percent > 0 {
                let stale = Date() > window.reset || Date().timeIntervalSince(usage.time) > 900
                (stale ? quiet : window.percent >= 90 ? attentionColor : NSColor(calibratedWhite: 0.78, alpha: 1)).setFill()
                NSBezierPath(roundedRect: NSRect(x: track.minX, y: track.minY, width: max(1, track.width * min(100, window.percent) / 100), height: 2), xRadius: 1, yRadius: 1).fill()
            }
        }
    }
}

final class IslandView: NSView {
    var expanded = false
    var notch: CGFloat = 0
    var notchWidth: CGFloat = 0
    var count = 0
    var status = "当前空闲"
    var message: String?
    var pinned = false
    var showHistory = false
    var toggle: (() -> Void)?
    var pin: (() -> Void)?
    var history: (() -> Void)?
    var openApp: (() -> Void)?
    let pinButton = NSButton()
    let closeButton = NSButton()
    let moreButton = NSButton()
    let attentionButton = NSButton()
    let scroll = NSScrollView()
    let document = FlippedView()
    let quota = QuotaView(frame: .zero)
    var rows: [TaskRow] = []
    var historyCount = 0
    var recentLimit: Int { count > 0 ? 1 : 2 }
    var footerHeight: CGFloat { quota.preferredHeight + 12 }
    var headerHeight: CGFloat { message == nil ? 44 : 70 }
    var preferredHeight: CGFloat { headerHeight + document.frame.height + footerHeight + (historyCount > recentLimit ? 26 : 0) }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        scroll.drawsBackground = false; scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true; scroll.scrollerStyle = .overlay
        scroll.documentView = document; scroll.contentView.drawsBackground = false
        addSubview(scroll); addSubview(quota)
        for button in [pinButton, closeButton, moreButton, attentionButton] {
            button.isBordered = false; button.bezelStyle = .inline; button.target = self
            button.font = .systemFont(ofSize: 11); button.contentTintColor = quiet
            button.setButtonType(.momentaryPushIn); addSubview(button)
        }
        pinButton.action = #selector(pinTapped); closeButton.action = #selector(closeTapped); moreButton.action = #selector(historyTapped)
        attentionButton.title = "打开 Codex"; attentionButton.action = #selector(openAppTapped)
        attentionButton.setAccessibilityLabel("打开 Codex 查看状态")
        closeButton.image = NSImage(systemSymbolName: "chevron.up", accessibilityDescription: "收起面板")
        closeButton.toolTip = "收起面板"; closeButton.setAccessibilityLabel("收起面板")
        setAccessibilityElement(true); setAccessibilityRole(.group)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func openAppTapped() { openApp?() }
    @objc private func pinTapped() { pin?() }
    @objc private func closeTapped() { toggle?() }
    @objc private func historyTapped() { history?() }
    override func mouseDown(with event: NSEvent) { if !expanded { toggle?() } }
    func refreshControls() {
        pinButton.image = NSImage(systemSymbolName: pinned ? "pin.fill" : "pin", accessibilityDescription: pinned ? "取消固定" : "固定面板")
        pinButton.contentTintColor = pinned ? ink : quiet
        pinButton.toolTip = pinned ? "取消固定，恢复移开收起" : "固定面板，移开鼠标也保持展开"
        pinButton.setAccessibilityLabel(pinned ? "取消固定" : "固定面板")
        moreButton.title = showHistory ? "收起较早记录" : "再看 \(max(0, historyCount - recentLimit)) 个会话"
        moreButton.setAccessibilityLabel(moreButton.title)
        needsLayout = true
    }
    override func draw(_ dirtyRect: NSRect) {
        let bodyTop = notch > 0 && expanded ? notch - 1 : 0
        let body = NSRect(x: 0, y: bodyTop, width: bounds.width, height: bounds.height - bodyTop)
        let shape = NSBezierPath(roundedRect: body, xRadius: expanded ? 22 : 18, yRadius: expanded ? 22 : 18)
        (notch > 0 ? NSColor.black : NSColor(calibratedWhite: 0.025, alpha: 1)).setFill(); shape.fill()
        if notch > 0 {
            NSColor.black.setFill()
            NSBezierPath(roundedRect: NSRect(x: (bounds.width - notchWidth - 108) / 2, y: 0,
                width: notchWidth + 108, height: notch + (expanded ? 16 : 0)), xRadius: 12, yRadius: 12).fill()
        }
        if expanded {
            let heading = message != nil ? "需要关注" : count > 0 ? "正在进行 · \(count)" : "当前空闲"
            text(heading, in: NSRect(x: 24, y: notch + 16, width: bounds.width - 110, height: 19), size: 13,
                 color: message != nil ? attentionColor : count > 0 ? activeColor : quiet, weight: .medium)
            if let message {
                text(message, in: NSRect(x: 24, y: notch + 43, width: bounds.width - 140, height: 18), size: 11, color: quiet)
            }
        } else if notch > 0 {
            symbol(message != nil ? "exclamationmark.circle" : "terminal", in: NSRect(x: (bounds.width - notchWidth) / 2 - 32, y: notch / 2 - 7, width: 14, height: 14), color: message != nil ? attentionColor : quiet)
            text(count > 0 ? "\(count)" : "空闲", in: NSRect(x: (bounds.width + notchWidth) / 2 + 14, y: notch / 2 - 8, width: 36, height: 17), size: 11, color: count > 0 ? activeColor : quiet, mono: true)
        } else {
            symbol(message != nil ? "exclamationmark.circle" : "terminal", in: NSRect(x: 16, y: 10, width: 13, height: 13), color: message != nil ? attentionColor : quiet)
            text(status, in: NSRect(x: 38, y: 8, width: bounds.width - 54, height: 19), size: 12, weight: .medium)
        }
    }
    override func layout() {
        super.layout()
        let moreHeight: CGFloat = historyCount > recentLimit ? 26 : 0
        let bodyHeight = max(0, bounds.height - notch - headerHeight - footerHeight - moreHeight)
        scroll.isHidden = !expanded; quota.isHidden = !expanded
        pinButton.isHidden = !expanded; closeButton.isHidden = !expanded
        moreButton.isHidden = !expanded || historyCount <= recentLimit
        attentionButton.isHidden = !expanded || message == nil
        attentionButton.frame = NSRect(x: bounds.width - 104, y: notch + 36, width: 86, height: 28)
        pinButton.frame = NSRect(x: bounds.width - 78, y: notch + 9, width: 28, height: 28)
        closeButton.frame = NSRect(x: bounds.width - 46, y: notch + 9, width: 28, height: 28)
        scroll.frame = NSRect(x: 10, y: notch + headerHeight, width: bounds.width - 20, height: bodyHeight)
        document.setFrameSize(NSSize(width: scroll.contentSize.width, height: document.frame.height))
        rows.forEach { $0.frame.size.width = scroll.contentSize.width }
        moreButton.frame = NSRect(x: 21, y: scroll.frame.maxY, width: 160, height: moreHeight)
        quota.frame = NSRect(x: 24, y: bounds.height - footerHeight, width: bounds.width - 48, height: quota.preferredHeight)
    }
    private func header(_ title: String, y: CGFloat) {
        let field = NSTextField(labelWithString: title)
        field.font = .systemFont(ofSize: 11, weight: .medium); field.textColor = quiet
        field.frame = NSRect(x: 14, y: y + 8, width: 350, height: 17); document.addSubview(field)
    }
    func rebuild(store: EventStore, navigation: SessionNavigation, open: @escaping (Destination) -> Void) {
        let position = scroll.contentView.bounds.origin
        document.subviews.forEach { $0.removeFromSuperview() }; rows.removeAll()
        var y: CGFloat = 0
        func add(session: String?, project: String, title: String, start: Date? = nil, completed: Date? = nil) {
            let row = TaskRow(frame: NSRect(x: 0, y: y, width: scroll.contentSize.width, height: 52))
            row.project = project; row.detail = title; row.start = start; row.completed = completed; row.active = start != nil
            row.destination = navigation.destination(source: "Codex", session: session, client: session.flatMap { store.clients["codex:" + $0] })
            row.invoke = open; row.toolTip = "\(project)\n\(title)\n\(row.destination.label)"
            row.updateElapsed(); document.addSubview(row); rows.append(row); y += 52
        }
        let running = store.running.values.filter { $0.source == "Codex" }.sorted { $0.start > $1.start }
        for value in running { add(session: value.session, project: value.project, title: value.title, start: value.start) }
        // One row per session; a currently running session is already visible above.
        let recent = store.recent.filter { value in
            value.source == "Codex" && !running.contains { $0.session != nil && $0.session == value.session }
        }
        historyCount = recent.count
        if !recent.isEmpty {
            if !running.isEmpty { y += 8 }
            header("最近结束", y: y); y += 24
            for value in recent.prefix(showHistory ? 5 : recentLimit) {
                add(session: value.session, project: value.project, title: value.summary, completed: value.time)
            }
        } else if running.isEmpty {
            header("任务结束后，可以从这里返回会话", y: y); y += 34
        }
        document.frame.size = NSSize(width: scroll.contentSize.width, height: y + 6)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: min(position.y, max(0, y - scroll.contentSize.height))))
        scroll.reflectScrolledClipView(scroll.contentView); refreshControls()
    }
}
final class IslandController {
    let panel: IslandPanel
    let view = IslandView(frame: .zero)
    private(set) var expanded = false
    private var screenNumber: NSNumber?
    private var fixedScreen: NSScreen?
    private var intendedFrame = NSRect.zero
    private var outsideSince: Date?
    private var suppressHoverUntil = Date.distantPast
    private var pinnedUntil = Date.distantPast
    private var timer: Timer?
    private var store: EventStore
    private let navigation = SessionNavigation()
    private var signature = ""
    private var transientMessage: String?
    private var messageUntil = Date.distantPast

    init(store: EventStore) {
        self.store = store
        panel = IslandPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "AgentBell Island"
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.hasShadow = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle, .transient]
        panel.isReleasedWhenClosed = false
        panel.contentView = view
        view.toggle = { [weak self] in
            guard let self else { return }
            if self.expanded { self.view.pinned = false; self.fixedScreen = nil; self.setExpanded(false) } else { self.show() }
            self.suppressHoverUntil = Date().addingTimeInterval(0.6)
        }
        view.pin = { [weak self] in
            guard let self else { return }
            let screen = self.mouseScreen()
            self.view.pinned.toggle()
            self.fixedScreen = self.view.pinned ? screen : nil
            if self.view.pinned { self.show() }
            self.view.refreshControls(); self.refresh()
        }
        view.openApp = { [weak self] in
            guard let self else { return }
            self.navigation.open(Destination(label: "打开 Codex", bundle: "com.openai.codex", url: nil)) { [weak self] message in
                self?.transientMessage = message; self?.messageUntil = Date().addingTimeInterval(6); self?.refresh()
            }
        }
        view.history = { [weak self] in
            guard let self else { return }
            self.view.showHistory.toggle(); self.signature = ""; self.refresh()
        }
        tick(); refresh()
        panel.orderFrontRegardless()
        let timer = Timer(timeInterval: 0.12, repeats: true) { [weak self] _ in self?.tick() }
        self.timer = timer; RunLoop.main.add(timer, forMode: .common)
    }
    func show() {
        pinnedUntil = Date().addingTimeInterval(3)
        setExpanded(true); panel.orderFrontRegardless()
    }
    private func setExpanded(_ value: Bool) {
        guard expanded != value else { return }
        expanded = value; view.expanded = value
        if !value { view.showHistory = false; signature = "" }
        view.refreshControls(); place(animated: true); view.needsDisplay = true
    }
    private func mouseScreen() -> NSScreen? {
        if let fixedScreen, NSScreen.screens.contains(fixedScreen) { return fixedScreen }
        fixedScreen = nil; view.pinned = false
        return NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
    }
    private func place(animated: Bool = false) {
        guard let screen = mouseScreen() else { return }
        screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        let notch = screen.safeAreaInsets.top
        let gap = max(0, (screen.auxiliaryTopRightArea?.minX ?? 0) - (screen.auxiliaryTopLeftArea?.maxX ?? 0))
        view.notch = notch; view.notchWidth = notch > 0 ? max(185, gap) : 0
        let compactWidth = max(148, min(360, (view.status as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 12, weight: .medium)]).width + 50))
        let width: CGFloat = expanded ? min(520, screen.frame.width - 32) : (notch > 0 ? view.notchWidth + 108 : compactWidth)
        let height: CGFloat = expanded ? min(max(180, min(520, view.preferredHeight)) + notch, screen.visibleFrame.height - 24) : max(34, notch)
        let top = notch > 0 ? screen.frame.maxY : min(screen.visibleFrame.maxY, screen.frame.maxY - 24) - 7
        let frame = NSRect(x: screen.frame.midX - width / 2, y: top - height, width: width, height: height)
        if intendedFrame != frame {
            intendedFrame = frame
            if animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.16; context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    panel.animator().setFrame(frame, display: true)
                }
            } else { panel.setFrame(frame, display: true) }
            view.needsLayout = true
        }
    }
    private func tick() {
        guard let screen = mouseScreen() else { return }
        let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        if screenNumber != number {
            expanded = false; view.expanded = false; outsideSince = nil; place()
        }
        // System display changes also update the frame without stealing focus.
        place()
        let inside = panel.frame.contains(NSEvent.mouseLocation)
        if inside {
            outsideSince = nil
            if Date() > suppressHoverUntil { setExpanded(true) }
        } else if !view.pinned && Date() > pinnedUntil {
            if outsideSince == nil { outsideSince = Date() }
            if Date().timeIntervalSince(outsideSince!) > 0.35 { setExpanded(false) }
        }
    }
    func refresh() {
        view.count = store.running.values.filter { $0.source == "Codex" }.count
        let current = store.running.values.filter { $0.source == "Codex" }.sorted { $0.start > $1.start }.first
        view.message = Date() < messageUntil ? transientMessage : (store.problem ?? store.codexProblem)
        view.status = current.map { "\(view.count) 进行中 · \($0.project) · \($0.title)" } ?? "当前空闲"
        if current == nil && view.message != nil { view.status = "状态暂不可确认" }
        view.quota.refresh(store.usage)
        view.toolTip = view.status
        view.setAccessibilityLabel("AgentBell · " + view.status + (view.pinned ? " · 已固定" : "") + (view.message.map { " · " + $0 } ?? ""))
        let next = store.running.sorted { $0.key < $1.key }.map { "\($0.key)\($0.value.start)\($0.value.background)\($0.value.title)" }.joined()
            + store.recent.map { "\($0.source)\($0.session ?? "")\($0.time)\($0.summary)" }.joined()
            + store.clients.description
        // Routing metadata may become available a few seconds after the first event.
        let routes = (store.running.values.map { ($0.source, $0.session) } + store.recent.map { ($0.source, $0.session) })
            .map { navigation.destination(source: $0.0, session: $0.1, client: $0.1.flatMap { store.clients["codex:" + $0] }).url?.absoluteString ?? "" }.joined()
        if signature != next + routes {
            signature = next + routes
            view.rebuild(store: store, navigation: navigation) { [weak self] destination in
                guard let self else { return }
                if !self.view.pinned { self.setExpanded(false) }
                self.suppressHoverUntil = Date().addingTimeInterval(1)
                self.navigation.open(destination) { [weak self] message in
                    guard let self else { return }
                    self.transientMessage = message
                    self.messageUntil = Date().addingTimeInterval(6)
                    self.pinnedUntil = self.messageUntil
                    self.view.message = message
                    self.setExpanded(true)
                    self.view.needsDisplay = true
                }
            }
        }
        view.rows.forEach { $0.updateElapsed() }
        place(); view.needsDisplay = true
    }
}
