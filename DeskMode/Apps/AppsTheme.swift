import UIKit

/// Design tokens and shared pointer-driven building blocks for the built-in apps (Notes, Tasks,
/// Settings).
///
/// The spacing / radius / motion scale mirrors the redesign brief. Values that `Theme` already
/// defines are forwarded so this namespace can be folded into `Theme` once the shell lands its
/// new tokens.
enum AppsTheme {

    enum Space {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    enum Radius {
        static let control: CGFloat = 6
        static let field: CGFloat = 8
        static let menu: CGFloat = 10
        static let window: CGFloat = 12
        static let panel: CGFloat = 14
        static let tile: CGFloat = 16
    }

    enum TextSize {
        static let caption: CGFloat = 11
        static let footnote: CGFloat = 12
        static let body: CGFloat = 13
        static let callout: CGFloat = 14
        static let headline: CGFloat = 15
        static let title3: CGFloat = 17
        static let title2: CGFloat = 20
    }

    enum Size {
        static let control: CGFloat = 28
        static let controlSmall: CGFloat = 24
        static let controlLarge: CGFloat = 32
    }

    enum Motion {
        static let fast: TimeInterval = 0.14
        static let normal: TimeInterval = 0.2
        static let slow: TimeInterval = 0.3

        /// Ease-out state change.
        static func animate(_ duration: TimeInterval = normal, _ changes: @escaping () -> Void, completion: ((Bool) -> Void)? = nil) {
            UIView.animate(withDuration: duration, delay: 0,
                           options: [.curveEaseOut, .allowUserInteraction, .beginFromCurrentState],
                           animations: changes, completion: completion)
        }

        /// Spring for things that move or scale into place.
        static func spring(_ duration: TimeInterval = slow, _ changes: @escaping () -> Void, completion: ((Bool) -> Void)? = nil) {
            UIView.animate(withDuration: duration, delay: 0, usingSpringWithDamping: 0.82, initialSpringVelocity: 0.4,
                           options: [.allowUserInteraction, .beginFromCurrentState],
                           animations: changes, completion: completion)
        }
    }

    /// Slightly darker than `Theme.windowBackground`, like a macOS source list.
    static let sidebarBackground = UIColor(red: 0.098, green: 0.102, blue: 0.116, alpha: 1)
    static let selectedRow = Theme.accent.withAlphaComponent(0.85)
    static let accentSoft = Theme.accent.withAlphaComponent(0.18)
    static let onAccent = UIColor.white
    static let onAccentSecondary = UIColor.white.withAlphaComponent(0.75)
    static let checkboxRing = UIColor(white: 1, alpha: 0.32)

    /// Section tile colours for the Settings sidebar (System Settings style).
    static let tileBlue = UIColor(red: 0.25, green: 0.52, blue: 0.98, alpha: 1)
    static let tileIndigo = UIColor(red: 0.42, green: 0.40, blue: 0.95, alpha: 1)
    static let tileGreen = UIColor(red: 0.20, green: 0.72, blue: 0.38, alpha: 1)
    static let tileOrange = UIColor(red: 0.98, green: 0.58, blue: 0.16, alpha: 1)
    static let tileGray = UIColor(white: 0.5, alpha: 1)

    static func sectionLabel(_ text: String) -> UILabel {
        let l = UILabel()
        l.text = text
        l.font = Theme.font(TextSize.caption, weight: .semibold)
        l.textColor = Theme.tertiaryText
        return l
    }
}

// MARK: - View helpers

extension UIView {
    /// One device pixel, for pixelHairline separators.
    var pixelHairline: CGFloat { 1 / max(1, traitCollection.displayScale) }

    /// The desktop controller hosting this view (walks the responder chain, so it also works for
    /// the phone preview where the desktop is a child controller).
    var enclosingDesktopController: DesktopViewController? {
        var r: UIResponder? = self
        while let cur = r {
            if let d = cur as? DesktopViewController { return d }
            r = cur.next
        }
        return nil
    }

