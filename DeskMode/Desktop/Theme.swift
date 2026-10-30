import UIKit

/// The DeskMode design system. Dark, translucent, macOS-grade.
///
/// Everything visual on the desktop reads its constants from here so the shell, the browser
/// and the apps stay one coherent product. Existing names are kept for compatibility; the
/// nested enums (`Space`, `Radius`, `Text`, `Motion`, `Shadow`) are the preferred vocabulary.
enum Theme {

    // MARK: Layout

    static let menuBarHeight: CGFloat = 28
    static let dockHeight: CGFloat = 76
    static let windowCornerRadius: CGFloat = 12
    static let titleBarHeight: CGFloat = 38

    /// 4-point spacing scale. Use these instead of ad-hoc numbers.
    enum Space {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    enum Radius {
        static let control: CGFloat = 6      // buttons, small chips
        static let field: CGFloat = 8        // text fields
        static let menu: CGFloat = 10        // popup menus
        static let panel: CGFloat = 14       // launcher, dialogs, dock
        static let window: CGFloat = 12
        static let tile: CGFloat = 16
    }

    /// Standard control heights.
    enum Size {
        static let controlSmall: CGFloat = 24
        static let control: CGFloat = 28
        static let controlLarge: CGFloat = 32
        static let menuRow: CGFloat = 26
        static let listRow: CGFloat = 44
        static let hairline: CGFloat = 1 / UIScreen.main.scale
    }

    // MARK: Type

    /// Type scale. SF Pro throughout; weights vary, sizes do not.
    enum Text {
        static let caption2: CGFloat = 10.5
        static let caption: CGFloat = 11
        static let footnote: CGFloat = 12
        static let body: CGFloat = 13
        static let callout: CGFloat = 14
        static let headline: CGFloat = 15
        static let title3: CGFloat = 17
        static let title2: CGFloat = 20
        static let title1: CGFloat = 24
        static let display: CGFloat = 32
    }

    static func font(_ size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        .systemFont(ofSize: size, weight: weight)
    }

