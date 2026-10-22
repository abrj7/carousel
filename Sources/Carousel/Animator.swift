import AppKit
import QuartzCore

/// Moves windows to target frames with an ease-out curve.
///
/// Accessibility writes are cross-process and slow-ish (~1ms each), so size is set once up
/// front and only position is interpolated per frame. Apps with AXEnhancedUserInterface on
/// (Chrome, Electron, anything VoiceOver-adjacent) animate AX moves themselves, which looks
/// terrible, so it is switched off for the duration.
final class Animator {
    private struct Track {
        let window: Window
        let from: CGRect
        let to: CGRect
    }

    private var tracks: [CGWindowID: Track] = [:]
    private var startTime: CFTimeInterval = 0
    private var duration: Double = 0.18
    private var timer: Timer?
    private var enhancedUI: [pid_t: AXUIElement] = [:]

    /// Last frame we set (or observed) for each window.
    private(set) var current: [CGWindowID: CGRect] = [:]

    /// Called after every applied frame, for overlays that follow windows.
    var onFrame: (() -> Void)?
    /// Called when an app refused a size we asked for (minimum widths etc).
    var onConstrained: ((CGWindowID, CGRect) -> Void)?

    var isAnimating: Bool { timer != nil }

    func setCurrent(_ id: CGWindowID, _ frame: CGRect?) { current[id] = frame }

    func forget(_ id: CGWindowID) {
        current[id] = nil
        tracks[id] = nil
    }

    func animate(_ targets: [CGWindowID: (Window, CGRect)], duration: Double) {
        var next: [CGWindowID: Track] = [:]
        for (id, (window, to)) in targets {
            let from = current[id] ?? window.frame ?? to
            if from != to { next[id] = Track(window: window, from: from, to: to) }
        }
        tracks = next
        guard !tracks.isEmpty else {
            if !isAnimating { onFrame?() }
            return
        }
        disableEnhancedUI()
        for track in tracks.values where track.from.size != track.to.size {
            track.window.setSize(track.to.size)
        }
        guard duration > 0 else { finish(); return }
        startTime = CACurrentMediaTime()
        self.duration = duration
        if timer == nil {
            let t = Timer(timeInterval: 1.0 / 120, repeats: true) { [weak self] _ in self?.tick() }
            RunLoop.main.add(t, forMode: .common)
            timer = t
        }
    }

    private func tick() {
        let t = min(1, (CACurrentMediaTime() - startTime) / duration)
        guard t < 1 else { finish(); return }
        let e = 1 - pow(1 - t, 3)
        for (id, track) in tracks {
            let x = track.from.minX + (track.to.minX - track.from.minX) * e
            let y = track.from.minY + (track.to.minY - track.from.minY) * e
            let p = CGPoint(x: x.rounded(), y: y.rounded())
            track.window.setPosition(p)
            current[id] = CGRect(origin: p, size: track.to.size)
        }
        onFrame?()
    }

    private func finish() {
        timer?.invalidate()
        timer = nil
        let done = tracks
        tracks.removeAll()
        for (id, track) in done {
            // Position-only moves (scrolling) are the hot path: one AX write per window.
            if track.from.size == track.to.size {
                track.window.setPosition(track.to.origin)
            } else {
                track.window.setFrame(track.to)
            }
            current[id] = track.to
        }
        restoreEnhancedUI()
        for (id, track) in done where track.from.size != track.to.size {
            guard let actual = track.window.frame else { continue }
            if abs(actual.width - track.to.width) > 3 {
                current[id] = actual
                onConstrained?(id, actual)
            }
        }
        onFrame?()
    }

    private func disableEnhancedUI() {
        for pid in Set(tracks.values.map(\.window.pid)) where enhancedUI[pid] == nil {
            let app = AXUIElementCreateApplication(pid)
            if app.attribute("AXEnhancedUserInterface") as Bool? == true {
                app.set("AXEnhancedUserInterface", kCFBooleanFalse)
                enhancedUI[pid] = app
            }
        }
    }

    private func restoreEnhancedUI() {
        for app in enhancedUI.values { app.set("AXEnhancedUserInterface", kCFBooleanTrue) }
        enhancedUI.removeAll()
    }
}
