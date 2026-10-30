import UIKit

/// The built-in apps that can appear in the Dock and the launcher.
enum DeskApp: String, CaseIterable, Codable {
    case browser, notes, tasks, settings

    var title: String {
        switch self {
        case .browser: return "Chrome"
        case .notes: return "Notes"
        case .tasks: return "Tasks"
        case .settings: return "Settings"
        }
    }

    var symbolName: String {
        switch self {
        case .browser: return "globe"
        case .notes: return "note.text"
        case .tasks: return "checklist"
        case .settings: return "gearshape.fill"
        }
    }

    /// Gradient used for the app icon tile (top, bottom).
    var iconColors: (UIColor, UIColor) {
        switch self {
        case .browser: return (UIColor(red: 0.45, green: 0.70, blue: 1.0, alpha: 1), UIColor(red: 0.16, green: 0.42, blue: 0.92, alpha: 1))
        case .notes: return (UIColor(red: 1.0, green: 0.82, blue: 0.36, alpha: 1), UIColor(red: 0.94, green: 0.56, blue: 0.10, alpha: 1))
        case .tasks: return (UIColor(red: 0.42, green: 0.84, blue: 0.52, alpha: 1), UIColor(red: 0.12, green: 0.58, blue: 0.32, alpha: 1))
        case .settings: return (UIColor(red: 0.62, green: 0.64, blue: 0.69, alpha: 1), UIColor(red: 0.28, green: 0.29, blue: 0.33, alpha: 1))
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

    /// Builds the app icon at the given size: a Chrome-style disc for the browser, a rounded
    /// gradient tile with a symbol for everything else.
    func icon(size: CGFloat) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        return renderer.image { ctx in
            if self == .browser {
                Self.drawChromeIcon(in: ctx.cgContext, size: size)
            } else {
                drawTileIcon(in: ctx.cgContext, size: size)
            }
        }
    }

    // MARK: - Drawing

    private func drawTileIcon(in cg: CGContext, size: CGFloat) {
        let rect = CGRect(x: 0, y: 0, width: size, height: size)
        let path = UIBezierPath(roundedRect: rect, cornerRadius: size * 0.225)
        cg.saveGState()
        cg.addPath(path.cgPath)
        cg.clip()
        let (top, bottom) = iconColors
        Self.linearGradient(in: cg, colors: [top, bottom], start: .zero, end: CGPoint(x: 0, y: size))
        // Soft top-left sheen so the tile reads as glass rather than flat paint.
        Self.linearGradient(in: cg, colors: [UIColor.white.withAlphaComponent(0.22), UIColor.white.withAlphaComponent(0)], start: .zero, end: CGPoint(x: size * 0.4, y: size * 0.75))
        cg.restoreGState()

        // Inner hairline keeps the edge crisp against dark and light wallpapers.
        cg.saveGState()
        cg.addPath(UIBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), cornerRadius: size * 0.225 - 0.5).cgPath)
        cg.setStrokeColor(UIColor.white.withAlphaComponent(0.18).cgColor)
        cg.setLineWidth(1)
        cg.strokePath()
        cg.restoreGState()

