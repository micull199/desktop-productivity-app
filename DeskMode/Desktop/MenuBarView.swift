import UIKit

/// The translucent bar along the top of the desktop: app menus on the left, status on the right.
///
/// Behaves like the Mac menu bar: clicking a title opens its menu, and while a menu is open,
/// hovering another title switches to it without a click. Left/right arrows do the same.
final class MenuBarView: UIView {

    var onAction: ((MenuAction) -> Void)?
    /// Asks the desktop to present a popup menu below a menu-bar item (anchor in menu-bar coordinates).
    var presentMenu: ((PopupMenuView, CGRect) -> Void)?

    private let material = Theme.materialView(.bar)
    private let hairline = UIView()
    private let logoButton = DeskButton(symbol: "desktopcomputer", style: .plain)
    private let appButton = DeskButton(title: "DeskMode", style: .plain)
    private var menuButtons: [DeskButton] = []
    private var menuBuilders: [() -> [MenuItem]] = []
    /// Every clickable title in order: logo, app name, then File … Help.
    private var titleButtons: [DeskButton] { [logoButton, appButton] + menuButtons }

    private let keyboardIcon = UIImageView()
    private let mouseIcon = UIImageView()
    private let batteryIcon = UIImageView()
    private let batteryLabel = UILabel()
    private let clockLabel = UILabel()
    private var clockTimer: Timer?
    private var openMenuButton: DeskButton?
    private var keyboardConnected = false
    private var mouseConnected = false

    private(set) var focusedApp: DeskApp?

    /// True while one of the menu-bar menus is open.
    var isMenuOpen: Bool { openMenuButton != nil }

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(material)
        addSubview(hairline)
        hairline.backgroundColor = Theme.hairlineDark

        logoButton.iconPointSize = Theme.Size.menuBarMark
        configureTitle(logoButton)
        logoButton.contentInsets = UIEdgeInsets(top: 0, left: Theme.Size.menuBarItemPadding + 2, bottom: 0, right: Theme.Size.menuBarItemPadding)
        logoButton.onTap = { [weak self] in
            guard let self else { return }
            self.showMenu(for: self.logoButton, items: self.systemMenu())
        }
        addSubview(logoButton)

        appButton.font = Theme.font(Theme.Text.body, weight: .semibold)
        configureTitle(appButton)
        appButton.onTap = { [weak self] in
            guard let self else { return }
            self.showMenu(for: self.appButton, items: self.appMenu())
        }
        addSubview(appButton)

        let menus: [(String, () -> [MenuItem])] = [
            ("File", { [unowned self] in self.fileMenu() }),
            ("Edit", { [unowned self] in self.editMenu() }),
            ("View", { [unowned self] in self.viewMenu() }),
            ("Window", { [unowned self] in self.windowMenu() }),
            ("Help", { [unowned self] in self.helpMenu() })
        ]
        for (title, builder) in menus {
            let b = DeskButton(title: title, style: .plain)
            configureTitle(b)
            b.onTap = { [weak self, weak b] in
                guard let self, let b else { return }
                self.showMenu(for: b, items: builder())
            }
            menuButtons.append(b)
            menuBuilders.append(builder)
            addSubview(b)
        }

        for (icon, name) in [(keyboardIcon, "keyboard"), (mouseIcon, "computermouse")] {
            icon.image = UIImage.symbol(name, size: Theme.Text.body)
            icon.tintColor = Theme.text
            icon.contentMode = .center
            icon.isHidden = true
            addSubview(icon)
        }
        batteryIcon.contentMode = .center
        batteryIcon.tintColor = Theme.text
        batteryLabel.font = Theme.tabularFont(Theme.Text.footnote, weight: .medium)
        batteryLabel.textColor = Theme.text
        clockLabel.font = Theme.tabularFont(Theme.Text.body, weight: .medium)
        clockLabel.textColor = Theme.text
        addSubview(batteryIcon)
        addSubview(batteryLabel)
        addSubview(clockLabel)

