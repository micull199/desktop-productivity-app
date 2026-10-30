import UIKit

/// Visual constants for the desktop. Dark, translucent, macOS-flavoured.
enum Theme {
    static let menuBarHeight: CGFloat = 30
    static let dockHeight: CGFloat = 76
    static let windowCornerRadius: CGFloat = 11
    static let titleBarHeight: CGFloat = 38

    static let windowBackground = UIColor(red: 0.118, green: 0.122, blue: 0.137, alpha: 1)
    static let titleBarBackground = UIColor(red: 0.165, green: 0.169, blue: 0.188, alpha: 1)
    static let titleBarBackgroundInactive = UIColor(red: 0.14, green: 0.142, blue: 0.155, alpha: 1)
    static let separator = UIColor(white: 1, alpha: 0.08)
    static let border = UIColor(white: 1, alpha: 0.14)
    static let controlBackground = UIColor(white: 1, alpha: 0.07)
    static let controlBackgroundHover = UIColor(white: 1, alpha: 0.13)
    static let controlBackgroundPressed = UIColor(white: 1, alpha: 0.2)
    static let accent = UIColor(red: 0.25, green: 0.52, blue: 0.98, alpha: 1)
    static let accentText = UIColor(red: 0.45, green: 0.66, blue: 1.0, alpha: 1)
    static let text = UIColor(white: 0.95, alpha: 1)
    static let secondaryText = UIColor(white: 0.62, alpha: 1)
    static let tertiaryText = UIColor(white: 0.42, alpha: 1)
    static let selection = UIColor(red: 0.25, green: 0.52, blue: 0.98, alpha: 0.35)
    static let destructive = UIColor(red: 1.0, green: 0.35, blue: 0.33, alpha: 1)

    static let trafficClose = UIColor(red: 1.0, green: 0.37, blue: 0.34, alpha: 1)
    static let trafficMinimize = UIColor(red: 1.0, green: 0.74, blue: 0.18, alpha: 1)
    static let trafficZoom = UIColor(red: 0.16, green: 0.78, blue: 0.25, alpha: 1)
    static let trafficInactive = UIColor(white: 0.35, alpha: 1)

    static func font(_ size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        .systemFont(ofSize: size, weight: weight)
    }

    static func monoFont(_ size: CGFloat) -> UIFont {
        .monospacedSystemFont(ofSize: size, weight: .regular)
    }

    static func wallpaperColors(_ wallpaper: Wallpaper) -> [CGColor] {
        switch wallpaper {
        case .sonoma:
            return [UIColor(red: 0.07, green: 0.25, blue: 0.52, alpha: 1).cgColor,
                    UIColor(red: 0.26, green: 0.47, blue: 0.78, alpha: 1).cgColor,
                    UIColor(red: 0.84, green: 0.56, blue: 0.47, alpha: 1).cgColor]
        case .midnight:
            return [UIColor(red: 0.03, green: 0.04, blue: 0.09, alpha: 1).cgColor,
                    UIColor(red: 0.08, green: 0.1, blue: 0.22, alpha: 1).cgColor,
                    UIColor(red: 0.2, green: 0.13, blue: 0.35, alpha: 1).cgColor]
        case .sunrise:
            return [UIColor(red: 0.34, green: 0.13, blue: 0.38, alpha: 1).cgColor,
                    UIColor(red: 0.86, green: 0.36, blue: 0.39, alpha: 1).cgColor,
                    UIColor(red: 0.99, green: 0.74, blue: 0.4, alpha: 1).cgColor]
        case .graphite:
            return [UIColor(white: 0.1, alpha: 1).cgColor,
                    UIColor(white: 0.2, alpha: 1).cgColor,
                    UIColor(white: 0.32, alpha: 1).cgColor]
        }
    }
}

extension UIView {
    /// Applies a soft drop shadow suitable for floating panels.
    func applyPanelShadow(radius: CGFloat = 18, opacity: Float = 0.4, offset: CGSize = CGSize(width: 0, height: 10)) {
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowRadius = radius
        layer.shadowOpacity = opacity
        layer.shadowOffset = offset
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
