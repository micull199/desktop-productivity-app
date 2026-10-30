import UIKit

/// One tab in the tab strip.
final class TabButton: UIView, PointerTarget {

    var onSelect: (() -> Void)?
    var onClose: (() -> Void)?
    var onMiddleClick: (() -> Void)?
    var onRightClick: ((CGPoint) -> Void)?

    var isActive = false { didSet { refresh() } }
    var title: String = "" { didSet { label.text = title } }
    var isLoading = false { didSet { refresh() } }

    private let background = UIView()
    private let label = UILabel()
    private let closeButton = DeskButton(symbol: "xmark", style: .toolbar)
    private let spinner = UIActivityIndicatorView(style: .medium)
    private var hovered = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(background)
        addSubview(spinner)
        addSubview(label)
        addSubview(closeButton)
        background.layer.cornerRadius = 7
        label.font = Theme.font(12.5)
        label.textColor = Theme.text
        label.lineBreakMode = .byTruncatingTail
        closeButton.iconPointSize = 9
        closeButton.contentInsets = .zero
        closeButton.onTap = { [weak self] in self?.onClose?() }
        spinner.color = Theme.secondaryText
        spinner.transform = CGAffineTransform(scaleX: 0.7, y: 0.7)
        spinner.hidesWhenStopped = true
        refresh()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        background.frame = bounds
        closeButton.frame = CGRect(x: 6, y: (bounds.height - 18) / 2, width: 18, height: 18)
        spinner.frame = CGRect(x: 6, y: (bounds.height - 18) / 2, width: 18, height: 18)
        label.frame = CGRect(x: 28, y: 0, width: bounds.width - 36, height: bounds.height)
    }

    private func refresh() {
        background.backgroundColor = isActive ? UIColor(white: 1, alpha: 0.14) : (hovered ? UIColor(white: 1, alpha: 0.07) : .clear)
        label.textColor = isActive ? Theme.text : Theme.secondaryText
        closeButton.isHidden = isLoading || !(hovered || isActive)
        if isLoading { spinner.startAnimating() } else { spinner.stopAnimating() }
    }

    func pointer(_ event: PointerEvent, local: CGPoint) {
        switch event.kind {
        case .up(.left): if bounds.contains(local) { onSelect?() }
        case .up(.middle): onMiddleClick?()
        case .down(.right): onRightClick?(local)
        default: break
        }
    }

    func pointerEntered() { hovered = true; refresh() }
    func pointerExited() { hovered = false; refresh() }
}

/// Horizontal strip of tabs plus a "new tab" button.
final class TabStripView: UIView, PointerTarget {

    var onSelect: ((Int) -> Void)?
    var onClose: ((Int) -> Void)?
    var onNewTab: (() -> Void)?
    var onTabContextMenu: ((Int, CGPoint) -> Void)?

    private var buttons: [TabButton] = []
    private let newTabButton = DeskButton(symbol: "plus", style: .toolbar)

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(white: 0, alpha: 0.18)
        addSubview(newTabButton)
        newTabButton.iconPointSize = 12
        newTabButton.onTap = { [weak self] in self?.onNewTab?() }
    }

    required init?(coder: NSCoder) { fatalError() }

    func update(titles: [String], loading: [Bool], activeIndex: Int) {
        while buttons.count > titles.count { buttons.removeLast().removeFromSuperview() }
        while buttons.count < titles.count {
            let b = TabButton()
            let index = buttons.count
            b.onSelect = { [weak self] in self?.onSelect?(index) }
            b.onClose = { [weak self] in self?.onClose?(index) }
            b.onMiddleClick = { [weak self] in self?.onClose?(index) }
            b.onRightClick = { [weak self, weak b] p in
                guard let self, let b else { return }
                self.onTabContextMenu?(index, b.convert(p, to: self))
            }
            buttons.append(b)
            addSubview(b)
        }
        for (i, b) in buttons.enumerated() {
            b.title = titles[i]
            b.isActive = i == activeIndex
            b.isLoading = loading[i]
        }
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let available = bounds.width - 44
        let w = min(220, max(90, available / CGFloat(max(1, buttons.count))))
        var x: CGFloat = 8
        for b in buttons {
            b.frame = CGRect(x: x, y: 5, width: w - 4, height: bounds.height - 10)
            x += w
        }
        newTabButton.frame = CGRect(x: x + 2, y: (bounds.height - 24) / 2, width: 26, height: 24)
    }

    func pointer(_ event: PointerEvent, local: CGPoint) {
        if case .up(.left) = event.kind, event.clickCount == 2 { onNewTab?() }
    }
}
