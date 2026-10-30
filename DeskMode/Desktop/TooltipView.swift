import UIKit

/// A small material pill with a single line of 12 pt text. Used for Dock labels and for the
/// desktop-wide tooltips driven by `PointerTarget.tooltipText`.
final class TooltipView: UIView {

    private let material = Theme.materialView(.menu, cornerRadius: Theme.Radius.tooltip)
    private let label = UILabel()

    private static let padding = UIEdgeInsets(top: Theme.Space.xs, left: Theme.Space.s, bottom: Theme.Space.xs, right: Theme.Space.s)

    var text: String {
        get { label.text ?? "" }
        set { label.text = newValue; sizeToFitText() }
    }

    init(text: String) {
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        addSubview(material)
        material.contentView.addSubview(label)
        material.layer.borderWidth = Theme.Size.hairline
        material.layer.borderColor = Theme.border.cgColor
        layer.cornerRadius = Theme.Radius.tooltip
        layer.cornerCurve = .continuous
        applyShadow(.subtle)
        label.font = Theme.font(Theme.Text.footnote)
        label.textColor = Theme.text
        label.textAlignment = .center
        label.lineBreakMode = .byTruncatingTail
        label.text = text
        sizeToFitText()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func sizeToFitText() {
        let size = label.sizeThatFits(CGSize(width: 320, height: 40))
        bounds.size = CGSize(width: ceil(size.width) + Self.padding.left + Self.padding.right,
                             height: ceil(size.height) + Self.padding.top + Self.padding.bottom)
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        material.frame = bounds
        label.frame = bounds.inset(by: Self.padding)
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: Theme.Radius.tooltip).cgPath
    }
}

/// Shows a `TooltipView` once the cursor has rested on a target that offers `tooltipText`, and
/// hides it again when the cursor leaves or clicks.
@MainActor
final class TooltipPresenter {

    private unowned let container: UIView
    private var tooltip: TooltipView?
    private var timer: Timer?
    private weak var target: AnyObject?
    private var text: String?
    private var point = CGPoint.zero

    /// Distance between the cursor hot spot and the tooltip.
    private let cursorClearance: CGFloat = 22

    init(container: UIView) {
        self.container = container
    }

    /// Call on every hover update with the current target (or nil) and cursor position.
    func update(target: PointerTarget?, at point: CGPoint) {
        self.point = point
        if target !== self.target {
            self.target = target
            hide()
            text = target?.tooltipText
            schedule()
        } else if tooltip == nil {
            // Same target, cursor still moving: wait until it rests.
            schedule()
        }
    }

    /// Hides the tooltip immediately (clicks) and forgets the pending one.
    func hide() {
        timer?.invalidate()
        timer = nil
        guard let tooltip else { return }
        self.tooltip = nil
        Theme.Motion.animate(Theme.Motion.fast, animations: { tooltip.alpha = 0 }) { _ in tooltip.removeFromSuperview() }
    }

    /// Hides and suppresses the tooltip until the cursor moves to another target.
    func cancel() {
        hide()
        text = nil
    }

    private func schedule() {
        timer?.invalidate()
        timer = nil
        guard text != nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: Theme.Timing.tooltipDelay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.show() }
        }
    }

    private func show() {
        guard tooltip == nil, let text, !text.isEmpty else { return }
        let view = TooltipView(text: text)
        let bounds = container.bounds
        var origin = CGPoint(x: point.x - view.bounds.width / 2, y: point.y - cursorClearance - view.bounds.height)
        if origin.y < Theme.menuBarHeight + Theme.Space.xs {
            origin.y = point.y + cursorClearance
        }
        origin.x = min(max(Theme.Space.s, origin.x), bounds.width - view.bounds.width - Theme.Space.s)
        view.frame.origin = origin
        view.alpha = 0
        view.transform = CGAffineTransform(translationX: 0, y: 2)
        container.addSubview(view)
        tooltip = view
        Theme.Motion.animate(Theme.Motion.fast) {
            view.alpha = 1
            view.transform = .identity
        }
    }
}
