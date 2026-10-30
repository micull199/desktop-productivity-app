import UIKit

// MARK: - Button

/// A pointer-driven button with hover and pressed states. Works without touch input.
final class DeskButton: UIView, PointerTarget {

    enum Style {
        case plain        // transparent, highlight on hover (menu-bar titles, traffic lights)
        case toolbar      // small rounded icon button
        case primary      // accent filled
        case menuItem     // full-width row inside a popup menu
        case list         // full-width row inside a sidebar list
        case pill         // 24 pt capsule with text
    }

    var onTap: (() -> Void)?
    var onRightClick: ((CGPoint) -> Void)?
    var onDoubleClick: (() -> Void)?
    /// Called when the cursor enters (`true`) or leaves (`false`) the button.
    var onHoverChange: ((Bool) -> Void)?

    var isEnabled = true { didSet { refresh() } }
    /// Traffic lights and other custom-drawn buttons turn this off.
    var showsHoverHighlight = true { didSet { refresh() } }
    var isSelected = false { didSet { refresh() } }
    var tintOverride: UIColor? { didSet { refresh() } }
    /// Shown by the desktop after the cursor rests on the button (see `PointerTarget`).
    var tooltipText: String?

    var title: String? {
        get { label.text }
        set { label.text = newValue; invalidateIntrinsicContentSize(); setNeedsLayout() }
    }

    var subtitle: String? {
        get { subtitleLabel.text }
        set { subtitleLabel.text = newValue; subtitleLabel.isHidden = (newValue ?? "").isEmpty; invalidateIntrinsicContentSize(); setNeedsLayout() }
    }

    var symbolName: String? {
        didSet { updateIcon() }
    }
    var image: UIImage? {
        didSet { icon.image = image; icon.isHidden = image == nil; invalidateIntrinsicContentSize(); setNeedsLayout() }
    }

    var font: UIFont {
        get { label.font }
        set { label.font = newValue; invalidateIntrinsicContentSize(); setNeedsLayout() }
    }

    var shortcutText: String? {
        get { shortcutLabel.text }
        set { shortcutLabel.text = newValue; shortcutLabel.isHidden = (newValue ?? "").isEmpty; invalidateIntrinsicContentSize(); setNeedsLayout() }
    }

    /// When set, the icon occupies a fixed-width column whether or not an icon is present, so
    /// titles in a list of rows line up (used by popup menus).
    var iconColumnWidth: CGFloat? { didSet { invalidateIntrinsicContentSize(); setNeedsLayout() } }

    private(set) var isHovered = false

    let style: Style
    private let highlight = UIView()
    private let label = UILabel()
    private let subtitleLabel = UILabel()
    private let shortcutLabel = UILabel()
    private let icon = UIImageView()
    private var pressed = false
    var iconPointSize: CGFloat = 14 { didSet { updateIcon() } }
    var contentInsets = UIEdgeInsets(top: 4, left: Theme.Space.m - 2, bottom: 4, right: Theme.Space.m - 2) {
        didSet { invalidateIntrinsicContentSize(); setNeedsLayout() }
    }

