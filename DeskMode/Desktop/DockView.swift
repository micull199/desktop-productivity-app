import UIKit

/// A single icon in the Dock: an app, the launcher, or a minimised window's thumbnail.
///
/// The view scales from its bottom centre (`anchorPoint` 0.5/1) so magnification grows upward
/// out of the Dock the way macOS icons do. The Dock itself positions items with `center` and
/// `bounds`, never `frame`, because of that anchor.
final class DockItemView: UIView, PointerTarget {

    var onTap: (() -> Void)?
    var onRightClick: ((CGPoint) -> Void)?
    var onHover: ((Bool) -> Void)?
    var isRunning = false
    let tooltip: String
    /// Side of the square slot the item occupies in the Dock.
    let slotSize: CGFloat

    private let imageView = UIImageView()
    private var pressed = false

    init(image: UIImage, tooltip: String, size: CGFloat = Theme.Size.dockIcon, thumbnail: Bool = false) {
        self.tooltip = tooltip
        self.slotSize = size
        super.init(frame: CGRect(x: 0, y: 0, width: size, height: size))
        layer.anchorPoint = CGPoint(x: 0.5, y: 1)
        imageView.image = image
        imageView.contentMode = .scaleAspectFit
        if thumbnail {
            imageView.layer.cornerRadius = Theme.Radius.control - 2
            imageView.layer.cornerCurve = .continuous
            imageView.clipsToBounds = true
            imageView.layer.borderWidth = Theme.Size.hairline
            imageView.layer.borderColor = Theme.borderStrong.cgColor
        }
        addSubview(imageView)
    }

    required init?(coder: NSCoder) { fatalError() }

    // The Dock measures items through this; without it they would collapse to zero width.
    override var intrinsicContentSize: CGSize { CGSize(width: slotSize, height: slotSize) }

    override func layoutSubviews() {
        super.layoutSubviews()
        if let image = imageView.image, image.size.width > 0, imageView.clipsToBounds {
            // Thumbnails keep their aspect ratio and sit on the Dock floor.
            let aspect = image.size.height / image.size.width
            let w = bounds.width
            let h = min(bounds.height, w * aspect)
            imageView.frame = CGRect(x: 0, y: (bounds.height - h) / 2, width: w, height: h)
        } else {
            imageView.frame = bounds
        }
    }

    /// Scales and lifts the icon; `scale` 1 and `lift` 0 restore it.
    func setMagnification(scale: CGFloat, lift: CGFloat, animated: Bool) {
        let t = CGAffineTransform(translationX: 0, y: -lift).scaledBy(x: scale, y: scale)
        if animated {
            Theme.Motion.spring(Theme.Motion.slow, damping: 0.78) { self.transform = t }
        } else {
            transform = t
        }
    }

    /// Two decaying hops, used when the app launches.
    func bounce() {
        let base = transform
        UIView.animateKeyframes(withDuration: 0.56, delay: 0, options: [.calculationModeCubic, .beginFromCurrentState]) {
            UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 0.27) { self.transform = base.translatedBy(x: 0, y: -22) }
            UIView.addKeyframe(withRelativeStartTime: 0.27, relativeDuration: 0.27) { self.transform = base }
            UIView.addKeyframe(withRelativeStartTime: 0.54, relativeDuration: 0.23) { self.transform = base.translatedBy(x: 0, y: -9) }
            UIView.addKeyframe(withRelativeStartTime: 0.77, relativeDuration: 0.23) { self.transform = base }
        }
    }

    func pointer(_ event: PointerEvent, local: CGPoint) {
        switch event.kind {
        case .down(.left):
            pressed = true
            Theme.Motion.animate(Theme.Motion.fast) { self.imageView.alpha = 0.65 }
        case .up(.left):
            Theme.Motion.animate(Theme.Motion.fast) { self.imageView.alpha = 1 }
            if pressed, bounds.insetBy(dx: -Theme.Space.s, dy: -Theme.Space.s).contains(local) { onTap?() }
            pressed = false
        case .down(.right):
            onRightClick?(local)
        default: break
        }
    }

    func pointerEntered() { onHover?(true) }
    func pointerExited() { onHover?(false); pressed = false; imageView.alpha = 1 }
}

