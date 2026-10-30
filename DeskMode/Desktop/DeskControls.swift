import UIKit

// MARK: - Button

/// A pointer-driven button with hover and pressed states. Works without touch input.
final class DeskButton: UIView, PointerTarget {

    enum Style {
        case plain        // transparent, highlight on hover
        case toolbar      // small rounded icon button
        case primary      // accent filled
        case menuItem     // full-width row inside a popup menu
        case list         // full-width row inside a sidebar list
        case pill         // rounded capsule with text
    }

    var onTap: (() -> Void)?
    var onRightClick: ((CGPoint) -> Void)?
    var onDoubleClick: (() -> Void)?

    var isEnabled = true { didSet { refresh() } }
    /// Traffic lights and other custom-drawn buttons turn this off.
    var showsHoverHighlight = true { didSet { refresh() } }
    var isSelected = false { didSet { refresh() } }
    var tintOverride: UIColor? { didSet { refresh() } }

    var title: String? {
        get { label.text }
        set { label.text = newValue; setNeedsLayout() }
    }

    var subtitle: String? {
        get { subtitleLabel.text }
        set { subtitleLabel.text = newValue; subtitleLabel.isHidden = (newValue ?? "").isEmpty; setNeedsLayout() }
    }

    var symbolName: String? {
        didSet { updateIcon() }
    }
    var image: UIImage? {
        didSet { icon.image = image; icon.isHidden = image == nil; setNeedsLayout() }
    }

    var font: UIFont {
        get { label.font }
        set { label.font = newValue; invalidateIntrinsicContentSize(); setNeedsLayout() }
    }

    var shortcutText: String? {
        get { shortcutLabel.text }
        set { shortcutLabel.text = newValue; shortcutLabel.isHidden = (newValue ?? "").isEmpty; setNeedsLayout() }
    }

    let style: Style
    private let highlight = UIView()
    private let label = UILabel()
    private let subtitleLabel = UILabel()
    private let shortcutLabel = UILabel()
    private let icon = UIImageView()
    private var hovered = false
    private var pressed = false
    var iconPointSize: CGFloat = 14 { didSet { updateIcon() } }
    var contentInsets = UIEdgeInsets(top: 4, left: 10, bottom: 4, right: 10)

    init(title: String? = nil, symbol: String? = nil, style: Style = .plain) {
        self.style = style
        super.init(frame: .zero)
        addSubview(highlight)
        addSubview(icon)
        addSubview(label)
        addSubview(subtitleLabel)
        addSubview(shortcutLabel)
        highlight.isUserInteractionEnabled = false
        icon.contentMode = .center
        icon.isHidden = true
        label.text = title
        label.font = Theme.font(13, weight: style == .primary ? .semibold : .regular)
        label.textColor = Theme.text
        label.lineBreakMode = .byTruncatingTail
        subtitleLabel.font = Theme.font(11)
        subtitleLabel.textColor = Theme.secondaryText
        subtitleLabel.isHidden = true
        shortcutLabel.font = Theme.font(12)
        shortcutLabel.textColor = Theme.tertiaryText
        shortcutLabel.isHidden = true
        shortcutLabel.textAlignment = .right
        symbolName = symbol
        switch style {
        case .plain: highlight.layer.cornerRadius = 5
        case .toolbar: highlight.layer.cornerRadius = 6; contentInsets = UIEdgeInsets(top: 4, left: 6, bottom: 4, right: 6)
        case .primary: highlight.layer.cornerRadius = 7
        case .menuItem: highlight.layer.cornerRadius = 5; contentInsets = UIEdgeInsets(top: 4, left: 10, bottom: 4, right: 10)
        case .list: highlight.layer.cornerRadius = 7; contentInsets = UIEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)
        case .pill: highlight.layer.cornerRadius = 12; contentInsets = UIEdgeInsets(top: 3, left: 10, bottom: 3, right: 10)
        }
        updateIcon()
        refresh()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func updateIcon() {
        guard let symbolName else {
            if image == nil { icon.isHidden = true }
            return
        }
        icon.image = UIImage.symbol(symbolName, size: iconPointSize, weight: .medium)
        icon.isHidden = false
        setNeedsLayout()
    }

