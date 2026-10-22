import CarouselCore
import Foundation

/// User preferences, persisted in UserDefaults. Changes apply live.
final class Settings {
    static let shared = Settings()
    private let d = UserDefaults.standard

    let widthPresets = [0.25, 1.0 / 3, 0.5, 2.0 / 3, 0.75]

    var gap: Double {
        get { d.object(forKey: "gap") as? Double ?? 8 }
        set { d.set(newValue, forKey: "gap") }
    }

    var focusBorder: Bool {
        get { d.object(forKey: "focusBorder") as? Bool ?? false }
        set { d.set(newValue, forKey: "focusBorder") }
    }

    var dimInactive: Bool {
        get { d.object(forKey: "dimInactive") as? Bool ?? false }
        set { d.set(newValue, forKey: "dimInactive") }
    }

    var showIndicator: Bool {
        get { d.object(forKey: "showIndicator") as? Bool ?? true }
        set { d.set(newValue, forKey: "showIndicator") }
    }

    var animate: Bool {
        get { d.object(forKey: "animate") as? Bool ?? true }
        set { d.set(newValue, forKey: "animate") }
    }

    var animationDuration: Double {
        get { d.object(forKey: "animationDuration") as? Double ?? 0.18 }
        set { d.set(newValue, forKey: "animationDuration") }
    }

    var centreMode: CentreMode {
        get { CentreMode(rawValue: d.string(forKey: "centreMode") ?? "") ?? .never }
        set { d.set(newValue.rawValue, forKey: "centreMode") }
    }

    /// Scroll speed multiplier for ⌃⌥ + trackpad/mouse scrolling.
    var scrollSpeed: Double {
        get { d.object(forKey: "scrollSpeed") as? Double ?? 1.5 }
        set { d.set(newValue, forKey: "scrollSpeed") }
    }
}
