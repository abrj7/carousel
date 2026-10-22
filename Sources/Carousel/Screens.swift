import AppKit

/// Accessibility uses a flipped coordinate space: origin at the top-left of the main display,
/// y growing downward. AppKit uses bottom-left. These helpers convert between the two.
enum Screens {
    static var primaryHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }

    static func ax(fromCocoa r: CGRect) -> CGRect {
        CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }

    static func cocoa(fromAX r: CGRect) -> CGRect {
        CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }

    static func screen(for display: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first { $0.displayID == display }
    }

    /// The screen a window (AX frame) mostly sits on.
    static func screen(containing axFrame: CGRect) -> NSScreen? {
        NSScreen.screens.max { a, b in
            area(a.axFrame.intersection(axFrame)) < area(b.axFrame.intersection(axFrame))
        }
    }

    static var underMouse: NSScreen? {
        let p = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(p, $0.frame, false) } ?? NSScreen.main
    }

    /// The Space currently shown on a display (each display has its own when
    /// "Displays have separate Spaces" is on, which is the macOS default).
    static func currentSpace(_ display: CGDirectDisplayID) -> UInt64 {
        let cid = CGSMainConnectionID()
        if let uuid = CGDisplayCreateUUIDFromDisplayID(display)?.takeRetainedValue(),
           let string = CFUUIDCreateString(nil, uuid) {
            let space = CGSManagedDisplayGetCurrentSpace(cid, string)
            if space != 0 { return space }
        }
        return CGSGetActiveSpace(cid)
    }

    private static func area(_ r: CGRect) -> CGFloat { r.isNull ? 0 : r.width * r.height }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    var axFrame: CGRect { Screens.ax(fromCocoa: frame) }

    /// Usable area (minus menu bar and Dock) in AX coordinates. This is the strip's viewport.
    var axVisibleFrame: CGRect { Screens.ax(fromCocoa: visibleFrame) }

    /// Whether another display touches this one on the given side.
    func hasNeighbour(onRight right: Bool) -> Bool {
        NSScreen.screens.contains { other in
            guard other != self else { return false }
            let verticalOverlap = other.frame.maxY > frame.minY && other.frame.minY < frame.maxY
            return verticalOverlap && (right ? abs(other.frame.minX - frame.maxX) < 2 : abs(other.frame.maxX - frame.minX) < 2)
        }
    }
}