    override var intrinsicContentSize: CGSize {
        let labelSize = label.text?.isEmpty == false ? label.intrinsicContentSize : .zero
        let iconW: CGFloat = icon.isHidden ? 0 : (iconPointSize + 8)
        let gap: CGFloat = (!icon.isHidden && labelSize.width > 0) ? 6 : 0
        let shortcutW: CGFloat = shortcutLabel.isHidden ? 0 : shortcutLabel.intrinsicContentSize.width + 24
        let subtitleH: CGFloat = subtitleLabel.isHidden ? 0 : subtitleLabel.intrinsicContentSize.height
        let h = max(labelSize.height + subtitleH, iconPointSize + 8) + contentInsets.top + contentInsets.bottom
        return CGSize(width: iconW + gap + labelSize.width + shortcutW + contentInsets.left + contentInsets.right, height: max(h, 24))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        highlight.frame = bounds
        var x = contentInsets.left
        if !icon.isHidden {
            let w = iconPointSize + 8
            icon.frame = CGRect(x: x, y: 0, width: w, height: bounds.height)
            x += w + (label.text?.isEmpty == false ? 6 : 0)
        }
        var right = bounds.width - contentInsets.right
        if !shortcutLabel.isHidden {
            let w = shortcutLabel.intrinsicContentSize.width
            shortcutLabel.frame = CGRect(x: right - w, y: 0, width: w, height: bounds.height)
            right -= w + 16
        }
        let available = max(0, right - x)
        if subtitleLabel.isHidden {
            label.frame = CGRect(x: x, y: 0, width: available, height: bounds.height)
        } else {
            let lh = label.intrinsicContentSize.height
            let sh = subtitleLabel.intrinsicContentSize.height
            let top = (bounds.height - lh - sh) / 2
            label.frame = CGRect(x: x, y: top, width: available, height: lh)
            subtitleLabel.frame = CGRect(x: x, y: top + lh, width: available, height: sh)
        }
    }

    private func refresh() {
        alpha = isEnabled ? 1 : 0.4
        let tint = tintOverride ?? Theme.text
        label.textColor = tint
        icon.tintColor = tint
        switch style {
        case .primary:
            highlight.backgroundColor = pressed ? Theme.accent.withAlphaComponent(0.7) : (hovered ? Theme.accent.withAlphaComponent(0.9) : Theme.accent)
            label.textColor = .white
            icon.tintColor = .white
        case .menuItem:
            highlight.backgroundColor = hovered ? Theme.accent : .clear
            label.textColor = hovered ? .white : tint
            shortcutLabel.textColor = hovered ? UIColor.white.withAlphaComponent(0.8) : Theme.tertiaryText
            icon.tintColor = hovered ? .white : tint
        case .list:
            highlight.backgroundColor = isSelected ? Theme.accent.withAlphaComponent(0.85) : (hovered ? Theme.controlBackgroundHover : .clear)
            label.textColor = isSelected ? .white : tint
            subtitleLabel.textColor = isSelected ? UIColor.white.withAlphaComponent(0.75) : Theme.secondaryText
            icon.tintColor = isSelected ? .white : tint
        case .pill:
            highlight.backgroundColor = isSelected ? Theme.accent : (hovered ? Theme.controlBackgroundHover : Theme.controlBackground)
            label.textColor = isSelected ? .white : tint
        case .plain, .toolbar:
            if !showsHoverHighlight {
                highlight.backgroundColor = .clear
            } else if isSelected {
                highlight.backgroundColor = Theme.controlBackgroundPressed
            } else {
                highlight.backgroundColor = pressed ? Theme.controlBackgroundPressed : (hovered ? Theme.controlBackgroundHover : .clear)
            }
        }
    }

    // MARK: PointerTarget

    func pointer(_ event: PointerEvent, local: CGPoint) {
        guard isEnabled else { return }
        switch event.kind {
        case .down(.left):
            pressed = true
            refresh()
        case .up(.left):
            let inside = bounds.contains(local)
            pressed = false
            refresh()
            if inside {
                if event.clickCount == 2, let onDoubleClick { onDoubleClick() } else { onTap?() }
            }
        case .down(.right):
            onRightClick?(local)
        default:
            break
        }
    }