    static func roundedFont(_ size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        return base.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: size) } ?? base
    }

    static func monoFont(_ size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        .monospacedSystemFont(ofSize: size, weight: weight)
    }

    // MARK: Colour

    // Surfaces
    static let windowBackground = UIColor(red: 0.110, green: 0.114, blue: 0.129, alpha: 1)
    static let titleBarBackground = UIColor(red: 0.165, green: 0.169, blue: 0.188, alpha: 1)
    static let titleBarBackgroundInactive = UIColor(red: 0.135, green: 0.138, blue: 0.152, alpha: 1)
    static let sidebarBackground = UIColor(red: 0.090, green: 0.093, blue: 0.106, alpha: 1)
    static let elevatedBackground = UIColor(red: 0.150, green: 0.154, blue: 0.172, alpha: 1)
    static let separator = UIColor(white: 1, alpha: 0.08)
    static let border = UIColor(white: 1, alpha: 0.14)
    static let borderStrong = UIColor(white: 1, alpha: 0.22)
    static let hairlineDark = UIColor(white: 0, alpha: 0.45)

    // Interactive fills
    static let controlBackground = UIColor(white: 1, alpha: 0.07)
    static let controlBackgroundHover = UIColor(white: 1, alpha: 0.13)
    static let controlBackgroundPressed = UIColor(white: 1, alpha: 0.2)
    static let hoverOverlay = UIColor(white: 1, alpha: 0.06)
    static let pressedOverlay = UIColor(white: 1, alpha: 0.12)

    // Accent (Chrome-blue leaning, tuned for dark surfaces)
    static let accent = UIColor(red: 0.26, green: 0.52, blue: 0.96, alpha: 1)
    static let accentHover = UIColor(red: 0.33, green: 0.58, blue: 0.98, alpha: 1)
    static let accentPressed = UIColor(red: 0.21, green: 0.44, blue: 0.86, alpha: 1)
    static let accentText = UIColor(red: 0.47, green: 0.67, blue: 1.0, alpha: 1)
    static let accentSoft = UIColor(red: 0.26, green: 0.52, blue: 0.96, alpha: 0.18)
    static let focusRing = UIColor(red: 0.26, green: 0.52, blue: 0.96, alpha: 0.55)
    static let selection = UIColor(red: 0.26, green: 0.52, blue: 0.96, alpha: 0.35)

    // Text
    static let text = UIColor(white: 0.96, alpha: 1)
    static let secondaryText = UIColor(white: 0.64, alpha: 1)
    static let tertiaryText = UIColor(white: 0.44, alpha: 1)
    static let quaternaryText = UIColor(white: 0.30, alpha: 1)
    static let textOnAccent = UIColor.white

    // Semantic
    static let destructive = UIColor(red: 1.0, green: 0.38, blue: 0.35, alpha: 1)
    static let success = UIColor(red: 0.30, green: 0.80, blue: 0.45, alpha: 1)
    static let warning = UIColor(red: 1.0, green: 0.72, blue: 0.25, alpha: 1)

    // Traffic lights
    static let trafficClose = UIColor(red: 1.0, green: 0.37, blue: 0.34, alpha: 1)
    static let trafficMinimize = UIColor(red: 1.0, green: 0.74, blue: 0.18, alpha: 1)
    static let trafficZoom = UIColor(red: 0.16, green: 0.78, blue: 0.25, alpha: 1)
    static let trafficInactive = UIColor(white: 0.35, alpha: 1)

    // MARK: Materials

    enum Material {
        case bar        // menu bar, dock
        case menu       // popup menus, tooltips
        case panel      // launcher, dialogs
        case sheet      // heavy, nearly opaque

        var blurStyle: UIBlurEffect.Style {
            switch self {
            case .bar: return .systemThinMaterialDark
            case .menu: return .systemThickMaterialDark
            case .panel: return .systemThickMaterialDark
            case .sheet: return .systemChromeMaterialDark
            }
        }

        /// Tint laid over the blur so materials read as one family.
        var tint: UIColor {
            switch self {
            case .bar: return UIColor(white: 0.06, alpha: 0.35)
            case .menu: return UIColor(white: 0.10, alpha: 0.45)
            case .panel: return UIColor(white: 0.08, alpha: 0.5)
            case .sheet: return UIColor(white: 0.07, alpha: 0.7)
            }
        }
    }

    /// A blurred, tinted, bordered background view.
    static func materialView(_ material: Material, cornerRadius: CGFloat = 0) -> UIVisualEffectView {
        let v = UIVisualEffectView(effect: UIBlurEffect(style: material.blurStyle))
        v.layer.cornerRadius = cornerRadius
        v.layer.cornerCurve = .continuous
        v.clipsToBounds = true
        let tint = UIView()
        tint.backgroundColor = material.tint
        tint.isUserInteractionEnabled = false
        tint.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        tint.frame = v.bounds
        v.contentView.addSubview(tint)
        return v
    }

    // MARK: Motion

    enum Motion {
        static let instant: TimeInterval = 0.08
        static let fast: TimeInterval = 0.14
        static let normal: TimeInterval = 0.22
        static let slow: TimeInterval = 0.32
        static let springDamping: CGFloat = 0.82
        static let springVelocity: CGFloat = 0.4

        /// Ease-out animation with the house timing.
        static func animate(_ duration: TimeInterval = normal, delay: TimeInterval = 0, animations: @escaping () -> Void, completion: ((Bool) -> Void)? = nil) {
            UIView.animate(withDuration: duration, delay: delay, options: [.curveEaseOut, .allowUserInteraction, .beginFromCurrentState], animations: animations, completion: completion)
        }

        /// Gentle spring for things that move or scale into place.
        static func spring(_ duration: TimeInterval = slow, damping: CGFloat = springDamping, animations: @escaping () -> Void, completion: ((Bool) -> Void)? = nil) {
            UIView.animate(withDuration: duration, delay: 0, usingSpringWithDamping: damping, initialSpringVelocity: springVelocity, options: [.allowUserInteraction, .beginFromCurrentState], animations: animations, completion: completion)
        }
    }

    // MARK: Shadows

    enum Shadow {
        case windowFocused, windowInactive, panel, menu, dock, subtle

        var radius: CGFloat {
            switch self {
            case .windowFocused: return 36
            case .windowInactive: return 18
            case .panel: return 40
            case .menu: return 24
            case .dock: return 22
            case .subtle: return 8
            }
        }
        var opacity: Float {
            switch self {
            case .windowFocused: return 0.6
            case .windowInactive: return 0.32
            case .panel: return 0.6
            case .menu: return 0.5
            case .dock: return 0.45
            case .subtle: return 0.3
            }
        }
        var offset: CGSize {
            switch self {
            case .windowFocused: return CGSize(width: 0, height: 18)
            case .windowInactive: return CGSize(width: 0, height: 10)
            case .panel: return CGSize(width: 0, height: 22)
            case .menu: return CGSize(width: 0, height: 12)
            case .dock: return CGSize(width: 0, height: 10)
            case .subtle: return CGSize(width: 0, height: 3)
            }
        }
    }

    // MARK: Wallpapers

    static func wallpaperColors(_ wallpaper: Wallpaper) -> [CGColor] {
        switch wallpaper {
        case .sonoma:
            return [UIColor(red: 0.06, green: 0.20, blue: 0.46, alpha: 1).cgColor,
                    UIColor(red: 0.22, green: 0.42, blue: 0.76, alpha: 1).cgColor,
                    UIColor(red: 0.84, green: 0.55, blue: 0.46, alpha: 1).cgColor]
        case .midnight:
            return [UIColor(red: 0.02, green: 0.03, blue: 0.08, alpha: 1).cgColor,
                    UIColor(red: 0.07, green: 0.09, blue: 0.21, alpha: 1).cgColor,
                    UIColor(red: 0.19, green: 0.12, blue: 0.34, alpha: 1).cgColor]
        case .sunrise:
            return [UIColor(red: 0.32, green: 0.11, blue: 0.36, alpha: 1).cgColor,
                    UIColor(red: 0.86, green: 0.34, blue: 0.38, alpha: 1).cgColor,
                    UIColor(red: 0.99, green: 0.74, blue: 0.40, alpha: 1).cgColor]
        case .graphite:
            return [UIColor(white: 0.08, alpha: 1).cgColor,
                    UIColor(white: 0.17, alpha: 1).cgColor,
                    UIColor(white: 0.28, alpha: 1).cgColor]
        }
    }
}

