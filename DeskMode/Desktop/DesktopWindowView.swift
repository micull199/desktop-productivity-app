import UIKit

/// Content hosted inside a desktop window.
@MainActor
protocol WindowContent: UIView {
    var app: DeskApp { get }
    var windowTitle: String { get }
    var onTitleChange: ((String) -> Void)? { get set }
    /// Keyboard events reach the content only when its window is focused.
    func handleKey(_ event: KeyEvent) -> Bool
    /// Menu-bar actions (File › New Tab, Edit › Copy …). Return `true` when handled.
    func handleMenuAction(_ action: MenuAction) -> Bool
    func contentDidFocus()
    func contentDidBlur()
    func windowWillClose()
}

enum MenuAction {
    case newWindow, newTab, closeTab, closeWindow, reopenClosedTab
    case cut, copy, paste, selectAll, find
    case reload, zoomIn, zoomOut, zoomReset, back, forward, openLocation
    case minimize, zoom, tileLeft, tileRight, tileFull, cycleWindows, closeAllWindows
    case settings, about, launcher, newNote, newTask
}

/// The chrome around a `WindowContent`: title bar, traffic lights, drag + resize handling,
/// focus state and open/close animations.
final class DesktopWindowView: UIView, PointerTarget {

    private enum Zone { case titleBar, content, top, bottom, left, right, topLeft, topRight, bottomLeft, bottomRight }
    private enum Drag { case move(offset: CGPoint), resize(zone: Zone, origin: CGRect, start: CGPoint) }

    let content: WindowContent
    private unowned let manager: WindowManager

    var app: DeskApp { content.app }
    var isMinimized = false
    var frameBeforeZoom: CGRect?
    private(set) var hasFocus = false

    /// Called while dragging near a screen edge so the desktop can show a snap preview.
    var onSnapPreview: ((WindowManager.Tile?) -> Void)?

    private let clipView = UIView()
    private let titleBar = UIView()
    private let hairline = UIView()
    private let titleLabel = UILabel()
    private let closeButton = DeskButton(style: .plain)
    private let minimizeButton = DeskButton(style: .plain)
    private let zoomButton = DeskButton(style: .plain)
    private let trafficLightSymbols = [UIImageView(), UIImageView(), UIImageView()]
    private let contentContainer = UIView()
    private let borderLayer = CALayer()
    private var drag: Drag?
    private var pendingSnap: WindowManager.Tile?
    private var trafficHovered = false

    private let resizeInset: CGFloat = 6

