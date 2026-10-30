import UIKit
import Combine

/// Root of the external display. Owns wallpaper, menu bar, windows, dock, launcher, popups and
/// the cursor, and routes every pointer / key event to the right target.
final class DesktopViewController: UIViewController, InputSink {

    var onWindowCountChange: ((Int) -> Void)?

    /// When true the desktop is being shown on the phone itself and touches drive the cursor.
    var allowsTouchInput = false {
        didSet { touchCapture.isUserInteractionEnabled = allowsTouchInput }
    }

    private let wallpaper = CAGradientLayer()
    private let windowContainer = UIView()
    private let menuBar = MenuBarView()
    private let dock = DockView()
    private let overlay = PassThroughView() // popups, launcher, toasts
    private let snapPreview = UIView()
    private let touchCapture = TouchCaptureView()
    private let cursorView = CursorView()
    private lazy var windowManager = WindowManager(container: windowContainer)

    private var hovered: (PointerTarget, UIView)?
    private var captured: (PointerTarget, UIView)?
    private var popup: PopupMenuView?
    private var launcher: LauncherView?
    private var aboutPanel: UIView?
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
        applyWallpaper()

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

        snapPreview.backgroundColor = UIColor(white: 1, alpha: 0.12)
        snapPreview.layer.cornerRadius = Theme.windowCornerRadius
        snapPreview.layer.borderWidth = 1
        snapPreview.layer.borderColor = UIColor(white: 1, alpha: 0.35).cgColor
        snapPreview.isHidden = true
        snapPreview.isUserInteractionEnabled = false

        overlay.backgroundColor = .clear

        menuBar.onAction = { [weak self] action in self?.performAction(action) }
        menuBar.presentMenu = { [weak self] menu, anchor in
            guard let self else { return }
            let rect = self.menuBar.convert(anchor, to: self.view)
            self.present(menu, at: CGPoint(x: rect.minX, y: rect.maxY + 2))
        }

