import UIKit

/// Settings for input, display and the browser. Changes apply immediately.
final class SettingsWindowContent: UIView, WindowContent {

    let app: DeskApp = .settings
    var windowTitle: String { "Settings" }
    var onTitleChange: ((String) -> Void)?

    private let scroll = UIScrollView()
    private let stack = UIStackView()
    private let settings = Settings.shared
    private var speedLabel: UILabel?
    private var trackpadLabel: UILabel?
    private var enginePills: [DeskButton] = []
    private var wallpaperPills: [DeskButton] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = Theme.windowBackground
        addSubview(scroll)
        scroll.addSubview(stack)
        scroll.indicatorStyle = .white
        stack.axis = .vertical
        stack.spacing = 8
        build()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        scroll.frame = bounds
        let width = min(bounds.width - 48, 640)
        let h = stack.systemLayoutSizeFitting(CGSize(width: width, height: 0), withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel).height
        stack.frame = CGRect(x: (bounds.width - width) / 2, y: 20, width: width, height: h)
        scroll.contentSize = CGSize(width: bounds.width, height: h + 48)
    }

    // MARK: - Building blocks

    private func header(_ text: String) {
        let l = UILabel()
        l.text = text.uppercased()
        l.font = Theme.font(11, weight: .semibold)
        l.textColor = Theme.tertiaryText
        let wrap = UIView()
        wrap.addSubview(l)
        l.pin(to: wrap, insets: UIEdgeInsets(top: 14, left: 6, bottom: 2, right: 6))
        stack.addArrangedSubview(wrap)
    }

    private func row(_ title: String, _ subtitle: String? = nil, control: UIView) -> UIView {
        let r = UIView()
        r.backgroundColor = Theme.controlBackground
        r.layer.cornerRadius = 10
        let t = UILabel()
        t.text = title
        t.font = Theme.font(14)
        t.textColor = Theme.text
        let s = UILabel()
        s.text = subtitle
        s.font = Theme.font(11.5)
        s.textColor = Theme.secondaryText
        s.numberOfLines = 2
        r.addSubview(t)
        r.addSubview(s)
        r.addSubview(control)
        t.translatesAutoresizingMaskIntoConstraints = false
        s.translatesAutoresizingMaskIntoConstraints = false
        control.translatesAutoresizingMaskIntoConstraints = false
        let hasSubtitle = !(subtitle ?? "").isEmpty
        NSLayoutConstraint.activate([
            t.leadingAnchor.constraint(equalTo: r.leadingAnchor, constant: 14),
            t.topAnchor.constraint(equalTo: r.topAnchor, constant: hasSubtitle ? 10 : 14),
            s.leadingAnchor.constraint(equalTo: t.leadingAnchor),
            s.topAnchor.constraint(equalTo: t.bottomAnchor, constant: 2),
            s.trailingAnchor.constraint(lessThanOrEqualTo: control.leadingAnchor, constant: -12),
            r.bottomAnchor.constraint(equalTo: hasSubtitle ? s.bottomAnchor : t.bottomAnchor, constant: hasSubtitle ? 10 : 14),
            control.trailingAnchor.constraint(equalTo: r.trailingAnchor, constant: -12),
            control.centerYAnchor.constraint(equalTo: r.centerYAnchor),
            t.trailingAnchor.constraint(lessThanOrEqualTo: control.leadingAnchor, constant: -12)
        ])
        stack.addArrangedSubview(r)
        return r
    }

    private func toggleRow(_ title: String, _ subtitle: String? = nil, value: Bool, onChange: @escaping (Bool) -> Void) {
        let t = DeskToggle(isOn: value)
        t.onChange = onChange
        t.widthAnchor.constraint(equalToConstant: 40).isActive = true
        t.heightAnchor.constraint(equalToConstant: 24).isActive = true
        _ = row(title, subtitle, control: t)
    }

    private func stepperRow(_ title: String, _ subtitle: String?, value: @escaping () -> CGFloat, range: ClosedRange<CGFloat>, step: CGFloat, onChange: @escaping (CGFloat) -> Void) -> UILabel {
        let container = UIStackView()
        container.axis = .horizontal
        container.spacing = 4
        container.alignment = .center
        let minus = DeskButton(symbol: "minus", style: .toolbar)
        let plus = DeskButton(symbol: "plus", style: .toolbar)
        let label = UILabel()
        label.font = Theme.monoFont(13)
        label.textColor = Theme.text
        label.textAlignment = .center
        label.text = String(format: "%.1f×", value())
        label.widthAnchor.constraint(equalToConstant: 52).isActive = true
        for b in [minus, plus] {
            b.widthAnchor.constraint(equalToConstant: 28).isActive = true
            b.heightAnchor.constraint(equalToConstant: 26).isActive = true
        }
        minus.onTap = {
            let v = max(range.lowerBound, value() - step)
            onChange(v); label.text = String(format: "%.1f×", v)
        }
        plus.onTap = {
            let v = min(range.upperBound, value() + step)
            onChange(v); label.text = String(format: "%.1f×", v)
        }
        container.addArrangedSubview(minus)
        container.addArrangedSubview(label)
        container.addArrangedSubview(plus)
        _ = row(title, subtitle, control: container)
        return label
    }

    private func pillRow<T: Equatable>(_ title: String, options: [(String, T)], current: @escaping () -> T, onSelect: @escaping (T) -> Void) -> [DeskButton] {
        let container = UIStackView()
        container.axis = .horizontal
        container.spacing = 6
        var pills: [DeskButton] = []
        for (name, value) in options {
            let p = DeskButton(title: name, style: .pill)
            p.isSelected = current() == value
            p.heightAnchor.constraint(equalToConstant: 24).isActive = true
            pills.append(p)
            container.addArrangedSubview(p)
        }
        for (i, p) in pills.enumerated() {
            p.onTap = {
                onSelect(options[i].1)
                for (j, q) in pills.enumerated() { q.isSelected = j == i }
            }
        }
        _ = row(title, nil, control: container)
        return pills
    }

    private func build() {
        header("Mouse & trackpad")
        speedLabel = stepperRow("Cursor speed", "How far the cursor travels per mouse movement.",
                                value: { Settings.shared.cursorSpeed }, range: 0.4...4.0, step: 0.2) { Settings.shared.cursorSpeed = $0 }
        toggleRow("Natural scrolling", "Content follows the scroll wheel, like a trackpad.", value: settings.naturalScrolling) { Settings.shared.naturalScrolling = $0 }
        toggleRow("Invert vertical mouse axis", "Turn on if the cursor moves the wrong way.", value: settings.invertMouseY) { Settings.shared.invertMouseY = $0 }

        header("iPhone screen")
        toggleRow("Dim iPhone screen while connected", "Turns brightness to zero and shows a black screen so the phone stays out of the way.", value: settings.dimPhoneWhenConnected) { Settings.shared.dimPhoneWhenConnected = $0 }
        toggleRow("Use the iPhone as a trackpad", "Drag on the phone to move the cursor, tap to click, two fingers to scroll.", value: settings.phoneAsTrackpad) { Settings.shared.phoneAsTrackpad = $0 }
        trackpadLabel = stepperRow("Trackpad sensitivity", nil, value: { Settings.shared.trackpadSensitivity }, range: 1.0...5.0, step: 0.2) { Settings.shared.trackpadSensitivity = $0 }

        header("Browser")
        enginePills = pillRow("Search engine", options: SearchEngine.allCases.map { ($0.title, $0) }, current: { Settings.shared.searchEngine }) { Settings.shared.searchEngine = $0 }
        toggleRow("Request desktop websites", "Identify as Safari on a Mac. Applies to new tabs.", value: settings.desktopWebsites) { Settings.shared.desktopWebsites = $0 }

        header("Desktop")
        wallpaperPills = pillRow("Wallpaper", options: Wallpaper.allCases.map { ($0.title, $0) }, current: { Settings.shared.wallpaper }) { Settings.shared.wallpaper = $0 }
        toggleRow("Show seconds in the clock", nil, value: settings.showClockSeconds) { Settings.shared.showClockSeconds = $0 }

        header("About")
        let reset = DeskButton(title: "Reset to Defaults", style: .pill)
        reset.heightAnchor.constraint(equalToConstant: 26).isActive = true
        reset.onTap = { [weak self] in
            Settings.shared.resetToDefaults()
            self?.rebuildAll()
        }
        _ = row("DeskMode 1.0", "A desktop for iPhone on an external display.", control: reset)
    }

    private func rebuildAll() {
        for v in stack.arrangedSubviews { stack.removeArrangedSubview(v); v.removeFromSuperview() }
        build()
        setNeedsLayout()
    }

    // MARK: - WindowContent

    func contentDidFocus() {}
    func contentDidBlur() {}
    func windowWillClose() {}
    func handleMenuAction(_ action: MenuAction) -> Bool { false }
    func handleKey(_ event: KeyEvent) -> Bool { false }
}