    init(content: WindowContent, manager: WindowManager) {
        self.content = content
        self.manager = manager
        super.init(frame: .zero)

        backgroundColor = Theme.windowBackground
        layer.cornerRadius = Theme.windowCornerRadius
        layer.cornerCurve = .continuous
        layer.masksToBounds = false
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOffset = CGSize(width: 0, height: 14)

        clipView.layer.cornerRadius = Theme.windowCornerRadius
        clipView.layer.cornerCurve = .continuous
        clipView.clipsToBounds = true
        addSubview(clipView)
        clipView.addSubview(contentContainer)
        clipView.addSubview(titleBar)
        contentContainer.addSubview(content)

        titleBar.backgroundColor = Theme.titleBarBackground
        hairline.backgroundColor = UIColor(white: 0, alpha: 0.35)
        titleBar.addSubview(hairline)

        titleLabel.font = Theme.font(13, weight: .semibold)
        titleLabel.textColor = Theme.text
        titleLabel.textAlignment = .center
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.text = content.windowTitle
        titleBar.addSubview(titleLabel)

        let lights: [(DeskButton, UIColor, String)] = [
            (closeButton, Theme.trafficClose, "xmark"),
            (minimizeButton, Theme.trafficMinimize, "minus"),
            (zoomButton, Theme.trafficZoom, "arrow.up.left.and.arrow.down.right")
        ]
        for (i, (button, color, symbol)) in lights.enumerated() {
            button.backgroundColor = color
            button.layer.cornerRadius = 6
            button.layer.borderWidth = 0.5
            button.layer.borderColor = UIColor(white: 0, alpha: 0.25).cgColor
            button.showsHoverHighlight = false
            titleBar.addSubview(button)
            let iv = trafficLightSymbols[i]
            iv.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 7, weight: .black))?
                .withTintColor(UIColor(white: 0, alpha: 0.6), renderingMode: .alwaysOriginal)
            iv.contentMode = .center
            iv.isHidden = true
            iv.isUserInteractionEnabled = false
            button.addSubview(iv)
        }
        closeButton.onTap = { [weak self] in guard let self else { return }; self.manager.close(self) }
        minimizeButton.onTap = { [weak self] in guard let self else { return }; self.manager.minimize(self) }
        zoomButton.onTap = { [weak self] in guard let self else { return }; self.manager.zoom(self) }

        layer.addSublayer(borderLayer)
        borderLayer.borderWidth = 0.5
        borderLayer.cornerRadius = Theme.windowCornerRadius
        borderLayer.cornerCurve = .continuous

        content.onTitleChange = { [weak self] title in self?.titleLabel.text = title }
        setFocused(false)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        clipView.frame = bounds
        titleBar.frame = CGRect(x: 0, y: 0, width: bounds.width, height: Theme.titleBarHeight)
        hairline.frame = CGRect(x: 0, y: Theme.titleBarHeight - 1, width: bounds.width, height: 1)
        contentContainer.frame = CGRect(x: 0, y: Theme.titleBarHeight, width: bounds.width, height: bounds.height - Theme.titleBarHeight)
        content.frame = contentContainer.bounds
        let lightY = (Theme.titleBarHeight - 12) / 2
        closeButton.frame = CGRect(x: 12, y: lightY, width: 12, height: 12)
        minimizeButton.frame = CGRect(x: 32, y: lightY, width: 12, height: 12)
        zoomButton.frame = CGRect(x: 52, y: lightY, width: 12, height: 12)
        for iv in trafficLightSymbols { iv.frame = CGRect(x: 0, y: 0, width: 12, height: 12) }
        titleLabel.frame = CGRect(x: 80, y: 0, width: bounds.width - 160, height: Theme.titleBarHeight)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        borderLayer.frame = bounds
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: Theme.windowCornerRadius).cgPath
        CATransaction.commit()
    }

    /// Lets content close its own window (e.g. when the last browser tab is closed).
    func requestClose() { manager.close(self) }

    // MARK: - Focus

    func setFocused(_ focused: Bool) {
        hasFocus = focused
        titleBar.backgroundColor = focused ? Theme.titleBarBackground : Theme.titleBarBackgroundInactive
        titleLabel.textColor = focused ? Theme.text : Theme.secondaryText
        layer.shadowOpacity = focused ? 0.55 : 0.3
        layer.shadowRadius = focused ? 28 : 14
        borderLayer.borderColor = (focused ? Theme.border : UIColor(white: 1, alpha: 0.08)).cgColor
        closeButton.backgroundColor = focused ? Theme.trafficClose : Theme.trafficInactive
        minimizeButton.backgroundColor = focused ? Theme.trafficMinimize : Theme.trafficInactive
        zoomButton.backgroundColor = focused ? Theme.trafficZoom : Theme.trafficInactive
        if focused { content.contentDidFocus() } else { content.contentDidBlur() }
    }

    // MARK: - Pointer

    private func zone(at local: CGPoint) -> Zone {
        let r = resizeInset
        let b = bounds
        let left = local.x < r, right = local.x > b.width - r
        let top = local.y < r, bottom = local.y > b.height - r
        switch (top, bottom, left, right) {
        case (true, _, true, _): return .topLeft
        case (true, _, _, true): return .topRight
        case (_, true, true, _): return .bottomLeft
        case (_, true, _, true): return .bottomRight
        case (true, _, _, _): return .top
        case (_, true, _, _): return .bottom
        case (_, _, true, _): return .left
        case (_, _, _, true): return .right
        default: return local.y < Theme.titleBarHeight ? .titleBar : .content
        }
    }

    func cursorStyle(at local: CGPoint) -> CursorStyle {
        if case .move? = drag { return .closedHand }
        switch zone(at: local) {
        case .left, .right: return .resizeHorizontal
        case .top, .bottom: return .resizeVertical
        case .topLeft, .bottomRight: return .resizeDiagonalNWSE
        case .topRight, .bottomLeft: return .resizeDiagonalNESW
        default: return .arrow
        }
    }

    func pointerEntered() {
        setTrafficHovered(true)
    }

    func pointerExited() {
        setTrafficHovered(false)
    }

    private func setTrafficHovered(_ hovered: Bool) {
        trafficHovered = hovered
        for iv in trafficLightSymbols { iv.isHidden = !hovered }
    }

    /// Traffic lights are nested buttons; the desktop asks the window to show their glyphs when
    /// the cursor is anywhere over the title bar.
    func trafficLightsHover(_ hovered: Bool) { setTrafficHovered(hovered) }

    func pointer(_ event: PointerEvent, local: CGPoint) {
        switch event.kind {
        case .down(.left):
            let z = zone(at: local)
            switch z {
            case .titleBar:
                if event.clickCount == 2 { manager.zoom(self); return }
                drag = .move(offset: CGPoint(x: event.location.x - frame.minX, y: event.location.y - frame.minY))
            case .content:
                break
            default:
                drag = .resize(zone: z, origin: frame, start: event.location)
            }
        case .move:
            guard let drag else { return }
            switch drag {
            case .move(let offset):
                var origin = CGPoint(x: event.location.x - offset.x, y: event.location.y - offset.y)
                origin = manager.clampOrigin(origin, size: frame.size)
                frame.origin = origin
                frameBeforeZoom = nil
                updateSnap(for: event.location)
            case .resize(let z, let origin, let start):
                frame = resized(origin, zone: z, dx: event.location.x - start.x, dy: event.location.y - start.y)
            }
        case .up(.left):
            if drag != nil {
                drag = nil
                if let snap = pendingSnap {
                    pendingSnap = nil
                    onSnapPreview?(nil)
                    manager.tile(self, snap)
                }
            }
        case .down(.right):
            if zone(at: local) == .titleBar {
                NotificationCenter.default.post(name: .deskWindowContextMenu, object: self, userInfo: ["point": NSValue(cgPoint: event.location)])
            }
        default:
            break
        }
    }

    private func updateSnap(for cursor: CGPoint) {
        let area = manager.workArea
        var snap: WindowManager.Tile?
        if cursor.x <= area.minX + 2 { snap = .left }
        else if cursor.x >= area.maxX - 3 { snap = .right }
        else if cursor.y <= area.minY + 1 { snap = .full }
        if snap != pendingSnap {
            pendingSnap = snap
            onSnapPreview?(snap)
        }
    }

    private func resized(_ origin: CGRect, zone: Zone, dx: CGFloat, dy: CGFloat) -> CGRect {
        var f = origin
        let minSize = app.minimumSize
        func growRight(_ d: CGFloat) { f.size.width = max(minSize.width, origin.width + d) }
        func growBottom(_ d: CGFloat) { f.size.height = max(minSize.height, origin.height + d) }
        func growLeft(_ d: CGFloat) {
            let w = max(minSize.width, origin.width - d)
            f.origin.x = origin.maxX - w
            f.size.width = w
        }
        func growTop(_ d: CGFloat) {
            let h = max(minSize.height, origin.height - d)
            f.origin.y = max(manager.workArea.minY, origin.maxY - h)
            f.size.height = origin.maxY - f.origin.y
        }
        switch zone {
        case .right: growRight(dx)
        case .left: growLeft(dx)
        case .bottom: growBottom(dy)
        case .top: growTop(dy)
        case .bottomRight: growRight(dx); growBottom(dy)
        case .bottomLeft: growLeft(dx); growBottom(dy)
        case .topRight: growRight(dx); growTop(dy)
        case .topLeft: growLeft(dx); growTop(dy)
        default: break
        }
        return f
    }

    // MARK: - Animations

    func animateOpen() {
        alpha = 0
        transform = CGAffineTransform(scaleX: 0.94, y: 0.94)
        UIView.animate(withDuration: 0.22, delay: 0, options: [.curveEaseOut]) {
            self.alpha = 1
            self.transform = .identity
        }
    }

    func animateClose(completion: @escaping () -> Void) {
        UIView.animate(withDuration: 0.16, delay: 0, options: [.curveEaseIn]) {
            self.alpha = 0
            self.transform = CGAffineTransform(scaleX: 0.95, y: 0.95)
        } completion: { _ in completion() }
    }

    func animateMinimize() {
        let target = CGPoint(x: manager.workArea.midX, y: manager.workArea.maxY + 60)
        UIView.animate(withDuration: 0.28, delay: 0, options: [.curveEaseIn]) {
            self.alpha = 0
            self.transform = CGAffineTransform(translationX: target.x - self.center.x, y: target.y - self.center.y)
                .scaledBy(x: 0.1, y: 0.1)
        } completion: { _ in
            self.isHidden = self.isMinimized
        }
    }

    func animateRestore() {
        isHidden = false
        UIView.animate(withDuration: 0.28, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0.5) {
            self.alpha = 1
            self.transform = .identity
        }
    }

    func animate(to target: CGRect) {
        UIView.animate(withDuration: 0.25, delay: 0, usingSpringWithDamping: 0.9, initialSpringVelocity: 0.4) {
            self.frame = target
            self.layoutIfNeeded()
        }
    }
}

extension Notification.Name {
    static let deskWindowContextMenu = Notification.Name("DeskWindowContextMenu")
}