    func pointerEntered() { hovered = true; refresh() }
    func pointerExited() { hovered = false; pressed = false; refresh() }
    func cursorStyle(at local: CGPoint) -> CursorStyle { .arrow }
}

// MARK: - Toggle

/// A macOS-style switch.
final class DeskToggle: UIView, PointerTarget {

    var isOn: Bool { didSet { animateKnob() } }
    var onChange: ((Bool) -> Void)?

    private let track = UIView()
    private let knob = UIView()

    init(isOn: Bool) {
        self.isOn = isOn
        super.init(frame: CGRect(x: 0, y: 0, width: 40, height: 24))
        addSubview(track)
        track.addSubview(knob)
        track.layer.cornerRadius = 12
        knob.backgroundColor = .white
        knob.layer.cornerRadius = 10
        knob.layer.shadowColor = UIColor.black.cgColor
        knob.layer.shadowOpacity = 0.3
        knob.layer.shadowRadius = 2
        knob.layer.shadowOffset = CGSize(width: 0, height: 1)
        animateKnob(animated: false)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: CGSize { CGSize(width: 40, height: 24) }

    override func layoutSubviews() {
        super.layoutSubviews()
        track.frame = bounds
        animateKnob(animated: false)
    }

    private func animateKnob(animated: Bool = true) {
        let apply = {
            self.track.backgroundColor = self.isOn ? Theme.accent : UIColor(white: 1, alpha: 0.18)
            self.knob.frame = CGRect(x: self.isOn ? self.bounds.width - 22 : 2, y: 2, width: 20, height: 20)
        }
        if animated { UIView.animate(withDuration: 0.18, animations: apply) } else { apply() }
    }

    func pointer(_ event: PointerEvent, local: CGPoint) {
        if event.isLeftUp, bounds.insetBy(dx: -4, dy: -4).contains(local) {
            isOn.toggle()
            onChange?(isOn)
        }
    }

    func cursorStyle(at local: CGPoint) -> CursorStyle { .arrow }
}

// MARK: - Text field

/// A single-line text field that is edited through the desktop's own key routing rather than
/// UIKit's first-responder system (which would try to show the keyboard on the wrong screen).
final class DeskTextField: UIView, PointerTarget, Focusable {

    var text: String = "" { didSet { caretIndex = min(caretIndex, text.count); onChange?(text); setNeedsLayout() } }
    var placeholder: String = "" { didSet { setNeedsLayout() } }
    var font: UIFont = Theme.font(13) { didSet { label.font = font; placeholderLabel.font = font } }
    var textAlignment: NSTextAlignment = .left
    var leadingSymbol: String? { didSet { leadingIcon.image = leadingSymbol.flatMap { UIImage.symbol($0, size: 12) }; setNeedsLayout() } }
    var selectsAllOnFocus = false
    var showsBackground = true { didSet { refresh() } }

    var onChange: ((String) -> Void)?
    var onSubmit: ((String) -> Void)?
    var onEscape: (() -> Void)?
    var onFocusChange: ((Bool) -> Void)?
    /// Called for keys the field does not handle itself (e.g. arrows up/down for a results list).
    var onUnhandledKey: ((KeyEvent) -> Bool)?

    weak var focusGroup: FocusGroup?

    private(set) var hasFocus = false
    private(set) var caretIndex = 0
    private var isAllSelected = false

