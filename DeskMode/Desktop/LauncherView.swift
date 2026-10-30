import UIKit

/// Spotlight-style launcher (⌘Space): open apps, search the web or jump to a URL.
///
/// 640 pt wide: a 64 pt search field on top and 44 pt result rows below. The desktop positions
/// it horizontally centred with its top at 22 % of the screen and animates it in and out.
final class LauncherView: UIView, PointerTarget {

    enum Result {
        case app(DeskApp)
        case search(String)
        case url(URL)

        var title: String {
            switch self {
            case .app(let a): return a.title
            case .search(let q): return "Search for “\(q)”"
            case .url(let u): return "Open \(u.absoluteString)"
            }
        }

        @MainActor var subtitle: String {
            switch self {
            case .app: return "Application"
            case .search: return "Search with \(Settings.shared.searchEngine.title)"
            case .url: return "Website"
            }
        }

        var symbol: String {
            switch self {
            case .app(let a): return a.symbolName
            case .search: return "magnifyingglass"
            case .url: return "globe"
            }
        }
    }

    var onSelect: ((Result) -> Void)?
    var onDismiss: (() -> Void)?

    private let material = Theme.materialView(.panel, cornerRadius: Theme.Radius.panel)
    private let field = DeskTextField()
    private let divider = UIView()
    private let focusGroup = FocusGroup()
    private var results: [Result] = []
    private var rows: [LauncherRowView] = []
    private var selectedIndex = 0

    private static let rowInset: CGFloat = Theme.Space.s
    private static let listPaddingTop: CGFloat = Theme.Space.s - 2
    private static let listPaddingBottom: CGFloat = Theme.Space.s

    override init(frame: CGRect) {
        super.init(frame: CGRect(x: 0, y: 0, width: Theme.Size.launcherWidth, height: Theme.Size.launcherField))
        addSubview(material)
        material.layer.borderWidth = Theme.Size.hairline
        material.layer.borderColor = Theme.border.cgColor
        layer.cornerRadius = Theme.Radius.panel
        layer.cornerCurve = .continuous
        applyShadow(.panel)

        field.font = Theme.font(Theme.Text.launcherField, weight: .regular)
        field.placeholder = "Search apps, the web or type a URL"
        field.leadingSymbol = "magnifyingglass"
        field.leadingSymbolPointSize = Theme.Text.launcherIconSymbol
        field.showsBackground = false
        field.focusGroup = focusGroup
        field.insets = UIEdgeInsets(top: 0, left: Theme.Space.l + 2, bottom: 0, right: Theme.Space.l + 2)
        field.onChange = { [weak self] _ in self?.refreshResults() }
        field.onSubmit = { [weak self] _ in self?.activateSelected() }
        field.onEscape = { [weak self] in self?.onDismiss?() }
        field.onUnhandledKey = { [weak self] event in
            guard let self else { return false }
            switch event.keyCode {
            case .keyboardDownArrow: self.select(self.selectedIndex + 1); return true
            case .keyboardUpArrow: self.select(self.selectedIndex - 1); return true
            case .keyboardTab: self.select(self.selectedIndex + (event.shift ? -1 : 1)); return true
            default: return false
            }
        }
        material.contentView.addSubview(field)

        divider.backgroundColor = Theme.separator
        divider.isHidden = true
        material.contentView.addSubview(divider)
        refreshResults()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        material.frame = bounds
        field.frame = CGRect(x: 0, y: 0, width: bounds.width, height: Theme.Size.launcherField)
        divider.frame = CGRect(x: 0, y: Theme.Size.launcherField, width: bounds.width, height: Theme.Size.hairline)
        var y = Theme.Size.launcherField + Theme.Size.hairline + Self.listPaddingTop
        for row in rows {
            row.frame = CGRect(x: Self.rowInset, y: y, width: bounds.width - Self.rowInset * 2, height: Theme.Size.listRow)
            y += Theme.Size.listRow
        }
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: Theme.Radius.panel).cgPath
    }

    private var preferredHeight: CGFloat {
        guard !rows.isEmpty else { return Theme.Size.launcherField }
        return Theme.Size.launcherField + Theme.Size.hairline + Self.listPaddingTop + CGFloat(rows.count) * Theme.Size.listRow + Self.listPaddingBottom
    }

    func activate() {
        field.replaceAll(with: "")
        focusGroup.focus(field)
        refreshResults()
    }

    func key(_ event: KeyEvent) -> Bool {
        if event.isDown, event.isEscape { onDismiss?(); return true }
        return focusGroup.key(event)
    }

    private func refreshResults() {
        let query = field.text.trimmingCharacters(in: .whitespaces)
        var list: [Result] = []
        if query.isEmpty {
            list = DeskApp.allCases.map { .app($0) }
        } else {
            let q = query.lowercased()
            list = DeskApp.allCases.filter { $0.title.lowercased().hasPrefix(q) || $0.rawValue.hasPrefix(q) }.map { .app($0) }
            if let url = URLGuess.url(from: query) { list.append(.url(url)) }
            list.append(.search(query))
        }
        results = list
        selectedIndex = 0
        rebuild()
    }

    private func rebuild() {
        for r in rows { r.removeFromSuperview() }
        rows = []
        for (i, result) in results.enumerated() {
            let row = LauncherRowView(result: result)
            row.isSelected = i == selectedIndex
            row.onTap = { [weak self] in self?.select(i); self?.activateSelected() }
            rows.append(row)
            material.contentView.addSubview(row)
        }
        divider.isHidden = rows.isEmpty
        let height = preferredHeight
        if bounds.height != height {
            frame.size.height = height
        }
        setNeedsLayout()
    }

    private func select(_ index: Int) {
        guard !results.isEmpty else { return }
        selectedIndex = (index + results.count) % results.count
        for (i, r) in rows.enumerated() { r.isSelected = i == selectedIndex }
    }

    private func activateSelected() {
        guard results.indices.contains(selectedIndex) else { return }
        onSelect?(results[selectedIndex])
    }

    func pointer(_ event: PointerEvent, local: CGPoint) {}
}

