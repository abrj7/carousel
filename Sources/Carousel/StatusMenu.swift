import AppKit
import CarouselCore
import ServiceManagement

/// Menu bar item. Rebuilt every time it opens, so it always reflects current state.
final class StatusMenu: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let settings = Settings.shared
    private var manager: WindowManager { .shared }

    override init() {
        super.init()
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        refreshIcon()
    }

    func refreshIcon() {
        let name = manager.enabled ? "rectangle.split.3x1.fill" : "rectangle.split.3x1"
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "Carousel")
        image?.isTemplate = true
        item.button?.image = image
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let trusted = Accessibility.isTrusted(prompt: false)

        let header = NSMenuItem(title: !trusted ? "Carousel needs Accessibility access" : manager.enabled ? "Carousel is tiling" : "Carousel is paused",
                                action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        if !trusted {
            menu.addItem(action("Grant Accessibility Access…", #selector(openAccessibility)))
        }
        menu.addItem(action(manager.enabled ? "Pause Tiling" : "Resume Tiling", #selector(toggleEnabled)))
        menu.addItem(action("Retile Now", #selector(retile)))
        menu.addItem(.separator())

        menu.addItem(toggle("Focus Border", settings.focusBorder, #selector(toggleBorder)))
        menu.addItem(toggle("Dim Inactive Windows", settings.dimInactive, #selector(toggleDim)))
        menu.addItem(toggle("Strip Indicator", settings.showIndicator, #selector(toggleIndicator)))
        menu.addItem(toggle("Animations", settings.animate, #selector(toggleAnimate)))

        let centre = NSMenu()
        for (mode, title) in [(CentreMode.never, "Never"), (.onOverflow, "When Strip Overflows"), (.always, "Always")] {
            let mi = toggle(title, settings.centreMode == mode, #selector(setCentreMode(_:)))
            mi.representedObject = mode.rawValue
            centre.addItem(mi)
        }
        menu.addItem(submenu("Centre Focused Column", centre))

        let gaps = NSMenu()
        for g in [0.0, 4, 8, 12, 16, 24] {
            let mi = toggle("\(Int(g)) pt", settings.gap == g, #selector(setGap(_:)))
            mi.representedObject = g
            gaps.addItem(mi)
        }
        menu.addItem(submenu("Gaps", gaps))
        menu.addItem(.separator())

        menu.addItem(toggle("Launch at Login", SMAppService.mainApp.status == .enabled, #selector(toggleLogin)))
        menu.addItem(action("Keyboard Shortcuts…", #selector(showShortcuts)))
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Carousel", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    private func action(_ title: String, _ sel: Selector) -> NSMenuItem {
        let mi = NSMenuItem(title: title, action: sel, keyEquivalent: "")
        mi.target = self
        return mi
    }

    private func toggle(_ title: String, _ on: Bool, _ sel: Selector) -> NSMenuItem {
        let mi = action(title, sel)
        mi.state = on ? .on : .off
        return mi
    }

    private func submenu(_ title: String, _ sub: NSMenu) -> NSMenuItem {
        let mi = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        mi.submenu = sub
        return mi
    }

    @objc private func openAccessibility() { Accessibility.openSettings() }
    @objc private func toggleEnabled() { manager.perform(.toggleEnabled) }
    @objc private func retile() { manager.perform(.retile) }

    @objc private func toggleBorder() { settings.focusBorder.toggle(); manager.updateOverlays() }
    @objc private func toggleDim() { settings.dimInactive.toggle(); manager.updateOverlays() }
    @objc private func toggleIndicator() { settings.showIndicator.toggle() }
    @objc private func toggleAnimate() { settings.animate.toggle() }

    @objc private func setCentreMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let mode = CentreMode(rawValue: raw) else { return }
        settings.centreMode = mode
        manager.relayout()
    }

    @objc private func setGap(_ sender: NSMenuItem) {
        guard let g = sender.representedObject as? Double else { return }
        settings.gap = g
        manager.relayout()
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("Carousel: launch at login failed: \(error)")
        }
    }

    @objc private func showShortcuts() {
        var seen = Set<String>()
        var lines: [String] = []
        var digitsShown = false
        for b in Keymap.defaults {
            if case .focusIndex = b.command {
                if !digitsShown { lines.append("⌃⌥1 … 9\tJump to window 1–9") }
                digitsShown = true
                continue
            }
            let label = b.label
            if seen.contains(label) {
                if let i = lines.firstIndex(where: { $0.hasSuffix("\t" + label) }) {
                    lines[i] = lines[i].replacingOccurrences(of: "\t", with: " / \(Keymap.describe(b))\t")
                }
                continue
            }
            seen.insert(label)
            lines.append("\(Keymap.describe(b))\t\(label)")
        }
        lines.append("⌃⌥ + scroll\tScroll the strip")
        let alert = NSAlert()
        alert.messageText = "Keyboard Shortcuts"
        alert.informativeText = lines.joined(separator: "\n")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
