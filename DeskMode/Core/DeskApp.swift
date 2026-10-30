import UIKit

/// The built-in apps that can appear in the Dock and the launcher.
enum DeskApp: String, CaseIterable, Codable {
    case browser, notes, tasks, settings

    var title: String {
        switch self {
        case .browser: return "Browser"
        case .notes: return "Notes"
        case .tasks: return "Tasks"
        case .settings: return "Settings"
        }
    }

    var symbolName: String {
        switch self {
        case .browser: return "safari.fill"
        case .notes: return "note.text"
        case .tasks: return "checklist"
        case .settings: return "gearshape.fill"
        }
    }

    /// Gradient used for the app icon tile.
    var iconColors: (UIColor, UIColor) {
        switch self {
        case .browser: return (UIColor(red: 0.25, green: 0.62, blue: 1.0, alpha: 1), UIColor(red: 0.05, green: 0.36, blue: 0.95, alpha: 1))
        case .notes: return (UIColor(red: 1.0, green: 0.85, blue: 0.35, alpha: 1), UIColor(red: 0.98, green: 0.66, blue: 0.1, alpha: 1))
        case .tasks: return (UIColor(red: 0.45, green: 0.85, blue: 0.5, alpha: 1), UIColor(red: 0.15, green: 0.62, blue: 0.3, alpha: 1))
        case .settings: return (UIColor(white: 0.6, alpha: 1), UIColor(white: 0.3, alpha: 1))
        }
    }

    /// Whether more than one window of this app may be open at the same time.
    var supportsMultipleWindows: Bool { self == .browser }

    var defaultSize: CGSize {
        switch self {
        case .browser: return CGSize(width: 1180, height: 760)
        case .notes: return CGSize(width: 820, height: 560)
        case .tasks: return CGSize(width: 560, height: 620)
        case .settings: return CGSize(width: 640, height: 600)
        }
    }

    var minimumSize: CGSize {
        switch self {
        case .browser: return CGSize(width: 520, height: 360)
        case .notes: return CGSize(width: 480, height: 320)
        case .tasks: return CGSize(width: 360, height: 320)
        case .settings: return CGSize(width: 480, height: 400)
        }
    }

    /// Builds an icon image (rounded tile with a symbol) of the given size.
    func icon(size: CGFloat) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        return renderer.image { ctx in
            let rect = CGRect(x: 0, y: 0, width: size, height: size)
            let path = UIBezierPath(roundedRect: rect, cornerRadius: size * 0.225)
            ctx.cgContext.addPath(path.cgPath)
            ctx.cgContext.clip()
            let (top, bottom) = iconColors
            let colors = [top.cgColor, bottom.cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                ctx.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size), options: [])
            }
            let config = UIImage.SymbolConfiguration(pointSize: size * 0.5, weight: .medium)
            if let symbol = UIImage(systemName: symbolName, withConfiguration: config)?.withTintColor(.white, renderingMode: .alwaysOriginal) {
                let s = symbol.size
                symbol.draw(in: CGRect(x: (size - s.width) / 2, y: (size - s.height) / 2, width: s.width, height: s.height))
            }
        }
    }
}