/// One launcher result: a 32 pt icon (app icon, or a symbol in a rounded tile), a 14 pt title
/// and a 12 pt subtitle. The selected row is filled with the accent colour.
final class LauncherRowView: UIView, PointerTarget {

    var onTap: (() -> Void)?
    var isSelected = false { didSet { if isSelected != oldValue { refresh() } } }

    private let highlight = UIView()
    private let iconView = UIImageView()
    private let tile = UIView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private var hovered = false
    private var pressed = false
    private let usesTile: Bool

    init(result: LauncherView.Result) {
        if case .app = result { usesTile = false } else { usesTile = true }
        super.init(frame: .zero)
        addSubview(highlight)
        highlight.layer.cornerRadius = Theme.Radius.field
        highlight.layer.cornerCurve = .continuous
        highlight.isUserInteractionEnabled = false

        if case .app(let app) = result {
            iconView.image = app.icon(size: Theme.Size.launcherIcon * 2)
            iconView.contentMode = .scaleAspectFit
            addSubview(iconView)
        } else {
            tile.backgroundColor = Theme.controlBackground
            tile.layer.cornerRadius = Theme.Radius.field
            tile.layer.cornerCurve = .continuous
            tile.layer.borderWidth = Theme.Size.hairline
            tile.layer.borderColor = Theme.border.cgColor
            iconView.image = UIImage.symbol(result.symbol, size: Theme.Text.launcherIconSymbol, weight: .medium)
            iconView.contentMode = .center
            iconView.tintColor = Theme.text
            tile.addSubview(iconView)
            addSubview(tile)
        }

        titleLabel.text = result.title
        titleLabel.font = Theme.font(Theme.Text.callout)
        titleLabel.textColor = Theme.text
        titleLabel.lineBreakMode = .byTruncatingMiddle
        subtitleLabel.text = result.subtitle
        subtitleLabel.font = Theme.font(Theme.Text.footnote)
        subtitleLabel.textColor = Theme.secondaryText
        addSubview(titleLabel)
        addSubview(subtitleLabel)
        refresh(animated: false)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        highlight.frame = bounds
        let icon = Theme.Size.launcherIcon
        let iconFrame = CGRect(x: Theme.Space.m, y: (bounds.height - icon) / 2, width: icon, height: icon)
        if usesTile {
            tile.frame = iconFrame
            iconView.frame = tile.bounds
        } else {
            iconView.frame = iconFrame
        }
        let x = iconFrame.maxX + Theme.Space.m
        let w = bounds.width - x - Theme.Space.m
        let th = titleLabel.font.lineHeight
        let sh = subtitleLabel.font.lineHeight
        let top = (bounds.height - th - sh) / 2
        titleLabel.frame = CGRect(x: x, y: top, width: w, height: th)
        subtitleLabel.frame = CGRect(x: x, y: top + th, width: w, height: sh)
    }

