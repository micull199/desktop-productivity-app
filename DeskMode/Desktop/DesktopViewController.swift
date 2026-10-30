import UIKit
import Combine

/// Root of the external display. Owns wallpaper, menu bar, windows, dock, launcher, popups,
/// dialogs, toasts, tooltips and the cursor, and routes every pointer / key event to the right
/// target.
final class DesktopViewController: UIViewController, InputSink {

    var onWindowCountChange: ((Int) -> Void)?

    /// When true the desktop is being shown on the phone itself and touches drive the cursor.
    var allowsTouchInput = false {
        didSet { touchCapture.isUserInteractionEnabled = allowsTouchInput }
    }

    private let wallpaper = CAGradientLayer()
    private let wallpaperGlows = [CAGradientLayer(), CAGradientLayer()]
    private let windowContainer = UIView()
    private let menuBar = MenuBarView()
    private let dock = DockView()
    private let overlay = PassThroughView() // popups, launcher, dialogs, toasts, tooltips
    private let snapPreview = Theme.materialView(.panel, cornerRadius: Theme.Radius.window)
    private let touchCapture = TouchCaptureView()
    private let cursorView = CursorView()
    private lazy var windowManager = WindowManager(container: windowContainer)
    private lazy var tooltips = TooltipPresenter(container: overlay)

    private var hovered: (PointerTarget, UIView)?
    private var captured: (PointerTarget, UIView)?
    private var popup: PopupMenuView?
    private var launcher: LauncherView?
    private var dialog: DialogPanelView?
    private var toastViews: [ToastView] = []

    private let input = InputRouter.shared
    private let settings = Settings.shared

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        view.layer.addSublayer(wallpaper)
        wallpaper.startPoint = CGPoint(x: 0, y: 0)
        wallpaper.endPoint = CGPoint(x: 1, y: 1)
        for glow in wallpaperGlows {
            glow.type = .radial
            glow.locations = [0, 1]
            view.layer.addSublayer(glow)
        }
        applyWallpaper(animated: false)

        view.addSubview(windowContainer)
        view.addSubview(snapPreview)
        view.addSubview(menuBar)
        view.addSubview(dock)
        view.addSubview(overlay)
        view.addSubview(touchCapture)
        view.addSubview(cursorView)
        touchCapture.isUserInteractionEnabled = allowsTouchInput
        touchCapture.onBegan = { [weak self] p in self?.input.moveCursor(to: p); self?.input.button(.left, pressed: true) }
        touchCapture.onMoved = { [weak self] p in self?.input.moveCursor(to: p) }
        touchCapture.onEnded = { [weak self] p in self?.input.moveCursor(to: p); self?.input.button(.left, pressed: false) }

        snapPreview.layer.borderWidth = Theme.Size.hairline
        snapPreview.layer.borderColor = Theme.borderStrong.cgColor
        snapPreview.contentView.backgroundColor = Theme.snapPreviewFill
        snapPreview.alpha = 0
        snapPreview.isHidden = true
        snapPreview.isUserInteractionEnabled = false

        overlay.backgroundColor = .clear

        menuBar.onAction = { [weak self] action in self?.performAction(action) }
        menuBar.presentMenu = { [weak self] menu, anchor in
            guard let self else { return }
            let rect = self.menuBar.convert(anchor, to: self.view)
            self.present(menu, at: CGPoint(x: rect.minX, y: self.menuBar.frame.maxY))
        }

        dock.onOpenApp = { [weak self] app in self?.open(app) }
        dock.onNewWindow = { [weak self] app in self?.open(app, forceNew: true) }
        dock.onCloseApp = { [weak self] app in self?.closeAll(app) }
        dock.onRestoreWindow = { [weak self] w in self?.windowManager.focus(w) }
        dock.onLauncher = { [weak self] in self?.toggleLauncher() }
        dock.presentMenu = { [weak self] menu, anchor in
            guard let self else { return }
            let rect = self.dock.convert(anchor, to: self.view)
            self.present(menu, at: CGPoint(x: rect.midX - menu.bounds.width / 2, y: rect.minY - menu.bounds.height - Theme.Space.s))
        }

