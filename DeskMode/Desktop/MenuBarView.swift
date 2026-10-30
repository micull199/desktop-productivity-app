import UIKit

/// The translucent bar along the top of the desktop: app menus on the left, status on the right.
final class MenuBarView: UIView {

    var onAction: ((MenuAction) -> Void)?
    /// Asks the desktop to present a popup menu below a menu-bar item.
    var presentMenu: ((PopupMenuView, CGRect) -> Void)?

    private let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterialDark))
    private let leftStack = UIStackView()
    private let rightStack = UIStackView()
    private let hairline = UIView()
    private let logoButton = DeskButton(symbol: "desktopcomputer", style: .plain)
    private let appButton = DeskButton(title: "DeskMode", style: .plain)
    private var menuButtons: [DeskButton] = []
    private let keyboardIcon = UIImageView()
    private let mouseIcon = UIImageView()
    private let batteryLabel = UILabel()
    private let batteryIcon = UIImageView()
    private let clockLabel = UILabel()
    private var clockTimer: Timer?
    private var openMenuButton: DeskButton?

    private(set) var focusedApp: DeskApp?

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(blur)
        blur.contentView.addSubview(leftStack)
        blur.contentView.addSubview(rightStack)
        hairline.backgroundColor = UIColor(white: 0, alpha: 0.4)
        blur.contentView.addSubview(hairline)

        leftStack.axis = .horizontal
        leftStack.spacing = 2
        leftStack.alignment = .center
        rightStack.axis = .horizontal
        rightStack.spacing = 10
        rightStack.alignment = .center

        logoButton.iconPointSize = 15
        logoButton.contentInsets = UIEdgeInsets(top: 3, left: 10, bottom: 3, right: 10)
        logoButton.onTap = { [weak self] in
            guard let self else { return }
            self.showMenu(for: self.logoButton, items: self.systemMenu())
        }
        leftStack.addArrangedSubview(logoButton)

        appButton.onTap = { [weak self] in
            guard let self else { return }
            self.showMenu(for: self.appButton, items: self.appMenu())
        }
        styleMenuButton(appButton, bold: true)
        leftStack.addArrangedSubview(appButton)

        let menus: [(String, () -> [MenuItem])] = [
            ("File", { [unowned self] in self.fileMenu() }),
            ("Edit", { [unowned self] in self.editMenu() }),
            ("View", { [unowned self] in self.viewMenu() }),
            ("Window", { [unowned self] in self.windowMenu() }),
            ("Help", { [unowned self] in self.helpMenu() })
        ]
        for (title, builder) in menus {
            let b = DeskButton(title: title, style: .plain)
            styleMenuButton(b, bold: false)
            b.onTap = { [weak self, weak b] in
                guard let self, let b else { return }
                self.showMenu(for: b, items: builder())
            }
            menuButtons.append(b)
            leftStack.addArrangedSubview(b)
        }

        for (icon, name) in [(keyboardIcon, "keyboard"), (mouseIcon, "computermouse")] {
            icon.image = UIImage.symbol(name, size: 13)
            icon.tintColor = Theme.text
            icon.contentMode = .center
            rightStack.addArrangedSubview(icon)
        }
        batteryIcon.contentMode = .center
        batteryIcon.tintColor = Theme.text
        batteryLabel.font = Theme.font(12, weight: .medium)
        batteryLabel.textColor = Theme.text
        rightStack.addArrangedSubview(batteryLabel)
        rightStack.addArrangedSubview(batteryIcon)
        clockLabel.font = Theme.font(13, weight: .medium)
        clockLabel.textColor = Theme.text
        rightStack.addArrangedSubview(clockLabel)

        NotificationCenter.default.addObserver(self, selector: #selector(updateStatus), name: UIDevice.batteryLevelDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(updateStatus), name: UIDevice.batteryStateDidChangeNotification, object: nil)
        clockTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateStatus() }
        }
        updateStatus()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func styleMenuButton(_ b: DeskButton, bold: Bool) {
        b.contentInsets = UIEdgeInsets(top: 3, left: 10, bottom: 3, right: 10)
        if bold { b.font = Theme.font(13, weight: .bold) }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        blur.frame = bounds
        hairline.frame = CGRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1)
        let ls = leftStack.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        leftStack.frame = CGRect(x: 6, y: 0, width: ls.width, height: bounds.height)
        let rs = rightStack.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        rightStack.frame = CGRect(x: bounds.width - rs.width - 14, y: 0, width: rs.width, height: bounds.height)
    }

    // MARK: - State

    func setFocusedApp(_ app: DeskApp?) {
        focusedApp = app
        appButton.title = app?.title ?? "DeskMode"
        setNeedsLayout()
    }

    func setInputStatus(keyboard: Bool, mouse: Bool) {
        keyboardIcon.alpha = keyboard ? 1 : 0.35
        mouseIcon.alpha = mouse ? 1 : 0.35
    }

    @objc private func updateStatus() {
        let device = UIDevice.current
        let level = device.batteryLevel
        if level >= 0 {
            batteryLabel.text = "\(Int(level * 100))%"
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
            batteryIcon.image = UIImage.symbol(name, size: 14)
            batteryIcon.tintColor = level <= 0.1 && device.batteryState == .unplugged ? Theme.destructive : Theme.text
            batteryLabel.isHidden = false
            batteryIcon.isHidden = false
        } else {
            batteryLabel.isHidden = true
            batteryIcon.isHidden = true
        }
        let f = DateFormatter()
        f.locale = .current
        f.setLocalizedDateFormatFromTemplate(Settings.shared.showClockSeconds ? "EEE d MMM HH:mm:ss" : "EEE d MMM HH:mm")
        clockLabel.text = f.string(from: Date())
        setNeedsLayout()
    }

    // MARK: - Menus

    private func showMenu(for button: DeskButton, items: [MenuItem]) {
        let menu = PopupMenuView(items: items)
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
            item("Close Window", .closeWindow, shortcut: "⌘W", enabled: hasWindow),
            item("Close All Windows", .closeAllWindows, shortcut: "⇧⌘W", enabled: hasWindow)
        ]
    }

    private func fileMenu() -> [MenuItem] {
        let browser = focusedApp == .browser
        return [
            item("New Browser Window", .newWindow, shortcut: "⌘N", symbol: "safari"),
            item("New Tab", .newTab, shortcut: "⌘T", enabled: browser),
            item("Reopen Closed Tab", .reopenClosedTab, shortcut: "⇧⌘T", enabled: browser),
            item("Open Location…", .openLocation, shortcut: "⌘L", enabled: browser),
            .separator,
            item("New Note", .newNote, shortcut: "⌥⌘N", symbol: "note.text"),
            item("New Task", .newTask, shortcut: "⌥⌘T", symbol: "checklist"),
            .separator,
            item("Close Tab", .closeTab, shortcut: "⌘W", enabled: browser),
            item("Close Window", .closeWindow, shortcut: "⇧⌘W", enabled: focusedApp != nil)
        ]
    }

    private func editMenu() -> [MenuItem] {
        [
            item("Cut", .cut, shortcut: "⌘X"),
            item("Copy", .copy, shortcut: "⌘C"),
            item("Paste", .paste, shortcut: "⌘V"),
            item("Select All", .selectAll, shortcut: "⌘A"),
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
            MenuItem(title: "Keyboard Shortcuts", symbol: "keyboard") { [weak self] in self?.onAction?(.about) }
        ]
    }
}