    /// Hands a wheel event from a nested pointer target to the nearest `DeskScrollView`.
    func forwardScroll(_ event: PointerEvent) {
        guard case .scroll = event.kind else { return }
        var v = superview
        while let cur = v {
            if let s = cur as? DeskScrollView { s.pointer(event, local: .zero); return }
            v = cur.superview
        }
    }
}

// MARK: - Scroll view

/// A scroll view that moves with the desktop's wheel / two-finger scroll events.
final class DeskScrollView: UIScrollView, PointerTarget {

    override init(frame: CGRect) {
        super.init(frame: frame)
        indicatorStyle = .white
        showsHorizontalScrollIndicator = false
        alwaysBounceVertical = false
    }

    required init?(coder: NSCoder) { fatalError() }

    func pointer(_ event: PointerEvent, local: CGPoint) {
        if case .scroll(_, let dy) = event.kind { scroll(by: dy) }
    }

    func scroll(by dy: CGFloat) {
        let maxY = max(-contentInset.top, contentSize.height + contentInset.bottom - bounds.height)
        var o = contentOffset
        o.y = min(max(-contentInset.top, o.y + dy), maxY)
        guard o != contentOffset else { return }
        setContentOffset(o, animated: false)
        flashScrollIndicators()
    }

    func cursorStyle(at local: CGPoint) -> CursorStyle { .arrow }
}

// MARK: - Hover row

/// Base class for list rows and custom controls: hover, pressed and selected fills, click,
/// double-click and right-click, with wheel events forwarded to the enclosing scroll view.
class HoverRow: UIView, PointerTarget {

    var onTap: (() -> Void)?
    var onDoubleTap: (() -> Void)?
    /// Receives the original pointer event (its `location` is in desktop coordinates).
    var onRightClick: ((PointerEvent) -> Void)?

    var isSelected = false { didSet { if oldValue != isSelected { refreshState(animated: true) } } }
    var showsHoverHighlight = true { didSet { refreshState(animated: false) } }
    var highlightInsets = UIEdgeInsets.zero { didSet { setNeedsLayout() } }
    private(set) var isHovered = false
    private(set) var isPressed = false

    let highlight = UIView()

    init(cornerRadius: CGFloat = AppsTheme.Radius.control) {
        super.init(frame: .zero)
        addSubview(highlight)
        highlight.isUserInteractionEnabled = false
        highlight.layer.cornerRadius = cornerRadius
        highlight.layer.cornerCurve = .continuous
        refreshState(animated: false)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        highlight.frame = bounds.inset(by: highlightInsets)
    }

    func highlightColor() -> UIColor {
        if isSelected { return AppsTheme.selectedRow }
        guard showsHoverHighlight else { return .clear }
        if isPressed { return Theme.controlBackgroundPressed }
        if isHovered { return Theme.controlBackgroundHover }
        return .clear
    }

    /// Subclasses recolour their labels here; called inside the state animation.
    func stateDidChange() {}

    func refreshState(animated: Bool) {
        let apply = {
            self.highlight.backgroundColor = self.highlightColor()
            self.stateDidChange()
        }
        if animated { AppsTheme.Motion.animate(AppsTheme.Motion.fast, apply) } else { apply() }
    }

    // MARK: PointerTarget

    func pointer(_ event: PointerEvent, local: CGPoint) {
        switch event.kind {
        case .down(.left):
            isPressed = true
            refreshState(animated: false)
        case .up(.left):
            let inside = bounds.contains(local)
            isPressed = false
            refreshState(animated: true)
            if inside {
                if event.clickCount == 2, let onDoubleTap { onDoubleTap() } else { onTap?() }
            }
        case .down(.right):
            onRightClick?(event)
        case .scroll:
            forwardScroll(event)
        default:
            break
        }
    }

    func pointerEntered() { isHovered = true; refreshState(animated: true) }
    func pointerExited() { isHovered = false; isPressed = false; refreshState(animated: true) }
    func cursorStyle(at local: CGPoint) -> CursorStyle { .arrow }
}

// MARK: - Checkbox

/// An 18 pt circular checkbox: accent ring, fills with a check mark when on.
final class DeskCheckbox: UIView, PointerTarget {

    static let size: CGFloat = 18

    private(set) var isOn: Bool
    var onToggle: ((Bool) -> Void)?