        windowManager.onChange = { [weak self] in self?.windowsDidChange() }
        windowManager.onFocusChange = { [weak self] w in self?.menuBar.setFocusedApp(w?.app) }

        NotificationCenter.default.addObserver(self, selector: #selector(windowContextMenu(_:)), name: .deskWindowContextMenu, object: nil)

        input.sink = self
        menuBar.setInputStatus(keyboard: input.keyboardConnected, mouse: input.mouseConnected)
        observeInputStatus()
        observeSettings()
        #if DEBUG
        startSnapshotTimer()
        #endif
    }

    #if DEBUG
    private var snapshotTimer: Timer?

    /// Debug builds write Documents/desktop.png every few seconds while on the external display,
    /// so the desktop can be reviewed from a Mac with `devicectl device copy from`.
    private func startSnapshotTimer() {
        snapshotTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.writeSnapshot() }
        }
    }

    private func writeSnapshot() {
        guard !allowsTouchInput, view.window != nil, view.bounds.width > 0 else { return }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(bounds: view.bounds, format: format).image { _ in
            view.drawHierarchy(in: view.bounds, afterScreenUpdates: false)
        }
        guard let data = image.pngData() else { return }
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("desktop.png")
        DispatchQueue.global(qos: .utility).async { try? data.write(to: url, options: .atomic) }
    }
    #endif

    private var openedInitialWindow = false

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        cursorView.place(at: input.cursor)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let b = view.bounds
        layoutWallpaper(in: b)
        windowContainer.frame = b
        overlay.frame = b
        touchCapture.frame = b
        menuBar.frame = CGRect(x: 0, y: 0, width: b.width, height: Theme.menuBarHeight)
        let dockSize = dock.intrinsicContentSize
        dock.frame = CGRect(x: ((b.width - dockSize.width) / 2).rounded(), y: b.height - dockSize.height - Theme.Size.dockBottomMargin,
                            width: dockSize.width, height: dockSize.height)
        windowManager.workArea = CGRect(x: 0, y: Theme.menuBarHeight, width: b.width,
                                        height: b.height - Theme.menuBarHeight - Theme.dockHeight - Theme.Size.dockBottomMargin)
        windowManager.relayout()
        input.desktopBounds = b
        if !openedInitialWindow, b.width > 200, b.height > 200 {
            // First real layout: open the browser so the desktop is immediately useful.
            openedInitialWindow = true
            if windowManager.windows.isEmpty { open(.browser) }
            cursorView.place(at: input.cursor)
        }
        if let launcher { positionLauncher(launcher) }
        positionToasts(animated: false)
        view.bringSubviewToFront(cursorView)
    }

    func desktopWillDisconnect() {
        if input.sink === self { input.sink = nil }
    }

    private var statusObservers: [Any] = []

    private func observeInputStatus() {
        statusObservers.append(input.$keyboardConnected.sink { [weak self] kb in
            guard let self else { return }
            self.menuBar.setInputStatus(keyboard: kb, mouse: self.input.mouseConnected)
        })
        statusObservers.append(input.$mouseConnected.sink { [weak self] m in
            guard let self else { return }
            self.menuBar.setInputStatus(keyboard: self.input.keyboardConnected, mouse: m)
        })
    }

    private func observeSettings() {
        statusObservers.append(settings.$wallpaper.sink { [weak self] _ in
            DispatchQueue.main.async { self?.applyWallpaper(animated: true) }
        })
    }

    // MARK: - Wallpaper

    /// Base linear gradient plus two large soft radial highlights. Switching wallpapers
    /// crossfades: standalone layers animate colour changes implicitly within the transaction.
    private func applyWallpaper(animated: Bool) {
        let wp = settings.wallpaper
        CATransaction.begin()
        if animated {
            CATransaction.setAnimationDuration(Theme.Motion.slow)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
        } else {
            CATransaction.setDisableActions(true)
        }
        wallpaper.colors = Theme.wallpaperColors(wp)
        let highlights = Theme.wallpaperHighlights(wp)
        for (i, glow) in wallpaperGlows.enumerated() {
            guard highlights.indices.contains(i) else { glow.isHidden = true; continue }
            glow.isHidden = false
            glow.colors = [highlights[i].color.cgColor, highlights[i].color.withAlphaComponent(0).cgColor]
        }
        CATransaction.commit()
        layoutWallpaper(in: view.bounds)
    }

    private func layoutWallpaper(in bounds: CGRect) {
        guard bounds.width > 0, bounds.height > 0 else { return }
        let highlights = Theme.wallpaperHighlights(settings.wallpaper)
        let aspect = bounds.width / bounds.height
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        wallpaper.frame = bounds
        for (i, glow) in wallpaperGlows.enumerated() {
            glow.frame = bounds
            guard highlights.indices.contains(i) else { continue }
            let h = highlights[i]
            glow.startPoint = h.center
            glow.endPoint = CGPoint(x: h.center.x + h.radius, y: h.center.y + h.radius * aspect)
        }
        CATransaction.commit()
    }

    // MARK: - Apps & windows

    @discardableResult
    func open(_ app: DeskApp, forceNew: Bool = false, url: URL? = nil) -> DesktopWindowView? {
        if !forceNew || !app.supportsMultipleWindows, let existing = windowManager.windows(for: app).last {
            windowManager.focus(existing)
            if let url, let browser = existing.content as? BrowserWindowContent { browser.openTab(url: url) }
            return existing
        }
        let content: WindowContent
        switch app {
        case .browser:
            let browser = BrowserWindowContent(desktop: self)
            if let url { browser.openTab(url: url) } else if browser.tabs.isEmpty { browser.openTab(url: nil) }
            content = browser
        case .notes: content = NotesWindowContent()
        case .tasks: content = TasksWindowContent()
        case .settings: content = SettingsWindowContent()
        }
        let window = windowManager.open(content)
        window.onSnapPreview = { [weak self] tile in self?.showSnapPreview(tile) }
        window.minimizeTarget = { [weak self] in self?.dock.frame(for: app) }
        dock.bounce(app)
        return window
    }

    func closeAll(_ app: DeskApp) {
        for w in windowManager.windows(for: app) { windowManager.close(w) }
    }

    private func windowsDidChange() {
        let running = Set(windowManager.windows.map { $0.app })
        dock.update(running: running, minimized: windowManager.minimizedWindows)
        onWindowCountChange?(windowManager.windows.count)
        view.setNeedsLayout()
    }

    private func showSnapPreview(_ tile: WindowManager.Tile?) {
        guard let tile else {
            Theme.Motion.animate(Theme.Motion.fast, animations: { self.snapPreview.alpha = 0 }) { _ in
                if self.snapPreview.alpha == 0 { self.snapPreview.isHidden = true }
            }
            return
        }
        let target = windowManager.frame(for: tile)
        if snapPreview.isHidden {
            snapPreview.isHidden = false
            snapPreview.frame = target.insetBy(dx: target.width * 0.02, dy: target.height * 0.02)
        }
        Theme.Motion.spring(Theme.Motion.slow) {
            self.snapPreview.alpha = 1
            self.snapPreview.frame = target
        }
    }

    // MARK: - Popups

    private func present(_ menu: PopupMenuView, at origin: CGPoint) {
        dismissPopup()
        tooltips.cancel()
        var o = origin
        o.x = min(max(Theme.Space.s, o.x), view.bounds.width - menu.bounds.width - Theme.Space.s)
        o.y = min(max(Theme.menuBarHeight, o.y), view.bounds.height - menu.bounds.height - Theme.Space.s)
        menu.frame.origin = o
        let previousDismiss = menu.onDismiss
        menu.onDismiss = { [weak self, weak menu] in
            previousDismiss?()
            if let menu, self?.popup === menu { self?.dismissPopup() }
        }
        overlay.addSubview(menu)
        popup = menu
        menu.alpha = 0
        menu.transform = CGAffineTransform(translationX: 0, y: -Theme.Space.xs)
        Theme.Motion.animate(Theme.Motion.fast) {
            menu.alpha = 1
            menu.transform = .identity
        }
    }

    func presentContextMenu(items: [MenuItem], at point: CGPoint) {
        present(PopupMenuView(items: items, minWidth: 200), at: point)
    }

    private func dismissPopup() {
        guard let popup else { return }
        self.popup = nil
        let dismissHandler = popup.onDismiss
        popup.onDismiss = nil
        dismissHandler?()
        Theme.Motion.animate(Theme.Motion.fast, animations: { popup.alpha = 0 }) { _ in popup.removeFromSuperview() }
    }

    // MARK: - Launcher

    func toggleLauncher() {
        if launcher != nil { dismissLauncher(); return }
        dismissPopup()
        tooltips.cancel()
        let l = LauncherView()
        l.onDismiss = { [weak self] in self?.dismissLauncher() }
        l.onSelect = { [weak self] result in
            guard let self else { return }
            self.dismissLauncher()
            switch result {
            case .app(let app): self.open(app)
            case .search(let q): self.open(.browser, url: Settings.shared.searchEngine.searchURL(for: q))
            case .url(let u): self.open(.browser, url: u)
            }
        }
        overlay.addSubview(l)
        launcher = l
        l.activate()
        positionLauncher(l)
        l.layoutIfNeeded()
        l.alpha = 0
        l.transform = CGAffineTransform(scaleX: Theme.Motion.appearScale, y: Theme.Motion.appearScale)
        Theme.Motion.spring(0.3) {
            l.alpha = 1
            l.transform = .identity
        }
    }

    /// Horizontally centred, top edge at 22 % of the screen; the frame grows downward with results.
    private func positionLauncher(_ l: LauncherView) {
        let b = view.bounds
        l.frame.origin = CGPoint(x: ((b.width - l.bounds.width) / 2).rounded(), y: (b.height * 0.22).rounded())
    }

    private func dismissLauncher() {
        guard let l = launcher else { return }
        launcher = nil
        Theme.Motion.animate(Theme.Motion.fast, animations: { l.alpha = 0 }) { _ in l.removeFromSuperview() }
    }

    // MARK: - Toasts

    func showToast(_ text: String) {
        showToast(text, symbol: nil)
    }

    /// Notification-style card in the top-right corner; slides in from the right and fades
    /// after `Theme.Timing.toastDuration`. Several toasts stack vertically.
    func showToast(_ text: String, symbol: String?) {
        let toast = ToastView(text: text, symbol: symbol)
        toastViews.append(toast)
        overlay.addSubview(toast)
        toast.alpha = 0
        positionToasts(animated: false)
        toast.transform = CGAffineTransform(translationX: toast.bounds.width + Theme.Space.l, y: 0)
        Theme.Motion.spring(Theme.Motion.slow) {
            toast.alpha = 1
            toast.transform = .identity
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Theme.Timing.toastDuration) { [weak self, weak toast] in
            guard let self, let toast, self.toastViews.contains(where: { $0 === toast }) else { return }
            Theme.Motion.animate(Theme.Motion.normal, animations: {
                toast.alpha = 0
                toast.transform = CGAffineTransform(translationX: Theme.Space.l, y: 0)
            }) { _ in
                toast.removeFromSuperview()
                self.toastViews.removeAll { $0 === toast }
                self.positionToasts(animated: true)
            }
        }
    }

    private func positionToasts(animated: Bool) {
        var y = Theme.menuBarHeight + Theme.Space.m
        let right = view.bounds.width - Theme.Space.m
        for toast in toastViews {
            let origin = CGPoint(x: right - toast.bounds.width, y: y)
            if animated {
                Theme.Motion.animate(Theme.Motion.normal) { toast.frame.origin = origin }
            } else {
                toast.frame.origin = origin
            }
            y += toast.bounds.height + Theme.Space.s
        }
    }

    // MARK: - Dialogs

    private func present(_ panel: DialogPanelView) {
        dismissDialog()
        dismissPopup()
        tooltips.cancel()
        panel.onClose = { [weak self] in self?.dismissDialog() }
        panel.center = CGPoint(x: view.bounds.midX, y: view.bounds.midY - Theme.Space.xl)
        panel.frame = panel.frame.integral
        overlay.addSubview(panel)
        dialog = panel
        panel.alpha = 0
        panel.transform = CGAffineTransform(scaleX: Theme.Motion.appearScale, y: Theme.Motion.appearScale)
        Theme.Motion.spring(0.3) {
            panel.alpha = 1
            panel.transform = .identity
        }
    }

    private func dismissDialog() {
        guard let dialog else { return }
        self.dialog = nil
        Theme.Motion.animate(Theme.Motion.fast, animations: {
            dialog.alpha = 0
            dialog.transform = CGAffineTransform(scaleX: Theme.Motion.disappearScale, y: Theme.Motion.disappearScale)
        }) { _ in dialog.removeFromSuperview() }
    }

    private func showAbout() {
        present(AboutPanelView(displaySize: view.bounds.size, displayScale: view.traitCollection.displayScale))
    }

    private func showShortcuts() {
        present(ShortcutsPanelView())
    }

    // MARK: - Menu actions

    func performAction(_ action: MenuAction) {
        let focused = windowManager.focused
        switch action {
        case .about: showAbout()
        case .keyboardShortcuts: showShortcuts()
        case .settings: open(.settings)
        case .launcher: toggleLauncher()
        case .newWindow: open(.browser, forceNew: true)
        case .newNote: _ = open(.notes)?.content.handleMenuAction(.newNote)
        case .newTask: _ = open(.tasks)?.content.handleMenuAction(.newTask)
        case .closeWindow: if let focused { windowManager.close(focused) }
        case .closeAllWindows: if let focused { closeAll(focused.app) }
        case .minimize: if let focused { windowManager.minimize(focused) }
        case .zoom: if let focused { windowManager.zoom(focused) }
        case .tileLeft: if let focused { windowManager.tile(focused, .left) }
        case .tileRight: if let focused { windowManager.tile(focused, .right) }
        case .tileFull: if let focused { windowManager.tile(focused, .full) }
        case .cycleWindows: windowManager.cycleFocus()
        default:
            if let focused, focused.content.handleMenuAction(action) { return }
            if action == .closeTab, let focused { windowManager.close(focused) }
        }
    }

    // MARK: - Context menus

    @objc private func windowContextMenu(_ note: Notification) {
        guard let window = note.object as? DesktopWindowView,
              let point = (note.userInfo?["point"] as? NSValue)?.cgPointValue else { return }
        let items: [MenuItem] = [
            MenuItem(title: "Minimize", symbol: "minus") { [weak self] in self?.windowManager.minimize(window) },
            MenuItem(title: "Zoom", symbol: "arrow.up.left.and.arrow.down.right") { [weak self] in self?.windowManager.zoom(window) },
            .separator,
            MenuItem(title: "Tile Left", symbol: "rectangle.lefthalf.filled") { [weak self] in self?.windowManager.tile(window, .left) },
            MenuItem(title: "Tile Right", symbol: "rectangle.righthalf.filled") { [weak self] in self?.windowManager.tile(window, .right) },
            MenuItem(title: "Center", symbol: "rectangle.center.inset.filled") { [weak self] in self?.windowManager.tile(window, .centered) },
            .separator,
            MenuItem(title: "Close", symbol: "xmark") { [weak self] in self?.windowManager.close(window) }
        ]
        presentContextMenu(items: items, at: point)
    }

    private func desktopContextMenu(at point: CGPoint) {
        var items: [MenuItem] = [
            MenuItem(title: "New \(DeskApp.browser.title) Window", symbol: DeskApp.browser.symbolName) { [weak self] in self?.open(.browser, forceNew: true) },
            MenuItem(title: "New Note", symbol: DeskApp.notes.symbolName) { [weak self] in self?.performAction(.newNote) },
            MenuItem(title: "New Task", symbol: DeskApp.tasks.symbolName) { [weak self] in self?.performAction(.newTask) },
            .separator
        ]
        for wp in Wallpaper.allCases {
            items.append(MenuItem(title: "Wallpaper: \(wp.title)", isChecked: settings.wallpaper == wp) { Settings.shared.wallpaper = wp })
        }
        items.append(.separator)
        items.append(MenuItem(title: "Settings…", symbol: DeskApp.settings.symbolName) { [weak self] in self?.open(.settings) })
        presentContextMenu(items: items, at: point)
    }

    // MARK: - Hit testing

    /// Finds the `PointerTarget` under a desktop point.
    ///
    /// Overlay content (menus, launcher, dialogs) and the chrome always win. Otherwise a window's
    /// resize zone (`Theme.Size.resizeZone`, extending `resizeOutset` beyond its frame) wins over
    /// anything inside the window. Finally the hit view's ancestors are walked up to the nearest
    /// target; for content that draws its own title bar this walk reaches the window itself for
    /// any point in the top `Theme.titleBarHeight` that no inner target claims, so dragging works.
    private func target(at point: CGPoint) -> (PointerTarget, UIView)? {
        let touchEnabled = touchCapture.isUserInteractionEnabled
        touchCapture.isUserInteractionEnabled = false
        defer { touchCapture.isUserInteractionEnabled = touchEnabled }
        guard let hit = view.hitTest(point, with: nil) else { return nil }

        let isOverlay = hit.isDescendant(of: overlay) || hit.isDescendant(of: menuBar) || hit.isDescendant(of: dock)
        if !isOverlay {
            let outset = Theme.Size.resizeOutset
            let inset = Theme.Size.resizeZone - Theme.Size.resizeOutset
            for w in windowManager.visibleWindows.reversed() {
                let f = w.frame
                if f.insetBy(dx: -outset, dy: -outset).contains(point), !f.insetBy(dx: inset, dy: inset).contains(point) {
                    return (w, w)
                }
                if f.contains(point) { break }
            }
        }
        var v: UIView? = hit
        while let cur = v {
            if let t = cur as? PointerTarget { return (t, cur) }
            v = cur.superview
        }
        return nil
    }

    private func window(containing view: UIView) -> DesktopWindowView? {
        var v: UIView? = view
        while let cur = v {
            if let w = cur as? DesktopWindowView { return w }
            v = cur.superview
        }
        return nil
    }

    // MARK: - InputSink

    func handlePointer(_ event: PointerEvent) {
        cursorView.place(at: event.location)

        // While a button is held, the target that received the press keeps receiving events.
        if let (target, targetView) = captured {
            let local = view.convert(event.location, to: targetView)
            target.pointer(event, local: local)
            cursorView.style = target.cursorStyle(at: local)
            if case .up(.left) = event.kind {
                captured = nil
                updateHover(at: event.location)
            }
            return
        }

        switch event.kind {
        case .move:
            updateHover(at: event.location)
        case .down(let button):
            tooltips.hide()
            let found = target(at: event.location)
            if let popup {
                let insideMenu = found.map { $0.1.isDescendant(of: popup) } ?? false
                if !insideMenu {
                    dismissPopup()
                    return
                }
            }
            if let launcher {
                let insideLauncher = found.map { $0.1.isDescendant(of: launcher) } ?? false
                if !insideLauncher { dismissLauncher() }
            }
            if let (_, tv) = found, let w = window(containing: tv) {
                windowManager.focus(w)
            }
            guard let (target, targetView) = found else {
                if button == .right { desktopContextMenu(at: event.location) }
                return
            }
            if button == .left { captured = (target, targetView) }
            target.pointer(event, local: view.convert(event.location, to: targetView))
        case .up, .scroll:
            if let (target, targetView) = target(at: event.location) {
                target.pointer(event, local: view.convert(event.location, to: targetView))
            }
        }
    }

    private func updateHover(at point: CGPoint) {
        let found = target(at: point)
        if let (newTarget, _) = found {
            if let (old, _) = hovered {
                if old !== newTarget { old.pointerExited(); newTarget.pointerEntered() }
            } else {
                newTarget.pointerEntered()
            }
        } else if let (old, _) = hovered {
            old.pointerExited()
        }
        hovered = found
        if let (target, targetView) = found {
            let local = view.convert(point, to: targetView)
            target.pointer(PointerEvent(kind: .move, location: point, modifiers: input.modifiers, clickCount: 1, timestamp: 0), local: local)
            cursorView.style = target.cursorStyle(at: local)
        } else {
            cursorView.style = .arrow
        }
        tooltips.update(target: found?.0, at: point)
        // Reveal traffic-light glyphs when hovering any part of a title bar (also for content
        // that draws its own title bar, whose top strip belongs to the window for dragging).
        for w in windowManager.visibleWindows {
            let local = view.convert(point, to: w)
            w.trafficLightsHover(w.bounds.contains(local) && local.y < Theme.titleBarHeight)
        }
    }

    /// Lets content (e.g. the browser) refresh the cursor after an asynchronous style lookup.
    func refreshCursorStyle(for target: PointerTarget) {
        guard let (hoveredTarget, targetView) = hovered, hoveredTarget === target else { return }
        cursorView.style = target.cursorStyle(at: view.convert(input.cursor, to: targetView))
    }

    func handleKey(_ event: KeyEvent) {
        if let launcher {
            if event.isDown { _ = launcher.key(event) }
            return
        }
        if let popup {
            if event.isDown {
                if event.isEscape { dismissPopup() }
                else if !popup.key(event) {
                    switch event.keyCode {
                    case .keyboardLeftArrow: menuBar.switchOpenMenu(by: -1)
                    case .keyboardRightArrow: menuBar.switchOpenMenu(by: 1)
                    default: break
                    }
                }
            }
            return
        }
        if dialog != nil, event.isDown, event.isEscape || event.isEnter {
            dismissDialog()
            return
        }

        if event.isDown, let action = globalShortcut(for: event) {
            performAction(action)
            return
        }

        if let focused = windowManager.focused {
            if focused.content.handleKey(event) { return }
        }

        // Fallbacks that content did not claim.
        guard event.isDown, event.command else { return }
        switch event.letter {
        case "w": if let f = windowManager.focused { windowManager.close(f) }
        case "n": open(.browser, forceNew: true)
        case "t": open(.browser)
        default: break
        }
    }

    private func globalShortcut(for e: KeyEvent) -> MenuAction? {
        if e.isSpace, e.command || e.control { return .launcher }
        if e.command {
            if e.charactersIgnoringModifiers == "`" { return .cycleWindows }
            if e.keyCode == .keyboardTab { return .cycleWindows }
            if e.charactersIgnoringModifiers == "," { return .settings }
            if e.letter == "m", !e.shift { return .minimize }
            if e.letter == "w", e.shift { return .closeWindow }
            if e.letter == "n", e.option { return .newNote }
            if e.letter == "t", e.option { return .newTask }
            if e.charactersIgnoringModifiers == "/", e.shift { return .keyboardShortcuts }
        }
        if e.control, e.option {
            switch e.keyCode {
            case .keyboardLeftArrow: return .tileLeft
            case .keyboardRightArrow: return .tileRight
            case .keyboardReturnOrEnter: return .tileFull
            default: break
            }
        }
        return nil
    }
}

/// A container that only hit-tests its subviews, never itself.
final class PassThroughView: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        return hit === self ? nil : hit
    }
}

/// Transparent view used only when the desktop is previewed on the phone: it turns touches
/// into cursor movement and clicks.
final class TouchCaptureView: UIView {
    var onBegan: ((CGPoint) -> Void)?
    var onMoved: ((CGPoint) -> Void)?
    var onEnded: ((CGPoint) -> Void)?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let t = touches.first { onBegan?(t.location(in: self)) }
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let t = touches.first { onMoved?(t.location(in: self)) }
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let t = touches.first { onEnded?(t.location(in: self)) }
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let t = touches.first { onEnded?(t.location(in: self)) }
    }
}
