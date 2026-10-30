import UIKit

/// One Chrome-style tab: the active tab is a rounded-top card with curved "feet" that joins the
/// toolbar; inactive tabs are flat text with a hover fill and a hairline separator.
final class TabButton: UIView, PointerTarget {

    static let cardRadius: CGFloat = 8

    var onSelect: (() -> Void)?
    var onClose: (() -> Void)?
    var onRightClick: ((CGPoint) -> Void)?
    var onHoverChange: (() -> Void)?

    var isActive = false { didSet { if isActive != oldValue { refresh() } } }
    var isWindowFocused = true { didSet { refresh() } }
    var showsSeparator = false { didSet { separator.isHidden = !showsSeparator || isActive || isHovered } }
    var title: String = "" { didSet { if title != oldValue { label.text = title; setNeedsLayout() } } }
    var isLoading = false { didSet { if isLoading != oldValue { refresh() } } }
    var favicon: UIImage? { didSet { faviconView.image = favicon ?? FaviconCache.placeholder } }

    private(set) var isHovered = false

    private let shape = CAShapeLayer()
    private let faviconView = UIImageView()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let label = UILabel()
    private let fade = CAGradientLayer()
    private let closeButton = BrowserIconButton(symbol: "xmark", pointSize: 9)
    private let separator = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.masksToBounds = false
        layer.insertSublayer(shape, at: 0)
        addSubview(separator)
        addSubview(faviconView)
        addSubview(spinner)
        addSubview(label)
        addSubview(closeButton)

        shape.fillColor = UIColor.clear.cgColor
        faviconView.contentMode = .scaleAspectFit
        faviconView.layer.cornerRadius = 2
        faviconView.clipsToBounds = true
        faviconView.image = FaviconCache.placeholder
        spinner.color = Theme.secondaryText
        spinner.transform = CGAffineTransform(scaleX: 0.65, y: 0.65)
        spinner.hidesWhenStopped = true
        label.font = Theme.font(Theme.Text.footnote)
        label.textColor = Theme.secondaryText
        label.lineBreakMode = .byClipping
        fade.startPoint = CGPoint(x: 0, y: 0.5)
        fade.endPoint = CGPoint(x: 1, y: 0.5)
        label.layer.mask = fade
        closeButton.weight = .semibold
        closeButton.tooltip = "Close tab"
        closeButton.onTap = { [weak self] in self?.onClose?() }
        separator.backgroundColor = Theme.border
        separator.isHidden = true
        refresh()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        let h = bounds.height, w = bounds.width
        let r = Self.cardRadius

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shape.frame = bounds.insetBy(dx: -r, dy: 0)
        shape.path = Self.cardPath(width: w, height: h, radius: r).cgPath
        CATransaction.commit()

        separator.frame = CGRect(x: w - Theme.Size.hairline, y: (h - 16) / 2, width: Theme.Size.hairline, height: 16)

        let compact = w < 96
        let iconSize: CGFloat = 16
        let iconX: CGFloat = compact ? max(Theme.Space.s, (w - iconSize - (closeVisible ? 22 : 0)) / 2) : Theme.Space.m
        faviconView.frame = CGRect(x: iconX, y: (h - iconSize) / 2, width: iconSize, height: iconSize)
        spinner.frame = faviconView.frame

        let closeSize: CGFloat = 18
        closeButton.frame = CGRect(x: w - closeSize - Theme.Space.s + 1, y: (h - closeSize) / 2, width: closeSize, height: closeSize)

        let textX = faviconView.frame.maxX + Theme.Space.s
        let textRight = closeVisible ? closeButton.frame.minX - Theme.Space.xs : w - Theme.Space.m
        let textWidth = max(0, textRight - textX)
        label.frame = CGRect(x: textX, y: 0, width: textWidth, height: h)
        label.isHidden = compact || textWidth < 18

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fade.frame = label.bounds
        let fadeStart = textWidth > 0 ? max(0, 1 - 18 / textWidth) : 1
        fade.colors = [UIColor.black.cgColor, UIColor.black.cgColor, UIColor.clear.cgColor]
        fade.locations = [0, NSNumber(value: Double(fadeStart)), 1]
        CATransaction.commit()
    }

    private var closeVisible: Bool { isActive || (isHovered && bounds.width >= 72) }

    /// Rounded-top tab outline with concave feet at the bottom corners, like Chrome on the Mac.
    /// Drawn in a layer that extends `radius` beyond the tab on both sides.
    static func cardPath(width w: CGFloat, height h: CGFloat, radius r: CGFloat) -> UIBezierPath {
        let p = UIBezierPath()
        // Coordinates are in the extended layer: the tab body spans x = r … r + w.
        p.move(to: CGPoint(x: 0, y: h))
        p.addQuadCurve(to: CGPoint(x: r, y: h - r), controlPoint: CGPoint(x: r, y: h))
        p.addLine(to: CGPoint(x: r, y: r))
        p.addQuadCurve(to: CGPoint(x: 2 * r, y: 0), controlPoint: CGPoint(x: r, y: 0))
        p.addLine(to: CGPoint(x: w, y: 0))
        p.addQuadCurve(to: CGPoint(x: w + r, y: r), controlPoint: CGPoint(x: w + r, y: 0))
        p.addLine(to: CGPoint(x: w + r, y: h - r))
        p.addQuadCurve(to: CGPoint(x: w + 2 * r, y: h), controlPoint: CGPoint(x: w + r, y: h))
        p.close()
        return p
    }

    private func refresh() {
        let toolbarColor = isWindowFocused ? Theme.titleBarBackground : Theme.titleBarBackgroundInactive
        let fill: UIColor = isActive ? toolbarColor : (isHovered ? Theme.hoverOverlay : .clear)
        let textColor: UIColor = isActive ? Theme.text : (isHovered ? Theme.text : Theme.secondaryText)
        Theme.Motion.animate(Theme.Motion.fast) {
            self.shape.fillColor = fill.cgColor
            self.label.textColor = self.isWindowFocused ? textColor : Theme.secondaryText
            self.faviconView.alpha = self.isWindowFocused || self.isActive ? 1 : 0.7
        }
        closeButton.isHidden = !closeVisible
        separator.isHidden = !showsSeparator || isActive || isHovered
        if isLoading {
            faviconView.isHidden = true
            spinner.startAnimating()
        } else {
            faviconView.isHidden = false
            spinner.stopAnimating()
        }
        setNeedsLayout()
    }

    // MARK: PointerTarget

    func pointer(_ event: PointerEvent, local: CGPoint) {
        switch event.kind {
        case .down(.left): if !isActive { onSelect?() }
        case .up(.middle): onClose?()
        case .down(.right): onRightClick?(local)
        default: break
        }
    }

    func pointerEntered() {
        isHovered = true
        refresh()
        onHoverChange?()
    }

    func pointerExited() {
        isHovered = false
        refresh()
        onHoverChange?()
    }

    func cursorStyle(at local: CGPoint) -> CursorStyle { .arrow }
}

