import UIKit

/// Owns the stack of open windows, focus and z-order. Pure state + geometry; the
/// `DesktopViewController` performs the view work.
@MainActor
final class WindowManager {

    enum Tile { case left, right, full, centered }

    private(set) var windows: [DesktopWindowView] = []
    private(set) weak var focused: DesktopWindowView?

    let container: UIView
    /// Area windows may occupy (below the menu bar, above the dock).
    var workArea: CGRect = .zero

    var onChange: (() -> Void)?
    var onFocusChange: ((DesktopWindowView?) -> Void)?

    private var cascadeIndex = 0

    /// Margin between tiled windows and the edges of the work area, and between tiles.
    static let tileGap: CGFloat = Theme.Space.s
    private static let cascadeInset: CGFloat = Theme.Space.m
    private static let cascadeStep: CGFloat = 28

    init(container: UIView) {
        self.container = container
    }

    var visibleWindows: [DesktopWindowView] { windows.filter { !$0.isMinimized } }
    var minimizedWindows: [DesktopWindowView] { windows.filter { $0.isMinimized } }

    func windows(for app: DeskApp) -> [DesktopWindowView] { windows.filter { $0.app == app } }

    // MARK: - Open / close

    @discardableResult
    func open(_ content: WindowContent, preferredFrame: CGRect? = nil) -> DesktopWindowView {
        let window = DesktopWindowView(content: content, manager: self)
        let frame = preferredFrame ?? cascadeFrame(for: content.app.defaultSize)
        window.frame = frame
        windows.append(window)
        container.addSubview(window)
        window.animateOpen()
        focus(window)
        onChange?()
        return window
    }

    func close(_ window: DesktopWindowView) {
        guard let idx = windows.firstIndex(where: { $0 === window }) else { return }
        windows.remove(at: idx)
        window.content.windowWillClose()
        window.animateClose { window.removeFromSuperview() }
        if focused === window {
            focused = nil
            focus(visibleWindows.last)
        }
        onChange?()
    }

    func closeAll() {
        for w in windows { close(w) }
    }

    // MARK: - Focus & ordering

    func focus(_ window: DesktopWindowView?) {
        if let window {
            if window.isMinimized { restore(window) }
            container.bringSubviewToFront(window)
            if let idx = windows.firstIndex(where: { $0 === window }) {
                windows.remove(at: idx)
                windows.append(window)
            }
        }
        guard focused !== window else { return }
        let old = focused
        focused = window
        old?.setFocused(false)
        window?.setFocused(true)
        onFocusChange?(window)
        onChange?()
    }

    func cycleFocus(backwards: Bool = false) {
        let visible = visibleWindows
        guard visible.count > 1 else { return }
        // `windows` is ordered back-to-front; the front-most is the focused one.
        let next = backwards ? visible.last(where: { $0 !== focused }) : visible.first
        focus(next)
    }

    // MARK: - Minimize / restore

    func minimize(_ window: DesktopWindowView) {
        guard !window.isMinimized else { return }
        window.isMinimized = true
        window.animateMinimize()
        if focused === window {
            focused = nil
            window.setFocused(false)
            focus(visibleWindows.last)
        }
        onChange?()
    }

    func restore(_ window: DesktopWindowView) {
        guard window.isMinimized else { return }
        window.isMinimized = false
        window.animateRestore()
        onChange?()
    }

    // MARK: - Tiling

    /// The frame a tile occupies, shared with the desktop's snap preview.
    func frame(for tile: Tile, of window: DesktopWindowView? = nil) -> CGRect {
        let gap = Self.tileGap
        let area = workArea.insetBy(dx: gap, dy: gap)
        switch tile {
        case .left:
            return CGRect(x: area.minX, y: area.minY, width: (area.width - gap) / 2, height: area.height)
        case .right:
            return CGRect(x: area.midX + gap / 2, y: area.minY, width: (area.width - gap) / 2, height: area.height)
        case .full:
            return area
        case .centered:
            let size = window?.app.defaultSize ?? CGSize(width: area.width * 0.6, height: area.height * 0.7)
            return CGRect(x: area.midX - size.width / 2, y: area.midY - size.height / 2,
                          width: min(size.width, area.width), height: min(size.height, area.height))
        }
    }

    func tile(_ window: DesktopWindowView, _ tile: Tile) {
        window.animate(to: frame(for: tile, of: window))
    }

    /// Toggles between the user's own frame and a zoomed (work-area) frame, like the green button.
    func zoom(_ window: DesktopWindowView) {
        let area = workArea.insetBy(dx: Self.tileGap, dy: Self.tileGap)
        if let saved = window.frameBeforeZoom, window.frame.size == area.size {
            window.frameBeforeZoom = nil
            window.animate(to: saved)
        } else {
            window.frameBeforeZoom = window.frame
            window.animate(to: area)
        }
    }

    // MARK: - Geometry

    private func cascadeFrame(for size: CGSize) -> CGRect {
        // Before the first layout the work area is empty; place the window at its natural size
        // and let `relayout()` put it somewhere sensible once the area is known.
        guard workArea.width > 200, workArea.height > 200 else { return CGRect(origin: .zero, size: size) }
        let area = workArea.insetBy(dx: Self.cascadeInset, dy: Self.cascadeInset)
        let w = min(size.width, area.width)
        let h = min(size.height, area.height)
        let step = Self.cascadeStep
        let maxSteps = Int(max(1, min((area.width - w) / step, (area.height - h) / step)))
        let i = CGFloat(cascadeIndex % max(maxSteps, 1))
        cascadeIndex += 1
        let origin = CGPoint(x: area.minX + (area.width - w) / 2 + i * step - CGFloat(maxSteps) * step / 2,
                             y: area.minY + (area.height - h) / 2 + i * step - CGFloat(maxSteps) * step / 2)
        return CGRect(origin: clampOrigin(origin, size: CGSize(width: w, height: h)), size: CGSize(width: w, height: h))
    }

    func clampOrigin(_ origin: CGPoint, size: CGSize) -> CGPoint {
        let area = workArea
        let x = min(max(origin.x, area.minX - size.width + 120), area.maxX - 120)
        let y = min(max(origin.y, area.minY), area.maxY - 60)
        return CGPoint(x: x, y: y)
    }

    /// Keeps windows reachable after the display size changes.
    func relayout() {
        guard workArea.width > 200, workArea.height > 200 else { return }
        for w in windows {
            var f = w.frame
            if f.width < 200 || f.height < 150 || (f.origin == .zero && !w.isMinimized) {
                // Opened before the display had a size (or collapsed): give it a proper frame.
                f = cascadeFrame(for: w.app.defaultSize)
            }
            f.size.width = min(f.width, workArea.width)
            f.size.height = min(f.height, workArea.height)
            f.origin = clampOrigin(f.origin, size: f.size)
            w.frame = f
        }
    }
}
