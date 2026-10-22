import Carbon.HIToolbox
import Foundation

enum Command: Equatable {
    case focusLeft, focusRight, focusUp, focusDown, focusFirst, focusLast
    case focusIndex(Int)
    case moveLeft, moveRight, moveUp, moveDown
    case cycleWidth, fullWidth, centre, wider, narrower, taller, shorter, equalizeHeights
    case stackLeft, stackRight, popOutLeft, popOutRight
    case toggleFloat, sendToNextDisplay, toggleEnabled, retile
}

struct Binding {
    let key: Int
    let mods: Int
    let command: Command
    let label: String
}

/// Default shortcuts. ⌃⌥ is the base modifier, with Vim keys or arrows.
enum Keymap {
    static let base = controlKey | optionKey
    static let shift = base | shiftKey
    static let cmd = base | cmdKey

    static let digits = [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5,
                         kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9]

    static var defaults: [Binding] {
        var b: [Binding] = [
            .init(key: kVK_ANSI_H, mods: base, command: .focusLeft, label: "Focus left"),
            .init(key: kVK_LeftArrow, mods: base, command: .focusLeft, label: "Focus left"),
            .init(key: kVK_ANSI_L, mods: base, command: .focusRight, label: "Focus right"),
            .init(key: kVK_RightArrow, mods: base, command: .focusRight, label: "Focus right"),
            .init(key: kVK_ANSI_K, mods: base, command: .focusUp, label: "Focus up (stack)"),
            .init(key: kVK_UpArrow, mods: base, command: .focusUp, label: "Focus up (stack)"),
            .init(key: kVK_ANSI_J, mods: base, command: .focusDown, label: "Focus down (stack)"),
            .init(key: kVK_DownArrow, mods: base, command: .focusDown, label: "Focus down (stack)"),
            .init(key: kVK_LeftArrow, mods: cmd, command: .focusFirst, label: "First window"),
            .init(key: kVK_RightArrow, mods: cmd, command: .focusLast, label: "Last window"),

            .init(key: kVK_ANSI_H, mods: shift, command: .moveLeft, label: "Move left"),
            .init(key: kVK_LeftArrow, mods: shift, command: .moveLeft, label: "Move left"),
            .init(key: kVK_ANSI_L, mods: shift, command: .moveRight, label: "Move right"),
            .init(key: kVK_RightArrow, mods: shift, command: .moveRight, label: "Move right"),
            .init(key: kVK_ANSI_K, mods: shift, command: .moveUp, label: "Move up (stack)"),
            .init(key: kVK_UpArrow, mods: shift, command: .moveUp, label: "Move up (stack)"),
            .init(key: kVK_ANSI_J, mods: shift, command: .moveDown, label: "Move down (stack)"),
            .init(key: kVK_DownArrow, mods: shift, command: .moveDown, label: "Move down (stack)"),

            .init(key: kVK_ANSI_R, mods: base, command: .cycleWidth, label: "Cycle width"),
            .init(key: kVK_ANSI_F, mods: base, command: .fullWidth, label: "Full width"),
            .init(key: kVK_ANSI_C, mods: base, command: .centre, label: "Centre column"),
            .init(key: kVK_ANSI_Equal, mods: base, command: .wider, label: "Wider"),
            .init(key: kVK_ANSI_Minus, mods: base, command: .narrower, label: "Narrower"),
            .init(key: kVK_ANSI_Equal, mods: shift, command: .taller, label: "Taller (stack)"),
            .init(key: kVK_ANSI_Minus, mods: shift, command: .shorter, label: "Shorter (stack)"),
            .init(key: kVK_ANSI_0, mods: base, command: .equalizeHeights, label: "Equalize heights"),

            .init(key: kVK_ANSI_LeftBracket, mods: base, command: .stackLeft, label: "Stack into left column"),
            .init(key: kVK_ANSI_RightBracket, mods: base, command: .stackRight, label: "Stack into right column"),
            .init(key: kVK_ANSI_LeftBracket, mods: shift, command: .popOutLeft, label: "Pop out left"),
            .init(key: kVK_ANSI_RightBracket, mods: shift, command: .popOutRight, label: "Pop out right"),

            .init(key: kVK_ANSI_T, mods: base, command: .toggleFloat, label: "Float / unfloat"),
            .init(key: kVK_ANSI_N, mods: base, command: .sendToNextDisplay, label: "Send to next display"),
            .init(key: kVK_ANSI_Q, mods: base, command: .toggleEnabled, label: "Pause / resume tiling"),
        ]
        for (i, key) in digits.enumerated() {
            b.append(.init(key: key, mods: base, command: .focusIndex(i), label: "Jump to window \(i + 1)"))
        }
        return b
    }

    static func describe(_ b: Binding) -> String {
        var s = ""
        if b.mods & controlKey != 0 { s += "⌃" }
        if b.mods & optionKey != 0 { s += "⌥" }
        if b.mods & shiftKey != 0 { s += "⇧" }
        if b.mods & cmdKey != 0 { s += "⌘" }
        let names: [Int: String] = [
            kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
            kVK_ANSI_Equal: "=", kVK_ANSI_Minus: "-", kVK_ANSI_LeftBracket: "[", kVK_ANSI_RightBracket: "]",
            kVK_ANSI_0: "0", kVK_ANSI_C: "C", kVK_ANSI_F: "F", kVK_ANSI_H: "H", kVK_ANSI_J: "J",
            kVK_ANSI_K: "K", kVK_ANSI_L: "L", kVK_ANSI_N: "N", kVK_ANSI_Q: "Q", kVK_ANSI_R: "R", kVK_ANSI_T: "T",
        ]
        if let i = digits.firstIndex(of: b.key) { return s + "\(i + 1)" }
        return s + (names[b.key] ?? "?")
    }
}

/// Global hotkeys via Carbon's RegisterEventHotKey. Old API, but it needs no permissions,
/// consumes the keystroke, and is what every launcher and window manager still uses.
final class HotkeyCenter {
    private var refs: [EventHotKeyRef] = []
    private var actions: [UInt32: () -> Void] = [:]
    private var handler: EventHandlerRef?

    init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetEventDispatcherTarget(), { _, event, userData in
            var hotkey = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hotkey)
            let center = Unmanaged<HotkeyCenter>.fromOpaque(userData!).takeUnretainedValue()
            center.actions[hotkey.id]?()
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }

    /// Returns false if another app already owns the combination.
    @discardableResult
    func register(key: Int, mods: Int, _ action: @escaping () -> Void) -> Bool {
        let id = UInt32(actions.count + 1)
        var ref: EventHotKeyRef?
        let hotkeyID = EventHotKeyID(signature: OSType(0x4352_534C), id: id) // 'CRSL'
        guard RegisterEventHotKey(UInt32(key), UInt32(mods), hotkeyID, GetEventDispatcherTarget(), 0, &ref) == noErr,
              let ref else { return false }
        refs.append(ref)
        actions[id] = action
        return true
    }
}