/// The tab row at the top of a browser window. Not a `PointerTarget` itself: clicks on empty
/// strip reach the window, so the strip doubles as the drag handle like Chrome's title bar.
final class TabStripView: UIView {

    struct Item {
        var title: String
        var isLoading: Bool
        var favicon: UIImage?
    }

    /// Space reserved on the left for the window's traffic lights.
    static let leadingInset: CGFloat = 80
    static let minTabWidth: CGFloat = 64
    static let maxTabWidth: CGFloat = 240
    static let tabTop: CGFloat = 6

    var onSelect: ((Int) -> Void)?
    var onClose: ((Int) -> Void)?
    var onNewTab: (() -> Void)?
    var onTabContextMenu: ((Int, CGPoint) -> Void)?
    var onButtonHover: ((BrowserIconButton, Bool) -> Void)?

    var isWindowFocused = true {
        didSet {
            backgroundColor = isWindowFocused ? Theme.sidebarBackground : Theme.windowBackground
            for b in buttons { b.isWindowFocused = isWindowFocused }
        }
    }

    private var buttons: [TabButton] = []
    private var activeIndex = 0
    private let newTabButton = BrowserIconButton(symbol: "plus", pointSize: 13)

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = Theme.sidebarBackground
        addSubview(newTabButton)
        newTabButton.tooltip = "New tab (⌘T)"
        newTabButton.onTap = { [weak self] in self?.onNewTab?() }
        newTabButton.onHover = { [weak self] b, h in self?.onButtonHover?(b, h) }
    }

    required init?(coder: NSCoder) { fatalError() }

    func update(items: [Item], activeIndex: Int) {
        let countChanged = items.count != buttons.count
        while buttons.count > items.count {
            let b = buttons.removeLast()
            Theme.Motion.animate(Theme.Motion.fast, animations: { b.alpha = 0 }) { _ in b.removeFromSuperview() }
        }
        while buttons.count < items.count {
            let b = TabButton()
            let index = buttons.count
            b.isWindowFocused = isWindowFocused
            b.onSelect = { [weak self] in self?.onSelect?(index) }
            b.onClose = { [weak self] in self?.onClose?(index) }
            b.onRightClick = { [weak self, weak b] p in
                guard let self, let b else { return }
                self.onTabContextMenu?(index, b.convert(p, to: self))
            }
            b.onHoverChange = { [weak self] in self?.updateSeparators() }
            // New tabs grow out of the "+" button.
            b.frame = CGRect(x: newTabButton.frame.minX, y: Self.tabTop, width: 0, height: bounds.height - Self.tabTop)
            b.alpha = 0
            buttons.append(b)
            insertSubview(b, belowSubview: newTabButton)
        }
        self.activeIndex = activeIndex
        for (i, b) in buttons.enumerated() {
            b.title = items[i].title
            b.isLoading = items[i].isLoading
            b.favicon = items[i].favicon
            b.isActive = i == activeIndex
        }
        updateSeparators()
        // The active card sits above its neighbours so its feet overlap them.
        if buttons.indices.contains(activeIndex) { bringSubviewToFront(buttons[activeIndex]) }
        bringSubviewToFront(newTabButton)
        if countChanged {
            setNeedsLayout()
            Theme.Motion.animate(Theme.Motion.normal) { self.layoutIfNeeded() }
        } else {
            setNeedsLayout()
        }
    }

    private func updateSeparators() {
        for (i, b) in buttons.enumerated() {
            let next = i + 1 < buttons.count ? buttons[i + 1] : nil
            let nextBlocks = next.map { $0.isActive || $0.isHovered } ?? true
            b.showsSeparator = !b.isActive && !b.isHovered && !nextBlocks
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let h = bounds.height - Self.tabTop
        let trailing = Theme.Size.control + Theme.Space.s * 2
        let available = max(0, bounds.width - Self.leadingInset - trailing)
        let count = CGFloat(max(1, buttons.count))
        let w = min(Self.maxTabWidth, max(Self.minTabWidth, floor(available / count)))
        var x = Self.leadingInset
        for b in buttons {
            b.frame = CGRect(x: x, y: Self.tabTop, width: w, height: h)
            b.alpha = 1
            x += w
        }
        let btn = Theme.Size.control
        newTabButton.frame = CGRect(x: x + Theme.Space.xs, y: Self.tabTop + (h - btn) / 2, width: btn, height: btn)
    }
}
