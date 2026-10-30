import UIKit

// MARK: - Sections

private enum SettingsSection: CaseIterable {
    case mouse, phone, chrome, desktop, about

    var title: String {
        switch self {
        case .mouse: return "Mouse & Trackpad"
        case .phone: return "iPhone Screen"
        case .chrome: return "Chrome"
        case .desktop: return "Desktop"
        case .about: return "About"
        }
    }

    var symbol: String {
        switch self {
        case .mouse: return "computermouse.fill"
        case .phone: return "iphone"
        case .chrome: return "globe"
        case .desktop: return "menubar.dock.rectangle"
        case .about: return "info.circle.fill"
        }
    }

    var tint: UIColor {
        switch self {
        case .mouse: return AppsTheme.tileBlue
        case .phone: return AppsTheme.tileIndigo
        case .chrome: return AppsTheme.tileGreen
        case .desktop: return AppsTheme.tileOrange
        case .about: return AppsTheme.tileGray
        }
    }
}

// MARK: - Sidebar row

private final class SidebarRow: HoverRow {
    static let height: CGFloat = 32

    private let tile = UIView()
    private let icon = UIImageView()
    private let label = UILabel()

    init(section: SettingsSection) {
        super.init(cornerRadius: AppsTheme.Radius.control)
        addSubview(tile)
        tile.addSubview(icon)
        addSubview(label)
        tile.backgroundColor = section.tint
        tile.layer.cornerRadius = 6
        tile.layer.cornerCurve = .continuous
        tile.isUserInteractionEnabled = false
        icon.image = UIImage(systemName: section.symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold))?
            .withTintColor(.white, renderingMode: .alwaysOriginal)
        icon.contentMode = .center
        label.text = section.title
        label.font = Theme.font(AppsTheme.TextSize.body)
        label.textColor = Theme.text
        label.lineBreakMode = .byTruncatingTail
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        tile.frame = CGRect(x: AppsTheme.Space.s, y: (bounds.height - 24) / 2, width: 24, height: 24)
        icon.frame = tile.bounds
        label.frame = CGRect(x: tile.frame.maxX + AppsTheme.Space.s + 2, y: 0, width: bounds.width - tile.frame.maxX - AppsTheme.Space.l, height: bounds.height)
    }

    override func stateDidChange() {
        label.textColor = isSelected ? AppsTheme.onAccent : Theme.text
    }
}

// MARK: - Grouped rows

/// Title, optional subtitle and a trailing control.
private final class SettingRow: UIView {
    private static let padV: CGFloat = 10
    private static let padH: CGFloat = 14
    private static let titleHeight: CGFloat = 18

    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let control: UIView
    private let controlSize: CGSize
    private let subtitleFont = Theme.font(AppsTheme.TextSize.footnote)

    init(title: String, subtitle: String? = nil, control: UIView, controlSize: CGSize) {
        self.control = control
        self.controlSize = controlSize
        super.init(frame: .zero)
        addSubview(titleLabel)
        addSubview(subtitleLabel)
        addSubview(control)
        titleLabel.text = title
        titleLabel.font = Theme.font(AppsTheme.TextSize.callout)
        titleLabel.textColor = Theme.text
        titleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.text = subtitle
        subtitleLabel.font = subtitleFont
        subtitleLabel.textColor = Theme.secondaryText
        subtitleLabel.numberOfLines = 0
        subtitleLabel.isHidden = (subtitle ?? "").isEmpty
    }

    required init?(coder: NSCoder) { fatalError() }

    private func textWidth(for width: CGFloat) -> CGFloat {
        max(40, width - Self.padH * 2 - controlSize.width - AppsTheme.Space.m)
    }

    private func subtitleHeight(for width: CGFloat) -> CGFloat {
        guard let text = subtitleLabel.text, !text.isEmpty else { return 0 }
        let rect = (text as NSString).boundingRect(with: CGSize(width: textWidth(for: width), height: .greatestFiniteMagnitude),
                                                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                                                    attributes: [.font: subtitleFont], context: nil)
        return ceil(rect.height)
    }

