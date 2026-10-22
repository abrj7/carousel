import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menu: StatusMenu!
    private let hotkeys = HotkeyCenter()
    private let scrollTap = ScrollTap()
    private var trustTimer: Timer?
    private var signalSources: [DispatchSourceSignal] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        let manager = WindowManager.shared
        menu = StatusMenu()
        manager.onStateChange = { [weak self] in self?.menu.refreshIcon() }

        for binding in Keymap.defaults {
            let command = binding.command
            if !hotkeys.register(key: binding.key, mods: binding.mods, { manager.perform(command) }) {
                NSLog("Carousel: \(Keymap.describe(binding)) is taken by another app")
            }
        }
        scrollTap.onScroll = { manager.scroll(by: $0) }
        installSignalHandlers()

        if Accessibility.isTrusted(prompt: true) {
            begin()
        } else {
            // Wait for the user to flip the switch in System Settings, then start on our own.
            trustTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
                guard Accessibility.isTrusted(prompt: false) else { return }
                timer.invalidate()
                self?.begin()
            }
        }
    }

    private func begin() {
        WindowManager.shared.start()
        scrollTap.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        WindowManager.shared.releaseAll()
    }

    /// `kill`/Ctrl-C during development should also put parked windows back on screen.
    private func installSignalHandlers() {
        for sig in [SIGINT, SIGTERM] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler {
                WindowManager.shared.releaseAll()
                exit(0)
            }
            source.resume()
            signalSources.append(source)
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