    init(title: String? = nil, symbol: String? = nil, style: Style = .plain) {
        self.style = style
        super.init(frame: .zero)
        addSubview(highlight)
        addSubview(icon)
        addSubview(label)
        addSubview(subtitleLabel)
        addSubview(shortcutLabel)
        highlight.isUserInteractionEnabled = false
        highlight.layer.cornerCurve = .continuous
        icon.contentMode = .center
        icon.isHidden = true
        label.text = title
        label.font = Theme.font(Theme.Text.body, weight: style == .primary ? .semibold : .regular)
        label.textColor = Theme.text
        label.lineBreakMode = .byTruncatingTail
        subtitleLabel.font = Theme.font(Theme.Text.caption)
        subtitleLabel.textColor = Theme.secondaryText
        subtitleLabel.isHidden = true
        shortcutLabel.font = Theme.font(Theme.Text.footnote)
        shortcutLabel.textColor = Theme.secondaryText
        shortcutLabel.isHidden = true
        shortcutLabel.textAlignment = .right
        symbolName = symbol
        switch style {
        case .plain:
            highlight.layer.cornerRadius = Theme.Radius.menuBarItem
        case .toolbar:
            highlight.layer.cornerRadius = Theme.Radius.control
            contentInsets = UIEdgeInsets(top: 4, left: 6, bottom: 4, right: 6)
        case .primary:
            highlight.layer.cornerRadius = Theme.Radius.control
            contentInsets = UIEdgeInsets(top: 4, left: Theme.Space.l, bottom: 4, right: Theme.Space.l)
        case .menuItem:
            highlight.layer.cornerRadius = Theme.Radius.menuBarItem
            contentInsets = UIEdgeInsets(top: 4, left: Theme.Space.s, bottom: 4, right: Theme.Space.m - 2)
        case .list:
            highlight.layer.cornerRadius = Theme.Radius.field
            contentInsets = UIEdgeInsets(top: 6, left: Theme.Space.m - 2, bottom: 6, right: Theme.Space.m - 2)
        case .pill:
            highlight.layer.cornerRadius = Theme.Radius.pill
            contentInsets = UIEdgeInsets(top: 3, left: Theme.Space.m, bottom: 3, right: Theme.Space.m)
        }
        updateIcon()
        refresh(animated: false)
    }

    required init?(coder: NSCoder) { fatalError() }