    private let ring = UIView()
    private let fill = UIView()
    private let check = UIImageView()
    private var hovered = false

    init(isOn: Bool) {
        self.isOn = isOn
        super.init(frame: CGRect(x: 0, y: 0, width: Self.size, height: Self.size))
        addSubview(ring)
        addSubview(fill)
        fill.addSubview(check)
        ring.isUserInteractionEnabled = false
        fill.isUserInteractionEnabled = false
        ring.layer.borderWidth = 1.5
        ring.layer.cornerRadius = Self.size / 2
        fill.backgroundColor = Theme.accent
        fill.layer.cornerRadius = Self.size / 2
        check.image = UIImage(systemName: "checkmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 9, weight: .bold))?
            .withTintColor(AppsTheme.onAccent, renderingMode: .alwaysOriginal)
        check.contentMode = .center
        render(animated: false)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: CGSize { CGSize(width: Self.size, height: Self.size) }

    override func layoutSubviews() {
        super.layoutSubviews()
        let r = CGRect(x: (bounds.width - Self.size) / 2, y: (bounds.height - Self.size) / 2, width: Self.size, height: Self.size)
        ring.frame = r
        fill.bounds = CGRect(origin: .zero, size: r.size)
        fill.center = CGPoint(x: r.midX, y: r.midY)
        check.frame = fill.bounds
    }

    func setOn(_ on: Bool, animated: Bool) {
        guard on != isOn else { return }
        isOn = on
        render(animated: animated)
    }

    private func render(animated: Bool) {
        let apply = {
            self.ring.layer.borderColor = (self.isOn || self.hovered ? Theme.accent : AppsTheme.checkboxRing).cgColor
            self.fill.transform = self.isOn ? .identity : CGAffineTransform(scaleX: 0.01, y: 0.01)
            self.fill.alpha = self.isOn ? 1 : 0
        }
        if animated {
            AppsTheme.Motion.animate(0.2, apply)
        } else {
            apply()
        }
    }

    func pointer(_ event: PointerEvent, local: CGPoint) {
        switch event.kind {
        case .up(.left):
            if bounds.insetBy(dx: -6, dy: -6).contains(local) {
                setOn(!isOn, animated: true)
                onToggle?(isOn)
            }
        case .scroll:
            forwardScroll(event)
        default:
            break
        }
    }

    func pointerEntered() { hovered = true; render(animated: true) }
    func pointerExited() { hovered = false; render(animated: true) }
    func cursorStyle(at local: CGPoint) -> CursorStyle { .arrow }
}

// MARK: - Empty state

/// Centred glyph + title + hint for lists with nothing in them.
final class EmptyStateView: UIView {
    private let icon = UIImageView()
    private let title = UILabel()
    private let hint = UILabel()

    init(symbol: String, title text: String, hint hintText: String) {
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        addSubview(icon)
        addSubview(title)
        addSubview(hint)
        icon.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 36, weight: .light))?
            .withTintColor(Theme.tertiaryText, renderingMode: .alwaysOriginal)
        icon.contentMode = .center
        title.text = text
        title.font = Theme.font(AppsTheme.TextSize.headline, weight: .semibold)
        title.textColor = Theme.secondaryText
        title.textAlignment = .center
        hint.text = hintText
        hint.font = Theme.font(AppsTheme.TextSize.body)
        hint.textColor = Theme.tertiaryText
        hint.textAlignment = .center
        hint.numberOfLines = 2
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        let total: CGFloat = 48 + AppsTheme.Space.m + 20 + AppsTheme.Space.xs + 36
        let top = max(AppsTheme.Space.l, (bounds.height - total) / 2 - 12)
        icon.frame = CGRect(x: 0, y: top, width: bounds.width, height: 48)
        title.frame = CGRect(x: AppsTheme.Space.l, y: icon.frame.maxY + AppsTheme.Space.m, width: bounds.width - AppsTheme.Space.xxl, height: 20)
        hint.frame = CGRect(x: AppsTheme.Space.l, y: title.frame.maxY + AppsTheme.Space.xs, width: bounds.width - AppsTheme.Space.xxl, height: 36)
    }
}