        dock.onOpenApp = { [weak self] app in self?.open(app) }
        dock.onNewWindow = { [weak self] app in self?.open(app, forceNew: true) }
        dock.onCloseApp = { [weak self] app in self?.closeAll(app) }
        dock.onRestoreWindow = { [weak self] w in self?.windowManager.focus(w) }
        dock.onLauncher = { [weak self] in self?.toggleLauncher() }
        dock.presentMenu = { [weak self] menu, anchor in
            guard let self else { return }
            let rect = self.dock.convert(anchor, to: self.view)
            self.present(menu, at: CGPoint(x: rect.midX - menu.bounds.width / 2, y: rect.minY - menu.bounds.height - 10))
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
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        wallpaper.frame = b
        CATransaction.commit()
        windowContainer.frame = b
        overlay.frame = b
        touchCapture.frame = b
        menuBar.frame = CGRect(x: 0, y: 0, width: b.width, height: Theme.menuBarHeight)
        let dockSize = dock.intrinsicContentSize
        dock.frame = CGRect(x: (b.width - dockSize.width) / 2, y: b.height - dockSize.height - 8, width: dockSize.width, height: dockSize.height)
        windowManager.workArea = CGRect(x: 0, y: Theme.menuBarHeight, width: b.width, height: b.height - Theme.menuBarHeight - Theme.dockHeight - 10)
        windowManager.relayout()
        input.desktopBounds = b
        if !openedInitialWindow, b.width > 200, b.height > 200 {
            // First real layout: open the browser so the desktop is immediately useful.
            openedInitialWindow = true
            if windowManager.windows.isEmpty { open(.browser) }
            cursorView.place(at: input.cursor)
        }
        if let launcher {
            launcher.center = CGPoint(x: b.midX, y: b.height * 0.22 + launcher.bounds.height / 2)
        }
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
            DispatchQueue.main.async { self?.applyWallpaper() }
        })
    }

    private func applyWallpaper() {
        wallpaper.colors = Theme.wallpaperColors(settings.wallpaper)
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
            UIView.animate(withDuration: 0.15) { self.snapPreview.alpha = 0 } completion: { _ in self.snapPreview.isHidden = true }
            return
        }
        let area = windowManager.workArea.insetBy(dx: 8, dy: 8)
        let gap: CGFloat = 8
        let target: CGRect
        switch tile {
        case .left: target = CGRect(x: area.minX, y: area.minY, width: (area.width - gap) / 2, height: area.height)
        case .right: target = CGRect(x: area.midX + gap / 2, y: area.minY, width: (area.width - gap) / 2, height: area.height)
        default: target = area
        }
        snapPreview.isHidden = false
        UIView.animate(withDuration: 0.18) {
            self.snapPreview.alpha = 1
            self.snapPreview.frame = target
        }
    }

    // MARK: - Popups, launcher, toasts

    private func present(_ menu: PopupMenuView, at origin: CGPoint) {
        dismissPopup()
        var o = origin
        o.x = min(max(8, o.x), view.bounds.width - menu.bounds.width - 8)
        o.y = min(max(Theme.menuBarHeight, o.y), view.bounds.height - menu.bounds.height - 8)
        menu.frame.origin = o
        let previousDismiss = menu.onDismiss
        menu.onDismiss = { [weak self, weak menu] in
            previousDismiss?()
            if let menu, self?.popup === menu { self?.dismissPopup() }
        }
        overlay.addSubview(menu)
        popup = menu
        menu.alpha = 0
        menu.transform = CGAffineTransform(translationX: 0, y: -4)
        UIView.animate(withDuration: 0.12) {
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
        UIView.animate(withDuration: 0.1) { popup.alpha = 0 } completion: { _ in popup.removeFromSuperview() }
    }

    func toggleLauncher() {
        if launcher != nil { dismissLauncher(); return }
        dismissPopup()
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
        view.setNeedsLayout()
        view.layoutIfNeeded()
        l.alpha = 0
        l.transform = CGAffineTransform(scaleX: 0.96, y: 0.96)
        UIView.animate(withDuration: 0.15) { l.alpha = 1; l.transform = .identity }
    }

    private func dismissLauncher() {
        guard let l = launcher else { return }
        launcher = nil
        UIView.animate(withDuration: 0.12) { l.alpha = 0 } completion: { _ in l.removeFromSuperview() }
    }

    func showToast(_ text: String) {
        let toast = ToastView(text: text)
        toast.center = CGPoint(x: view.bounds.midX, y: Theme.menuBarHeight + 34 + CGFloat(toastViews.count) * (toast.bounds.height + 8))
        toast.alpha = 0
        overlay.addSubview(toast)
        toastViews.append(toast)
        UIView.animate(withDuration: 0.2) { toast.alpha = 1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { [weak self, weak toast] in
            guard let toast else { return }
            UIView.animate(withDuration: 0.25) { toast.alpha = 0 } completion: { _ in
                toast.removeFromSuperview()
                self?.toastViews.removeAll { $0 === toast }
            }
        }
    }

    private func showAbout() {
        aboutPanel?.removeFromSuperview()
        let panel = UIVisualEffectView(effect: UIBlurEffect(style: .systemThickMaterialDark))
        panel.frame = CGRect(x: 0, y: 0, width: 520, height: 420)
        panel.center = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
        panel.layer.cornerRadius = 16
        panel.clipsToBounds = true
        panel.layer.borderWidth = 0.5
        panel.layer.borderColor = Theme.border.cgColor
        let title = UILabel(frame: CGRect(x: 24, y: 22, width: 472, height: 30))
        title.text = "DeskMode"
        title.font = Theme.font(22, weight: .bold)
        title.textColor = Theme.text
        let body = UILabel(frame: CGRect(x: 24, y: 60, width: 472, height: 300))
        body.numberOfLines = 0
        body.font = Theme.monoFont(12.5)
        body.textColor = Theme.secondaryText
        body.text = """
        A desktop for your iPhone on an external display.

        ⌘Space        Launcher          ⌘`            Cycle windows
        ⌘N            New browser window ⌘T           New tab
        ⌘W            Close tab / window ⇧⌘T          Reopen closed tab
        ⌘L            Address bar        ⌘R           Reload
        ⌘[ / ⌘]       Back / forward     ⌃Tab         Next tab
        ⌘1…9          Switch tab         ⌘F           Find in page
        ⌘+ / ⌘−       Zoom page          ⌘0           Actual size
        ⌘M            Minimize           ⌃⌥← / ⌃⌥→    Tile left / right
        ⌃⌥↩           Fill screen        ⌘,           Settings
        Esc           Close menus / launcher
        """
        let close = DeskButton(title: "OK", style: .primary)
        close.frame = CGRect(x: 420, y: 370, width: 76, height: 30)
        close.onTap = { [weak self] in
            self?.aboutPanel?.removeFromSuperview()
            self?.aboutPanel = nil
        }
        panel.contentView.addSubview(title)
        panel.contentView.addSubview(body)
        panel.contentView.addSubview(close)
        overlay.addSubview(panel)
        aboutPanel = panel
    }

    // MARK: - Menu actions

    func performAction(_ action: MenuAction) {
        let focused = windowManager.focused
        switch action {
        case .about: showAbout()
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
            MenuItem(title: "New Browser Window", symbol: "safari") { [weak self] in self?.open(.browser, forceNew: true) },
            MenuItem(title: "New Note", symbol: "note.text") { [weak self] in self?.performAction(.newNote) },
            .separator
        ]
        for wp in Wallpaper.allCases {
            items.append(MenuItem(title: "Wallpaper: \(wp.title)", isChecked: settings.wallpaper == wp) { Settings.shared.wallpaper = wp })
        }
        items.append(.separator)
        items.append(MenuItem(title: "Settings…", symbol: "gearshape") { [weak self] in self?.open(.settings) })
        presentContextMenu(items: items, at: point)
    }

    // MARK: - Hit testing

    private func target(at point: CGPoint) -> (PointerTarget, UIView)? {
        let touchEnabled = touchCapture.isUserInteractionEnabled
        touchCapture.isUserInteractionEnabled = false
        defer { touchCapture.isUserInteractionEnabled = touchEnabled }
        guard let hit = view.hitTest(point, with: nil) else { return nil }

        // Overlay content (menus, launcher, about) and the chrome always win.
        let isOverlay = hit.isDescendant(of: overlay) || hit.isDescendant(of: menuBar) || hit.isDescendant(of: dock)
        if !isOverlay {
            // Resize edges extend slightly outside a window's frame and over its content.
            for w in windowManager.visibleWindows.reversed() {
                let f = w.frame
                if f.insetBy(dx: -5, dy: -5).contains(point), !f.insetBy(dx: 6, dy: 6).contains(point) {
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
        // Reveal traffic-light glyphs when hovering any part of a title bar.
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
                if event.isEscape { dismissPopup() } else { _ = popup.key(event) }
            }
            return
        }
        if aboutPanel != nil, event.isDown, event.isEscape {
            aboutPanel?.removeFromSuperview()
            aboutPanel = nil
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
