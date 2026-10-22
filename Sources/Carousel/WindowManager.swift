import AppKit
import CarouselCore

/// One strip per display per Space.
struct StripKey: Hashable {
    let display: CGDirectDisplayID
    let space: UInt64
}

final class WindowManager {
    static let shared = WindowManager()

    private let settings = Settings.shared
    private(set) var enabled = false

    private var windows: [CGWindowID: Window] = [:]
    private var keys: [CGWindowID: StripKey] = [:]
    private var strips: [StripKey: Strip] = [:]
    private var floating = Set<CGWindowID>()
    private var observers: [pid_t: AppObserver] = [:]

    private let animator = Animator()
    private let overlays = OverlayController()
    private let indicator = StripIndicator()

    private var tokens: [NSObjectProtocol] = []
    private var safetyTimer: Timer?
    private var snapTimer: Timer?
    private var settleTimer: Timer?
    private let ownPID = ProcessInfo.processInfo.processIdentifier

    /// Fired when enabled state changes, so the menu bar icon can update.
    var onStateChange: (() -> Void)?

    private init() {
        animator.onFrame = { [weak self] in self?.updateOverlays() }
        animator.onConstrained = { [weak self] id, actual in self?.adoptActualWidth(id, actual) }
        indicator.onSelect = { [weak self] key, index in self?.jump(key, to: index) }
        indicator.onReorder = { [weak self] key, from, to in self?.reorder(key, from: from, to: to) }
    }

    // MARK: Lifecycle

    func start() {
        guard !enabled else { return }
        enabled = true
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.5)

