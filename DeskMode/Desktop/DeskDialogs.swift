import UIKit

// MARK: - Dialog panel

/// A floating dialog: `.panel` material, 14 pt radius, border, panel shadow, a content area and
/// a primary button in the bottom-right corner. The desktop presents it in its overlay layer and
/// closes it on Escape or when the button is clicked. It can be dragged by any empty point.
class DialogPanelView: UIView, PointerTarget {

    var onClose: (() -> Void)?

    let contentView = UIView()
    private let material = Theme.materialView(.panel, cornerRadius: Theme.Radius.panel)
    private let footerHairline = UIView()
    private let primaryButton = DeskButton(title: "OK", style: .primary)
    private var dragOffset: CGPoint?

    static let footerHeight: CGFloat = Theme.Size.controlLarge + Theme.Space.l * 2 - Theme.Space.s
    static let contentInset: CGFloat = Theme.Space.xl

    init(size: CGSize, buttonTitle: String = "OK") {
        super.init(frame: CGRect(origin: .zero, size: size))
        addSubview(material)
        material.contentView.addSubview(contentView)
        material.contentView.addSubview(footerHairline)
        material.contentView.addSubview(primaryButton)
        material.layer.borderWidth = Theme.Size.hairline
        material.layer.borderColor = Theme.border.cgColor
        layer.cornerRadius = Theme.Radius.panel
        layer.cornerCurve = .continuous
        applyShadow(.panel)
        footerHairline.backgroundColor = Theme.separator
        primaryButton.title = buttonTitle
        primaryButton.onTap = { [weak self] in self?.onClose?() }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        material.frame = bounds
        let footer = Self.footerHeight
        contentView.frame = CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height - footer)
        footerHairline.frame = CGRect(x: 0, y: bounds.height - footer, width: bounds.width, height: Theme.Size.hairline)
        let bw = max(primaryButton.intrinsicContentSize.width, 84)
        primaryButton.frame = CGRect(x: bounds.width - Self.contentInset + Theme.Space.s - bw,
                                     y: bounds.height - footer + (footer - Theme.Size.control) / 2,
                                     width: bw, height: Theme.Size.control)
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: Theme.Radius.panel).cgPath
    }

    // MARK: PointerTarget

    func pointer(_ event: PointerEvent, local: CGPoint) {
        switch event.kind {
        case .down(.left):
            dragOffset = CGPoint(x: event.location.x - frame.minX, y: event.location.y - frame.minY)
        case .move:
            guard let dragOffset else { return }
            frame.origin = CGPoint(x: event.location.x - dragOffset.x, y: event.location.y - dragOffset.y)
        case .up(.left):
            dragOffset = nil
        default:
            break
        }
    }

    func cursorStyle(at local: CGPoint) -> CursorStyle { dragOffset == nil ? .arrow : .closedHand }

    // MARK: Shared helpers

    static func label(_ text: String, size: CGFloat, weight: UIFont.Weight = .regular, color: UIColor = Theme.text, alignment: NSTextAlignment = .left) -> UILabel {
        let l = UILabel()
        l.text = text
        l.font = Theme.font(size, weight: weight)
        l.textColor = color
        l.textAlignment = alignment
        l.lineBreakMode = .byTruncatingTail
        return l
    }
}

// MARK: - About

/// About DeskMode: app glyph, version, device and display details.
final class AboutPanelView: DialogPanelView {

    private let iconView = UIImageView()
    private let nameLabel = DialogPanelView.label("DeskMode", size: Theme.Text.title2, weight: .semibold, alignment: .center)
    private let versionLabel = DialogPanelView.label("", size: Theme.Text.footnote, color: Theme.secondaryText, alignment: .center)
    private let taglineLabel = DialogPanelView.label("A desktop for your iPhone on an external display.", size: Theme.Text.body, color: Theme.secondaryText, alignment: .center)
    private var detailRows: [(UILabel, UILabel)] = []

    private static let iconSize: CGFloat = 64

