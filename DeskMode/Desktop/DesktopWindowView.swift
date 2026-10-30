import UIKit

/// Content hosted inside a desktop window.
@MainActor
protocol WindowContent: UIView {
    var app: DeskApp { get }
    var windowTitle: String { get }
    var onTitleChange: ((String) -> Void)? { get set }
    /// When true the content fills the whole window and draws its own title bar (e.g. the
    /// browser's tab strip). The traffic lights stay; the window still handles dragging for any
    /// point in the top `Theme.titleBarHeight` that no PointerTarget inside the content claims.
    var drawsOwnTitleBar: Bool { get }
    /// Keyboard events reach the content only when its window is focused.
    func handleKey(_ event: KeyEvent) -> Bool
    /// Menu-bar actions (File › New Tab, Edit › Copy …). Return `true` when handled.
    func handleMenuAction(_ action: MenuAction) -> Bool
    func contentDidFocus()
    func contentDidBlur()
    func windowWillClose()
}

extension WindowContent {
    var drawsOwnTitleBar: Bool { false }
}

enum MenuAction {
    case newWindow, newTab, closeTab, closeWindow, reopenClosedTab
    case cut, copy, paste, selectAll, find
    case reload, zoomIn, zoomOut, zoomReset, back, forward, openLocation
    case minimize, zoom, tileLeft, tileRight, tileFull, cycleWindows, closeAllWindows
    case settings, about, launcher, newNote, newTask
    /// Help › Keyboard Shortcuts: the shortcuts sheet.
    case keyboardShortcuts
}

