import UIKit

/// Characters for keys reported by GameController, which only gives HID usage codes.
/// US (ANSI) layout; letters and digits are right everywhere, punctuation may differ on others.
enum KeyCharacterMap {

    /// (unshifted, shifted) for printable keys; nil for keys that produce no text.
    static func characters(for code: UIKeyboardHIDUsage) -> (String, String)? {
        let raw = code.rawValue
        if (0x04...0x1D).contains(raw) {
            let letter = String(UnicodeScalar(UInt8(raw - 0x04) + UInt8(ascii: "a")))
            return (letter, letter.uppercased())
        }
        if (0x1E...0x27).contains(raw) {
            let digits = Array("1234567890")
            let shifted = Array("!@#$%^&*()")
            return (String(digits[raw - 0x1E]), String(shifted[raw - 0x1E]))
        }
        switch code {
        case .keyboardReturnOrEnter, .keypadEnter: return ("\r", "\r")
        case .keyboardEscape: return ("\u{1B}", "\u{1B}")
        case .keyboardDeleteOrBackspace: return ("\u{8}", "\u{8}")
        case .keyboardTab: return ("\t", "\t")
        case .keyboardSpacebar: return (" ", " ")
        case .keyboardHyphen: return ("-", "_")
        case .keyboardEqualSign: return ("=", "+")
        case .keyboardOpenBracket: return ("[", "{")
        case .keyboardCloseBracket: return ("]", "}")
        case .keyboardBackslash, .keyboardNonUSPound: return ("\\", "|")
        case .keyboardSemicolon: return (";", ":")
        case .keyboardQuote: return ("'", "\"")
        case .keyboardGraveAccentAndTilde, .keyboardNonUSBackslash: return ("`", "~")
        case .keyboardComma: return (",", "<")
        case .keyboardPeriod: return (".", ">")
        case .keyboardSlash: return ("/", "?")
        case .keypadSlash: return ("/", "/")
        case .keypadAsterisk: return ("*", "*")
        case .keypadHyphen: return ("-", "-")
        case .keypadPlus: return ("+", "+")
        case .keypadPeriod: return (".", ".")
        case .keypadEqualSign: return ("=", "=")
        case .keypad1: return ("1", "1")
        case .keypad2: return ("2", "2")
        case .keypad3: return ("3", "3")
        case .keypad4: return ("4", "4")
        case .keypad5: return ("5", "5")
        case .keypad6: return ("6", "6")
        case .keypad7: return ("7", "7")
        case .keypad8: return ("8", "8")
        case .keypad9: return ("9", "9")
        case .keypad0: return ("0", "0")
        default: return nil
        }
    }

    /// Builds the `characters` / `charactersIgnoringModifiers` pair UIKit would have produced.
    static func text(for code: UIKeyboardHIDUsage, modifiers: UIKeyModifierFlags) -> (characters: String, ignoringModifiers: String) {
        guard let (plain, shifted) = characters(for: code) else { return ("", "") }
        let isLetter = (0x04...0x1D).contains(code.rawValue)
        let shift = modifiers.contains(.shift)
        let caps = modifiers.contains(.alphaShift)
        let useUpper = isLetter ? (shift != caps) : shift
        return (useUpper ? shifted : plain, plain)
    }
}