    init(displaySize: CGSize, displayScale: CGFloat) {
        super.init(size: CGSize(width: 440, height: 372))
        iconView.image = Self.appGlyph(size: Self.iconSize)
        iconView.contentMode = .center
        contentView.addSubview(iconView)
        contentView.addSubview(nameLabel)
        contentView.addSubview(versionLabel)
        contentView.addSubview(taglineLabel)

        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info["CFBundleVersion"] as? String ?? "1"
        versionLabel.text = "Version \(version) (\(build))"

        let device = UIDevice.current
        let px = CGSize(width: displaySize.width * displayScale, height: displaySize.height * displayScale)
        let resolution = displayScale == 1
            ? "\(Int(displaySize.width)) × \(Int(displaySize.height))"
            : "\(Int(displaySize.width)) × \(Int(displaySize.height)) pt · \(Int(px.width)) × \(Int(px.height)) px"
        let rows: [(String, String)] = [
            ("Device", "\(device.model) · \(device.systemName) \(device.systemVersion)"),
            ("Model", Self.machineIdentifier),
            ("Display", resolution)
        ]
        for (key, value) in rows {
            let k = DialogPanelView.label(key, size: Theme.Text.body, color: Theme.secondaryText, alignment: .right)
            let v = DialogPanelView.label(value, size: Theme.Text.body)
            contentView.addSubview(k)
            contentView.addSubview(v)
            detailRows.append((k, v))
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = contentView.bounds.width
        var y = Theme.Space.xxl
        iconView.frame = CGRect(x: (w - Self.iconSize) / 2, y: y, width: Self.iconSize, height: Self.iconSize)
        y += Self.iconSize + Theme.Space.l
        nameLabel.frame = CGRect(x: Theme.Space.xl, y: y, width: w - Theme.Space.xl * 2, height: 26)
        y += 26 + Theme.Space.xxs
        versionLabel.frame = CGRect(x: Theme.Space.xl, y: y, width: w - Theme.Space.xl * 2, height: 16)
        y += 16 + Theme.Space.m
        taglineLabel.frame = CGRect(x: Theme.Space.xl, y: y, width: w - Theme.Space.xl * 2, height: 18)
        y += 18 + Theme.Space.xl
        let keyWidth: CGFloat = 96
        for (k, v) in detailRows {
            k.frame = CGRect(x: Theme.Space.xl, y: y, width: keyWidth, height: 20)
            v.frame = CGRect(x: Theme.Space.xl + keyWidth + Theme.Space.m, y: y, width: w - Theme.Space.xl * 2 - keyWidth - Theme.Space.m, height: 20)
            y += 20 + Theme.Space.xs
        }
    }

    /// The app's own mark: a rounded tile with a monitor glyph (not the browser icon).
    static func appGlyph(size: CGFloat) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: size, height: size)).image { ctx in
            let rect = CGRect(x: 0, y: 0, width: size, height: size)
            ctx.cgContext.addPath(UIBezierPath(roundedRect: rect, cornerRadius: size * 0.225).cgPath)
            ctx.cgContext.clip()
            let colors = [UIColor(red: 0.36, green: 0.40, blue: 0.52, alpha: 1).cgColor,
                          UIColor(red: 0.12, green: 0.14, blue: 0.22, alpha: 1).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                ctx.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size), options: [])
            }
            let config = UIImage.SymbolConfiguration(pointSize: size * 0.46, weight: .medium)
            if let symbol = UIImage(systemName: "desktopcomputer", withConfiguration: config)?.withTintColor(.white, renderingMode: .alwaysOriginal) {
                let s = symbol.size
                symbol.draw(in: CGRect(x: (size - s.width) / 2, y: (size - s.height) / 2, width: s.width, height: s.height))
            }
        }
    }

    private static var machineIdentifier: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let mirror = Mirror(reflecting: systemInfo.machine)
        let id = mirror.children.reduce(into: "") { result, element in
            guard let value = element.value as? Int8, value != 0 else { return }
            result.append(String(UnicodeScalar(UInt8(value))))
        }
        return id.isEmpty ? UIDevice.current.model : id
    }
}

// MARK: - Keyboard shortcuts

/// Help › Keyboard Shortcuts: a two-column sheet of key chips and descriptions.
final class ShortcutsPanelView: DialogPanelView {

    private struct Section { let title: String; let rows: [(keys: String, text: String)] }

    private static let leftSections: [Section] = [
        Section(title: "General", rows: [
            ("⌘Space", "Launcher"),
            ("⌘`", "Cycle windows"),
            ("⌘,", "Settings"),
            ("⌥⌘N", "New note"),
            ("⌥⌘T", "New task"),
            ("Esc", "Close menus and launcher")
        ]),
        Section(title: "Windows", rows: [
            ("⌘N", "New browser window"),
            ("⌘M", "Minimize"),
            ("⇧⌘W", "Close window"),
            ("⌃⌥← / ⌃⌥→", "Tile left / right"),
            ("⌃⌥↩", "Fill screen")
        ])
    ]

    private static let rightSections: [Section] = [
        Section(title: "Browser", rows: [
            ("⌘T", "New tab"),
            ("⇧⌘T", "Reopen closed tab"),
            ("⌘W", "Close tab"),
            ("⌘L", "Address bar"),
            ("⌘R", "Reload"),
            ("⌘[ / ⌘]", "Back / forward"),
            ("⌃Tab / ⌃⇧Tab", "Next / previous tab"),
            ("⌘1 … ⌘9", "Switch to tab"),
            ("⌘F / ⌘G", "Find / next match"),
            ("⌘+ / ⌘− / ⌘0", "Zoom in / out / reset")
        ]),
        Section(title: "Editing", rows: [
            ("⌘A", "Select all"),
            ("⌘C / ⌘X / ⌘V", "Copy / cut / paste")
        ])
    ]

