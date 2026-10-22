import AppKit

/// Intercepts scroll events while ⌃⌥ is held and turns them into strip scrolling.
///
/// A gesture that starts with the modifiers held stays ours through its momentum phase,
/// even if the keys are released mid-flick, so the app under the cursor never sees half of it.
final class ScrollTap {
    /// Receives a horizontal delta in points. Return true if the event was used.
    var onScroll: ((Double) -> Bool)?

    private var tap: CFMachPort?
    private var gestureIsOurs = false

    func start() {
        guard tap == nil else { return }
        let mask = CGEventMask(1 << CGEventType.scrollWheel.rawValue)
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                eventsOfInterest: mask, callback: { _, type, event, refcon in
            let me = Unmanaged<ScrollTap>.fromOpaque(refcon!).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = me.tap { CGEvent.tapEnable(tap: tap, enable: true) }
                return Unmanaged.passUnretained(event)
            }
            return me.handle(event) ? nil : Unmanaged.passUnretained(event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque())
        guard let tap else { NSLog("Carousel: could not create scroll event tap"); return }
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func handle(_ event: CGEvent) -> Bool {
        let flags = event.flags
        let held = flags.contains(.maskControl) && flags.contains(.maskAlternate)
        let phase = event.getIntegerValueField(.scrollWheelEventScrollPhase)
        let momentum = event.getIntegerValueField(.scrollWheelEventMomentumPhase)
        let continuous = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0

        // kCGScrollPhaseBegan = 1; discrete mouse wheels report no phase at all.
        if phase == 1 || (phase == 0 && momentum == 0) { gestureIsOurs = held }
        guard gestureIsOurs else { return false }

        let dy = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)
        let dx = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2)
        var delta = abs(dx) > abs(dy) ? dx : dy
        if !continuous { delta *= 4 }
        guard delta != 0 else { return true }
        return onScroll?(delta) ?? false
    }
}