        NotificationCenter.default.addObserver(self, selector: #selector(updateStatus), name: UIDevice.batteryLevelDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(updateStatus), name: UIDevice.batteryStateDidChangeNotification, object: nil)
        clockTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateStatus() }
        }
        updateStatus()
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Menu titles: regular 13 pt, 10 pt horizontal padding, no hover fill, highlight while open.
    private func configureTitle(_ b: DeskButton) {
        b.contentInsets = UIEdgeInsets(top: 0, left: Theme.Size.menuBarItemPadding, bottom: 0, right: Theme.Size.menuBarItemPadding)
        b.showsHoverHighlight = false
        b.onHoverChange = { [weak self, weak b] on in
            guard let self, let b, on, let open = self.openMenuButton, open !== b else { return }
            self.open(b)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        material.frame = bounds
        hairline.frame = CGRect(x: 0, y: bounds.height - Theme.Size.hairline, width: bounds.width, height: Theme.Size.hairline)

        // Left: titles.
        let itemHeight = bounds.height - Theme.Space.xs
        let itemY = (bounds.height - itemHeight) / 2
        var x = Theme.Space.xs
        for b in titleButtons {
            let w = ceil(b.intrinsicContentSize.width)
            b.frame = CGRect(x: x, y: itemY, width: w, height: itemHeight)
            x += w
        }

        // Right: status items, laid out from the trailing edge.
        var right = bounds.width - Theme.Size.menuBarStatusSpacing
        func place(_ view: UIView, width: CGFloat) {
            guard !view.isHidden else { return }
            view.frame = CGRect(x: right - width, y: 0, width: width, height: bounds.height)
            right -= width + Theme.Size.menuBarStatusSpacing
        }
        place(clockLabel, width: ceil(clockLabel.intrinsicContentSize.width))
        if !batteryIcon.isHidden {
            // Glyph and percentage read as one item: a small gap, not the full spacing.
            let labelW = ceil(batteryLabel.intrinsicContentSize.width)
            let iconW: CGFloat = 22
            batteryIcon.frame = CGRect(x: right - iconW, y: 0, width: iconW, height: bounds.height)
            batteryLabel.frame = CGRect(x: right - iconW - Theme.Space.xs - labelW, y: 0, width: labelW, height: bounds.height)
            right -= iconW + Theme.Space.xs + labelW + Theme.Size.menuBarStatusSpacing
        }
        place(mouseIcon, width: 18)
        place(keyboardIcon, width: 18)
    }

    // MARK: - State

    func setFocusedApp(_ app: DeskApp?) {
        focusedApp = app
        appButton.title = app?.title ?? "DeskMode"
        setNeedsLayout()
    }

    func setInputStatus(keyboard: Bool, mouse: Bool) {
        keyboardConnected = keyboard
        mouseConnected = mouse
        keyboardIcon.isHidden = !keyboard
        mouseIcon.isHidden = !mouse
        setNeedsLayout()
    }

    @objc private func updateStatus() {
        let device = UIDevice.current
        let level = device.batteryLevel
        if level >= 0 {
            batteryLabel.text = "\(Int((level * 100).rounded()))%"
            let name: String
            switch device.batteryState {
            case .charging, .full: name = "battery.100percent.bolt"
            default:
                if level > 0.85 { name = "battery.100percent" }
                else if level > 0.6 { name = "battery.75percent" }
                else if level > 0.35 { name = "battery.50percent" }
                else if level > 0.1 { name = "battery.25percent" }
                else { name = "battery.0percent" }
            }
            batteryIcon.image = UIImage.symbol(name, size: Theme.Text.callout)
            batteryIcon.tintColor = level <= 0.1 && device.batteryState == .unplugged ? Theme.destructive : Theme.text
            batteryLabel.isHidden = false
            batteryIcon.isHidden = false
        } else {
            batteryLabel.isHidden = true
            batteryIcon.isHidden = true
        }
        clockLabel.text = Self.clockString(Date(), seconds: Settings.shared.showClockSeconds)
        setNeedsLayout()
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = .current
        f.setLocalizedDateFormatFromTemplate("EEE d MMM")
        return f
    }()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = .current
        f.setLocalizedDateFormatFromTemplate("HH:mm")
        return f
    }()

    private static let timeWithSecondsFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = .current
        f.setLocalizedDateFormatFromTemplate("HH:mm:ss")
        return f
    }()

    /// "Fri 30 Oct  22:49": date, two spaces, time.
    static func clockString(_ date: Date, seconds: Bool) -> String {
        dateFormatter.string(from: date) + "  " + (seconds ? timeWithSecondsFormatter : timeFormatter).string(from: date)
    }

    // MARK: - Menus

    private func open(_ button: DeskButton) {
        if button === logoButton { showMenu(for: logoButton, items: systemMenu()); return }
        if button === appButton { showMenu(for: appButton, items: appMenu()); return }
        if let i = menuButtons.firstIndex(where: { $0 === button }) { showMenu(for: button, items: menuBuilders[i]()) }
    }

    /// Opens the menu to the left (-1) or right (+1) of the open one; used for arrow keys.
    func switchOpenMenu(by delta: Int) {
        guard let open = openMenuButton, let i = titleButtons.firstIndex(where: { $0 === open }) else { return }
        let all = titleButtons
        self.open(all[(i + delta + all.count) % all.count])
    }

    private func showMenu(for button: DeskButton, items: [MenuItem]) {
        let menu = PopupMenuView(items: items)
        openMenuButton?.isSelected = false
        button.isSelected = true
        openMenuButton = button
        menu.onDismiss = { [weak self, weak button] in
            button?.isSelected = false
            if self?.openMenuButton === button { self?.openMenuButton = nil }
        }
        presentMenu?(menu, button.convert(button.bounds, to: self))
    }

    private func item(_ title: String, _ action: MenuAction, shortcut: String? = nil, symbol: String? = nil, enabled: Bool = true) -> MenuItem {
        MenuItem(title: title, symbol: symbol, shortcut: shortcut, isEnabled: enabled) { [weak self] in self?.onAction?(action) }
    }

    private var browserTitle: String { DeskApp.browser.title }

    private func systemMenu() -> [MenuItem] {
        [
            item("About DeskMode", .about),
            .separator,
            item("Settings…", .settings, shortcut: "⌘,"),
            item("Launcher", .launcher, shortcut: "⌘Space"),
            .separator,
            item("Close All Windows", .closeAllWindows, shortcut: "⇧⌘W")
        ]
    }

    private func appMenu() -> [MenuItem] {
        let hasWindow = focusedApp != nil
        return [
            item("About \(focusedApp?.title ?? "DeskMode")", .about),
            .separator,
            item("Settings…", .settings, shortcut: "⌘,"),
            .separator,
            item("Close Window", .closeWindow, shortcut: "⇧⌘W", enabled: hasWindow),
            item("Close All Windows", .closeAllWindows, enabled: hasWindow)
        ]
    }

    private func fileMenu() -> [MenuItem] {
        let browser = focusedApp == .browser
        return [
            item("New \(browserTitle) Window", .newWindow, shortcut: "⌘N", symbol: DeskApp.browser.symbolName),
            item("New Tab", .newTab, shortcut: "⌘T", enabled: browser),
            item("Reopen Closed Tab", .reopenClosedTab, shortcut: "⇧⌘T", enabled: browser),
            item("Open Location…", .openLocation, shortcut: "⌘L", enabled: browser),
            .separator,
            item("New Note", .newNote, shortcut: "⌥⌘N", symbol: DeskApp.notes.symbolName),
            item("New Task", .newTask, shortcut: "⌥⌘T", symbol: DeskApp.tasks.symbolName),
            .separator,
            item("Close Tab", .closeTab, shortcut: "⌘W", enabled: browser),
            item("Close Window", .closeWindow, shortcut: "⇧⌘W", enabled: focusedApp != nil)
        ]
    }

    private func editMenu() -> [MenuItem] {
        let hasWindow = focusedApp != nil
        return [
            item("Cut", .cut, shortcut: "⌘X", enabled: hasWindow),
            item("Copy", .copy, shortcut: "⌘C", enabled: hasWindow),
            item("Paste", .paste, shortcut: "⌘V", enabled: hasWindow),
            item("Select All", .selectAll, shortcut: "⌘A", enabled: hasWindow),
            .separator,
            item("Find…", .find, shortcut: "⌘F", enabled: focusedApp == .browser)
        ]
    }

    private func viewMenu() -> [MenuItem] {
        let browser = focusedApp == .browser
        return [
            item("Reload Page", .reload, shortcut: "⌘R", enabled: browser),
            item("Back", .back, shortcut: "⌘[", enabled: browser),
            item("Forward", .forward, shortcut: "⌘]", enabled: browser),
            .separator,
            item("Actual Size", .zoomReset, shortcut: "⌘0", enabled: browser),
            item("Zoom In", .zoomIn, shortcut: "⌘+", enabled: browser),
            item("Zoom Out", .zoomOut, shortcut: "⌘−", enabled: browser)
        ]
    }

    private func windowMenu() -> [MenuItem] {
        let hasWindow = focusedApp != nil
        return [
            item("Minimize", .minimize, shortcut: "⌘M", enabled: hasWindow),
            item("Zoom", .zoom, enabled: hasWindow),
            .separator,
            item("Tile Left", .tileLeft, shortcut: "⌃⌥←", enabled: hasWindow),
            item("Tile Right", .tileRight, shortcut: "⌃⌥→", enabled: hasWindow),
            item("Fill Screen", .tileFull, shortcut: "⌃⌥↩", enabled: hasWindow),
            .separator,
            item("Cycle Windows", .cycleWindows, shortcut: "⌘`")
        ]
    }

    private func helpMenu() -> [MenuItem] {
        [
            item("Keyboard Shortcuts", .keyboardShortcuts, symbol: "keyboard"),
            .separator,
            item("About DeskMode", .about)
        ]
    }
}