    func height(for width: CGFloat) -> CGFloat {
        var h = Self.titleHeight
        let sub = subtitleHeight(for: width)
        if sub > 0 { h += 2 + sub }
        return max(h + Self.padV * 2, 44)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = bounds.width
        let textW = textWidth(for: w)
        let sub = subtitleHeight(for: w)
        let textH = Self.titleHeight + (sub > 0 ? 2 + sub : 0)
        let top = (bounds.height - textH) / 2
        titleLabel.frame = CGRect(x: Self.padH, y: top, width: textW, height: Self.titleHeight)
        subtitleLabel.frame = CGRect(x: Self.padH, y: top + Self.titleHeight + 2, width: textW, height: sub)
        control.frame = CGRect(x: w - Self.padH + 2 - controlSize.width, y: (bounds.height - controlSize.height) / 2,
                               width: controlSize.width, height: controlSize.height)
    }
}

/// A card of rows with pixelHairline separators, like a System Settings group.
private final class GroupedCard: UIView {
    private var rows: [SettingRow] = []
    private var separators: [UIView] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = Theme.controlBackground
        layer.cornerRadius = AppsTheme.Radius.menu
        layer.cornerCurve = .continuous
        clipsToBounds = true
    }

    required init?(coder: NSCoder) { fatalError() }

    func add(_ row: SettingRow) {
        if !rows.isEmpty {
            let s = UIView()
            s.backgroundColor = Theme.separator
            s.isUserInteractionEnabled = false
            addSubview(s)
            separators.append(s)
        }
        rows.append(row)
        addSubview(row)
    }

    func height(for width: CGFloat) -> CGFloat {
        rows.reduce(0) { $0 + $1.height(for: width) }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        var y: CGFloat = 0
        for (i, row) in rows.enumerated() {
            let h = row.height(for: bounds.width)
            row.frame = CGRect(x: 0, y: y, width: bounds.width, height: h)
            y += h
            if i < separators.count {
                separators[i].frame = CGRect(x: 14, y: y - pixelHairline, width: bounds.width - 14, height: pixelHairline)
            }
        }
    }
}

// MARK: - Controls

/// − value + stepper built from desk buttons.
private final class StepperControl: UIView {
    static let size = CGSize(width: 120, height: AppsTheme.Size.controlSmall + 2)

    private let minus = DeskButton(symbol: "minus", style: .toolbar)
    private let plus = DeskButton(symbol: "plus", style: .toolbar)
    private let label = UILabel()

    init(value: @escaping () -> CGFloat, range: ClosedRange<CGFloat>, step: CGFloat, onChange: @escaping (CGFloat) -> Void) {
        super.init(frame: .zero)
        addSubview(minus)
        addSubview(label)
        addSubview(plus)
        label.font = Theme.monoFont(AppsTheme.TextSize.body)
        label.textColor = Theme.text
        label.textAlignment = .center
        minus.iconPointSize = 11
        plus.iconPointSize = 11
        let show = { [weak self] (v: CGFloat) in
            self?.label.text = String(format: "%.1f×", v)
            self?.minus.isEnabled = v > range.lowerBound + 0.001
            self?.plus.isEnabled = v < range.upperBound - 0.001
        }
        show(value())
        minus.onTap = {
            let v = max(range.lowerBound, ((value() - step) * 10).rounded() / 10)
            onChange(v); show(v)
        }
        plus.onTap = {
            let v = min(range.upperBound, ((value() + step) * 10).rounded() / 10)
            onChange(v); show(v)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        let b: CGFloat = 28
        minus.frame = CGRect(x: 0, y: 0, width: b, height: bounds.height)
        plus.frame = CGRect(x: bounds.width - b, y: 0, width: b, height: bounds.height)
        label.frame = CGRect(x: b, y: 0, width: bounds.width - b * 2, height: bounds.height)
    }
}

/// A row of mutually exclusive pills.
private final class PillGroup<Value: Equatable>: UIView {
    private var pills: [DeskButton] = []
    private static var spacing: CGFloat { AppsTheme.Space.xs + 2 }
    let size: CGSize

