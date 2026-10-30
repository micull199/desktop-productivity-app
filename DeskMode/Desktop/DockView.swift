import UIKit

/// A single icon in the Dock.
final class DockItemView: UIView, PointerTarget {

    var onTap: (() -> Void)?
    var onRightClick: ((CGPoint) -> Void)?
    var onHover: ((Bool) -> Void)?
    var isRunning = false { didSet { dot.isHidden = !isRunning } }
    let tooltip: String

    private let imageView = UIImageView()
    private let dot = UIView()
    private var pressed = false

    init(image: UIImage, tooltip: String) {
        self.tooltip = tooltip
        super.init(frame: CGRect(x: 0, y: 0, width: 56, height: 64))
        imageView.image = image
        imageView.contentMode = .scaleAspectFit
        addSubview(imageView)
        dot.backgroundColor = UIColor(white: 1, alpha: 0.8)
        dot.layer.cornerRadius = 2
        dot.isHidden = true
        addSubview(dot)
    }

    required init?(coder: NSCoder) { fatalError() }

    // The Dock measures its stack with Auto Layout; without this the items compress to zero width.
    override var intrinsicContentSize: CGSize { CGSize(width: 56, height: 64) }

    override func layoutSubviews() {
        super.layoutSubviews()
        imageView.frame = CGRect(x: 4, y: 2, width: bounds.width - 8, height: bounds.width - 8)
        dot.frame = CGRect(x: bounds.midX - 2, y: bounds.height - 6, width: 4, height: 4)
    }

    func pointer(_ event: PointerEvent, local: CGPoint) {
        switch event.kind {
        case .down(.left):
            pressed = true
            UIView.animate(withDuration: 0.1) { self.imageView.alpha = 0.6 }
        case .up(.left):
            UIView.animate(withDuration: 0.1) { self.imageView.alpha = 1 }
            if pressed, bounds.insetBy(dx: -6, dy: -6).contains(local) { onTap?() }
            pressed = false
        case .down(.right):
            onRightClick?(local)
        default: break
        }
    }

    func pointerEntered() { onHover?(true) }
    func pointerExited() { onHover?(false); pressed = false; imageView.alpha = 1 }
}

/// The Dock: launch and switch between apps, restore minimized windows.
final class DockView: UIView {

    var onOpenApp: ((DeskApp) -> Void)?
    var onNewWindow: ((DeskApp) -> Void)?
    var onCloseApp: ((DeskApp) -> Void)?
    var onRestoreWindow: ((DesktopWindowView) -> Void)?
    var onLauncher: (() -> Void)?
    var presentMenu: ((PopupMenuView, CGRect) -> Void)?

