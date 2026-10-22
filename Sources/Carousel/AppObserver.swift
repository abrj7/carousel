import AppKit
import ApplicationServices

/// Subscribes to one app's Accessibility notifications (window created/destroyed/moved,
/// focus changes) and forwards them to the window manager on the main run loop.
final class AppObserver {
    let pid: pid_t
    private let app: AXUIElement
    private let observer: AXObserver
    private let refcon: UnsafeMutableRawPointer

    private static let appNotifications = [
        kAXWindowCreatedNotification,
        kAXFocusedWindowChangedNotification,
        kAXMainWindowChangedNotification,
    ]

    private static let windowNotifications = [
        kAXUIElementDestroyedNotification,
        kAXWindowMiniaturizedNotification,
        kAXWindowDeminiaturizedNotification,
        kAXWindowMovedNotification,
        kAXWindowResizedNotification,
    ]

    init?(pid: pid_t, manager: WindowManager) {
        var created: AXObserver?
        guard AXObserverCreate(pid, axCallback, &created) == .success, let created else { return nil }
        self.pid = pid
        app = AXUIElementCreateApplication(pid)
        observer = created
        refcon = Unmanaged.passUnretained(manager).toOpaque()
        var ok = false
        for n in Self.appNotifications {
            ok = AXObserverAddNotification(observer, app, n as CFString, refcon) == .success || ok
        }
        // Apps that are still launching refuse; the manager retries on its next reconcile.
        guard ok else { return nil }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
    }

    func watch(_ window: AXUIElement) {
        for n in Self.windowNotifications {
            AXObserverAddNotification(observer, window, n as CFString, refcon)
        }
    }

    deinit {
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
    }
}

private func axCallback(_ observer: AXObserver, _ element: AXUIElement, _ notification: CFString, _ refcon: UnsafeMutableRawPointer?) {
    guard let refcon else { return }
    let manager = Unmanaged<WindowManager>.fromOpaque(refcon).takeUnretainedValue()
    manager.handle(notification as String, element: element)
}