/// The Dock: launch and switch between apps, restore minimised windows.
///
/// A material pill that sits `Theme.Size.dockBottomMargin` above the bottom of the display.
/// The view's frame is taller than the pill so magnified icons and the tooltip have room above
/// it; `hitTest` only accepts points over the pill or over an icon, so the transparent band
/// never swallows clicks meant for windows behind it.
final class DockView: UIView, PointerTarget {

    var onOpenApp: ((DeskApp) -> Void)?
    var onNewWindow: ((DeskApp) -> Void)?
    var onCloseApp: ((DeskApp) -> Void)?
    var onRestoreWindow: ((DesktopWindowView) -> Void)?
    var onLauncher: (() -> Void)?
    /// Asks the desktop to present a menu above an item (anchor in Dock coordinates).
    var presentMenu: ((PopupMenuView, CGRect) -> Void)?

    private let pill = Theme.materialView(.bar, cornerRadius: Theme.Radius.dock)
    private let shadowHost = UIView()
    private let launcherItem: DockItemView
    private var appItems: [DeskApp: DockItemView] = [:]
    private var windowItems: [DockItemView] = []
    private var dots: [DeskApp: UIView] = [:]
    private let separator = UIView()
    private var tooltip: TooltipView?
    private var hoveredItem: DockItemView?

    /// Space above the pill reserved for magnified icons and the tooltip.
    static let overflowTop: CGFloat = Theme.Size.dockIcon * (Theme.Motion.dockMagnification - 1) + Theme.Motion.dockLift + 34

    override init(frame: CGRect) {
        launcherItem = DockItemView(image: DockView.launcherIcon(), tooltip: "Launcher")
        super.init(frame: frame)
        addSubview(shadowHost)
        shadowHost.addSubview(pill)
        shadowHost.applyShadow(.dock)
        pill.layer.borderWidth = Theme.Size.hairline
        pill.layer.borderColor = Theme.border.cgColor

        launcherItem.onTap = { [weak self] in self?.onLauncher?() }
        launcherItem.onHover = { [weak self, weak launcherItem] on in self?.hover(launcherItem, on) }
        addSubview(launcherItem)

        for app in DeskApp.allCases {
            let item = DockItemView(image: app.icon(size: Theme.Size.dockIcon * 2), tooltip: app.title)
            item.onTap = { [weak self] in self?.onOpenApp?(app) }
            item.onHover = { [weak self, weak item] on in self?.hover(item, on) }
            item.onRightClick = { [weak self, weak item] _ in self?.showMenu(for: app, item: item) }
            appItems[app] = item
            addSubview(item)
            let dot = UIView()
            dot.backgroundColor = Theme.dockIndicator
            dot.layer.cornerRadius = Theme.Size.dockIndicator / 2
            dot.isHidden = true
            dot.isUserInteractionEnabled = false
            dots[app] = dot
            addSubview(dot)
        }

        separator.backgroundColor = Theme.border
        separator.isHidden = true
        addSubview(separator)
    }

    required init?(coder: NSCoder) { fatalError() }

    /// The launcher tile: a grid of coloured dots on a dark rounded square.
    private static func launcherIcon() -> UIImage {
        let size: CGFloat = Theme.Size.dockIcon * 2
        return UIGraphicsImageRenderer(size: CGSize(width: size, height: size)).image { ctx in
            let rect = CGRect(x: 0, y: 0, width: size, height: size)
            ctx.cgContext.addPath(UIBezierPath(roundedRect: rect, cornerRadius: size * 0.225).cgPath)
            ctx.cgContext.clip()
            let bg = [UIColor(white: 0.30, alpha: 1).cgColor, UIColor(white: 0.16, alpha: 1).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: bg, locations: [0, 1]) {
                ctx.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size), options: [])
            }
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

