import AppKit

private let ink = NSColor(calibratedWhite: 0.94, alpha: 1)
private let quiet = NSColor(calibratedWhite: 0.64, alpha: 1)
private let mint = NSColor(calibratedRed: 0.49, green: 0.88, blue: 0.72, alpha: 1)
private let clay = NSColor(calibratedRed: 0.92, green: 0.68, blue: 0.51, alpha: 1)

private func text(_ value: String, in rect: NSRect, size: CGFloat, color: NSColor = ink,
                  weight: NSFont.Weight = .regular, mono: Bool = false) {
    let style = NSMutableParagraphStyle()
    style.lineBreakMode = .byTruncatingTail
    (value as NSString).draw(in: rect, withAttributes: [
        .font: mono ? NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight) : NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: color, .paragraphStyle: style
    ])
}

final class IslandPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class FlippedView: NSView { override var isFlipped: Bool { true } }

final class TaskRow: NSButton {
    var source = "", project = "", detail = "", stamp = ""
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
        isBordered = false
        target = self; action = #selector(openRow)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }
    override func mouseEntered(with event: NSEvent) { hovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true }
    @objc private func openRow() { invoke?(destination) }
    func updateElapsed() {
        if let start { stamp = TaskTime.elapsed(start) }
        else if let completed { stamp = TaskTime.completed(completed) }
        setAccessibilityLabel("\(source) · \(project) · \(detail) · \(stamp) · \(destination.label)")
        needsDisplay = true
    }
    override func draw(_ dirtyRect: NSRect) {
        if hovered || isHighlighted {
            NSColor.white.withAlphaComponent(isHighlighted ? 0.12 : 0.065).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 1), xRadius: 12, yRadius: 12).fill()
        }
        let color = source == "Claude" ? clay : mint
        color.setFill()
        NSBezierPath(roundedRect: NSRect(x: 13, y: 16, width: 3, height: active ? 28 : 15), xRadius: 1.5, yRadius: 1.5).fill()
        text(source, in: NSRect(x: 27, y: 10, width: 56, height: 17), size: 12, color: color, weight: .semibold)
        text(project, in: NSRect(x: 89, y: 10, width: bounds.width - 219, height: 18), size: 13, weight: .medium)
        text(stamp, in: NSRect(x: bounds.width - 120, y: 10, width: 108, height: 17), size: 11, color: quiet, mono: true)
        text(detail, in: NSRect(x: 27, y: 29, width: bounds.width - 47, height: 18), size: 12, color: quiet)
    }
}

