import UIKit

// MARK: - Icon button

/// A Chrome-style round icon button driven by the desktop pointer: hover ring, pressed fill,
/// disabled dimming, optional tooltip. Used by the toolbar, tab strip and find bar.
final class BrowserIconButton: UIView, PointerTarget {

    var onTap: (() -> Void)?
    var onRightClick: ((CGPoint) -> Void)?
    /// Hover notifications for the tooltip presenter.
    var onHover: ((BrowserIconButton, Bool) -> Void)?

    var tooltip: String?
    var isEnabled = true { didSet { refresh() } }
    /// Draws the glyph in the accent colour (e.g. a filled bookmark star).
    var isAccented = false { didSet { refresh() } }
    var symbolName: String { didSet { if symbolName != oldValue { updateImage() } } }
    var pointSize: CGFloat { didSet { if pointSize != oldValue { updateImage() } } }
    var weight: UIFont.Weight = .medium { didSet { if weight != oldValue { updateImage() } } }
    /// Rotation of the glyph in radians (the ⋮ menu is a rotated ellipsis).
    var glyphRotation: CGFloat = 0 { didSet { icon.transform = CGAffineTransform(rotationAngle: glyphRotation) } }
    /// Hover/pressed fill shape. Chrome uses circles in the toolbar and rounded squares in menus.
    var isCircular = true { didSet { setNeedsLayout() } }

    private let fill = UIView()
    private let icon = UIImageView()
    private(set) var isHovered = false
    private var isPressed = false

    init(symbol: String, pointSize: CGFloat = 15) {
        self.symbolName = symbol
        self.pointSize = pointSize
        super.init(frame: .zero)
        addSubview(fill)
        addSubview(icon)
        fill.isUserInteractionEnabled = false
        icon.isUserInteractionEnabled = false
        icon.contentMode = .center
        updateImage()
        refresh()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        fill.frame = bounds
        fill.layer.cornerRadius = isCircular ? min(bounds.width, bounds.height) / 2 : Theme.Radius.control
        fill.layer.cornerCurve = .continuous
        icon.bounds = CGRect(origin: .zero, size: bounds.size)
        icon.center = CGPoint(x: bounds.midX, y: bounds.midY)
    }

    private func updateImage() {
        icon.image = UIImage.symbol(symbolName, size: pointSize, weight: weight)?.withRenderingMode(.alwaysTemplate)
    }

    private func refresh() {
        let tint = isAccented ? Theme.accentText : Theme.text
        icon.tintColor = isEnabled ? tint : Theme.quaternaryText
        let target: UIColor = !isEnabled ? .clear : isPressed ? Theme.pressedOverlay : isHovered ? Theme.controlBackgroundHover : .clear
        Theme.Motion.animate(Theme.Motion.fast) { self.fill.backgroundColor = target }
    }

    // MARK: PointerTarget

    func pointer(_ event: PointerEvent, local: CGPoint) {
        switch event.kind {
        case .down(.left):
            guard isEnabled else { return }
            isPressed = true
            refresh()
        case .up(.left):
            let inside = bounds.insetBy(dx: -2, dy: -2).contains(local)
            let wasPressed = isPressed
            isPressed = false
            refresh()
            if inside, wasPressed, isEnabled { onTap?() }
        case .down(.right):
            onRightClick?(local)
        default:
            break
        }
    }

    func pointerEntered() {
        isHovered = true
        refresh()
        onHover?(self, true)
    }

    func pointerExited() {
        isHovered = false
        isPressed = false
        refresh()
        onHover?(self, false)
    }

    func cursorStyle(at local: CGPoint) -> CursorStyle { .arrow }
}

// MARK: - Tooltip

/// Small material pill shown under a control after a short hover.
final class BrowserTooltipView: UIView {
    private let material = Theme.materialView(.menu, cornerRadius: Theme.Radius.control)
    private let label = UILabel()

    init(text: String) {
        super.init(frame: .zero)
        addSubview(material)
        material.contentView.addSubview(label)
        label.text = text
        label.font = Theme.font(Theme.Text.footnote)
        label.textColor = Theme.text
        let size = label.sizeThatFits(CGSize(width: 320, height: 40))
        frame = CGRect(x: 0, y: 0, width: ceil(size.width) + Theme.Space.l, height: Theme.Size.controlSmall)
        layer.borderWidth = Theme.Size.hairline
        layer.borderColor = Theme.border.cgColor
        layer.cornerRadius = Theme.Radius.control
        layer.cornerCurve = .continuous
        applyShadow(.subtle)
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        material.frame = bounds
        label.frame = bounds.insetBy(dx: Theme.Space.s, dy: 0)
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: Theme.Radius.control).cgPath
    }
}

/// Shows a tooltip for a hovered button after ~0.5 s and hides it when the hover ends.
@MainActor
final class BrowserTooltipPresenter {
    private weak var host: UIView?
    private var timer: Timer?
    private var tooltip: BrowserTooltipView?
    private weak var anchor: UIView?

    init(host: UIView) { self.host = host }

    func hover(_ view: UIView, text: String?, hovering: Bool) {
        timer?.invalidate()
        timer = nil
        if hovering, let text, !text.isEmpty {
            anchor = view
            timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.show(text) }
            }
        } else if anchor === view || !hovering {
            hide()
        }
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
        hide()
    }

    private func show(_ text: String) {
        guard let host, let anchor, anchor.window != nil else { return }
        hide()
        let tip = BrowserTooltipView(text: text)
        let anchorFrame = anchor.convert(anchor.bounds, to: host)
        var x = anchorFrame.midX - tip.bounds.width / 2
        x = min(max(Theme.Space.s, x), host.bounds.width - tip.bounds.width - Theme.Space.s)
        var y = anchorFrame.maxY + Theme.Space.xs
        if y + tip.bounds.height > host.bounds.height { y = anchorFrame.minY - tip.bounds.height - Theme.Space.xs }
        tip.frame.origin = CGPoint(x: x, y: y)
        tip.alpha = 0
        tip.transform = CGAffineTransform(translationX: 0, y: -2)
        host.addSubview(tip)
        tooltip = tip
        Theme.Motion.animate(Theme.Motion.fast) { tip.alpha = 1; tip.transform = .identity }
    }

    private func hide() {
        guard let tip = tooltip else { return }
        tooltip = nil
        Theme.Motion.animate(Theme.Motion.instant, animations: { tip.alpha = 0 }) { _ in tip.removeFromSuperview() }
    }
}