    private let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterialDark))
    private let stack = UIStackView()
    private var appItems: [DeskApp: DockItemView] = [:]
    private var windowItems: [DockItemView] = []
    private let separator = UIView()
    private let tooltipLabel = UILabel()
    private let tooltipBackground = UIVisualEffectView(effect: UIBlurEffect(style: .systemThickMaterialDark))

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(blur)
        blur.layer.cornerRadius = 20
        blur.clipsToBounds = true
        blur.layer.borderWidth = 0.5
        blur.layer.borderColor = Theme.border.cgColor
        applyPanelShadow(radius: 20, opacity: 0.45)
        blur.contentView.addSubview(stack)
        stack.axis = .horizontal
        stack.alignment = .bottom
        stack.spacing = 6

        let launcher = DockItemView(image: launcherIcon(), tooltip: "Launcher")
        launcher.onTap = { [weak self] in self?.onLauncher?() }
        launcher.onHover = { [weak self, weak launcher] on in self?.hover(launcher, on) }
        stack.addArrangedSubview(launcher)

        for app in DeskApp.allCases {
            let item = DockItemView(image: app.icon(size: 112), tooltip: app.title)
            item.onTap = { [weak self] in self?.onOpenApp?(app) }
            item.onHover = { [weak self, weak item] on in self?.hover(item, on) }
            item.onRightClick = { [weak self, weak item] _ in self?.showMenu(for: app, item: item) }
            appItems[app] = item
            stack.addArrangedSubview(item)
        }

        separator.backgroundColor = Theme.separator
        separator.isHidden = true
        stack.addArrangedSubview(separator)
        separator.widthAnchor.constraint(equalToConstant: 1).isActive = true
        separator.heightAnchor.constraint(equalToConstant: 48).isActive = true

        addSubview(tooltipBackground)
        tooltipBackground.layer.cornerRadius = 6
        tooltipBackground.clipsToBounds = true
        tooltipBackground.contentView.addSubview(tooltipLabel)
        tooltipLabel.font = Theme.font(12, weight: .medium)
        tooltipLabel.textColor = Theme.text
        tooltipBackground.alpha = 0
    }

    required init?(coder: NSCoder) { fatalError() }

    private func launcherIcon() -> UIImage {
        let size: CGFloat = 112
        return UIGraphicsImageRenderer(size: CGSize(width: size, height: size)).image { ctx in
            let rect = CGRect(x: 0, y: 0, width: size, height: size)
            ctx.cgContext.addPath(UIBezierPath(roundedRect: rect, cornerRadius: size * 0.225).cgPath)
            ctx.cgContext.clip()
            UIColor(white: 0.22, alpha: 1).setFill()
            ctx.fill(rect)
            let colors = [UIColor(red: 1, green: 0.4, blue: 0.4, alpha: 1), UIColor(red: 1, green: 0.8, blue: 0.3, alpha: 1),
                          UIColor(red: 0.3, green: 0.8, blue: 0.5, alpha: 1), UIColor(red: 0.3, green: 0.6, blue: 1, alpha: 1),
                          UIColor(red: 0.7, green: 0.45, blue: 1, alpha: 1), UIColor(red: 1, green: 0.55, blue: 0.75, alpha: 1),
                          UIColor(red: 0.4, green: 0.85, blue: 0.9, alpha: 1), UIColor(red: 0.95, green: 0.6, blue: 0.3, alpha: 1),
                          UIColor(white: 0.85, alpha: 1)]
            let cell = size / 4.2
            for (i, c) in colors.enumerated() {
                let x = size * 0.17 + CGFloat(i % 3) * cell
                let y = size * 0.17 + CGFloat(i / 3) * cell
                c.setFill()
                UIBezierPath(ovalIn: CGRect(x: x, y: y, width: cell * 0.72, height: cell * 0.72)).fill()
            }
        }
    }

    override var intrinsicContentSize: CGSize {
        let s = stack.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        return CGSize(width: s.width + 24, height: 72)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        blur.frame = bounds
        let s = stack.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        stack.frame = CGRect(x: 12, y: bounds.height - s.height - 4, width: s.width, height: s.height)
    }

    func update(running: Set<DeskApp>, minimized: [DesktopWindowView]) {
        for (app, item) in appItems { item.isRunning = running.contains(app) }
        for item in windowItems { stack.removeArrangedSubview(item); item.removeFromSuperview() }
        windowItems = []
        separator.isHidden = minimized.isEmpty
        for window in minimized {
            let icon = window.app.icon(size: 112)
            let item = DockItemView(image: icon, tooltip: window.content.windowTitle)
            item.alpha = 0.85
            item.onTap = { [weak self, weak window] in if let window { self?.onRestoreWindow?(window) } }
            item.onHover = { [weak self, weak item] on in self?.hover(item, on) }
            windowItems.append(item)
            stack.addArrangedSubview(item)
        }
        invalidateIntrinsicContentSize()
        superview?.setNeedsLayout()
    }

    private func hover(_ item: DockItemView?, _ on: Bool) {
        guard let item else { return }
        UIView.animate(withDuration: 0.25, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0.5) {
            item.transform = on ? CGAffineTransform(translationX: 0, y: -8).scaledBy(x: 1.18, y: 1.18) : .identity
        }
        if on {
            tooltipLabel.text = item.tooltip
            let w = tooltipLabel.intrinsicContentSize.width + 20
            let center = convert(item.center, from: stack)
            tooltipBackground.frame = CGRect(x: center.x - w / 2, y: -38, width: w, height: 24)
            tooltipLabel.frame = tooltipBackground.bounds
            tooltipLabel.textAlignment = .center
            UIView.animate(withDuration: 0.12) { self.tooltipBackground.alpha = 1 }
        } else {
            UIView.animate(withDuration: 0.12) { self.tooltipBackground.alpha = 0 }
        }
    }

    private func showMenu(for app: DeskApp, item: DockItemView?) {
        guard let item else { return }
        var items: [MenuItem] = [
            MenuItem(title: "Open \(app.title)", symbol: app.symbolName) { [weak self] in self?.onOpenApp?(app) }
        ]
        if app.supportsMultipleWindows {
            items.append(MenuItem(title: "New Window", symbol: "plus.rectangle") { [weak self] in self?.onNewWindow?(app) })
        }
        if item.isRunning {
            items.append(.separator)
            items.append(MenuItem(title: "Quit", symbol: "xmark.circle") { [weak self] in self?.onCloseApp?(app) })
        }
        let menu = PopupMenuView(items: items, minWidth: 180)
        presentMenu?(menu, convert(item.frame, from: stack))
    }
}
