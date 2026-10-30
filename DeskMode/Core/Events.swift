import UIKit

// MARK: - Pointer

enum PointerButton: Int {
    case left = 0
    case middle = 1
    case right = 2
}

enum PointerEventKind: Equatable {
    case move
    case down(PointerButton)
    case up(PointerButton)
    /// Scroll deltas in points. Positive `dy` means the content should move *up*
    /// (i.e. the user wants to see what is further down), matching a web `wheel` event.
    case scroll(dx: CGFloat, dy: CGFloat)
}

struct PointerEvent {
    let kind: PointerEventKind
    /// Location in desktop (external window) coordinates.
    let location: CGPoint
    let modifiers: UIKeyModifierFlags
    /// 1 for a single click, 2 for a double click, 3 for a triple click.
    let clickCount: Int
    let timestamp: TimeInterval

    func moved(to point: CGPoint) -> PointerEvent {
        PointerEvent(kind: kind, location: point, modifiers: modifiers, clickCount: clickCount, timestamp: timestamp)
    }

    var isLeftDown: Bool { kind == .down(.left) }
    var isLeftUp: Bool { kind == .up(.left) }
    var isRightDown: Bool { kind == .down(.right) }
}

// MARK: - Keyboard

struct KeyEvent {
    enum Phase { case down, up }

    let phase: Phase
    /// Characters produced with the current modifiers applied (e.g. "A" for shift+a). Empty for
    /// control keys such as arrows or modifiers themselves.
    let characters: String
    let charactersIgnoringModifiers: String
    let keyCode: UIKeyboardHIDUsage
    let modifiers: UIKeyModifierFlags
    let isRepeat: Bool

    var isDown: Bool { phase == .down }
    var command: Bool { modifiers.contains(.command) }
    var shift: Bool { modifiers.contains(.shift) }
    var option: Bool { modifiers.contains(.alternate) }
    var control: Bool { modifiers.contains(.control) }

    /// True when the key produces text and no command/control modifier is held.
    var isPrintable: Bool {
        guard !command, !control, !characters.isEmpty else { return false }
        guard let scalar = characters.unicodeScalars.first else { return false }
        if characters.count == 1, scalar.value < 0x20 || scalar.value == 0x7F { return false }
        // UIKit reports arrows etc. as private-use characters; those are not printable text.
        if (0xF700...0xF8FF).contains(scalar.value) { return false }
        return true
    }

    /// Lower-cased key letter ignoring modifiers, handy for shortcuts: `cmd + "t"`.
    var letter: String { charactersIgnoringModifiers.lowercased() }

    var isEnter: Bool { keyCode == .keyboardReturnOrEnter || keyCode == .keypadEnter }
    var isEscape: Bool { keyCode == .keyboardEscape }
    var isBackspace: Bool { keyCode == .keyboardDeleteOrBackspace }
    var isForwardDelete: Bool { keyCode == .keyboardDeleteForward }
    var isTab: Bool { keyCode == .keyboardTab }
    var isSpace: Bool { keyCode == .keyboardSpacebar }
    var isArrow: Bool { [.keyboardLeftArrow, .keyboardRightArrow, .keyboardUpArrow, .keyboardDownArrow].contains(keyCode) }

    var isModifierKey: Bool {
        switch keyCode {
        case .keyboardLeftShift, .keyboardRightShift, .keyboardLeftControl, .keyboardRightControl,
             .keyboardLeftAlt, .keyboardRightAlt, .keyboardLeftGUI, .keyboardRightGUI, .keyboardCapsLock:
            return true
        default:
            return false
        }
    }

    /// The `KeyboardEvent.key` value a browser would report for this key.
    var webKey: String {
        switch keyCode {
        case .keyboardReturnOrEnter, .keypadEnter: return "Enter"
        case .keyboardEscape: return "Escape"
        case .keyboardDeleteOrBackspace: return "Backspace"
        case .keyboardDeleteForward: return "Delete"
        case .keyboardTab: return "Tab"
        case .keyboardSpacebar: return " "
        case .keyboardLeftArrow: return "ArrowLeft"
        case .keyboardRightArrow: return "ArrowRight"
        case .keyboardUpArrow: return "ArrowUp"
        case .keyboardDownArrow: return "ArrowDown"
        case .keyboardHome: return "Home"
        case .keyboardEnd: return "End"
        case .keyboardPageUp: return "PageUp"
        case .keyboardPageDown: return "PageDown"
        case .keyboardLeftShift, .keyboardRightShift: return "Shift"
        case .keyboardLeftControl, .keyboardRightControl: return "Control"
        case .keyboardLeftAlt, .keyboardRightAlt: return "Alt"
        case .keyboardLeftGUI, .keyboardRightGUI: return "Meta"
        case .keyboardCapsLock: return "CapsLock"
        default:
            if !characters.isEmpty, isPrintable { return characters }
            if !charactersIgnoringModifiers.isEmpty { return charactersIgnoringModifiers }
            return "Unidentified"
        }
    }

