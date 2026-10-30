import UIKit

/// A multi-line text editor driven by the desktop's own pointer and key routing.
///
/// It wraps a `UITextView` purely for layout and rendering; UIKit never makes it first
/// responder (that would summon the keyboard on the phone), so caret and selection are drawn
/// by this class.
final class DeskTextView: UIView, PointerTarget, Focusable {

    var text: String {
        get { textView.text ?? "" }
        set { textView.text = newValue; caretOffset = min(caretOffset, (newValue as NSString).length); selection = nil; updateCaret(); onChange?(newValue) }
    }
    var onChange: ((String) -> Void)?
    var placeholder: String = "" { didSet { placeholderLabel.text = placeholder; updatePlaceholder() } }
    var font: UIFont = Theme.font(15) { didSet { textView.font = font; placeholderLabel.font = font } }

    weak var focusGroup: FocusGroup?
    private(set) var hasFocus = false

    private let textView = UITextView()
    private let caret = UIView()
    private let placeholderLabel = UILabel()
    private var selectionLayers: [CALayer] = []
    private var caretOffset = 0
    /// Selection as (anchor, head) offsets; nil when nothing is selected.
    private var selection: (Int, Int)? { didSet { drawSelection() } }
    private var dragging = false
    private var blinkTimer: Timer?

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(textView)
        textView.isEditable = false
        textView.isSelectable = false
        textView.isScrollEnabled = true
        textView.backgroundColor = .clear
        textView.textColor = Theme.text
        textView.font = font
        textView.textContainerInset = UIEdgeInsets(top: 16, left: 14, bottom: 24, right: 14)
        textView.showsVerticalScrollIndicator = true
        textView.indicatorStyle = .white
        textView.addSubview(placeholderLabel)
        placeholderLabel.textColor = Theme.tertiaryText
        placeholderLabel.font = font
        textView.addSubview(caret)
        caret.backgroundColor = Theme.accentText
        caret.isHidden = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        textView.frame = bounds
        placeholderLabel.frame = CGRect(x: textView.textContainerInset.left + 5, y: textView.textContainerInset.top,
                                        width: bounds.width - 40, height: 22)
        updateCaret()
    }

    private func updatePlaceholder() {
        placeholderLabel.isHidden = !text.isEmpty
    }

    // MARK: Focus

    func setFocused(_ focused: Bool) {
        hasFocus = focused
        if focused { startBlink() } else { stopBlink(); selection = nil }
    }

    private func startBlink() {
        caret.isHidden = false
        blinkTimer?.invalidate()
        blinkTimer = Timer.scheduledTimer(withTimeInterval: 0.55, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.caret.isHidden.toggle() }
        }
    }

    private func stopBlink() {
        blinkTimer?.invalidate()
        blinkTimer = nil
        caret.isHidden = true
    }

    // MARK: Geometry helpers

    private func position(_ offset: Int) -> UITextPosition? {
        textView.position(from: textView.beginningOfDocument, offset: offset)
    }

    private func offset(at point: CGPoint) -> Int {
        let p = CGPoint(x: point.x + textView.contentOffset.x, y: point.y + textView.contentOffset.y)
        guard let pos = textView.closestPosition(to: p) else { return length }
        return textView.offset(from: textView.beginningOfDocument, to: pos)
    }

    private func updateCaret() {
        updatePlaceholder()
        guard let pos = position(caretOffset) else { return }
        var r = textView.caretRect(for: pos)
        if r.isNull || r.isInfinite { r = CGRect(x: textView.textContainerInset.left + 5, y: textView.textContainerInset.top, width: 2, height: font.lineHeight) }
        caret.frame = CGRect(x: r.minX, y: r.minY, width: 2, height: max(r.height, font.lineHeight))
        if hasFocus { startBlink() }
        scrollCaretIntoView()
    }

    private func scrollCaretIntoView() {
        let visible = CGRect(origin: textView.contentOffset, size: textView.bounds.size)
        guard !visible.contains(caret.frame) else { return }
        var offset = textView.contentOffset
        if caret.frame.maxY > visible.maxY { offset.y = caret.frame.maxY - textView.bounds.height + 24 }
        if caret.frame.minY < visible.minY { offset.y = max(0, caret.frame.minY - 24) }
        textView.setContentOffset(offset, animated: false)
    }

    private func drawSelection() {
        selectionLayers.forEach { $0.removeFromSuperlayer() }
        selectionLayers = []
        guard let (a, b) = selection, a != b,
              let start = position(min(a, b)), let end = position(max(a, b)),
              let range = textView.textRange(from: start, to: end) else { return }
        for rect in textView.selectionRects(for: range) {
            let l = CALayer()
            l.backgroundColor = Theme.selection.cgColor
            l.frame = rect.rect
            textView.layer.insertSublayer(l, at: 0)
            selectionLayers.append(l)
        }
    }

    /// All offsets in this class are UTF-16 offsets, matching NSRange and UITextPosition.
    private var length: Int { (text as NSString).length }
    private var units: [unichar] { Array(text.utf16) }
    private func isWordUnit(_ u: unichar) -> Bool {
        guard let scalar = UnicodeScalar(u) else { return true }
        return CharacterSet.alphanumerics.contains(scalar)
    }
    private let spaceUnit: unichar = 32
    private let newlineUnit: unichar = 10

    private var selectedRange: NSRange? {
        guard let (a, b) = selection, a != b else { return nil }
        return NSRange(location: min(a, b), length: abs(a - b))
    }

    // MARK: Editing primitives

    private func replace(_ range: NSRange, with string: String) {
        let attributed = NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: Theme.text])
        textView.textStorage.replaceCharacters(in: range, with: attributed)
        caretOffset = range.location + (string as NSString).length
        selection = nil
        updateCaret()
        onChange?(text)
    }

    func insert(_ string: String) {
        if let r = selectedRange { replace(r, with: string) }
        else { replace(NSRange(location: caretOffset, length: 0), with: string) }
    }

    private func deleteBackward(word: Bool) {
        if let r = selectedRange { replace(r, with: ""); return }
        guard caretOffset > 0 else { return }
        var len = 1
        if word {
            let chars = units
            var i = caretOffset
            while i > 0, chars[i - 1] == spaceUnit { i -= 1 }
            while i > 0, chars[i - 1] != spaceUnit, chars[i - 1] != newlineUnit { i -= 1 }
            len = max(1, caretOffset - i)
        } else if caretOffset >= 2, let pos = position(caretOffset), let prev = textView.position(from: pos, offset: -1) {
            // Step over a whole grapheme (emoji, combined characters).
            len = max(1, caretOffset - textView.offset(from: textView.beginningOfDocument, to: prev))
        }
        replace(NSRange(location: caretOffset - len, length: len), with: "")
    }

    private func deleteForward() {
        if let r = selectedRange { replace(r, with: ""); return }
        guard caretOffset < length else { return }
        var len = 1
        if let pos = position(caretOffset), let next = textView.position(from: pos, offset: 1) {
            len = max(1, textView.offset(from: textView.beginningOfDocument, to: next) - caretOffset)
        }
        replace(NSRange(location: caretOffset, length: len), with: "")
    }

    private func move(_ direction: UITextLayoutDirection, extend: Bool, byWord: Bool = false, toLineEdge: Bool = false) {
        let anchor = selection?.0 ?? caretOffset
        var target = caretOffset
        if toLineEdge {
            if let pos = position(caretOffset), let r = textView.tokenizer.rangeEnclosingPosition(pos, with: .line, inDirection: UITextDirection.layout(direction)) {
                target = textView.offset(from: textView.beginningOfDocument, to: direction == .left ? r.start : r.end)
            } else {
                target = direction == .left ? 0 : length
            }
        } else if byWord {
            let chars = units
            var i = caretOffset
            if direction == .left {
                while i > 0, !isWordUnit(chars[i - 1]) { i -= 1 }
                while i > 0, isWordUnit(chars[i - 1]) { i -= 1 }
            } else {
                while i < chars.count, !isWordUnit(chars[i]) { i += 1 }
                while i < chars.count, isWordUnit(chars[i]) { i += 1 }
            }
            target = i
        } else if let pos = position(caretOffset), let next = textView.position(from: pos, in: direction, offset: 1) {
            target = textView.offset(from: textView.beginningOfDocument, to: next)
        } else {
            target = direction == .left || direction == .up ? 0 : length
        }
        if !extend, let r = selectedRange {
            // Collapse the selection toward the direction of travel.
            target = (direction == .left || direction == .up) ? r.location : r.location + r.length
        }
        caretOffset = max(0, min(length, target))
        selection = extend ? (anchor, caretOffset) : nil
        updateCaret()
    }

    func selectAll() {
        selection = (0, length)
        caretOffset = length
        updateCaret()
    }

    // MARK: Pointer

    func pointer(_ event: PointerEvent, local: CGPoint) {
        switch event.kind {
        case .down(.left):
            focusGroup?.focus(self)
            let off = offset(at: local)
            if event.clickCount == 2 { selectWord(at: off) }
            else if event.clickCount >= 3 { selectLine(at: off) }
            else {
                caretOffset = off
                selection = event.modifiers.contains(.shift) ? (selection?.0 ?? caretOffset, off) : nil
                dragging = true
            }
            updateCaret()
        case .move:
            if dragging {
                let off = offset(at: local)
                let anchor = selection?.0 ?? caretOffset
                selection = (anchor, off)
                caretOffset = off
                updateCaret()
            }
        case .up(.left):
            dragging = false
        case .scroll(_, let dy):
            var o = textView.contentOffset
            o.y = max(0, min(o.y + dy, max(0, textView.contentSize.height - textView.bounds.height)))
            textView.setContentOffset(o, animated: false)
        default:
            break
        }
    }

    private func selectWord(at off: Int) {
        let chars = units
        guard !chars.isEmpty else { return }
        var a = min(off, chars.count), b = a
        while a > 0, isWordUnit(chars[a - 1]) { a -= 1 }
        while b < chars.count, isWordUnit(chars[b]) { b += 1 }
        selection = (a, b)
        caretOffset = b
    }

    private func selectLine(at off: Int) {
        let chars = units
        var a = min(off, chars.count), b = a
        while a > 0, chars[a - 1] != newlineUnit { a -= 1 }
        while b < chars.count, chars[b] != newlineUnit { b += 1 }
        selection = (a, b)
        caretOffset = b
    }

    func cursorStyle(at local: CGPoint) -> CursorStyle { .iBeam }

    // MARK: Keys

    func key(_ event: KeyEvent) -> Bool {
        guard event.isDown else { return true }
        if event.command {
            switch event.letter {
            case "a": selectAll(); return true
            case "c":
                if let r = selectedRange { UIPasteboard.general.string = (text as NSString).substring(with: r) }
                return true
            case "x":
                if let r = selectedRange { UIPasteboard.general.string = (text as NSString).substring(with: r); replace(r, with: "") }
                return true
            case "v":
                if let s = UIPasteboard.general.string { insert(s) }
                return true
            default: break
            }
            switch event.keyCode {
            case .keyboardLeftArrow: move(.left, extend: event.shift, toLineEdge: true); return true
            case .keyboardRightArrow: move(.right, extend: event.shift, toLineEdge: true); return true
            case .keyboardUpArrow: caretOffset = 0; selection = event.shift ? (selection?.0 ?? caretOffset, 0) : nil; updateCaret(); return true
            case .keyboardDownArrow: caretOffset = length; selection = nil; updateCaret(); return true
            case .keyboardDeleteOrBackspace:
                // ⌘⌫ deletes to the start of the line.
                let chars = units; var i = caretOffset
                while i > 0, chars[i - 1] != newlineUnit { i -= 1 }
                replace(NSRange(location: i, length: caretOffset - i), with: "")
                return true
            default: return false
            }
        }
        if event.isBackspace { deleteBackward(word: event.option); return true }
        if event.isForwardDelete { deleteForward(); return true }
        if event.isEnter { insert("\n"); return true }
        if event.isTab { insert("\t"); return true }
        if event.isEscape { selection = nil; updateCaret(); return true }
        switch event.keyCode {
        case .keyboardLeftArrow: move(.left, extend: event.shift, byWord: event.option); return true
        case .keyboardRightArrow: move(.right, extend: event.shift, byWord: event.option); return true
        case .keyboardUpArrow: move(.up, extend: event.shift); return true
        case .keyboardDownArrow: move(.down, extend: event.shift); return true
        case .keyboardHome: move(.left, extend: event.shift, toLineEdge: true); return true
        case .keyboardEnd: move(.right, extend: event.shift, toLineEdge: true); return true
        default: break
        }
        if event.isPrintable { insert(event.characters); return true }
        return false
    }
}