    private let background = UIView()
    private let label = UILabel()
    private let placeholderLabel = UILabel()
    private let leadingIcon = UIImageView()
    private let selectionView = UIView()
    private let caret = UIView()
    private let clip = UIView()
    private var scrollOffset: CGFloat = 0
    private var blinkTimer: Timer?
    var insets = UIEdgeInsets(top: 0, left: 10, bottom: 0, right: 10)

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(background)
        addSubview(leadingIcon)
        addSubview(clip)
        clip.clipsToBounds = true
        clip.addSubview(selectionView)
        clip.addSubview(placeholderLabel)
        clip.addSubview(label)
        clip.addSubview(caret)
        background.layer.cornerRadius = 7
        background.layer.borderWidth = 1
        leadingIcon.contentMode = .center
        leadingIcon.tintColor = Theme.secondaryText
        label.font = font
        label.textColor = Theme.text
        placeholderLabel.font = font
        placeholderLabel.textColor = Theme.tertiaryText
        selectionView.backgroundColor = Theme.selection
        selectionView.isHidden = true
        caret.backgroundColor = Theme.accentText
        caret.isHidden = true
        refresh()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: 30) }

    override func layoutSubviews() {
        super.layoutSubviews()
        background.frame = bounds
        var left = insets.left
        if leadingSymbol != nil {
            leadingIcon.frame = CGRect(x: 8, y: 0, width: 20, height: bounds.height)
            left = 32
        } else {
            leadingIcon.frame = .zero
        }
        clip.frame = CGRect(x: left, y: 0, width: max(0, bounds.width - left - insets.right), height: bounds.height)
        let textWidth = (text as NSString).size(withAttributes: [.font: font]).width
        let caretX = (String(text.prefix(caretIndex)) as NSString).size(withAttributes: [.font: font]).width

        // Keep the caret visible by scrolling horizontally.
        let visible = clip.bounds.width
        if textWidth <= visible {
            scrollOffset = (textAlignment == .center) ? -(visible - textWidth) / 2 : 0
        } else if caretX - scrollOffset > visible - 2 {
            scrollOffset = caretX - visible + 2
        } else if caretX - scrollOffset < 0 {
            scrollOffset = caretX
        }
        scrollOffset = max(0, min(scrollOffset, max(0, textWidth - visible)))
        if textAlignment == .center, textWidth <= visible { scrollOffset = -(visible - textWidth) / 2 }

        label.text = text
        label.frame = CGRect(x: -scrollOffset, y: 0, width: max(textWidth, 1), height: bounds.height)
        placeholderLabel.text = placeholder
        placeholderLabel.isHidden = !text.isEmpty
        placeholderLabel.frame = CGRect(x: textAlignment == .center ? 0 : 0, y: 0, width: clip.bounds.width, height: bounds.height)
        placeholderLabel.textAlignment = textAlignment
        selectionView.frame = CGRect(x: -scrollOffset - 1, y: 6, width: textWidth + 2, height: bounds.height - 12)
        selectionView.isHidden = !(isAllSelected && hasFocus && !text.isEmpty)
        caret.frame = CGRect(x: caretX - scrollOffset, y: 7, width: 1.5, height: bounds.height - 14)
    }

    private func refresh() {
        background.isHidden = !showsBackground
        background.backgroundColor = hasFocus ? UIColor(white: 1, alpha: 0.1) : Theme.controlBackground
        background.layer.borderColor = hasFocus ? Theme.accent.withAlphaComponent(0.9).cgColor : UIColor(white: 1, alpha: 0.1).cgColor
        setNeedsLayout()
    }

    // MARK: Focus

    func setFocused(_ focused: Bool) {
        guard hasFocus != focused else { return }
        hasFocus = focused
        if focused {
            if selectsAllOnFocus, !text.isEmpty { isAllSelected = true }
            caretIndex = text.count
            startBlink()
        } else {
            isAllSelected = false
            stopBlink()
        }
        refresh()
        onFocusChange?(focused)
    }

    func requestFocus() { focusGroup?.focus(self) }

    func selectAll() { isAllSelected = !text.isEmpty; caretIndex = text.count; setNeedsLayout() }

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

    private func resetBlink() {
        if hasFocus { startBlink() }
    }

    // MARK: Pointer

    func pointer(_ event: PointerEvent, local: CGPoint) {
        switch event.kind {
        case .down(.left):
            let wasFocused = hasFocus
            requestFocus()
            if wasFocused {
                if event.clickCount >= 2 { selectAll() } else { isAllSelected = false; caretIndex = index(at: local) }
            }
            setNeedsLayout()
        default:
            break
        }
    }

    func cursorStyle(at local: CGPoint) -> CursorStyle { .iBeam }

    private func index(at local: CGPoint) -> Int {
        let x = local.x - clip.frame.minX + scrollOffset
        var best = 0
        var bestDist = CGFloat.greatestFiniteMagnitude
        for i in 0...text.count {
            let w = (String(text.prefix(i)) as NSString).size(withAttributes: [.font: font]).width
            let d = abs(w - x)
            if d < bestDist { bestDist = d; best = i }
        }
        return best
    }

    // MARK: Keys

    func key(_ event: KeyEvent) -> Bool {
        guard event.isDown else { return true }
        resetBlink()
        if event.isEnter { onSubmit?(text); return true }
        if event.isEscape {
            if isAllSelected { isAllSelected = false; setNeedsLayout() } else { onEscape?() }
            return true
        }
        if event.command {
            switch event.letter {
            case "a": selectAll(); return true
            case "c": UIPasteboard.general.string = isAllSelected ? text : text; return true
            case "x": UIPasteboard.general.string = text; replaceAll(with: ""); return true
            case "v":
                if let s = UIPasteboard.general.string?.replacingOccurrences(of: "\n", with: " ") { insert(s) }
                return true
            default: return onUnhandledKey?(event) ?? false
            }
        }
        if event.isBackspace {
            if isAllSelected { replaceAll(with: "") }
            else if event.option { deleteWordBackward() }
            else if caretIndex > 0 {
                text.remove(at: text.index(text.startIndex, offsetBy: caretIndex - 1))
                caretIndex -= 1
            }
            setNeedsLayout()
            return true
        }
        if event.isForwardDelete {
            if isAllSelected { replaceAll(with: "") }
            else if caretIndex < text.count { text.remove(at: text.index(text.startIndex, offsetBy: caretIndex)) }
            setNeedsLayout()
            return true
        }
        switch event.keyCode {
        case .keyboardLeftArrow:
            if isAllSelected { isAllSelected = false; caretIndex = 0 }
            else if event.command { caretIndex = 0 }
            else if event.option { caretIndex = wordBoundary(backward: true) }
            else { caretIndex = max(0, caretIndex - 1) }
            setNeedsLayout(); return true
        case .keyboardRightArrow:
            if isAllSelected { isAllSelected = false; caretIndex = text.count }
            else if event.command { caretIndex = text.count }
            else if event.option { caretIndex = wordBoundary(backward: false) }
            else { caretIndex = min(text.count, caretIndex + 1) }
            setNeedsLayout(); return true
        case .keyboardHome: caretIndex = 0; isAllSelected = false; setNeedsLayout(); return true
        case .keyboardEnd: caretIndex = text.count; isAllSelected = false; setNeedsLayout(); return true
        default: break
        }
        if event.isPrintable {
            insert(event.characters)
            return true
        }
        return onUnhandledKey?(event) ?? false
    }

    func insert(_ s: String) {
        if isAllSelected { replaceAll(with: s); return }
        text.insert(contentsOf: s, at: text.index(text.startIndex, offsetBy: caretIndex))
        caretIndex += s.count
        setNeedsLayout()
    }

    func replaceAll(with s: String) {
        isAllSelected = false
        text = s
        caretIndex = s.count
        setNeedsLayout()
    }

    private func wordBoundary(backward: Bool) -> Int {
        let chars = Array(text)
        var i = caretIndex
        if backward {
            while i > 0, chars[i - 1] == " " { i -= 1 }
            while i > 0, chars[i - 1] != " " { i -= 1 }
        } else {
            while i < chars.count, chars[i] == " " { i += 1 }
            while i < chars.count, chars[i] != " " { i += 1 }
        }
        return i
    }

    private func deleteWordBackward() {
        let target = wordBoundary(backward: true)
        let start = text.index(text.startIndex, offsetBy: target)
        let end = text.index(text.startIndex, offsetBy: caretIndex)
        text.removeSubrange(start..<end)
        caretIndex = target
    }
}