        let config = UIImage.SymbolConfiguration(pointSize: size * 0.48, weight: .medium)
        if let symbol = UIImage(systemName: symbolName, withConfiguration: config)?.withTintColor(.white, renderingMode: .alwaysOriginal) {
            let s = symbol.size
            cg.saveGState()
            cg.setShadow(offset: CGSize(width: 0, height: size * 0.015), blur: size * 0.04, color: UIColor.black.withAlphaComponent(0.28).cgColor)
            symbol.draw(in: CGRect(x: (size - s.width) / 2, y: (size - s.height) / 2, width: s.width, height: s.height))
            cg.restoreGState()
        }
    }

    /// An original Chrome-style mark: three coloured segments around a white ring and a blue
    /// disc, with soft gradients and a gentle top gloss.
    private static func drawChromeIcon(in cg: CGContext, size: CGFloat) {
        let center = CGPoint(x: size / 2, y: size / 2)
        let outer = size * 0.46
        let disc = CGRect(x: center.x - outer, y: center.y - outer, width: outer * 2, height: outer * 2)

        // Drop shadow under the whole disc.
        cg.saveGState()
        cg.setShadow(offset: CGSize(width: 0, height: size * 0.025), blur: size * 0.07, color: UIColor.black.withAlphaComponent(0.4).cgColor)
        cg.setFillColor(UIColor(white: 0.2, alpha: 1).cgColor)
        cg.fillEllipse(in: disc)
        cg.restoreGState()

        // Segments: red on top, yellow bottom-right, green bottom-left (angles clockwise, y down).
        let third = CGFloat.pi * 2 / 3
        let segments: [(start: CGFloat, light: UIColor, dark: UIColor)] = [
            (-CGFloat.pi * 5 / 6, UIColor(red: 0.96, green: 0.33, blue: 0.27, alpha: 1), UIColor(red: 0.80, green: 0.16, blue: 0.13, alpha: 1)),
            (-CGFloat.pi / 6, UIColor(red: 1.0, green: 0.80, blue: 0.14, alpha: 1), UIColor(red: 0.96, green: 0.62, blue: 0.02, alpha: 1)),
            (CGFloat.pi / 2, UIColor(red: 0.30, green: 0.74, blue: 0.40, alpha: 1), UIColor(red: 0.10, green: 0.53, blue: 0.27, alpha: 1))
        ]
        for seg in segments {
            cg.saveGState()
            let wedge = UIBezierPath()
            wedge.move(to: center)
            wedge.addArc(withCenter: center, radius: outer, startAngle: seg.start, endAngle: seg.start + third, clockwise: true)
            wedge.close()
            cg.addPath(wedge.cgPath)
            cg.clip()
            let mid = seg.start + third / 2
            let dir = CGPoint(x: cos(mid), y: sin(mid))
            let from = CGPoint(x: center.x + dir.x * outer, y: center.y + dir.y * outer)
            let to = CGPoint(x: center.x - dir.x * outer * 0.15, y: center.y - dir.y * outer * 0.15)
            linearGradient(in: cg, colors: [seg.light, seg.dark], start: from, end: to)
            cg.restoreGState()
        }

        // Soft seams between the segments.
        cg.saveGState()
        cg.setStrokeColor(UIColor.black.withAlphaComponent(0.10).cgColor)
        cg.setLineWidth(max(1, size * 0.012))
        for seg in segments {
            let a = seg.start
            cg.move(to: CGPoint(x: center.x + cos(a) * outer * 0.42, y: center.y + sin(a) * outer * 0.42))
            cg.addLine(to: CGPoint(x: center.x + cos(a) * outer, y: center.y + sin(a) * outer))
        }
        cg.strokePath()
        cg.restoreGState()

        // Gloss across the top half.
        cg.saveGState()
        cg.addEllipse(in: disc)
        cg.clip()
        linearGradient(in: cg, colors: [UIColor.white.withAlphaComponent(0.20), UIColor.white.withAlphaComponent(0.0)], start: CGPoint(x: center.x, y: disc.minY), end: CGPoint(x: center.x, y: center.y))
        cg.restoreGState()

        // White ring with a faint shadow where it meets the colours.
        let ringR = outer * 0.47
        let ringRect = CGRect(x: center.x - ringR, y: center.y - ringR, width: ringR * 2, height: ringR * 2)
        cg.saveGState()
        cg.setShadow(offset: CGSize(width: 0, height: size * 0.008), blur: size * 0.03, color: UIColor.black.withAlphaComponent(0.3).cgColor)
        cg.setFillColor(UIColor.white.cgColor)
        cg.fillEllipse(in: ringRect)
        cg.restoreGState()
        cg.saveGState()
        cg.addEllipse(in: ringRect)
        cg.clip()
        linearGradient(in: cg, colors: [UIColor.white, UIColor(white: 0.90, alpha: 1)], start: CGPoint(x: center.x, y: ringRect.minY), end: CGPoint(x: center.x, y: ringRect.maxY))
        cg.restoreGState()

        // Blue disc with a radial highlight.
        let blueR = outer * 0.36
        let blueRect = CGRect(x: center.x - blueR, y: center.y - blueR, width: blueR * 2, height: blueR * 2)
        cg.saveGState()
        cg.addEllipse(in: blueRect)
        cg.clip()
        let blueColors = [UIColor(red: 0.55, green: 0.76, blue: 1.0, alpha: 1).cgColor,
                          UIColor(red: 0.26, green: 0.52, blue: 0.96, alpha: 1).cgColor,
                          UIColor(red: 0.13, green: 0.38, blue: 0.85, alpha: 1).cgColor] as CFArray
        if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: blueColors, locations: [0, 0.55, 1]) {
            let highlight = CGPoint(x: center.x - blueR * 0.35, y: center.y - blueR * 0.4)
            cg.drawRadialGradient(g, startCenter: highlight, startRadius: 0, endCenter: center, endRadius: blueR * 1.05, options: [.drawsAfterEndLocation])
        }
        cg.restoreGState()
    }

    private static func linearGradient(in cg: CGContext, colors: [UIColor], start: CGPoint, end: CGPoint) {
        let cgColors = colors.map { $0.cgColor } as CFArray
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: cgColors, locations: nil) else { return }
        cg.drawLinearGradient(gradient, start: start, end: end, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }
}
