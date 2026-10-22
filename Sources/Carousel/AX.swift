import AppKit
import ApplicationServices

// Private but stable for a decade; every macOS window manager uses these.
@_silgen_name("_AXUIElementGetWindow")
@discardableResult
func _AXUIElementGetWindow(_ element: AXUIElement, _ id: UnsafeMutablePointer<CGWindowID>) -> AXError

@_silgen_name("CGSMainConnectionID")
func CGSMainConnectionID() -> Int32

@_silgen_name("CGSGetActiveSpace")
func CGSGetActiveSpace(_ cid: Int32) -> UInt64

@_silgen_name("CGSManagedDisplayGetCurrentSpace")
func CGSManagedDisplayGetCurrentSpace(_ cid: Int32, _ displayUUID: CFString) -> UInt64

enum Accessibility {
    static func isTrusted(prompt: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: prompt] as CFDictionary)
    }

    static func openSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
}

extension AXUIElement {
    func attribute<T>(_ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, name as CFString, &value) == .success else { return nil }
        return value as? T
    }

    func element(_ name: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, name as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private func axValue(_ name: String) -> AXValue? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, name as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        return (value as! AXValue)
    }

    @discardableResult
    func set(_ name: String, _ value: CFTypeRef) -> Bool {
        AXUIElementSetAttributeValue(self, name as CFString, value) == .success
    }

    func isSettable(_ name: String) -> Bool {
        var settable: DarwinBoolean = false
        return AXUIElementIsAttributeSettable(self, name as CFString, &settable) == .success && settable.boolValue
    }

    var windowID: CGWindowID? {
        var id: CGWindowID = 0
        return _AXUIElementGetWindow(self, &id) == .success && id != 0 ? id : nil
    }

    var pid: pid_t? {
        var pid: pid_t = 0
        return AXUIElementGetPid(self, &pid) == .success ? pid : nil
    }

    var position: CGPoint? {
        guard let v = axValue(kAXPositionAttribute) else { return nil }
        var p = CGPoint.zero
        return AXValueGetValue(v, .cgPoint, &p) ? p : nil
    }

    var size: CGSize? {
        guard let v = axValue(kAXSizeAttribute) else { return nil }
        var s = CGSize.zero
        return AXValueGetValue(v, .cgSize, &s) ? s : nil
    }

    func setPosition(_ point: CGPoint) {
        var p = point
        if let v = AXValueCreate(.cgPoint, &p) { set(kAXPositionAttribute, v) }
    }

    func setSize(_ size: CGSize) {
        var s = size
        if let v = AXValueCreate(.cgSize, &s) { set(kAXSizeAttribute, v) }
    }
}

/// A window belonging to another app, controlled through the Accessibility API.
final class Window {
    let id: CGWindowID
    let element: AXUIElement
    let pid: pid_t

    init(id: CGWindowID, element: AXUIElement, pid: pid_t) {
        self.id = id
        self.element = element
        self.pid = pid
    }

    var frame: CGRect? {
        guard let p = element.position, let s = element.size else { return nil }
        return CGRect(origin: p, size: s)
    }

    func setPosition(_ p: CGPoint) { element.setPosition(p) }
    func setSize(_ s: CGSize) { element.setSize(s) }

    /// Position, size, position: the second move fixes apps that clamp size against the old origin.
    func setFrame(_ r: CGRect) {
        element.setPosition(r.origin)
        element.setSize(r.size)
        element.setPosition(r.origin)
    }

    func focus() {
        let app = AXUIElementCreateApplication(pid)
        app.set(kAXFrontmostAttribute, kCFBooleanTrue)
        element.set(kAXMainAttribute, kCFBooleanTrue)
        AXUIElementPerformAction(element, kAXRaiseAction as CFString)
        if let running = NSRunningApplication(processIdentifier: pid) {
            if #available(macOS 14, *) { running.activate() } else { running.activate(options: []) }
        }
    }

    var appIcon: NSImage? { NSRunningApplication(processIdentifier: pid)?.icon }

    /// Normal, resizable document windows tile. Dialogs, sheets, panels, fixed-size windows
    /// (Calculator), minimized and native-fullscreen windows float.
    static func isManageable(_ el: AXUIElement) -> Bool {
        guard el.attribute(kAXRoleAttribute) as String? == kAXWindowRole,
              el.attribute(kAXSubroleAttribute) as String? == kAXStandardWindowSubrole else { return false }
        if el.attribute(kAXMinimizedAttribute) as Bool? == true { return false }
        if el.attribute("AXFullScreen") as Bool? == true { return false }
        guard el.isSettable(kAXPositionAttribute), el.isSettable(kAXSizeAttribute) else { return false }
        if let zoom = el.element(kAXZoomButtonAttribute), zoom.attribute(kAXEnabledAttribute) as Bool? == false {
            return false
        }
        if let s = el.size, s.width < 120 || s.height < 80 { return false }
        return true
    }
}

/// All window numbers the window server knows about, on any Space.
func existingWindowIDs() -> Set<CGWindowID> {
    guard let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] else { return [] }
    return Set(list.compactMap { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value })
}