        let ws = NSWorkspace.shared.notificationCenter
        func on(_ name: Notification.Name, _ center: NotificationCenter = ws, _ block: @escaping (NSRunningApplication?) -> Void) {
            tokens.append(center.addObserver(forName: name, object: nil, queue: .main) { n in
                block(n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)
            })
        }
        on(NSWorkspace.didLaunchApplicationNotification) { [weak self] app in
            guard let app else { return }
            self?.track(app)
            // Launching apps open their first window a beat later.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self?.reconcile(pid: app.processIdentifier); self?.relayout() }
        }
        on(NSWorkspace.didTerminateApplicationNotification) { [weak self] app in
            if let pid = app?.processIdentifier { self?.untrack(pid) }
        }
        on(NSWorkspace.didActivateApplicationNotification) { [weak self] app in
            if let pid = app?.processIdentifier { self?.focusChanged(pid: pid) }
        }
        on(NSWorkspace.didHideApplicationNotification) { [weak self] app in
            guard let self, let pid = app?.processIdentifier else { return }
            for (id, w) in windows where w.pid == pid { forget(id) }
            relayout()
        }
        on(NSWorkspace.didUnhideApplicationNotification) { [weak self] app in
            if let pid = app?.processIdentifier { self?.reconcile(pid: pid); self?.relayout() }
        }
        on(NSWorkspace.activeSpaceDidChangeNotification) { [weak self] _ in
            self?.reconcileAll()
            self?.relayout(animated: false)
        }
        on(NSWorkspace.didWakeNotification) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self?.reconcileAll(); self?.relayout(animated: false) }
        }
        on(NSApplication.didChangeScreenParametersNotification, .default) { [weak self] _ in
            self?.displaysChanged()
        }

        for app in NSWorkspace.shared.runningApplications { track(app) }
        reconcileAll(initial: true)
        if let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier { focusChanged(pid: pid) }
        relayout(animated: false)

        // Some apps never send window-created notifications. Catch them eventually.
        safetyTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            guard let self, !animator.isAnimating else { return }
            let before = strips
            reconcileAll()
            if strips != before { relayout() }
        }
        onStateChange?()
    }

    func stop() {
        guard enabled else { return }
        releaseAll()
        enabled = false
        for t in tokens {
            NSWorkspace.shared.notificationCenter.removeObserver(t)
            NotificationCenter.default.removeObserver(t)
        }
        tokens.removeAll()
        safetyTimer?.invalidate()
        observers.removeAll()
        windows.removeAll()
        keys.removeAll()
        strips.removeAll()
        floating.removeAll()
        overlays.render(border: nil, dims: [])
        indicator.hide()
        onStateChange?()
    }

    /// Pulls every parked window back on screen, so quitting never strands a window off the edge.
    func releaseAll() {
        guard enabled else { return }
        for (id, w) in windows {
            guard let f = w.frame, let key = keys[id], let screen = Screens.screen(for: key.display) else { continue }
            let vp = screen.axVisibleFrame
            if vp.intersection(f).width >= min(f.width, vp.width) * 0.9 { continue }
            var nf = f
            nf.size.width = min(f.width, vp.width)
            nf.origin.x = min(max(f.minX, vp.minX), vp.maxX - nf.width)
            nf.origin.y = min(max(f.minY, vp.minY), vp.maxY - min(f.height, vp.height))
            w.setFrame(nf)
        }
    }

    // MARK: Tracking apps and windows

    private func track(_ app: NSRunningApplication) {
        let pid = app.processIdentifier
        guard enabled, pid != ownPID, app.activationPolicy == .regular, observers[pid] == nil else { return }
        if let observer = AppObserver(pid: pid, manager: self) {
            observers[pid] = observer
            for w in windows.values where w.pid == pid { observer.watch(w.element) }
        }
    }

    private func untrack(_ pid: pid_t) {
        observers[pid] = nil
        for (id, w) in windows where w.pid == pid { forget(id) }
        relayout()
    }

    private func reconcileAll(initial: Bool = false) {
        var found: [Window] = []
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            found += reconcile(pid: app.processIdentifier, adopt: !initial)
        }
        // On first start, keep whatever left-to-right order the user already had.
        for w in found.sorted(by: { ($0.frame?.minX ?? 0) < ($1.frame?.minX ?? 0) }) {
            adopt(w, atEnd: true)
        }
    }

    /// Syncs our model with what an app actually has open. Returns new windows if `adopt` is false.
    @discardableResult
    private func reconcile(pid: pid_t, adopt shouldAdopt: Bool = true) -> [Window] {
        guard enabled, pid != ownPID, let app = NSRunningApplication(processIdentifier: pid),
              app.activationPolicy == .regular else { return [] }
        if observers[pid] == nil { track(app) }

        let elements: [AXUIElement] = AXUIElementCreateApplication(pid).attribute(kAXWindowsAttribute) ?? []
        var seen = Set<CGWindowID>()
        var fresh: [Window] = []
        for el in elements {
            guard let id = el.windowID else { continue }
            seen.insert(id)
            let manageable = Window.isManageable(el)
            if windows[id] != nil {
                if !manageable { forget(id) } // minimized or went native-fullscreen
                continue
            }
            guard manageable, !floating.contains(id), !app.isHidden else { continue }
            let w = Window(id: id, element: el, pid: pid)
            if shouldAdopt { adopt(w) } else { fresh.append(w) }
        }
        // Windows missing from AX may just be on another Space; only drop ones that are truly gone.
        let missing = windows.filter { $0.value.pid == pid && !seen.contains($0.key) }
        if !missing.isEmpty {
            let alive = existingWindowIDs()
            for id in missing.keys where !alive.contains(id) { forget(id) }
        }
        return fresh
    }

    private func adopt(_ w: Window, atEnd: Bool = false) {
        guard let frame = w.frame, let screen = Screens.screen(containing: frame) else { return }
        let key = StripKey(display: screen.displayID, space: Screens.currentSpace(screen.displayID))
        let vw = Double(screen.axVisibleFrame.width)
        // Keep the window's own width: opening a window should never squash the others.
        let fraction = min(max(Strip.fraction(forPixelWidth: frame.width, viewportWidth: vw, gap: settings.gap), 0.2), 1)
        windows[w.id] = w
        keys[w.id] = key
        var strip = strips[key] ?? Strip()
        strip.insert(w.id, width: fraction, at: atEnd ? strip.columns.count : nil)
        strips[key] = strip
        observers[w.pid]?.watch(w.element)
        animator.setCurrent(w.id, frame)
    }

    private func forget(_ id: CGWindowID) {
        if let key = keys[id] {
            strips[key]?.remove(id)
            if strips[key]?.isEmpty == true { strips[key] = nil }
        }
        windows[id] = nil
        keys[id] = nil
        animator.forget(id)
    }

    private func window(for element: AXUIElement) -> Window? {
        if let id = element.windowID, let w = windows[id] { return w }
        return windows.values.first { CFEqual($0.element, element) }
    }

    // MARK: Accessibility notifications

    func handle(_ notification: String, element: AXUIElement) {
        guard enabled else { return }
        switch notification {
        case kAXWindowCreatedNotification:
            guard let pid = element.pid else { return }
            // Give the app a moment to finish setting the window up (subrole, size).
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.reconcile(pid: pid)
                self?.relayout()
            }
        case kAXUIElementDestroyedNotification, kAXWindowMiniaturizedNotification:
            if let w = window(for: element) {
                forget(w.id)
                floating.remove(w.id)
                relayout()
            } else if let id = element.windowID {
                floating.remove(id)
            }
        case kAXWindowDeminiaturizedNotification:
            if let pid = element.pid { reconcile(pid: pid); relayout() }
        case kAXFocusedWindowChangedNotification, kAXMainWindowChangedNotification:
            if let pid = element.pid { focusChanged(pid: pid) }
        case kAXWindowMovedNotification, kAXWindowResizedNotification:
            if let w = window(for: element) { windowChangedByUser(w) }
        default:
            break
        }
    }

    private func focusChanged(pid: pid_t) {
        guard enabled, pid != ownPID else { return }
        guard let el = AXUIElementCreateApplication(pid).element(kAXFocusedWindowAttribute),
              let id = el.windowID else { updateOverlays(); return }
        if windows[id] == nil && !floating.contains(id) { reconcile(pid: pid) }
        guard let key = keys[id], var strip = strips[key], let screen = Screens.screen(for: key.display) else {
            updateOverlays()
            return
        }
        let before = strip
        strip.focus(id)
        strip.scrollToFocused(viewportWidth: Double(screen.axVisibleFrame.width), gap: settings.gap, mode: settings.centreMode)
        strips[key] = strip
        if strip != before {
            relayout()
            showIndicator(key)
        } else {
            updateOverlays()
        }
    }

    /// The user dragged or resized a window by hand. Widths are adopted; positions snap back.
    private func windowChangedByUser(_ w: Window) {
        guard !animator.isAnimating, let actual = w.frame, let expected = animator.current[w.id] else { return }
        guard abs(actual.minX - expected.minX) > 2 || abs(actual.minY - expected.minY) > 2
            || abs(actual.width - expected.width) > 2 || abs(actual.height - expected.height) > 2 else { return }
        animator.setCurrent(w.id, actual)
        if abs(actual.width - expected.width) > 2, let key = keys[w.id], let screen = Screens.screen(for: key.display) {
            let vw = Double(screen.axVisibleFrame.width)
            strips[key]?.setWidth(of: w.id, to: Strip.fraction(forPixelWidth: actual.width, viewportWidth: vw, gap: settings.gap))
        }
        // Wait for the drag to finish before putting things back in order.
        settleTimer?.invalidate()
        settleTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self] _ in self?.relayout() }
    }

    private func adoptActualWidth(_ id: CGWindowID, _ actual: CGRect) {
        guard let key = keys[id], let screen = Screens.screen(for: key.display),
              let col = strips[key]?.columns.first(where: { $0.windows.contains(id) }) else { return }
        let vw = Double(screen.axVisibleFrame.width)
        let fraction = Strip.fraction(forPixelWidth: actual.width, viewportWidth: vw, gap: settings.gap)
        guard abs(fraction - col.width) > 0.01 else { return }
        strips[key]?.setWidth(of: id, to: fraction)
        relayout()
    }

    private func displaysChanged() {
        // Windows whose display vanished get re-homed on whatever screen they now sit on.
        let live = Set(NSScreen.screens.map(\.displayID))
        for (id, key) in keys where !live.contains(key.display) {
            guard let w = windows[id] else { continue }
            forget(id)
            adopt(w)
        }
        relayout(animated: false)
    }

    // MARK: Layout

    func relayout(animated: Bool = true) {
        guard enabled else { return }
        var targets: [CGWindowID: (Window, CGRect)] = [:]
        for screen in NSScreen.screens {
            let key = currentKey(screen)
            guard let strip = strips[key] else { continue }
            let vp = screen.axVisibleFrame
            for (id, frame) in strip.frames(in: vp, gap: settings.gap) {
                guard let w = windows[id] else { continue }
                var (f, side) = park(frame, in: vp)
                // If another display sits on that side, also drop the window below the screen
                // so the parked body doesn't show up on the neighbour.
                if side != .none, screen.hasNeighbour(onRight: side == .right) {
                    f.origin.y = screen.axFrame.maxY - 1
                }
                targets[id] = (w, f)
            }
        }
        animator.animate(targets, duration: animated && settings.animate ? settings.animationDuration : 0)
    }

    private func currentKey(_ screen: NSScreen) -> StripKey {
        StripKey(display: screen.displayID, space: Screens.currentSpace(screen.displayID))
    }

    /// The strip the user is working in: the focused window's, else the one under the mouse.
    private func activeKey() -> StripKey? {
        if let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
           let id = AXUIElementCreateApplication(pid).element(kAXFocusedWindowAttribute)?.windowID,
           let key = keys[id] {
            return key
        }
        return Screens.underMouse.map(currentKey)
    }

    // MARK: Overlays

    func updateOverlays() {
        guard enabled else { return }
        // Runs on every animation frame; skip the AX focus lookup when nothing is drawn.
        guard settings.focusBorder || settings.dimInactive else {
            overlays.render(border: nil, dims: [])
            return
        }
        let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let focusedID = activeKey().flatMap { strips[$0]?.focusedWindow }
        var border: CGRect?
        var dims: [CGRect] = []
        for screen in NSScreen.screens {
            guard let strip = strips[currentKey(screen)] else { continue }
            let vp = screen.axVisibleFrame
            for id in strip.windows {
                guard let f = animator.current[id], f.intersects(vp.insetBy(dx: 2, dy: 2)) else { continue }
                if id == focusedID && windows[id]?.pid == frontPID {
                    border = f
                } else {
                    dims.append(f.intersection(screen.axFrame))
                }
            }
        }
        overlays.render(border: settings.focusBorder ? border : nil, dims: settings.dimInactive ? dims : [])
    }

    private func showIndicator(_ key: StripKey) {
        guard settings.showIndicator, let strip = strips[key], let screen = Screens.screen(for: key.display) else { return }
        let vw = Double(screen.axVisibleFrame.width)
        let gap = settings.gap
        let total = strip.totalWidth(viewportWidth: vw, gap: gap)
        let tiles = strip.columns.enumerated().map { i, col in
            StripIndicator.Tile(icon: windows[col.focusedWindow]?.appIcon, width: col.width,
                                focused: i == strip.focusedColumn, stacked: col.windows.count)
        }
        let start = total > 0 ? strip.offset / total : 0
        let end = total > 0 ? (strip.offset + vw) / total : 1
        indicator.show(key: key, tiles: tiles, viewport: start...max(start, end), on: screen)
    }

    // MARK: Commands

    func perform(_ command: Command) {
        switch command {
        case .toggleEnabled:
            enabled ? stop() : start()
            return
        case .retile:
            guard enabled else { return }
            reconcileAll()
            relayout()
            return
        case .toggleFloat:
            toggleFloat()
            return
        case .sendToNextDisplay:
            sendToNextDisplay()
            return
        default:
            break
        }
        guard enabled, let key = activeKey(), var strip = strips[key], !strip.isEmpty,
              let screen = Screens.screen(for: key.display) else { return }
        let vw = Double(screen.axVisibleFrame.width)
        let gap = settings.gap
        var scroll = true

        switch command {
        case .focusLeft: strip.focusLeft()
        case .focusRight: strip.focusRight()
        case .focusUp: strip.focusUp()
        case .focusDown: strip.focusDown()
        case .focusFirst: strip.focusFirst()
        case .focusLast: strip.focusLast()
        case .focusIndex(let i): strip.focusColumn(i)
        case .moveLeft: strip.moveLeft()
        case .moveRight: strip.moveRight()
        case .moveUp: strip.moveUp()
        case .moveDown: strip.moveDown()
        case .cycleWidth: strip.cycleWidth(presets: settings.widthPresets)
        case .fullWidth: strip.toggleFullWidth()
        case .centre: strip.centreFocused(viewportWidth: vw, gap: gap); scroll = false
        case .wider: strip.resizeWidth(by: 0.1)
        case .narrower: strip.resizeWidth(by: -0.1)
        case .taller: strip.resizeHeight(by: 0.1)
        case .shorter: strip.resizeHeight(by: -0.1)
        case .equalizeHeights: strip.equalizeHeights()
        case .stackLeft: strip.stack(direction: -1)
        case .stackRight: strip.stack(direction: 1)
        case .popOutLeft: strip.popOut(direction: -1)
        case .popOutRight: strip.popOut(direction: 1)
        case .toggleEnabled, .retile, .toggleFloat, .sendToNextDisplay: break
        }
        if scroll { strip.scrollToFocused(viewportWidth: vw, gap: gap, mode: settings.centreMode) }
        strips[key] = strip
        relayout()
        if let id = strip.focusedWindow { windows[id]?.focus() }
        showIndicator(key)
    }

    private func jump(_ key: StripKey, to index: Int) {
        guard var strip = strips[key], let screen = Screens.screen(for: key.display) else { return }
        strip.focusColumn(index)
        strip.scrollToFocused(viewportWidth: Double(screen.axVisibleFrame.width), gap: settings.gap, mode: settings.centreMode)
        strips[key] = strip
        relayout()
        if let id = strip.focusedWindow { windows[id]?.focus() }
        showIndicator(key)
    }

    private func reorder(_ key: StripKey, from: Int, to: Int) {
        guard var strip = strips[key], let screen = Screens.screen(for: key.display) else { return }
        strip.reorder(from: from, to: to)
        strip.scrollToFocused(viewportWidth: Double(screen.axVisibleFrame.width), gap: settings.gap, mode: settings.centreMode)
        strips[key] = strip
        relayout()
        showIndicator(key)
    }

    private func focusedElement() -> (AXUIElement, CGWindowID, pid_t)? {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              let el = AXUIElementCreateApplication(pid).element(kAXFocusedWindowAttribute),
              let id = el.windowID else { return nil }
        return (el, id, pid)
    }

    private func toggleFloat() {
        guard enabled, let (el, id, pid) = focusedElement() else { return }
        if windows[id] != nil {
            forget(id)
            floating.insert(id)
            // Bring it back into the middle of the screen at a sensible size.
            let w = Window(id: id, element: el, pid: pid)
            if let screen = Screens.underMouse, let f = w.frame {
                let vp = screen.axVisibleFrame
                let size = CGSize(width: min(f.width, vp.width * 0.6), height: min(f.height, vp.height * 0.7))
                w.setFrame(CGRect(x: vp.midX - size.width / 2, y: vp.midY - size.height / 2, width: size.width, height: size.height))
            }
        } else {
            floating.remove(id)
            guard Window.isManageable(el) else { return }
            let w = Window(id: id, element: el, pid: pid)
            adopt(w)
            if let key = keys[id] { strips[key]?.focus(id) }
        }
        relayout()
    }

    private func sendToNextDisplay() {
        let screens = NSScreen.screens.sorted { $0.frame.minX < $1.frame.minX }
        guard enabled, screens.count > 1, let (_, id, _) = focusedElement(), let w = windows[id], let key = keys[id],
              let i = screens.firstIndex(where: { $0.displayID == key.display }) else { return }
        let target = screens[(i + 1) % screens.count]
        let targetKey = currentKey(target)
        let width = strips[key]?.columns.first { $0.windows.contains(id) }?.width ?? 0.5
        forget(id)
        windows[id] = w
        keys[id] = targetKey
        var strip = strips[targetKey] ?? Strip()
        strip.insert(id, width: width)
        strip.focus(id)
        strip.scrollToFocused(viewportWidth: Double(target.axVisibleFrame.width), gap: settings.gap, mode: settings.centreMode)
        strips[targetKey] = strip
        if let frame = w.frame { animator.setCurrent(id, frame) }
        relayout()
        w.focus()
        showIndicator(targetKey)
    }

    // MARK: Trackpad / wheel scrolling

    /// Scrolls the strip under the mouse by `delta` points. Settles onto a column when it stops.
    func scroll(by delta: Double) -> Bool {
        guard enabled, let screen = Screens.underMouse else { return false }
        let key = currentKey(screen)
        guard var strip = strips[key], !strip.isEmpty else { return false }
        let vw = Double(screen.axVisibleFrame.width)
        let total = strip.totalWidth(viewportWidth: vw, gap: settings.gap)
        strip.offset = min(max(strip.offset - delta * settings.scrollSpeed, -vw * 0.25), max(0, total - vw) + vw * 0.25)
        strips[key] = strip
        relayout(animated: false)
        showIndicator(key)
        snapTimer?.invalidate()
        snapTimer = Timer.scheduledTimer(withTimeInterval: 0.18, repeats: false) { [weak self] _ in self?.settle(key) }
        return true
    }

    private func settle(_ key: StripKey) {
        guard var strip = strips[key], let screen = Screens.screen(for: key.display) else { return }
        let before = strip.focusedWindow
        strip.snap(viewportWidth: Double(screen.axVisibleFrame.width), gap: settings.gap, mode: settings.centreMode)
        strips[key] = strip
        relayout()
        if let id = strip.focusedWindow, id != before { windows[id]?.focus() }
        showIndicator(key)
    }
}