    private func updateIcon() {
        guard let symbolName else {
            if image == nil { icon.isHidden = true }
            invalidateIntrinsicContentSize()
            return
        }
        icon.image = UIImage.symbol(symbolName, size: iconPointSize, weight: .medium)
        icon.isHidden = false
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    private var iconSlotWidth: CGFloat {
        if let iconColumnWidth { return iconColumnWidth }
        return icon.isHidden ? 0 : iconPointSize + Theme.Space.s
    }

    override var intrinsicContentSize: CGSize {
        let labelSize = label.text?.isEmpty == false ? label.intrinsicContentSize : .zero
        let iconW = iconSlotWidth
        let gap: CGFloat = (iconW > 0 && labelSize.width > 0) ? 6 : 0
        let shortcutW: CGFloat = shortcutLabel.isHidden ? 0 : shortcutLabel.intrinsicContentSize.width + Theme.Space.xl
        let subtitleH: CGFloat = subtitleLabel.isHidden ? 0 : subtitleLabel.intrinsicContentSize.height
        let h = max(labelSize.height + subtitleH, icon.isHidden ? 0 : iconPointSize + Theme.Space.s) + contentInsets.top + contentInsets.bottom
        return CGSize(width: iconW + gap + labelSize.width + shortcutW + contentInsets.left + contentInsets.right, height: max(h, Theme.Size.controlSmall))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        highlight.frame = bounds
        var x = contentInsets.left
        let iconW = iconSlotWidth
        if iconW > 0 {
            icon.frame = CGRect(x: x, y: 0, width: iconW, height: bounds.height)
            x += iconW + (label.text?.isEmpty == false ? 6 : 0)
        }
        var right = bounds.width - contentInsets.right
        if !shortcutLabel.isHidden {
            let w = shortcutLabel.intrinsicContentSize.width
            shortcutLabel.frame = CGRect(x: right - w, y: 0, width: w, height: bounds.height)
            right -= w + Theme.Space.l
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

    private func refresh(animated: Bool = true) {
        let tint = tintOverride ?? Theme.text
        let apply = { [self] in
            alpha = isEnabled ? 1 : Theme.disabledAlpha
            label.textColor = tint
            icon.tintColor = tint
            switch style {
            case .primary:
                highlight.backgroundColor = pressed ? Theme.accentPressed : (isHovered ? Theme.accentHover : Theme.accent)
                label.textColor = Theme.textOnAccent
                icon.tintColor = Theme.textOnAccent
            case .menuItem:
                let lit = isHovered && isEnabled
                highlight.backgroundColor = lit ? Theme.accent : .clear
                label.textColor = lit ? Theme.textOnAccent : tint
                shortcutLabel.textColor = lit ? Theme.textOnSelectionSecondary : Theme.secondaryText
                icon.tintColor = lit ? Theme.textOnAccent : tint
            case .list:
                highlight.backgroundColor = isSelected ? Theme.accent : (isHovered ? Theme.hoverOverlay : .clear)
                label.textColor = isSelected ? Theme.textOnAccent : tint
                subtitleLabel.textColor = isSelected ? Theme.textOnSelectionSecondary : Theme.secondaryText
                icon.tintColor = isSelected ? Theme.textOnAccent : tint
            case .pill:
                if isSelected {
                    highlight.backgroundColor = pressed ? Theme.accentPressed : (isHovered ? Theme.accentHover : Theme.accent)
                } else {
                    highlight.backgroundColor = pressed ? Theme.controlBackgroundPressed : (isHovered ? Theme.controlBackgroundHover : Theme.controlBackground)
                }
                label.textColor = isSelected ? Theme.textOnAccent : tint
                icon.tintColor = isSelected ? Theme.textOnAccent : tint
            case .plain, .toolbar:
                if !showsHoverHighlight {
                    // Menu-bar titles and traffic lights: no hover fill, but an open menu still shows.
                    highlight.backgroundColor = isSelected ? Theme.pressedOverlay : .clear
                } else if isSelected {
                    highlight.backgroundColor = Theme.pressedOverlay
                } else {
                    highlight.backgroundColor = pressed ? Theme.pressedOverlay : (isHovered ? Theme.hoverOverlay : .clear)
                }
            }
        }
        if animated, window != nil {
            Theme.Motion.animate(Theme.Motion.fast, animations: apply)
        } else {
            apply()
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

    func pointerEntered() { isHovered = true; refresh(); onHoverChange?(true) }
    func pointerExited() { isHovered = false; pressed = false; refresh(); onHoverChange?(false) }
    func cursorStyle(at local: CGPoint) -> CursorStyle { .arrow }
}

// MARK: - Toggle

/// A macOS-style switch: 38 × 22, 18 pt knob, spring animated.
final class DeskToggle: UIView, PointerTarget {

    var isOn: Bool { didSet { animateKnob() } }
    var onChange: ((Bool) -> Void)?
    var tooltipText: String?

    private let track = UIView()
    private let knob = UIView()
    private var hovered = false
    private var pressed = false

    init(isOn: Bool) {
        self.isOn = isOn
        super.init(frame: CGRect(x: 0, y: 0, width: Theme.Size.toggleWidth, height: Theme.Size.toggleHeight))
        addSubview(track)
        track.addSubview(knob)
        track.layer.cornerCurve = .continuous
        knob.backgroundColor = .white
        knob.layer.cornerCurve = .continuous
        knob.layer.shadowColor = UIColor.black.cgColor
        knob.layer.shadowOpacity = 0.3
        knob.layer.shadowRadius = 2
        knob.layer.shadowOffset = CGSize(width: 0, height: 1)
        animateKnob(animated: false)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: CGSize { CGSize(width: Theme.Size.toggleWidth, height: Theme.Size.toggleHeight) }

    override func layoutSubviews() {
        super.layoutSubviews()
        track.frame = bounds
        track.layer.cornerRadius = bounds.height / 2
        animateKnob(animated: false)
    }

    private var knobFrame: CGRect {
        let inset = (bounds.height - Theme.Size.toggleKnob) / 2
        let size = bounds.height - inset * 2
        let x = isOn ? bounds.width - size - inset : inset
        return CGRect(x: x, y: inset, width: size, height: size)
    }

    private func animateKnob(animated: Bool = true) {
        let apply = { [self] in
            if isOn {
                track.backgroundColor = pressed ? Theme.accentPressed : (hovered ? Theme.accentHover : Theme.accent)
            } else {
                track.backgroundColor = hovered || pressed ? Theme.toggleOffTrackHover : Theme.toggleOffTrack
            }
            let f = knobFrame
            knob.frame = pressed ? f.insetBy(dx: -1, dy: 0).offsetBy(dx: isOn ? -1 : 1, dy: 0) : f
            knob.layer.cornerRadius = knob.bounds.height / 2
            knob.layer.shadowPath = UIBezierPath(roundedRect: knob.bounds, cornerRadius: knob.bounds.height / 2).cgPath
        }
        if animated, window != nil {
            Theme.Motion.spring(Theme.Motion.normal, animations: apply)
        } else {
            apply()
        }
    }

    func pointer(_ event: PointerEvent, local: CGPoint) {
        switch event.kind {
        case .down(.left):
            pressed = true
            animateKnob()
        case .up(.left):
            pressed = false
            if bounds.insetBy(dx: -Theme.Space.xs, dy: -Theme.Space.xs).contains(local) {
                isOn.toggle()
                onChange?(isOn)
            } else {
                animateKnob()
            }
        default:
            break
        }
    }

    func pointerEntered() { hovered = true; animateKnob() }
    func pointerExited() { hovered = false; pressed = false; animateKnob() }
    func cursorStyle(at local: CGPoint) -> CursorStyle { .arrow }
}

// MARK: - Text field

/// A single-line text field that is edited through the desktop's own key routing rather than
/// UIKit's first-responder system (which would try to show the keyboard on the wrong screen).
final class DeskTextField: UIView, PointerTarget, Focusable {

    var text: String = "" { didSet { caretIndex = min(caretIndex, text.count); onChange?(text); setNeedsLayout() } }
    var placeholder: String = "" { didSet { setNeedsLayout() } }
    var font: UIFont = Theme.font(Theme.Text.body) { didSet { label.font = font; placeholderLabel.font = font; setNeedsLayout() } }
    var textAlignment: NSTextAlignment = .left { didSet { setNeedsLayout() } }
    var leadingSymbol: String? { didSet { updateLeadingIcon() } }
    /// Point size of `leadingSymbol` (12 by default; the launcher uses 18).
    var leadingSymbolPointSize: CGFloat = 12 { didSet { updateLeadingIcon() } }
    var selectsAllOnFocus = false
    var showsBackground = true { didSet { refresh() } }
    var tooltipText: String?

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
    private var hovered = false

    private let background = UIView()
    private let label = UILabel()
    private let placeholderLabel = UILabel()
    private let leadingIcon = UIImageView()
    private let selectionView = UIView()
    private let caret = UIView()
    private let clip = UIView()
    private var scrollOffset: CGFloat = 0
    private var blinkTimer: Timer?
    var insets = UIEdgeInsets(top: 0, left: Theme.Space.m - 2, bottom: 0, right: Theme.Space.m - 2) { didSet { setNeedsLayout() } }

    private static let caretWidth: CGFloat = 1.5

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
        background.layer.cornerRadius = Theme.Radius.field
        background.layer.cornerCurve = .continuous
        background.isUserInteractionEnabled = false
        leadingIcon.contentMode = .center
        leadingIcon.tintColor = Theme.secondaryText
        label.font = font
        label.textColor = Theme.text
        placeholderLabel.font = font
        placeholderLabel.textColor = Theme.tertiaryText
        selectionView.backgroundColor = Theme.selection
        selectionView.layer.cornerRadius = 2
        selectionView.isHidden = true
        caret.backgroundColor = Theme.caret
        caret.layer.cornerRadius = Self.caretWidth / 2
        caret.isHidden = true
        refresh(animated: false)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: Theme.Size.control) }

    private func updateLeadingIcon() {
        leadingIcon.image = leadingSymbol.flatMap { UIImage.symbol($0, size: leadingSymbolPointSize) }
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        background.frame = bounds
        var left = insets.left
        if leadingSymbol != nil {
            let w = leadingSymbolPointSize + Theme.Space.s
            leadingIcon.frame = CGRect(x: insets.left, y: 0, width: w, height: bounds.height)
            left = insets.left + w + 6
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
        placeholderLabel.frame = CGRect(x: 0, y: 0, width: clip.bounds.width, height: bounds.height)
        placeholderLabel.textAlignment = textAlignment
        let lineHeight = font.lineHeight + 4
        let textTop = (bounds.height - lineHeight) / 2
        selectionView.frame = CGRect(x: -scrollOffset - 1, y: textTop, width: textWidth + 2, height: lineHeight)
        selectionView.isHidden = !(isAllSelected && hasFocus && !text.isEmpty)
        caret.frame = CGRect(x: caretX - scrollOffset, y: textTop + 1, width: Self.caretWidth, height: lineHeight - 2)
    }

    private func refresh(animated: Bool = true) {
        let apply = { [self] in
            background.isHidden = !showsBackground
            if hasFocus {
                background.backgroundColor = Theme.accentSoft
                background.layer.borderWidth = 2
                background.layer.borderColor = Theme.focusRing.cgColor
            } else {
                background.backgroundColor = hovered ? Theme.controlBackgroundHover : Theme.controlBackground
                background.layer.borderWidth = Theme.Size.hairline
                background.layer.borderColor = (hovered ? Theme.borderStrong : Theme.border).cgColor
            }
        }
        if animated, window != nil {
            Theme.Motion.animate(Theme.Motion.fast, animations: apply)
        } else {
            apply()
        }
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
        blinkTimer = Timer.scheduledTimer(withTimeInterval: Theme.Timing.caretBlink, repeats: true) { [weak self] _ in
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

    func pointerEntered() { hovered = true; refresh() }
    func pointerExited() { hovered = false; refresh() }
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
            case "c": UIPasteboard.general.string = text; return true
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
///
/// Rows are `Theme.Size.menuRow` tall with a fixed icon column so titles line up, shortcuts are
/// right-aligned, separators are hairlines and disabled rows are dimmed. Arrow keys and Return
/// work while the menu is open; the desktop handles Escape and clicks outside.
final class PopupMenuView: UIView, PointerTarget {

    var onDismiss: (() -> Void)?
    private let material = Theme.materialView(.menu, cornerRadius: Theme.Radius.menu)
    private let stack = UIStackView()
    private var highlightedIndex: Int?
    private var buttons: [DeskButton] = []
    let items: [MenuItem]

    init(items: [MenuItem], minWidth: CGFloat = 220) {
        self.items = items
        super.init(frame: .zero)
        addSubview(material)
        layer.cornerRadius = Theme.Radius.menu
        layer.cornerCurve = .continuous
        material.layer.borderWidth = Theme.Size.hairline
        material.layer.borderColor = Theme.border.cgColor
        applyShadow(.menu)
        stack.axis = .vertical
        stack.spacing = 0
        material.contentView.addSubview(stack)

        let inset = Theme.Size.menuInset
        let row = Theme.Size.menuRow
        let separatorHeight = Theme.Size.hairline + Theme.Space.xs * 2
        var width = minWidth
        var height: CGFloat = 0
        for item in items {
            if item.isSeparator {
                let wrap = UIView()
                let sep = UIView()
                sep.backgroundColor = Theme.separator
                wrap.addSubview(sep)
                sep.pin(to: wrap, insets: UIEdgeInsets(top: Theme.Space.xs, left: Theme.Space.s + 2, bottom: Theme.Space.xs, right: Theme.Space.s + 2))
                sep.heightAnchor.constraint(equalToConstant: Theme.Size.hairline).isActive = true
                stack.addArrangedSubview(wrap)
                height += separatorHeight
                continue
            }
            let b = DeskButton(title: item.title, symbol: item.isChecked ? "checkmark" : item.symbol, style: .menuItem)
            b.iconPointSize = item.isChecked ? 11 : 13
            b.iconColumnWidth = Theme.Size.menuIconColumn
            b.isEnabled = item.isEnabled
            b.shortcutText = item.shortcut
            let index = buttons.count
            b.onTap = { [weak self] in
                self?.onDismiss?()
                item.action?()
            }
            b.onHoverChange = { [weak self] on in self?.rowHovered(index, on) }
            buttons.append(b)
            stack.addArrangedSubview(b)
            b.heightAnchor.constraint(equalToConstant: row).isActive = true
            height += row
            width = max(width, b.intrinsicContentSize.width + inset * 2)
        }
        frame = CGRect(x: 0, y: 0, width: ceil(width), height: height + inset * 2)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        material.frame = bounds
        stack.frame = bounds.insetBy(dx: Theme.Size.menuInset, dy: Theme.Size.menuInset)
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: Theme.Radius.menu).cgPath
    }

    private func rowHovered(_ index: Int, _ on: Bool) {
        if on {
            if let i = highlightedIndex, i != index { buttons[i].pointerExited() }
            highlightedIndex = index
        } else if highlightedIndex == index {
            highlightedIndex = nil
        }
    }

    /// Keyboard navigation (arrows + enter) while the menu is open.
    func key(_ event: KeyEvent) -> Bool {
        guard event.isDown else { return true }
        switch event.keyCode {
        case .keyboardDownArrow: moveHighlight(1); return true
        case .keyboardUpArrow: moveHighlight(-1); return true
        case .keyboardReturnOrEnter, .keypadEnter:
            if let i = highlightedIndex, buttons[i].isEnabled { buttons[i].onTap?() }
            return true
        default: return false
        }
    }

    private func moveHighlight(_ delta: Int) {
        guard buttons.contains(where: { $0.isEnabled }) else { return }
        var next = highlightedIndex ?? (delta > 0 ? -1 : buttons.count)
        repeat {
            next = (next + delta + buttons.count) % buttons.count
        } while !buttons[next].isEnabled
        if let i = highlightedIndex, i != next { buttons[i].pointerExited() }
        highlightedIndex = next
        buttons[next].pointerEntered()
    }

    func pointer(_ event: PointerEvent, local: CGPoint) {}
}

// MARK: - Toast

/// A notification-style card ("Copied", JavaScript alerts, zoom level…). The desktop stacks
/// these in the top-right corner and slides them in from the right.
final class ToastView: UIView {
    private let label = UILabel()
    private let iconView = UIImageView()
    private let material = Theme.materialView(.menu, cornerRadius: Theme.Radius.toast)
    private let hasIcon: Bool

    private static let maxWidth: CGFloat = 360
    private static let padding = UIEdgeInsets(top: Theme.Space.m, left: Theme.Space.l, bottom: Theme.Space.m, right: Theme.Space.l)
    private static let iconSize: CGFloat = 18

    convenience init(text: String) {
        self.init(text: text, symbol: nil)
    }

    init(text: String, symbol: String?) {
        hasIcon = symbol != nil
        super.init(frame: .zero)
        addSubview(material)
        material.contentView.addSubview(iconView)
        material.contentView.addSubview(label)
        layer.cornerRadius = Theme.Radius.toast
        layer.cornerCurve = .continuous
        material.layer.borderWidth = Theme.Size.hairline
        material.layer.borderColor = Theme.border.cgColor
        label.text = text
        label.textColor = Theme.text
        label.font = Theme.font(Theme.Text.body, weight: .medium)
        label.numberOfLines = 3
        label.textAlignment = .left
        if let symbol {
            iconView.image = UIImage.symbol(symbol, size: Self.iconSize, weight: .medium)
            iconView.tintColor = Theme.accentText
            iconView.contentMode = .center
        }
        let iconSpace: CGFloat = hasIcon ? Self.iconSize + Theme.Space.m : 0
        let textMax = Self.maxWidth - Self.padding.left - Self.padding.right - iconSpace
        let size = label.sizeThatFits(CGSize(width: textMax, height: 200))
        frame = CGRect(x: 0, y: 0,
                       width: ceil(size.width) + Self.padding.left + Self.padding.right + iconSpace,
                       height: max(ceil(size.height) + Self.padding.top + Self.padding.bottom, Theme.Size.listRow))
        applyShadow(.menu)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        material.frame = bounds
        var x = Self.padding.left
        if hasIcon {
            iconView.frame = CGRect(x: x, y: 0, width: Self.iconSize, height: bounds.height)
            x += Self.iconSize + Theme.Space.m
        }
        label.frame = CGRect(x: x, y: Self.padding.top, width: bounds.width - x - Self.padding.right, height: bounds.height - Self.padding.top - Self.padding.bottom)
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: Theme.Radius.toast).cgPath
    }
}
