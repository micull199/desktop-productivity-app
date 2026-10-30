import UIKit

/// Chrome's find bar: a small floating panel under the toolbar's right edge with the search
/// field, a status label, previous/next buttons and a close button.
final class FindBarView: UIView {

    static let size = CGSize(width: 380, height: 44)

    let field = DeskTextField()
    var onNext: (() -> Void)?
    var onPrevious: (() -> Void)?
    var onClose: (() -> Void)?
    var onButtonHover: ((BrowserIconButton, Bool) -> Void)?

    private let material = Theme.materialView(.panel, cornerRadius: Theme.Radius.menu)
    private let status = UILabel()
    private let divider = UIView()
    private let previousButton = BrowserIconButton(symbol: "chevron.up", pointSize: 12)
    private let nextButton = BrowserIconButton(symbol: "chevron.down", pointSize: 12)
    private let closeButton = BrowserIconButton(symbol: "xmark", pointSize: 11)
    private(set) var isShown = false

    override init(frame: CGRect) {
        super.init(frame: CGRect(origin: .zero, size: Self.size))
        addSubview(material)
        for v in [field, status, divider, previousButton, nextButton, closeButton] { material.contentView.addSubview(v) }

        layer.cornerRadius = Theme.Radius.menu
        layer.cornerCurve = .continuous
        layer.borderWidth = Theme.Size.hairline
        layer.borderColor = Theme.border.cgColor
        applyShadow(.menu)

        field.showsBackground = false
        field.placeholder = "Find in page"
        field.font = Theme.font(Theme.Text.body)
        field.insets = UIEdgeInsets(top: 0, left: Theme.Space.m, bottom: 0, right: Theme.Space.xs)

        status.font = Theme.font(Theme.Text.footnote)
        status.textColor = Theme.secondaryText
        status.textAlignment = .right
        divider.backgroundColor = Theme.separator

        previousButton.tooltip = "Previous (⇧⏎)"
        nextButton.tooltip = "Next (⏎)"
        closeButton.tooltip = "Close (Esc)"
        previousButton.isCircular = false
        nextButton.isCircular = false
        closeButton.isCircular = false
        previousButton.onTap = { [weak self] in self?.onPrevious?() }
        nextButton.onTap = { [weak self] in self?.onNext?() }
        closeButton.onTap = { [weak self] in self?.onClose?() }
        for b in [previousButton, nextButton, closeButton] {
            b.onHover = { [weak self] btn, h in self?.onButtonHover?(btn, h) }
        }
        isHidden = true
        alpha = 0
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        material.frame = bounds
        let h = bounds.height
        let b = Theme.Size.control
        let y = (h - b) / 2
        closeButton.frame = CGRect(x: bounds.width - b - Theme.Space.s, y: y, width: b, height: b)
        nextButton.frame = CGRect(x: closeButton.frame.minX - b - Theme.Space.xxs, y: y, width: b, height: b)
        previousButton.frame = CGRect(x: nextButton.frame.minX - b - Theme.Space.xxs, y: y, width: b, height: b)
        divider.frame = CGRect(x: previousButton.frame.minX - Theme.Space.s, y: Theme.Space.m, width: Theme.Size.hairline, height: h - Theme.Space.m * 2)
        let statusWidth: CGFloat = 76
        status.frame = CGRect(x: divider.frame.minX - Theme.Space.s - statusWidth, y: 0, width: statusWidth, height: h)
        field.frame = CGRect(x: Theme.Space.xs, y: 0, width: status.frame.minX - Theme.Space.xs, height: h)
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: Theme.Radius.menu).cgPath
    }

    /// `nil` clears the status; `false` shows "Not found" in the destructive colour.
    func setResult(found: Bool?) {
        switch found {
        case .none, .some(true):
            status.text = ""
        case .some(false):
            status.text = "Not found"
            status.textColor = Theme.destructive
        }
    }

    func show() {
        guard !isShown else { return }
        isShown = true
        isHidden = false
        transform = CGAffineTransform(translationX: 0, y: -8)
        Theme.Motion.animate(Theme.Motion.normal) {
            self.alpha = 1
            self.transform = .identity
        }
    }

    func hide() {
        guard isShown else { return }
        isShown = false
        Theme.Motion.animate(Theme.Motion.fast, animations: {
            self.alpha = 0
            self.transform = CGAffineTransform(translationX: 0, y: -8)
        }) { _ in
            if !self.isShown { self.isHidden = true; self.transform = .identity }
        }
    }
}