final class IslandView: NSView {
    var expanded = false
    var notch: CGFloat = 0
    var notchWidth: CGFloat = 0
    var count = 0
    var status = "一切就绪"
    var message: String?
    var usage = "Codex 用量不可用"
    var sourceMark = "CX"
    var toggle: (() -> Void)?
    let scroll = NSScrollView()
    let document = FlippedView()
    var rows: [TaskRow] = []
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.documentView = document
        scroll.contentView.drawsBackground = false
        addSubview(scroll)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("AgentBell 任务状态")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func mouseDown(with event: NSEvent) { toggle?() }
    override func draw(_ dirtyRect: NSRect) {
        let bodyTop = notch > 0 && expanded ? notch - 1 : 0
        let body = NSRect(x: 0.5, y: bodyTop + 0.5, width: bounds.width - 1, height: bounds.height - bodyTop - 1)
        let shape = NSBezierPath(roundedRect: body, xRadius: expanded ? 22 : 18, yRadius: expanded ? 22 : 18)
        NSColor(calibratedWhite: 0.065, alpha: 0.99).setFill(); shape.fill()
        NSColor.white.withAlphaComponent(0.14).setStroke(); shape.lineWidth = 0.5; shape.stroke()
        if notch > 0 {
            NSColor.black.setFill()
            NSBezierPath(roundedRect: NSRect(x: (bounds.width - notchWidth - 108) / 2, y: 0,
                                            width: notchWidth + 108, height: notch + (expanded ? 12 : 0)), xRadius: 12, yRadius: 12).fill()
        }
        if expanded {
            let y = notch + 15
            text("AgentBell", in: NSRect(x: 23, y: y, width: 160, height: 21), size: 16, weight: .semibold)
            text(count > 0 ? "\(count) 个进行中" : "一切就绪", in: NSRect(x: bounds.width - 125, y: y + 3, width: 100, height: 18), size: 12, color: count > 0 ? mint : quiet)
            text(message ?? "点击条目打开 · 移开收起", in: NSRect(x: 23, y: bounds.height - 45, width: bounds.width - 46, height: 17), size: 11, color: quiet)
            let available = bounds.width - 46
            let measured = (usage as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 11)]).width
            text(usage, in: NSRect(x: 23, y: bounds.height - 25, width: available, height: 17),
                 size: min(11, max(9, 11 * available / max(1, measured))), color: quiet)
        } else if notch > 0 {
            let left = (bounds.width - notchWidth) / 2
            text(sourceMark, in: NSRect(x: left - 37, y: notch / 2 - 9, width: 30, height: 18), size: 12, color: mint, weight: .semibold)
            text(count > 0 ? "\(count)" : "✓", in: NSRect(x: (bounds.width + notchWidth) / 2 + 16, y: notch / 2 - 9, width: 32, height: 18), size: 12, color: count > 0 ? mint : quiet, mono: true)
        } else {
            drawDot(x: 16, y: 14)
            text(status, in: NSRect(x: 32, y: 8, width: bounds.width - 48, height: 19), size: 12, weight: .medium)
        }
    }
    private func drawDot(x: CGFloat, y: CGFloat) {
        (count > 0 ? mint : quiet).setFill()
        NSBezierPath(ovalIn: NSRect(x: x, y: y, width: 6, height: 6)).fill()
    }
    override func layout() {
        super.layout()
        scroll.isHidden = !expanded
        scroll.frame = NSRect(x: 10, y: notch + 49, width: bounds.width - 20, height: max(0, bounds.height - notch - 104))
        document.setFrameSize(NSSize(width: scroll.contentSize.width, height: document.frame.height))
        rows.forEach { $0.frame.size.width = scroll.contentSize.width }
    }
    func header(_ title: String, y: CGFloat) {
        let field = NSTextField(labelWithString: title)
        field.font = .systemFont(ofSize: 11, weight: .semibold)
        field.textColor = quiet
        field.frame = NSRect(x: 13, y: y + 9, width: 350, height: 17)
        document.addSubview(field)
    }
    func rebuild(store: EventStore, navigation: SessionNavigation, open: @escaping (Destination) -> Void) {
        let position = scroll.contentView.bounds.origin
        document.subviews.forEach { $0.removeFromSuperview() }; rows.removeAll()
        var y: CGFloat = 0
        func add(source: String, session: String?, project: String, detail: String, stamp: String, start: Date? = nil, completed: Date? = nil) {
            let row = TaskRow(frame: NSRect(x: 0, y: y, width: scroll.contentSize.width, height: 52))
            row.source = source; row.project = project; row.detail = detail; row.stamp = stamp
            row.start = start; row.completed = completed; row.active = start != nil
            row.destination = navigation.destination(source: source, session: session,
                client: session.flatMap { store.clients["codex:" + $0] })
            row.invoke = open
            row.toolTip = "\(source) · \(project)\n\(detail)\n\(row.destination.label)"
            row.setAccessibilityLabel("\(source) · \(project) · \(detail) · \(row.destination.label)")
            row.updateElapsed(); document.addSubview(row); rows.append(row); y += 52
        }
        header("运行中", y: y); y += 25
        if store.running.isEmpty { header("暂无运行中的任务", y: y); y += 29 }
        for value in store.running.values.sorted(by: { $0.start < $1.start }) {
            add(source: value.source, session: value.session, project: value.project,
                detail: value.title, stamp: "", start: value.start)
        }
        y += 5; header("最近完成", y: y); y += 25
        if store.recent.isEmpty { header("完成后，任务会出现在这里", y: y); y += 29 }
        for value in store.recent {
            add(source: value.source, session: value.session, project: value.project,
                detail: value.summary, stamp: "", completed: value.time)
        }
        document.frame.size = NSSize(width: scroll.contentSize.width, height: y + 5)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: min(position.y, max(0, y - scroll.contentSize.height))))
        scroll.reflectScrolledClipView(scroll.contentView)
    }
}

final class IslandController {
    let panel: IslandPanel
    let view = IslandView(frame: .zero)
    private(set) var expanded = false
    private var screenNumber: NSNumber?
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
            if self.expanded { self.setExpanded(false) } else { self.show() }
            self.suppressHoverUntil = Date().addingTimeInterval(0.6)
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
        place(); view.needsDisplay = true
    }
    private func mouseScreen() -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
    }
    private func place() {
        guard let screen = mouseScreen() else { return }
        screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        let notch = screen.safeAreaInsets.top
        let gap = max(0, (screen.auxiliaryTopRightArea?.minX ?? 0) - (screen.auxiliaryTopLeftArea?.maxX ?? 0))
        view.notch = notch; view.notchWidth = notch > 0 ? max(185, gap) : 0
        let compactWidth = max(148, min(360, (view.status as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 12, weight: .medium)]).width + 50))
        let width: CGFloat = expanded ? min(460, screen.frame.width - 32) : (notch > 0 ? view.notchWidth + 108 : compactWidth)
        let height: CGFloat = expanded ? min(max(230, min(480, view.document.frame.height + 104)) + notch, screen.visibleFrame.height - 24) : max(34, notch)
        let top = notch > 0 ? screen.frame.maxY : min(screen.visibleFrame.maxY, screen.frame.maxY - 24) - 7
        let frame = NSRect(x: screen.frame.midX - width / 2, y: top - height, width: width, height: height)
        if panel.frame != frame { panel.setFrame(frame, display: true); view.needsLayout = true }
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
        } else if Date() > pinnedUntil {
            if outsideSince == nil { outsideSince = Date() }
            if Date().timeIntervalSince(outsideSince!) > 0.35 { setExpanded(false) }
        }
    }
    func refresh() {
        navigation.refresh()
        view.count = store.running.count
        let current = store.running.values.sorted { $0.start > $1.start }.first
        view.status = current.map { "\(store.running.count) 运行中 · \($0.title)" } ?? "AgentBell · 就绪"
        let sources = Set(store.running.values.map(\.source))
        view.sourceMark = sources.count > 1 ? "双" : (sources.first == "Claude" ? "CL" : "CX")
        view.usage = store.usage?.label() ?? "Codex 用量不可用"
        view.toolTip = view.usage
        view.setAccessibilityLabel("AgentBell · " + view.status + " · " + view.usage)
        view.message = Date() < messageUntil ? transientMessage : (store.problem ?? store.codexProblem)
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
                self.setExpanded(false)
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