// MARK: - View helpers

extension UIView {
    /// Applies one of the house shadows. Call again when the state changes (e.g. focus).
    func applyShadow(_ shadow: Theme.Shadow) {
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowRadius = shadow.radius
        layer.shadowOpacity = shadow.opacity
        layer.shadowOffset = shadow.offset
    }

    /// Applies a soft drop shadow suitable for floating panels.
    func applyPanelShadow(radius: CGFloat = 18, opacity: Float = 0.4, offset: CGSize = CGSize(width: 0, height: 10)) {
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowRadius = radius
        layer.shadowOpacity = opacity
        layer.shadowOffset = offset
    }

    /// Hairline border with a continuous corner curve.
    func applyBorder(_ color: UIColor = Theme.border, width: CGFloat = 0.5, cornerRadius: CGFloat? = nil) {
        layer.borderColor = color.cgColor
        layer.borderWidth = width
        if let cornerRadius {
            layer.cornerRadius = cornerRadius
            layer.cornerCurve = .continuous
        }
    }

    func pin(to other: UIView, insets: UIEdgeInsets = .zero) {
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            leadingAnchor.constraint(equalTo: other.leadingAnchor, constant: insets.left),
            trailingAnchor.constraint(equalTo: other.trailingAnchor, constant: -insets.right),
            topAnchor.constraint(equalTo: other.topAnchor, constant: insets.top),
            bottomAnchor.constraint(equalTo: other.bottomAnchor, constant: -insets.bottom)
        ])
    }
}

extension UIImage {
    static func symbol(_ name: String, size: CGFloat, weight: UIFont.Weight = .medium) -> UIImage? {
        UIImage(systemName: name, withConfiguration: UIImage.SymbolConfiguration(pointSize: size, weight: weight.symbolWeight))
    }
}

extension UIFont.Weight {
    var symbolWeight: UIImage.SymbolWeight {
        switch self {
        case .ultraLight: return .ultraLight
        case .thin: return .thin
        case .light: return .light
        case .regular: return .regular
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        case .heavy: return .heavy
        case .black: return .black
        default: return .regular
        }
    }
}