    init(options: [(String, Value)], current: Value, onSelect: @escaping (Value) -> Void) {
        var width: CGFloat = 0
        var made: [DeskButton] = []
        for (name, value) in options {
            let p = DeskButton(title: name, style: .pill)
            p.isSelected = value == current
            width += p.intrinsicContentSize.width
            made.append(p)
        }
        width += CGFloat(max(0, made.count - 1)) * Self.spacing
        size = CGSize(width: width, height: AppsTheme.Size.controlSmall)
        super.init(frame: .zero)
        pills = made
        for (i, p) in pills.enumerated() {
            addSubview(p)
            p.onTap = { [weak self] in
                onSelect(options[i].1)
                self?.pills.enumerated().forEach { j, q in q.isSelected = j == i }
            }
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        var x: CGFloat = 0
        for p in pills {
            let w = p.intrinsicContentSize.width
            p.frame = CGRect(x: x, y: 0, width: w, height: bounds.height)
            x += w + Self.spacing
        }
    }
}

// MARK: - Window content

/// Settings in the style of macOS System Settings: a sidebar of sections and grouped rows.
/// Every change applies immediately.
final class SettingsWindowContent: UIView, WindowContent {

    let app: DeskApp = .settings
    var windowTitle: String { "Settings › \(section.title)" }
    var onTitleChange: ((String) -> Void)?

    private static let sidebarWidth: CGFloat = 200
    private static let paneInset: CGFloat = AppsTheme.Space.xl
    private static let maxContentWidth: CGFloat = 600

    private var section: SettingsSection = .mouse
    private let settings = Settings.shared

    private let sidebar = UIView()
    private var sidebarRows: [SidebarRow] = []
    private let divider = UIView()
    private let headerLabel = UILabel()
    private let scroll = DeskScrollView()
    private let content = UIView()
    private var blocks: [(label: UILabel?, card: GroupedCard)] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = Theme.windowBackground

        addSubview(sidebar)
        sidebar.backgroundColor = AppsTheme.sidebarBackground
        for s in SettingsSection.allCases {
            let row = SidebarRow(section: s)
            row.onTap = { [weak self] in self?.show(s) }
            sidebar.addSubview(row)
            sidebarRows.append(row)
        }

        addSubview(divider)
        divider.backgroundColor = Theme.separator

        addSubview(headerLabel)
        headerLabel.font = Theme.font(AppsTheme.TextSize.title2, weight: .semibold)
        headerLabel.textColor = Theme.text

        addSubview(scroll)
        scroll.addSubview(content)
        show(.mouse, animated: false)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        let sw = Self.sidebarWidth
        sidebar.frame = CGRect(x: 0, y: 0, width: sw, height: bounds.height)
        for (i, row) in sidebarRows.enumerated() {
            row.frame = CGRect(x: AppsTheme.Space.s, y: AppsTheme.Space.m + CGFloat(i) * (SidebarRow.height + 2),
                               width: sw - AppsTheme.Space.l, height: SidebarRow.height)
        }
        divider.frame = CGRect(x: sw - pixelHairline, y: 0, width: pixelHairline, height: bounds.height)

        let paneX = sw
        let paneW = bounds.width - sw
        let contentW = min(paneW - Self.paneInset * 2, Self.maxContentWidth)
        headerLabel.frame = CGRect(x: paneX + Self.paneInset, y: AppsTheme.Space.xl - 4, width: contentW, height: 26)
        let scrollTop = headerLabel.frame.maxY + AppsTheme.Space.m
        scroll.frame = CGRect(x: paneX, y: scrollTop, width: paneW, height: bounds.height - scrollTop)