    private func refresh(animated: Bool = true) {
        let apply = { [self] in
            if isSelected {
                highlight.backgroundColor = pressed ? Theme.accentPressed : Theme.accent
                titleLabel.textColor = Theme.textOnAccent
                subtitleLabel.textColor = Theme.textOnSelectionSecondary
                if usesTile {
                    tile.backgroundColor = UIColor.white.withAlphaComponent(0.18)
                    tile.layer.borderColor = UIColor.clear.cgColor
                    iconView.tintColor = Theme.textOnAccent
                }
            } else {
                highlight.backgroundColor = pressed ? Theme.pressedOverlay : (hovered ? Theme.hoverOverlay : .clear)
                titleLabel.textColor = Theme.text
                subtitleLabel.textColor = Theme.secondaryText
                if usesTile {
                    tile.backgroundColor = Theme.controlBackground
                    tile.layer.borderColor = Theme.border.cgColor
                    iconView.tintColor = Theme.text
                }
            }
        }
        if animated, window != nil {
            Theme.Motion.animate(Theme.Motion.fast, animations: apply)
        } else {
            apply()
        }
    }

    func pointer(_ event: PointerEvent, local: CGPoint) {
        switch event.kind {
        case .down(.left):
            pressed = true
            refresh()
        case .up(.left):
            let inside = bounds.contains(local)
            pressed = false
            refresh()
            if inside { onTap?() }
        default:
            break
        }
    }

    func pointerEntered() { hovered = true; refresh() }
    func pointerExited() { hovered = false; pressed = false; refresh() }
}

/// Decides whether typed text is a URL or a search query, like a browser's address bar.
enum URLGuess {
    static func url(from text: String) -> URL? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !t.contains(" ") else { return nil }
        if t.hasPrefix("http://") || t.hasPrefix("https://") || t.hasPrefix("file://") || t.hasPrefix("about:") {
            return URL(string: t)
        }
        if t == "localhost" || t.hasPrefix("localhost:") { return URL(string: "http://" + t) }
        let host = t.split(separator: "/").first.map(String.init) ?? t
        let hostOnly = host.split(separator: ":").first.map(String.init) ?? host
        let parts = hostOnly.split(separator: ".")
        guard parts.count >= 2, let tld = parts.last, tld.count >= 2, tld.allSatisfy({ $0.isLetter }) || hostOnly.allSatisfy({ $0.isNumber || $0 == "." }) else {
            return nil
        }
        return URL(string: "https://" + t)
    }

    /// Resolves address-bar input to a URL, falling back to the configured search engine.
    @MainActor static func resolve(_ text: String) -> URL {
        url(from: text) ?? Settings.shared.searchEngine.searchURL(for: text)
    }
}