    private let titleLabel = DialogPanelView.label("Keyboard Shortcuts", size: Theme.Text.title3, weight: .semibold)
    private let columns: [UIView] = [UIView(), UIView()]
    private static let rowHeight: CGFloat = 28
    private static let headerHeight: CGFloat = 30
    private static let sectionGap: CGFloat = Theme.Space.l

    init() {
        let leftHeight = Self.height(of: Self.leftSections)
        let rightHeight = Self.height(of: Self.rightSections)
        let contentHeight = max(leftHeight, rightHeight)
        super.init(size: CGSize(width: 720, height: Theme.Space.xl + 24 + Theme.Space.l + contentHeight + Theme.Space.l + DialogPanelView.footerHeight), buttonTitle: "Done")
        contentView.addSubview(titleLabel)
        for (column, sections) in zip(columns, [Self.leftSections, Self.rightSections]) {
            contentView.addSubview(column)
            Self.build(sections, in: column)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    private static func height(of sections: [Section]) -> CGFloat {
        sections.reduce(0) { $0 + headerHeight + CGFloat($1.rows.count) * rowHeight } + CGFloat(max(0, sections.count - 1)) * sectionGap
    }

    private static func build(_ sections: [Section], in column: UIView) {
        var y: CGFloat = 0
        for (i, section) in sections.enumerated() {
            if i > 0 { y += sectionGap }
            let header = DialogPanelView.label(section.title, size: Theme.Text.footnote, weight: .semibold, color: Theme.secondaryText)
            header.frame = CGRect(x: 0, y: y, width: 300, height: headerHeight)
            header.autoresizingMask = [.flexibleWidth]
            column.addSubview(header)
            y += headerHeight
            for row in section.rows {
                let r = ShortcutRow(keys: row.keys, text: row.text)
                r.frame = CGRect(x: 0, y: y, width: 300, height: rowHeight)
                r.autoresizingMask = [.flexibleWidth]
                column.addSubview(r)
                y += rowHeight
            }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let inset = DialogPanelView.contentInset
        titleLabel.frame = CGRect(x: inset, y: Theme.Space.xl, width: contentView.bounds.width - inset * 2, height: 24)
        let top = Theme.Space.xl + 24 + Theme.Space.l
        let gutter = Theme.Space.xl
        let columnWidth = (contentView.bounds.width - inset * 2 - gutter) / 2
        let height = contentView.bounds.height - top - Theme.Space.l
        columns[0].frame = CGRect(x: inset, y: top, width: columnWidth, height: height)
        columns[1].frame = CGRect(x: inset + columnWidth + gutter, y: top, width: columnWidth, height: height)
    }
}

/// One shortcut: key chips on the left (monospaced, in small pills), the action on the right.
private final class ShortcutRow: UIView {

    private var chips: [UIView] = []
    private var joiners: [UILabel] = []
    private let textLabel: UILabel
    private static let chipHeight: CGFloat = 20
    private static let chipPadding: CGFloat = Theme.Space.s - 2
    private static let keysWidth: CGFloat = 150

    init(keys: String, text: String) {
        textLabel = DialogPanelView.label(text, size: Theme.Text.body)
        super.init(frame: .zero)
        let parts = keys.components(separatedBy: " / ")
        for (i, part) in parts.enumerated() {
            if i > 0 {
                let joiner = DialogPanelView.label("/", size: Theme.Text.footnote, color: Theme.tertiaryText, alignment: .center)
                joiners.append(joiner)
                addSubview(joiner)
            }
            let chip = UIView()
            chip.backgroundColor = Theme.controlBackground
            chip.layer.cornerRadius = Theme.Radius.control
            chip.layer.cornerCurve = .continuous
            chip.layer.borderWidth = Theme.Size.hairline
            chip.layer.borderColor = Theme.border.cgColor
            let label = UILabel()
            label.text = part
            label.font = Theme.monoFont(Theme.Text.caption, weight: .medium)
            label.textColor = Theme.text
            label.textAlignment = .center
            label.tag = 1
            chip.addSubview(label)
            chips.append(chip)
            addSubview(chip)
        }
        addSubview(textLabel)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        var x: CGFloat = 0
        let y = (bounds.height - Self.chipHeight) / 2
        for (i, chip) in chips.enumerated() {
            if i > 0 {
                let joiner = joiners[i - 1]
                joiner.frame = CGRect(x: x, y: y, width: 12, height: Self.chipHeight)
                x += 12
            }
            guard let label = chip.viewWithTag(1) as? UILabel else { continue }
            let w = ceil(label.intrinsicContentSize.width) + Self.chipPadding * 2
            chip.frame = CGRect(x: x, y: y, width: w, height: Self.chipHeight)
            label.frame = chip.bounds
            x += w + Theme.Space.xs
        }
        let textX = max(x + Theme.Space.s, Self.keysWidth)
        textLabel.frame = CGRect(x: textX, y: 0, width: bounds.width - textX, height: bounds.height)
    }
}