    /// The `KeyboardEvent.code` value a browser would report.
    var webCode: String {
        switch keyCode {
        case .keyboardReturnOrEnter: return "Enter"
        case .keypadEnter: return "NumpadEnter"
        case .keyboardEscape: return "Escape"
        case .keyboardDeleteOrBackspace: return "Backspace"
        case .keyboardDeleteForward: return "Delete"
        case .keyboardTab: return "Tab"
        case .keyboardSpacebar: return "Space"
        case .keyboardLeftArrow: return "ArrowLeft"
        case .keyboardRightArrow: return "ArrowRight"
        case .keyboardUpArrow: return "ArrowUp"
        case .keyboardDownArrow: return "ArrowDown"
        case .keyboardHome: return "Home"
        case .keyboardEnd: return "End"
        case .keyboardPageUp: return "PageUp"
        case .keyboardPageDown: return "PageDown"
        case .keyboardLeftShift: return "ShiftLeft"
        case .keyboardRightShift: return "ShiftRight"
        case .keyboardLeftControl: return "ControlLeft"
        case .keyboardRightControl: return "ControlRight"
        case .keyboardLeftAlt: return "AltLeft"
        case .keyboardRightAlt: return "AltRight"
        case .keyboardLeftGUI: return "MetaLeft"
        case .keyboardRightGUI: return "MetaRight"
        default:
            let c = charactersIgnoringModifiers
            if c.count == 1, let s = c.unicodeScalars.first {
                if CharacterSet.letters.contains(s) { return "Key" + c.uppercased() }
                if CharacterSet.decimalDigits.contains(s) { return "Digit" + c }
            }
            return "Unidentified"
        }
    }

    /// Legacy `keyCode` / `which` value for web pages that still rely on it.
    var legacyKeyCode: Int {
        switch keyCode {
        case .keyboardReturnOrEnter, .keypadEnter: return 13
        case .keyboardEscape: return 27
        case .keyboardDeleteOrBackspace: return 8
        case .keyboardDeleteForward: return 46
        case .keyboardTab: return 9
        case .keyboardSpacebar: return 32
        case .keyboardLeftArrow: return 37
        case .keyboardUpArrow: return 38
        case .keyboardRightArrow: return 39
        case .keyboardDownArrow: return 40
        case .keyboardHome: return 36
        case .keyboardEnd: return 35
        case .keyboardPageUp: return 33
        case .keyboardPageDown: return 34
        case .keyboardLeftShift, .keyboardRightShift: return 16
        case .keyboardLeftControl, .keyboardRightControl: return 17
        case .keyboardLeftAlt, .keyboardRightAlt: return 18
        case .keyboardLeftGUI, .keyboardRightGUI: return 91
        default:
            let c = charactersIgnoringModifiers.uppercased()
            if c.count == 1, let s = c.unicodeScalars.first, s.value < 128 { return Int(s.value) }
            return 0
        }
    }
}

// MARK: - Cursor

enum CursorStyle: Equatable {
    case arrow
    case iBeam
    case pointingHand
    case openHand
    case closedHand
    case crosshair
    case notAllowed
    case resizeHorizontal
    case resizeVertical
    case resizeDiagonalNWSE
    case resizeDiagonalNESW
    case hidden

    /// Maps a CSS `cursor` value to a cursor style.
    static func fromCSS(_ css: String) -> CursorStyle {
        switch css {
        case "pointer": return .pointingHand
        case "text", "vertical-text": return .iBeam
        case "grab", "all-scroll", "move": return .openHand
        case "grabbing": return .closedHand
        case "crosshair", "cell": return .crosshair
        case "not-allowed", "no-drop": return .notAllowed
        case "col-resize", "ew-resize", "e-resize", "w-resize": return .resizeHorizontal
        case "row-resize", "ns-resize", "n-resize", "s-resize": return .resizeVertical
        case "nwse-resize", "nw-resize", "se-resize": return .resizeDiagonalNWSE
        case "nesw-resize", "ne-resize", "sw-resize": return .resizeDiagonalNESW
        case "none": return .hidden
        default: return .arrow
        }
    }
}

extension UIKeyModifierFlags {
    /// Bit mask passed to the browser bridge: ctrl=1, alt=2, shift=4, meta=8.
    var webMask: Int {
        var m = 0
        if contains(.control) { m |= 1 }
        if contains(.alternate) { m |= 2 }
        if contains(.shift) { m |= 4 }
        if contains(.command) { m |= 8 }
        return m
    }
}
