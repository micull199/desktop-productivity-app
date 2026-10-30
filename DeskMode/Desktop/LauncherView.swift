import UIKit

/// Spotlight-style launcher (⌘Space): open apps, search the web or jump to a URL.
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

        var subtitle: String {
            switch self {
            case .app: return "Application"
            case .search: return Settings.shared.searchEngine.title
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

    private let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemThickMaterialDark))
    private let field = DeskTextField()
    private let resultsStack = UIStackView()
    private let focusGroup = FocusGroup()
    private var results: [Result] = []
    private var buttons: [DeskButton] = []
    private var selectedIndex = 0

    override init(frame: CGRect) {
        super.init(frame: CGRect(x: 0, y: 0, width: 680, height: 64))
        addSubview(blur)
        blur.layer.cornerRadius = 14
        blur.clipsToBounds = true
        layer.cornerRadius = 14
        layer.borderWidth = 0.5
        layer.borderColor = Theme.border.cgColor
        applyPanelShadow(radius: 40, opacity: 0.6, offset: CGSize(width: 0, height: 20))

        field.font = Theme.font(24, weight: .regular)
        field.placeholder = "Search apps, the web or type a URL"
        field.leadingSymbol = "magnifyingglass"
        field.showsBackground = false
        field.focusGroup = focusGroup
        field.insets = UIEdgeInsets(top: 0, left: 18, bottom: 0, right: 18)
        field.onChange = { [weak self] _ in self?.refreshResults() }
        field.onSubmit = { [weak self] _ in self?.activateSelected() }
        field.onEscape = { [weak self] in self?.onDismiss?() }
        field.onUnhandledKey = { [weak self] event in
            guard let self else { return false }
            switch event.keyCode {
            case .keyboardDownArrow: self.select(self.selectedIndex + 1); return true
            case .keyboardUpArrow: self.select(self.selectedIndex - 1); return true
            default: return false
            }
        }
        blur.contentView.addSubview(field)

        resultsStack.axis = .vertical
        resultsStack.spacing = 2
        blur.contentView.addSubview(resultsStack)
        refreshResults()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        blur.frame = bounds
        field.frame = CGRect(x: 8, y: 6, width: bounds.width - 16, height: 52)
        let h = CGFloat(buttons.count) * 46 + CGFloat(max(0, buttons.count - 1)) * 2
        resultsStack.frame = CGRect(x: 10, y: 66, width: bounds.width - 20, height: h)
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
            list = DeskApp.allCases.filter { $0.title.lowercased().hasPrefix(query.lowercased()) }.map { .app($0) }
            if let url = URLGuess.url(from: query) { list.append(.url(url)) }
            list.append(.search(query))
        }
        results = list
        selectedIndex = 0
        rebuild()
    }

    private func rebuild() {
        for b in buttons { resultsStack.removeArrangedSubview(b); b.removeFromSuperview() }
        buttons = []
        for (i, r) in results.enumerated() {
            let b: DeskButton
            if case .app(let app) = r {
                b = DeskButton(title: r.title, style: .list)
                b.image = app.icon(size: 28)
            } else {
                b = DeskButton(title: r.title, symbol: r.symbol, style: .list)
                b.iconPointSize = 18
            }
            b.subtitle = r.subtitle
            b.isSelected = i == selectedIndex
            b.onTap = { [weak self] in self?.select(i); self?.activateSelected() }
            b.heightAnchor.constraint(equalToConstant: 46).isActive = true
            buttons.append(b)
            resultsStack.addArrangedSubview(b)
        }
        let h = CGFloat(buttons.count) * 46 + CGFloat(max(0, buttons.count - 1)) * 2
        frame.size.height = 66 + h + (buttons.isEmpty ? 0 : 10)
        setNeedsLayout()
    }

    private func select(_ index: Int) {
        guard !results.isEmpty else { return }
        selectedIndex = (index + results.count) % results.count
        for (i, b) in buttons.enumerated() { b.isSelected = i == selectedIndex }
    }

    private func activateSelected() {
        guard results.indices.contains(selectedIndex) else { return }
        onSelect?(results[selectedIndex])
    }

    func pointer(_ event: PointerEvent, local: CGPoint) {}
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
    static func resolve(_ text: String) -> URL {
        url(from: text) ?? Settings.shared.searchEngine.searchURL(for: text)
    }
}