// MARK: - Popup menu

struct MenuItem {
    var title: String
    var symbol: String? = nil
    var shortcut: String? = nil
    var isEnabled = true
    var isSeparator = false
    var isChecked = false
    var action: (() -> Void)? = nil

    static let separator = MenuItem(title: "", isSeparator: true)
}

/// A floating list of actions used for menu-bar menus, context menus and dock menus.
final class PopupMenuView: UIView, PointerTarget {

    var onDismiss: (() -> Void)?
    private let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemThickMaterialDark))
    private let stack = UIStackView()
    private var highlightedIndex: Int?
    private var buttons: [DeskButton] = []
    let items: [MenuItem]

    init(items: [MenuItem], minWidth: CGFloat = 220) {
        self.items = items
        super.init(frame: .zero)
        addSubview(blur)
        blur.layer.cornerRadius = 9
        blur.clipsToBounds = true
        layer.cornerRadius = 9
        layer.borderWidth = 0.5
        layer.borderColor = Theme.border.cgColor
        applyPanelShadow(radius: 22, opacity: 0.5)
        stack.axis = .vertical
        stack.spacing = 1
        blur.contentView.addSubview(stack)

        var width = minWidth
        for item in items {
            if item.isSeparator {
                let sep = UIView()
                sep.backgroundColor = Theme.separator
                sep.heightAnchor.constraint(equalToConstant: 1).isActive = true
                let wrap = UIView()
                wrap.addSubview(sep)
                sep.pin(to: wrap, insets: UIEdgeInsets(top: 4, left: 10, bottom: 4, right: 10))
                stack.addArrangedSubview(wrap)
                continue
            }
            let b = DeskButton(title: item.title, symbol: item.isChecked ? "checkmark" : item.symbol, style: .menuItem)
            b.isEnabled = item.isEnabled
            b.shortcutText = item.shortcut
            b.contentInsets = UIEdgeInsets(top: 4, left: item.isChecked || item.symbol != nil ? 8 : 26, bottom: 4, right: 10)
            b.onTap = { [weak self] in
                self?.onDismiss?()
                item.action?()
            }
            buttons.append(b)
            stack.addArrangedSubview(b)
            b.heightAnchor.constraint(equalToConstant: 26).isActive = true
            width = max(width, b.intrinsicContentSize.width + 16)
        }
        let height = stack.arrangedSubviews.reduce(CGFloat(0)) { $0 + ($1 is DeskButton ? 26 : 9) } + CGFloat(stack.arrangedSubviews.count - 1)
        frame = CGRect(x: 0, y: 0, width: width, height: height + 10)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        blur.frame = bounds
        stack.frame = bounds.insetBy(dx: 5, dy: 5)
    }

    /// Keyboard navigation (arrows + enter) while the menu is open.
    func key(_ event: KeyEvent) -> Bool {
        guard event.isDown else { return true }
        switch event.keyCode {
        case .keyboardDownArrow: moveHighlight(1); return true
        case .keyboardUpArrow: moveHighlight(-1); return true
        case .keyboardReturnOrEnter, .keypadEnter:
            if let i = highlightedIndex { buttons[i].onTap?() }
            return true
        default: return false
        }
    }

    private func moveHighlight(_ delta: Int) {
        guard !buttons.isEmpty else { return }
        let next = ((highlightedIndex ?? -1) + delta + buttons.count) % buttons.count
        if let i = highlightedIndex { buttons[i].pointerExited() }
        highlightedIndex = next
        buttons[next].pointerEntered()
    }

    func pointer(_ event: PointerEvent, local: CGPoint) {}
}

// MARK: - Toast

/// A transient message shown near the top of the desktop ("Copied", JavaScript alerts, …).
final class ToastView: UIView {
    private let label = UILabel()
    private let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemThickMaterialDark))

    init(text: String) {
        super.init(frame: .zero)
        addSubview(blur)
        blur.contentView.addSubview(label)
        layer.cornerRadius = 12
        clipsToBounds = true
        blur.layer.cornerRadius = 12
        label.text = text
        label.textColor = Theme.text
        label.font = Theme.font(13, weight: .medium)
        label.numberOfLines = 3
        label.textAlignment = .center
        let size = label.sizeThatFits(CGSize(width: 480, height: 200))
        frame = CGRect(x: 0, y: 0, width: size.width + 36, height: size.height + 22)
        applyPanelShadow(radius: 14, opacity: 0.4)
        layer.masksToBounds = false
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        blur.frame = bounds
        label.frame = bounds.insetBy(dx: 18, dy: 11)
    }
}
