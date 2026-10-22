import AppKit

/// A transparent, click-through window that floats above normal windows on every Space.
final class OverlayPanel: NSPanel {
    init(level: NSWindow.Level = .floating) {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        self.level = level
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        isReleasedWhenClosed = false
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Draws the focus border and the dimming over inactive windows. Tiled windows never overlap,
/// so plain floating-level overlays sit on exactly the window they belong to.
final class OverlayController {
    private let border = OverlayPanel()
    private var dims: [OverlayPanel] = []
    private let radius: CGFloat = 12
    private let borderWidth: CGFloat = 3

    init() {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.borderColor = NSColor.systemOrange.cgColor
        view.layer?.borderWidth = borderWidth
        view.layer?.cornerRadius = radius + borderWidth
        border.contentView = view
    }

    /// Both rects are AX (top-left origin) frames of the windows themselves.
    func render(border rect: CGRect?, dims rects: [CGRect]) {
        while dims.count < rects.count {
            let panel = OverlayPanel()
            let view = NSView()
            view.wantsLayer = true
            view.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.28).cgColor
            view.layer?.cornerRadius = radius
            panel.contentView = view
            dims.append(panel)
        }
        for (i, panel) in dims.enumerated() {
            if i < rects.count {
                panel.setFrame(Screens.cocoa(fromAX: rects[i]), display: false)
                panel.orderFrontRegardless()
            } else {
                panel.orderOut(nil)
            }
        }
        if let rect {
            let outer = rect.insetBy(dx: -borderWidth, dy: -borderWidth)
            border.setFrame(Screens.cocoa(fromAX: outer), display: true)
            border.orderFrontRegardless()
        } else {
            border.orderOut(nil)
        }
    }
}

/// The frosted HUD at the bottom of the screen: one tile per column, sized by width, with the
/// visible part of the strip outlined. Click a tile to jump to it, drag to reorder.
final class StripIndicator {
    struct Tile {
        let icon: NSImage?
        let width: Double
        let focused: Bool
        let stacked: Int
    }

    var onSelect: ((StripKey, Int) -> Void)?
    var onReorder: ((StripKey, Int, Int) -> Void)?

    private let panel = OverlayPanel(level: .statusBar)
    private let effect = NSVisualEffectView()
    private let tilesView = TilesView()
    private var key: StripKey?
    private var hideTimer: Timer?

    init() {
        panel.ignoresMouseEvents = false
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 14
        effect.layer?.masksToBounds = true
        effect.addSubview(tilesView)
        panel.contentView = effect
        tilesView.onSelect = { [weak self] i in
            guard let self, let key else { return }
            onSelect?(key, i)
        }
        tilesView.onReorder = { [weak self] from, to in
            guard let self, let key else { return }
            onReorder?(key, from, to)
        }
    }

    func show(key: StripKey, tiles: [Tile], viewport: ClosedRange<Double>, on screen: NSScreen) {
        self.key = key
        tilesView.tiles = tiles
        tilesView.viewport = viewport
        let size = tilesView.preferredSize
        tilesView.frame = NSRect(x: 10, y: 10, width: size.width, height: size.height)
        let vf = screen.visibleFrame
        let frame = NSRect(x: vf.midX - (size.width + 20) / 2, y: vf.minY + 24, width: size.width + 20, height: size.height + 20)
        panel.setFrame(frame, display: true)
        tilesView.needsDisplay = true
        if !panel.isVisible || panel.alphaValue < 1 {
            panel.alphaValue = 1
            panel.orderFrontRegardless()
        }
        scheduleHide()
    }

    func hide() {
        hideTimer?.invalidate()
        panel.orderOut(nil)
    }

    private func scheduleHide() {
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: false) { [weak self] _ in
            guard let self else { return }
            // Holding ⌃⌥ keeps the indicator up so you can click it.
            let mods = NSEvent.modifierFlags
            if mods.contains(.control) && mods.contains(.option) || tilesView.isDragging {
                scheduleHide()
                return
            }
            let panel = panel
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.25
                panel.animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                if self?.panel.alphaValue == 0 { self?.panel.orderOut(nil) }
            })
        }
    }
}

private final class TilesView: NSView {
    var tiles: [StripIndicator.Tile] = []
    var viewport: ClosedRange<Double> = 0...1
    var onSelect: ((Int) -> Void)?
    var onReorder: ((Int, Int) -> Void)?
    private(set) var isDragging = false
    private var dragFrom: Int?

    private let height: CGFloat = 40
    private let spacing: CGFloat = 4
    private let unit: CGFloat = 120 // points for a full-width column
    private let maxWidth: CGFloat = 640

    private var scale: CGFloat {
        let natural = tiles.reduce(CGFloat(0)) { $0 + max(28, CGFloat($1.width) * unit) } + spacing * CGFloat(max(0, tiles.count - 1))
        return natural > maxWidth ? maxWidth / natural : 1
    }

    var preferredSize: NSSize {
        let w = tiles.reduce(CGFloat(0)) { $0 + max(28, CGFloat($1.width) * unit) } + spacing * CGFloat(max(0, tiles.count - 1))
        return NSSize(width: max(60, w * scale), height: height)
    }

    private func tileRects() -> [NSRect] {
        var x: CGFloat = 0
        return tiles.map { t in
            let w = max(28, CGFloat(t.width) * unit) * scale
            defer { x += w + spacing * scale }
            return NSRect(x: x, y: 0, width: w, height: height)
        }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let rects = tileRects()
        for (t, r) in zip(tiles, rects) {
            let path = NSBezierPath(roundedRect: r.insetBy(dx: 0.5, dy: 3), xRadius: 7, yRadius: 7)
            (t.focused ? NSColor.systemOrange : NSColor.white.withAlphaComponent(0.18)).setFill()
            path.fill()
            let icon = min(24, r.width - 6)
            t.icon?.draw(in: NSRect(x: r.midX - icon / 2, y: r.midY - icon / 2, width: icon, height: icon))
            if t.stacked > 1 {
                let badge = "\(t.stacked)" as NSString
                badge.draw(at: NSPoint(x: r.maxX - 10, y: r.minY + 4),
                           withAttributes: [.font: NSFont.boldSystemFont(ofSize: 9), .foregroundColor: NSColor.white])
            }
        }
        // Outline the part of the strip that's on screen.
        guard let first = rects.first, let last = rects.last else { return }
        let span = last.maxX - first.minX
        let x0 = first.minX + span * CGFloat(viewport.lowerBound)
        let x1 = first.minX + span * CGFloat(viewport.upperBound)
        let outline = NSBezierPath(roundedRect: NSRect(x: x0, y: 1, width: max(8, x1 - x0), height: height - 2), xRadius: 8, yRadius: 8)
        outline.lineWidth = 2
        NSColor.white.withAlphaComponent(0.9).setStroke()
        outline.stroke()
    }

    private func index(at point: NSPoint) -> Int? {
        tileRects().firstIndex { $0.insetBy(dx: -spacing / 2, dy: 0).contains(NSPoint(x: point.x, y: $0.midY)) }
    }

    override func mouseDown(with event: NSEvent) {
        dragFrom = index(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseDragged(with event: NSEvent) {
        isDragging = dragFrom != nil
    }

    override func mouseUp(with event: NSEvent) {
        defer { dragFrom = nil; isDragging = false }
        guard let from = dragFrom else { return }
        let to = index(at: convert(event.locationInWindow, from: nil)) ?? from
        if isDragging && to != from {
            onReorder?(from, to)
        } else {
            onSelect?(from)
        }
    }
}