        var y: CGFloat = AppsTheme.Space.xs
        for (i, block) in blocks.enumerated() {
            if i > 0 { y += AppsTheme.Space.xl }
            if let label = block.label {
                label.frame = CGRect(x: Self.paneInset + AppsTheme.Space.s, y: y, width: contentW - AppsTheme.Space.l, height: 14)
                y += 14 + AppsTheme.Space.s
            }
            let h = block.card.height(for: contentW)
            block.card.frame = CGRect(x: Self.paneInset, y: y, width: contentW, height: h)
            y += h
        }
        content.frame = CGRect(x: 0, y: 0, width: paneW, height: y + AppsTheme.Space.xxl)
        scroll.contentSize = content.frame.size
    }

    // MARK: - Sections

    private func show(_ s: SettingsSection, animated: Bool = true) {
        let changed = s != section
        section = s
        for row in sidebarRows.enumerated() { row.element.isSelected = SettingsSection.allCases[row.offset] == s }
        headerLabel.text = s.title
        onTitleChange?(windowTitle)
        rebuildPane()
        scroll.setContentOffset(.zero, animated: false)
        guard animated, changed else { return }
        content.alpha = 0
        content.transform = CGAffineTransform(translationX: 0, y: 6)
        AppsTheme.Motion.animate(AppsTheme.Motion.normal) {
            self.content.alpha = 1
            self.content.transform = .identity
        }
    }

    private func rebuildPane() {
        for b in blocks { b.label?.removeFromSuperview(); b.card.removeFromSuperview() }
        blocks = []
        switch section {
        case .mouse: buildMouse()
        case .phone: buildPhone()
        case .chrome: buildChrome()
        case .desktop: buildDesktop()
        case .about: buildAbout()
        }
        setNeedsLayout()
    }

    // MARK: Row factories

    @discardableResult
    private func card(_ label: String? = nil) -> GroupedCard {
        let c = GroupedCard()
        var l: UILabel?
        if let label {
            let lab = AppsTheme.sectionLabel(label.uppercased())
            content.addSubview(lab)
            l = lab
        }
        content.addSubview(c)
        blocks.append((l, c))
        return c
    }

    private func toggle(_ card: GroupedCard, _ title: String, _ subtitle: String? = nil, value: Bool, onChange: @escaping (Bool) -> Void) {
        let t = DeskToggle(isOn: value)
        t.onChange = onChange
        card.add(SettingRow(title: title, subtitle: subtitle, control: t, controlSize: t.intrinsicContentSize))
    }

    private func stepper(_ card: GroupedCard, _ title: String, _ subtitle: String?, value: @escaping () -> CGFloat,
                         range: ClosedRange<CGFloat>, step: CGFloat, onChange: @escaping (CGFloat) -> Void) {
        let s = StepperControl(value: value, range: range, step: step, onChange: onChange)
        card.add(SettingRow(title: title, subtitle: subtitle, control: s, controlSize: StepperControl.size))
    }

    private func pills<T: Equatable>(_ card: GroupedCard, _ title: String, _ subtitle: String? = nil, options: [(String, T)],
                                     current: T, onSelect: @escaping (T) -> Void) {
        let g = PillGroup(options: options, current: current, onSelect: onSelect)
        card.add(SettingRow(title: title, subtitle: subtitle, control: g, controlSize: g.size))
    }

    private func info(_ card: GroupedCard, _ title: String, _ value: String) {
        let l = UILabel()
        l.text = value
        l.font = Theme.font(AppsTheme.TextSize.callout)
        l.textColor = Theme.secondaryText
        l.textAlignment = .right
        let w = min(260, ceil(l.intrinsicContentSize.width))
        card.add(SettingRow(title: title, control: l, controlSize: CGSize(width: w, height: 18)))
    }

    private func button(_ card: GroupedCard, _ title: String, _ subtitle: String?, buttonTitle: String, destructive: Bool = false, action: @escaping () -> Void) {
        let b = DeskButton(title: buttonTitle, style: .pill)
        if destructive { b.tintOverride = Theme.destructive }
        b.onTap = action
        let w = ceil(b.intrinsicContentSize.width) + AppsTheme.Space.s
        card.add(SettingRow(title: title, subtitle: subtitle, control: b, controlSize: CGSize(width: w, height: AppsTheme.Size.controlSmall + 2)))
    }

