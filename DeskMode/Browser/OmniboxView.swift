import UIKit

// MARK: - Omnibox

/// Chrome's address bar: a 32 pt pill with a site-info glyph, the URL (host emphasised while
/// unfocused, plain editable text while focused) and a bookmark star.
final class OmniboxView: UIView, PointerTarget {

    enum SiteMode { case newTab, secure, insecure, local }

    var onSubmit: ((String) -> Void)?
    /// Fired only for text the user typed or pasted, not for programmatic updates.
    var onTextChange: ((String) -> Void)?
    var onEscape: (() -> Void)?
    var onFocusChange: ((Bool) -> Void)?
    /// Up (-1) / down (+1) arrows while focused, for the suggestion list.
    var onArrow: ((Int) -> Void)?
    var onToggleBookmark: (() -> Void)?
    var onButtonHover: ((BrowserIconButton, Bool) -> Void)?

    var focusGroup: FocusGroup? { didSet { field.focusGroup = focusGroup } }

    var hasFocus: Bool { field.hasFocus }
    var text: String { field.text }

    var isBookmarked = false {
        didSet {
            guard isBookmarked != oldValue else { return }
            star.symbolName = isBookmarked ? "star.fill" : "star"
            star.isAccented = isBookmarked
            star.tooltip = isBookmarked ? "Edit bookmark (⌘D)" : "Bookmark this tab (⌘D)"
        }
    }

    private let ring = UIView()
    private let background = UIView()
    private let siteIcon = UIImageView()
    private let field = DeskTextField()
    private let display = UILabel()
    private let star = BrowserIconButton(symbol: "star", pointSize: 14)
    private var mode: SiteMode = .newTab
    private var displayURL = ""
    private var suppressChange = false
    private var hovered = false

    private static let height: CGFloat = Theme.Size.controlLarge
    private static let radius: CGFloat = Theme.Size.controlLarge / 2

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(ring)
        addSubview(background)
        addSubview(siteIcon)
        addSubview(display)
        addSubview(field)
        addSubview(star)

        ring.isUserInteractionEnabled = false
        ring.layer.cornerRadius = Self.radius + 1.5
        ring.layer.cornerCurve = .continuous
        ring.layer.borderWidth = 2
        ring.layer.borderColor = Theme.focusRing.cgColor
        ring.layer.shadowColor = Theme.accent.cgColor
        ring.layer.shadowOpacity = 0.35
        ring.layer.shadowRadius = 6
        ring.layer.shadowOffset = .zero
        ring.alpha = 0

        background.isUserInteractionEnabled = false
        background.layer.cornerRadius = Self.radius
        background.layer.cornerCurve = .continuous
        background.layer.borderWidth = Theme.Size.hairline

        siteIcon.contentMode = .center
        siteIcon.tintColor = Theme.secondaryText
        siteIcon.isUserInteractionEnabled = false

        display.font = Theme.font(Theme.Text.callout)
        display.textColor = Theme.text
        display.lineBreakMode = .byTruncatingTail
        display.isUserInteractionEnabled = false

        field.showsBackground = false
        field.font = Theme.font(Theme.Text.callout)
        field.selectsAllOnFocus = true
        field.insets = .zero
        field.isHidden = true
        field.onChange = { [weak self] t in
            guard let self, !self.suppressChange, self.field.hasFocus else { return }
            self.onTextChange?(t)
        }
        field.onSubmit = { [weak self] t in self?.onSubmit?(t) }
        field.onEscape = { [weak self] in self?.onEscape?() }
        field.onFocusChange = { [weak self] focused in self?.focusDidChange(focused) }
        field.onUnhandledKey = { [weak self] event in
            guard let self else { return false }
            switch event.keyCode {
            case .keyboardUpArrow: self.onArrow?(-1); return true
            case .keyboardDownArrow: self.onArrow?(1); return true
            default: return false
            }
        }