/// The chrome around a `WindowContent`: title bar, traffic lights, drag + resize handling,
/// focus state and open / close / minimise animations.
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
    /// Where the window shrinks to when minimised (superview coordinates), e.g. its Dock icon.
    /// Falls back to the bottom centre of the work area when nil or when it returns nil.
    var minimizeTarget: (() -> CGRect?)?

    private let clipView = UIView()
    private let titleBar = PassThroughView()
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

    /// How far a resize zone reaches inside the frame; the rest lies outside (see `Theme.Size`).
    private let resizeInset: CGFloat = Theme.Size.resizeZone - Theme.Size.resizeOutset
    private var lights: [DeskButton] { [closeButton, minimizeButton, zoomButton] }
    private var lightColors: [UIColor] { [Theme.trafficClose, Theme.trafficMinimize, Theme.trafficZoom] }

    init(content: WindowContent, manager: WindowManager) {
        self.content = content
        self.manager = manager
        super.init(frame: .zero)

        backgroundColor = Theme.windowBackground
        layer.cornerRadius = Theme.Radius.window
        layer.cornerCurve = .continuous
        layer.masksToBounds = false

        clipView.layer.cornerRadius = Theme.Radius.window
        clipView.layer.cornerCurve = .continuous
        clipView.clipsToBounds = true
        addSubview(clipView)
        clipView.addSubview(contentContainer)
        clipView.addSubview(titleBar)
        contentContainer.addSubview(content)

        titleBar.backgroundColor = Theme.titleBarBackground
        hairline.backgroundColor = Theme.hairlineDark
        titleBar.addSubview(hairline)

        titleLabel.font = Theme.font(Theme.Text.body, weight: .semibold)
        titleLabel.textColor = Theme.text
        titleLabel.textAlignment = .center
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.text = content.windowTitle
        titleBar.addSubview(titleLabel)

        let glyphs = ["xmark", "minus", "arrow.up.left.and.arrow.down.right"]
        for (i, button) in lights.enumerated() {
            button.backgroundColor = lightColors[i]
            button.layer.cornerRadius = Theme.Radius.trafficLight
            button.layer.borderWidth = 0.5
            button.layer.borderColor = Theme.trafficBorder.cgColor
            button.showsHoverHighlight = false
            button.onHoverChange = { [weak self, weak button] on in
                guard let self, let button else { return }
                Theme.Motion.animate(Theme.Motion.fast) {
                    button.backgroundColor = self.lightColor(at: i, pressed: on)
                }
            }
            titleBar.addSubview(button)
            let iv = trafficLightSymbols[i]
            iv.image = UIImage(systemName: glyphs[i], withConfiguration: UIImage.SymbolConfiguration(pointSize: 7, weight: .black))?
                .withTintColor(Theme.trafficGlyph, renderingMode: .alwaysOriginal)
            iv.contentMode = .center
            iv.alpha = 0
            iv.isUserInteractionEnabled = false
            button.addSubview(iv)
        }
        closeButton.tooltipText = "Close"
        minimizeButton.tooltipText = "Minimize"
        zoomButton.tooltipText = "Zoom"
        closeButton.onTap = { [weak self] in guard let self else { return }; self.manager.close(self) }
        minimizeButton.onTap = { [weak self] in guard let self else { return }; self.manager.minimize(self) }
        zoomButton.onTap = { [weak self] in guard let self else { return }; self.manager.zoom(self) }

        layer.addSublayer(borderLayer)
        borderLayer.borderWidth = 0.5
        borderLayer.cornerRadius = Theme.Radius.window
        borderLayer.cornerCurve = .continuous

        content.onTitleChange = { [weak self] title in self?.titleLabel.text = title }
        if content.drawsOwnTitleBar {
            titleBar.backgroundColor = .clear
            hairline.isHidden = true
            titleLabel.isHidden = true
        }
        setFocused(false)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        clipView.frame = bounds
        titleBar.frame = CGRect(x: 0, y: 0, width: bounds.width, height: Theme.titleBarHeight)
        hairline.frame = CGRect(x: 0, y: Theme.titleBarHeight - Theme.Size.hairline, width: bounds.width, height: Theme.Size.hairline)
        contentContainer.frame = content.drawsOwnTitleBar
            ? bounds
            : CGRect(x: 0, y: Theme.titleBarHeight, width: bounds.width, height: bounds.height - Theme.titleBarHeight)
        content.frame = contentContainer.bounds
        let d = Theme.Size.trafficLight
        let lightY = (Theme.titleBarHeight - d) / 2
        for (i, button) in lights.enumerated() {
            button.frame = CGRect(x: Theme.Space.m + CGFloat(i) * Theme.Size.trafficLightSpacing, y: lightY, width: d, height: d)
        }
        for iv in trafficLightSymbols { iv.frame = CGRect(x: 0, y: 0, width: d, height: d) }
        let titleInset = Theme.Space.m + CGFloat(lights.count) * Theme.Size.trafficLightSpacing + Theme.Space.s
        titleLabel.frame = CGRect(x: titleInset, y: 0, width: max(0, bounds.width - titleInset * 2), height: Theme.titleBarHeight)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        borderLayer.frame = bounds
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: Theme.Radius.window).cgPath
        CATransaction.commit()
    }

    /// Lets content close its own window (e.g. when the last browser tab is closed).
    func requestClose() { manager.close(self) }

    // MARK: - Focus

    private func lightColor(at index: Int, pressed: Bool) -> UIColor {
        guard hasFocus || trafficHovered else { return Theme.trafficInactive }
        let base = lightColors[index]
        if pressed {
            var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            base.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
            return UIColor(hue: h, saturation: s, brightness: b * 0.82, alpha: a)
        }
        return base
    }

    func setFocused(_ focused: Bool) {
        hasFocus = focused
        if !content.drawsOwnTitleBar { titleBar.backgroundColor = focused ? Theme.titleBarBackground : Theme.titleBarBackgroundInactive }
        titleLabel.textColor = focused ? Theme.text : Theme.secondaryText
        applyShadow(focused ? .windowFocused : .windowInactive)
        borderLayer.borderColor = (focused ? Theme.border : Theme.inactiveBorder).cgColor
        for (i, button) in lights.enumerated() { button.backgroundColor = lightColor(at: i, pressed: button.isHovered) }
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
        if let drag {
            switch drag {
            case .move: return .closedHand
            case .resize(let z, _, _): return Self.resizeCursor(for: z)
            }
        }
        return Self.resizeCursor(for: zone(at: local))
    }

    private static func resizeCursor(for zone: Zone) -> CursorStyle {
        switch zone {
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
        guard trafficHovered != hovered else { return }
        trafficHovered = hovered
        Theme.Motion.animate(Theme.Motion.fast) {
            for iv in self.trafficLightSymbols { iv.alpha = hovered ? 1 : 0 }
            for (i, button) in self.lights.enumerated() { button.backgroundColor = self.lightColor(at: i, pressed: button.isHovered) }
        }
    }

    /// Traffic lights are nested buttons; the desktop asks the window to show their glyphs when
    /// the cursor is anywhere over the title bar (also for content that draws its own title bar).
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
        transform = CGAffineTransform(scaleX: Theme.Motion.appearScale, y: Theme.Motion.appearScale)
        Theme.Motion.spring(0.3) {
            self.alpha = 1
            self.transform = .identity
        }
    }

    func animateClose(completion: @escaping () -> Void) {
        Theme.Motion.animate(Theme.Motion.fast, animations: {
            self.alpha = 0
            self.transform = CGAffineTransform(scaleX: Theme.Motion.disappearScale, y: Theme.Motion.disappearScale)
        }, completion: { _ in completion() })
    }

    /// Shrinks the window toward its Dock icon (or the bottom centre when the Dock has no icon).
    func animateMinimize() {
        let fallback = CGRect(x: manager.workArea.midX - Theme.Size.dockIcon / 2, y: manager.workArea.maxY + Theme.Size.dockBottomMargin,
                              width: Theme.Size.dockIcon, height: Theme.Size.dockIcon)
        let target = minimizeTarget?() ?? fallback
        let scale = max(0.04, min(target.width / max(bounds.width, 1), target.height / max(bounds.height, 1)))
        let center = self.center
        UIView.animate(withDuration: Theme.Motion.slow, delay: 0, options: [.curveEaseIn, .beginFromCurrentState]) {
            self.alpha = 0
            self.transform = CGAffineTransform(translationX: target.midX - center.x, y: target.midY - center.y)
                .scaledBy(x: scale, y: scale)
        } completion: { _ in
            self.isHidden = self.isMinimized
        }
    }

    func animateRestore() {
        isHidden = false
        Theme.Motion.spring(Theme.Motion.slow) {
            self.alpha = 1
            self.transform = .identity
        }
    }

    func animate(to target: CGRect) {
        Theme.Motion.spring(0.3, damping: 0.9) {
            self.frame = target
            self.layoutIfNeeded()
        }
    }
}

extension Notification.Name {
    static let deskWindowContextMenu = Notification.Name("DeskWindowContextMenu")
}