    // MARK: Section builders

    private func buildMouse() {
        let mouse = card("Mouse")
        stepper(mouse, "Cursor speed", "How far the cursor travels per mouse movement.",
                value: { Settings.shared.cursorSpeed }, range: 0.4...4.0, step: 0.2) { Settings.shared.cursorSpeed = $0 }
        toggle(mouse, "Natural scrolling", "Content follows the scroll wheel, like a trackpad.", value: settings.naturalScrolling) { Settings.shared.naturalScrolling = $0 }
        toggle(mouse, "Invert vertical mouse axis", "Turn on if the cursor moves the wrong way.", value: settings.invertMouseY) { Settings.shared.invertMouseY = $0 }

        let trackpad = card("Trackpad")
        stepper(trackpad, "Trackpad sensitivity", "Cursor travel when dragging on the iPhone screen.",
                value: { Settings.shared.trackpadSensitivity }, range: 1.0...5.0, step: 0.2) { Settings.shared.trackpadSensitivity = $0 }
    }

    private func buildPhone() {
        let screen = card("While connected")
        toggle(screen, "Dim iPhone screen while connected", "Brightness goes to zero and the screen turns black. Press and hold to wake it.",
               value: settings.dimPhoneWhenConnected) { Settings.shared.dimPhoneWhenConnected = $0 }
        toggle(screen, "Use the iPhone as a trackpad", "Drag to move the cursor, tap to click, two fingers to scroll.",
               value: settings.phoneAsTrackpad) { Settings.shared.phoneAsTrackpad = $0 }
    }

    private func buildChrome() {
        let search = card("Search")
        pills(search, "Search engine", "Used by the address bar and the launcher.",
              options: SearchEngine.allCases.map { ($0.title, $0) }, current: settings.searchEngine) { Settings.shared.searchEngine = $0 }

        let sites = card("Websites")
        toggle(sites, "Request desktop websites", "Ask for the Mac version of sites. Applies to new tabs.",
               value: settings.desktopWebsites) { Settings.shared.desktopWebsites = $0 }
        toggle(sites, "Identify as Google Chrome", "Send a Chrome user agent so sites offer their Chrome features. Applies to new tabs.",
               value: settings.identifyAsChrome) { Settings.shared.identifyAsChrome = $0 }
    }

    private func buildDesktop() {
        let look = card("Appearance")
        pills(look, "Wallpaper", nil, options: Wallpaper.allCases.map { ($0.title, $0) }, current: settings.wallpaper) { Settings.shared.wallpaper = $0 }

        let bar = card("Menu bar")
        toggle(bar, "Show seconds in the clock", nil, value: settings.showClockSeconds) { Settings.shared.showClockSeconds = $0 }
    }

    private func buildAbout() {
        let about = card()
        let bundle = Bundle.main
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        info(about, "DeskMode", "Version \(version) (\(build))")
        info(about, "iOS", UIDevice.current.systemVersion)
        info(about, "Device", UIDevice.current.model)

        let reset = card()
        button(reset, "Reset all settings", "Restores every setting to its default value.", buttonTitle: "Reset to Defaults") { [weak self] in
            Settings.shared.resetToDefaults()
            self?.rebuildPane()
            self?.enclosingDesktopController?.showToast("Settings reset to defaults")
        }
    }

    // MARK: - WindowContent

    func contentDidFocus() {}
    func contentDidBlur() {}
    func windowWillClose() {}
    func handleMenuAction(_ action: MenuAction) -> Bool { false }

    func handleKey(_ event: KeyEvent) -> Bool {
        guard event.isDown, !event.command else { return false }
        let all = SettingsSection.allCases
        guard let i = all.firstIndex(of: section) else { return false }
        switch event.keyCode {
        case .keyboardUpArrow: show(all[max(0, i - 1)]); return true
        case .keyboardDownArrow: show(all[min(all.count - 1, i + 1)]); return true
        default: return false
        }
    }
}