        star.pointSize = 14
        star.onTap = { [weak self] in self?.onToggleBookmark?() }
        star.onHover = { [weak self] b, h in self?.onButtonHover?(b, h) }
        star.tooltip = "Bookmark this tab (⌘D)"
        refresh()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: Self.height) }

    override func layoutSubviews() {
        super.layoutSubviews()
        background.frame = bounds
        ring.frame = bounds.insetBy(dx: -1.5, dy: -1.5)
        ring.layer.shadowPath = UIBezierPath(roundedRect: ring.bounds, cornerRadius: Self.radius + 1.5).cgPath
        siteIcon.frame = CGRect(x: Theme.Space.s, y: 0, width: 24, height: bounds.height)
        let starSize: CGFloat = Theme.Size.control
        star.frame = CGRect(x: bounds.width - starSize - Theme.Space.xxs, y: (bounds.height - starSize) / 2, width: starSize, height: starSize)
        let textX = siteIcon.frame.maxX + Theme.Space.xs
        let textRight = star.isHidden ? bounds.width - Theme.Space.m : star.frame.minX - Theme.Space.xs
        let textFrame = CGRect(x: textX, y: 0, width: max(0, textRight - textX), height: bounds.height)
        display.frame = textFrame
        field.frame = textFrame
    }

    // MARK: State

    func setURL(_ url: String, mode: SiteMode) {
        guard url != displayURL || mode != self.mode else { return }
        self.mode = mode
        displayURL = url
        star.isHidden = mode == .newTab
        siteIcon.image = UIImage.symbol(Self.symbol(for: mode), size: 12, weight: .medium)?.withRenderingMode(.alwaysTemplate)
        if !field.hasFocus {
            setFieldText(url)
            updateDisplay()
        }
        setNeedsLayout()
    }

    func focus() { field.requestFocus() }

    /// Replaces the text without triggering `onTextChange` (used when arrowing through suggestions).
    func setText(_ s: String) { setFieldText(s) }

    /// Puts the current page URL back and ends editing (Escape).
    func restoreDisplay() {
        setFieldText(displayURL)
        updateDisplay()
    }

    private func setFieldText(_ s: String) {
        suppressChange = true
        field.replaceAll(with: s)
        suppressChange = false
    }

    private func focusDidChange(_ focused: Bool) {
        field.isHidden = !focused
        display.isHidden = focused
        if !focused { setFieldText(displayURL); updateDisplay() }
        refresh()
        onFocusChange?(focused)
    }

    private func updateDisplay() {
        if displayURL.isEmpty {
            display.attributedText = nil
            display.text = "Search \(Settings.shared.searchEngine.title) or type a URL"
            display.textColor = Theme.tertiaryText
            return
        }
        display.textColor = Theme.text
        display.attributedText = Self.styledURL(displayURL)
    }

    /// Host in `Theme.text`; scheme, path and query in `Theme.secondaryText`.
    static func styledURL(_ string: String) -> NSAttributedString {
        var shown = string
        if let u = URL(string: string), u.path == "/" || u.path.isEmpty, u.query == nil, u.fragment == nil, shown.hasSuffix("/") { shown.removeLast() }
        let font = Theme.font(Theme.Text.callout)
        let result = NSMutableAttributedString(string: shown, attributes: [.font: font, .foregroundColor: Theme.secondaryText])
        if let host = URL(string: string)?.host, let range = shown.range(of: host) {
            result.addAttribute(.foregroundColor, value: Theme.text, range: NSRange(range, in: shown))
        } else {
            result.addAttribute(.foregroundColor, value: Theme.text, range: NSRange(location: 0, length: result.length))
        }
        return result
    }

    private static func symbol(for mode: SiteMode) -> String {
        switch mode {
        case .newTab: return "magnifyingglass"
        case .secure: return "lock.fill"
        case .insecure: return "info.circle"
        case .local: return "doc"
        }
    }

    private func refresh() {
        let focused = field.hasFocus
        let fill: UIColor = focused ? Theme.sidebarBackground : (hovered ? Theme.elevatedBackground : Theme.windowBackground)
        Theme.Motion.animate(Theme.Motion.fast) {
            self.background.backgroundColor = fill
            self.background.layer.borderColor = (focused ? UIColor.clear : Theme.separator).cgColor
            self.ring.alpha = focused ? 1 : 0
        }
    }

    // MARK: PointerTarget

    func pointer(_ event: PointerEvent, local: CGPoint) {
        if case .down(.left) = event.kind, !field.hasFocus { field.requestFocus() }
    }

    func pointerEntered() { hovered = true; refresh() }
    func pointerExited() { hovered = false; refresh() }
    func cursorStyle(at local: CGPoint) -> CursorStyle { local.x > siteIcon.frame.maxX ? .iBeam : .arrow }
}

// MARK: - Suggestions

enum OmniboxSuggestion {
    /// What the user typed, resolved to a URL or a search.
    case typed(text: String, url: URL, isSearch: Bool)
    case history(HistoryEntry)
    case search(String)

    /// Text placed in the omnibox when the row is highlighted with the arrow keys.
    var fillText: String {
        switch self {
        case .typed(let text, _, _): return text
        case .history(let e): return e.url
        case .search(let q): return q
        }
    }

    @MainActor var url: URL {
        switch self {
        case .typed(_, let url, _): return url
        case .history(let e): return URL(string: e.url) ?? Settings.shared.searchEngine.searchURL(for: e.url)
        case .search(let q): return Settings.shared.searchEngine.searchURL(for: q)
        }
    }

    var symbol: String {
        switch self {
        case .typed(_, _, let isSearch): return isSearch ? "magnifyingglass" : "globe"
        case .history: return "clock"
        case .search: return "magnifyingglass"
        }
    }
}

/// One row of the suggestion dropdown.
final class SuggestionRow: UIView, PointerTarget {

    var onClick: (() -> Void)?
    var onHover: ((Bool) -> Void)?
    var isSelected = false { didSet { refresh() } }
    private(set) var isHovered = false