    // MARK: - Layout

    /// Items in display order, with `nil` marking the separator slot.
    private var orderedItems: [DockItemView?] {
        var items: [DockItemView?] = [launcherItem] + DeskApp.allCases.compactMap { appItems[$0] }
        if !windowItems.isEmpty {
            items.append(nil)
            items.append(contentsOf: windowItems)
        }
        return items
    }

    private var pillWidth: CGFloat {
        var w = Theme.Size.dockPadding * 2
        var first = true
        for item in orderedItems {
            if !first { w += Theme.Size.dockGap }
            first = false
            w += item?.slotSize ?? Theme.Size.hairline
        }
        return ceil(w)
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: pillWidth, height: Theme.Size.dockPill + Self.overflowTop)
    }

    /// The pill's frame in the Dock's own coordinates.
    var pillFrame: CGRect {
        CGRect(x: 0, y: bounds.height - Theme.Size.dockPill, width: bounds.width, height: Theme.Size.dockPill)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let pf = pillFrame
        shadowHost.frame = pf
        pill.frame = shadowHost.bounds
        shadowHost.layer.shadowPath = UIBezierPath(roundedRect: shadowHost.bounds, cornerRadius: Theme.Radius.dock).cgPath

        let floor = pf.maxY - Theme.Size.dockPadding
        var x = pf.minX + Theme.Size.dockPadding
        for item in orderedItems {
            guard let item else {
                separator.frame = CGRect(x: x, y: floor - Theme.Size.dockIcon + Theme.Space.xs, width: Theme.Size.hairline, height: Theme.Size.dockIcon - Theme.Space.xs * 2)
                x += Theme.Size.hairline + Theme.Size.dockGap
                continue
            }
            let w = item.slotSize
            let bottomInset = (Theme.Size.dockIcon - w) / 2
            item.bounds = CGRect(x: 0, y: 0, width: w, height: w)
            item.center = CGPoint(x: x + w / 2, y: floor - bottomInset)
            x += w + Theme.Size.dockGap
        }
        for (app, dot) in dots {
            guard let item = appItems[app] else { continue }
            let d = Theme.Size.dockIndicator
            dot.frame = CGRect(x: item.center.x - d / 2, y: pf.maxY - (Theme.Size.dockPadding + d) / 2, width: d, height: d)
        }
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard bounds.contains(point) else { return nil }
        if pillFrame.contains(point) { return super.hitTest(point, with: event) }
        for item in orderedItems.compactMap({ $0 }) where item.frame.contains(point) {
            return super.hitTest(point, with: event)
        }
        return nil
    }

    /// Frame of the app's Dock icon in the Dock's superview coordinates (for the minimise
    /// animation); `nil` before layout.
    func frame(for app: DeskApp) -> CGRect? {
        guard let item = appItems[app], let superview, bounds.width > 0 else { return nil }
        return convert(item.frame, to: superview)
    }

    // MARK: - State

    func update(running: Set<DeskApp>, minimized: [DesktopWindowView]) {
        for (app, dot) in dots { dot.isHidden = !running.contains(app) }
        for (app, item) in appItems { item.isRunning = running.contains(app) }
        for item in windowItems { item.removeFromSuperview() }
        windowItems = []
        separator.isHidden = minimized.isEmpty
        for window in minimized {
            let item: DockItemView
            if let snapshot = Self.thumbnail(of: window) {
                item = DockItemView(image: snapshot, tooltip: window.content.windowTitle, size: Theme.Size.dockThumbnail, thumbnail: true)
            } else {
                item = DockItemView(image: window.app.icon(size: Theme.Size.dockThumbnail * 2), tooltip: window.content.windowTitle, size: Theme.Size.dockThumbnail)
                item.alpha = 0.85
            }
            item.onTap = { [weak self, weak window] in if let window { self?.onRestoreWindow?(window) } }
            item.onHover = { [weak self, weak item] on in self?.hover(item, on) }
            windowItems.append(item)
            addSubview(item)
        }
        invalidateIntrinsicContentSize()
        setNeedsLayout()
        superview?.setNeedsLayout()
    }

    /// Bounces the app's icon (two decaying hops), e.g. when a new window opens.
    func bounce(_ app: DeskApp) {
        appItems[app]?.bounce()
    }

    /// Renders the window's content into a Dock-sized image; `nil` when nothing could be drawn.
    private static func thumbnail(of window: DesktopWindowView) -> UIImage? {
        let source = window.content
        guard !window.isHidden, window.window != nil, source.bounds.width > 40, source.bounds.height > 40 else { return nil }
        let w = Theme.Size.dockThumbnail
        let h = max(12, min(w, (w * source.bounds.height / source.bounds.width).rounded()))
        let format = UIGraphicsImageRendererFormat()
        format.scale = window.traitCollection.displayScale
        format.opaque = true
        var drawn = false
        let image = UIGraphicsImageRenderer(size: CGSize(width: w, height: h), format: format).image { ctx in
            Theme.windowBackground.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
            drawn = source.drawHierarchy(in: CGRect(x: 0, y: 0, width: w, height: h), afterScreenUpdates: false)
        }
        return drawn ? image : nil
    }

    // MARK: - Hover

    private func hover(_ item: DockItemView?, _ on: Bool) {
        guard let item else { return }
        if on {
            hoveredItem = item
        } else if hoveredItem === item {
            hoveredItem = nil
        }
        applyMagnification()
        updateTooltip()
    }

    private func applyMagnification() {
        let items = orderedItems
        let hoveredIndex = hoveredItem.flatMap { hovered in items.firstIndex(where: { $0 === hovered }) }
        for (i, item) in items.enumerated() {
            guard let item else { continue }
            var scale: CGFloat = 1
            var lift: CGFloat = 0
            if let h = hoveredIndex {
                if i == h {
                    scale = Theme.Motion.dockMagnification
                    lift = Theme.Motion.dockLift
                } else if abs(i - h) == 1, items[h] != nil {
                    scale = Theme.Motion.dockNeighbourMagnification
                    lift = Theme.Motion.dockLift * 0.35
                }
            }
            item.setMagnification(scale: scale, lift: lift, animated: true)
        }
    }

    private func updateTooltip() {
        guard let item = hoveredItem else {
            if let tooltip {
                self.tooltip = nil
                Theme.Motion.animate(Theme.Motion.fast, animations: { tooltip.alpha = 0 }) { _ in tooltip.removeFromSuperview() }
            }
            return
        }
        let view: TooltipView
        if let existing = tooltip {
            view = existing
            view.text = item.tooltip
        } else {
            view = TooltipView(text: item.tooltip)
            view.alpha = 0
            addSubview(view)
            tooltip = view
        }
        let top = pillFrame.minY - Theme.Motion.dockLift - item.slotSize * (Theme.Motion.dockMagnification - 1) - Theme.Space.s
        var x = item.center.x - view.bounds.width / 2
        x = min(max(0, x), bounds.width - view.bounds.width)
        let target = CGRect(x: x, y: top - view.bounds.height, width: view.bounds.width, height: view.bounds.height)
        if view.alpha == 0 {
            view.frame = target.offsetBy(dx: 0, dy: 3)
            Theme.Motion.animate(Theme.Motion.fast) { view.alpha = 1; view.frame = target }
        } else {
            Theme.Motion.animate(Theme.Motion.fast) { view.frame = target }
        }
    }

    // MARK: - PointerTarget

    /// Clicks on the pill between icons stop here instead of reaching the desktop behind it.
    func pointer(_ event: PointerEvent, local: CGPoint) {}

    // MARK: - Menus

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
        presentMenu?(menu, item.frame)
    }
}