    private let fill = UIView()
    private let icon = UIImageView()
    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(fill)
        addSubview(icon)
        addSubview(label)
        fill.layer.cornerRadius = Theme.Radius.control
        fill.layer.cornerCurve = .continuous
        fill.isUserInteractionEnabled = false
        icon.contentMode = .center
        icon.tintColor = Theme.secondaryText
        label.font = Theme.font(Theme.Text.body)
        label.lineBreakMode = .byTruncatingTail
        refresh()
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(_ s: OmniboxSuggestion) {
        icon.image = UIImage.symbol(s.symbol, size: 13, weight: .regular)?.withRenderingMode(.alwaysTemplate)
        let primary: [NSAttributedString.Key: Any] = [.font: Theme.font(Theme.Text.body), .foregroundColor: Theme.text]
        let secondary: [NSAttributedString.Key: Any] = [.font: Theme.font(Theme.Text.body), .foregroundColor: Theme.secondaryText]
        let text = NSMutableAttributedString()
        switch s {
        case .typed(let t, _, let isSearch):
            text.append(NSAttributedString(string: t, attributes: primary))
            if isSearch { text.append(NSAttributedString(string: " — \(Settings.shared.searchEngine.title) Search", attributes: secondary)) }
        case .history(let e):
            text.append(NSAttributedString(string: e.title, attributes: primary))
            text.append(NSAttributedString(string: " — \(BrowserHistory.bareURL(e.url))", attributes: secondary))
        case .search(let q):
            text.append(NSAttributedString(string: q, attributes: primary))
            text.append(NSAttributedString(string: " — \(Settings.shared.searchEngine.title) Search", attributes: secondary))
        }
        label.attributedText = text
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        fill.frame = bounds.insetBy(dx: Theme.Space.s, dy: 0)
        icon.frame = CGRect(x: Theme.Space.l, y: 0, width: 20, height: bounds.height)
        label.frame = CGRect(x: icon.frame.maxX + Theme.Space.s, y: 0, width: bounds.width - icon.frame.maxX - Theme.Space.s - Theme.Space.l, height: bounds.height)
    }

    private func refresh() {
        let color: UIColor = isSelected ? Theme.controlBackgroundHover : (isHovered ? Theme.hoverOverlay : .clear)
        Theme.Motion.animate(Theme.Motion.instant) { self.fill.backgroundColor = color }
    }

    func pointer(_ event: PointerEvent, local: CGPoint) {
        if case .up(.left) = event.kind, bounds.contains(local) { onClick?() }
    }

    func pointerEntered() { isHovered = true; refresh(); onHover?(true) }
    func pointerExited() { isHovered = false; refresh(); onHover?(false) }
    func cursorStyle(at local: CGPoint) -> CursorStyle { .arrow }
}

/// The dropdown under the omnibox: up to eight rows on a menu material.
final class OmniboxSuggestionsView: UIView {

    static let rowHeight: CGFloat = 36
    static let maxRows = 8
    private static let padding: CGFloat = Theme.Space.s

    var onSelect: ((Int) -> Void)?

    private(set) var items: [OmniboxSuggestion] = []
    private(set) var selectedIndex: Int?

    private let material = Theme.materialView(.menu, cornerRadius: Theme.Radius.menu)
    private var rows: [SuggestionRow] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(material)
        layer.cornerRadius = Theme.Radius.menu
        layer.cornerCurve = .continuous
        layer.borderWidth = Theme.Size.hairline
        layer.borderColor = Theme.border.cgColor
        applyShadow(.menu)
    }

    required init?(coder: NSCoder) { fatalError() }

    var preferredHeight: CGFloat {
        CGFloat(items.count) * Self.rowHeight + Self.padding * 2
    }

    func setItems(_ newItems: [OmniboxSuggestion]) {
        items = Array(newItems.prefix(Self.maxRows))
        while rows.count > items.count { rows.removeLast().removeFromSuperview() }
        while rows.count < items.count {
            let row = SuggestionRow()
            let index = rows.count
            row.onClick = { [weak self] in self?.onSelect?(index) }
            rows.append(row)
            material.contentView.addSubview(row)
        }
        for (i, row) in rows.enumerated() {
            row.configure(items[i])
            row.isSelected = i == selectedIndex
        }
        if let s = selectedIndex, !items.indices.contains(s) { selectedIndex = nil }
        setNeedsLayout()
    }

    func select(_ index: Int?) {
        selectedIndex = index.flatMap { items.indices.contains($0) ? $0 : nil }
        for (i, row) in rows.enumerated() { row.isSelected = i == selectedIndex }
    }

    /// Moves the keyboard highlight; wraps past the ends to "nothing selected" like Chrome.
    @discardableResult
    func moveSelection(_ delta: Int) -> OmniboxSuggestion? {
        guard !items.isEmpty else { return nil }
        let next: Int?
        if let s = selectedIndex {
            let n = s + delta
            next = items.indices.contains(n) ? n : nil
        } else {
            next = delta > 0 ? 0 : items.count - 1
        }
        select(next)
        return next.map { items[$0] }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        material.frame = bounds
        for (i, row) in rows.enumerated() {
            row.frame = CGRect(x: 0, y: Self.padding + CGFloat(i) * Self.rowHeight, width: bounds.width, height: Self.rowHeight)
        }
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: Theme.Radius.menu).cgPath
    }
}
