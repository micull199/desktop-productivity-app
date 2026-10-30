import UIKit

/// Draws the desktop's mouse cursor. It is always the top-most view on the external display.
///
/// Every cursor is a vector shape (black fill, 1.5 pt white outline, soft shadow) sized for a
/// 1080p display: the arrow is about 13 × 20 pt, like macOS. The two hand cursors that are hard
/// to draw by hand reuse SF Symbols, outlined in white so they match the rest of the set.
final class CursorView: UIView {

    var style: CursorStyle = .arrow {
        didSet { if style != oldValue { render() } }
    }

    /// Offset from the view's origin to the point that represents the cursor's hot spot.
    private(set) var hotspot = CGPoint.zero

    private let outline = CAShapeLayer()
    private let shape = CAShapeLayer()
    private let imageView = UIImageView()
    private static var symbolCache: [String: UIImage] = [:]

    private static let outlineWidth: CGFloat = 1.5
    private static let canvas = Theme.Size.cursorCanvas

    override init(frame: CGRect) {
        super.init(frame: CGRect(x: 0, y: 0, width: Self.canvas, height: Self.canvas))
        isUserInteractionEnabled = false
        layer.addSublayer(outline)
        layer.addSublayer(shape)
        addSubview(imageView)
        imageView.contentMode = .topLeft
        imageView.frame = bounds
        outline.lineJoin = .round
        outline.lineCap = .round
        shape.lineJoin = .round
        shape.lineCap = .round
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.4
        layer.shadowRadius = 1.6
        layer.shadowOffset = CGSize(width: 0.5, height: 1.5)
        render()
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Moves the cursor so that its hot spot sits at `point` (in the superview's coordinates).
    func place(at point: CGPoint) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        frame.origin = CGPoint(x: point.x - hotspot.x, y: point.y - hotspot.y)
        CATransaction.commit()
    }

    // MARK: - Rendering

    private func render() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        isHidden = style == .hidden
        imageView.image = nil
        shape.path = nil
        outline.path = nil

        let c = Self.canvas / 2
        switch style {
        case .arrow, .hidden:
            fill(Self.arrowPath(origin: CGPoint(x: 2, y: 2)), hotspot: CGPoint(x: 2, y: 2))
        case .iBeam:
            let p = UIBezierPath()
            p.move(to: CGPoint(x: c - 3.5, y: c - 9)); p.addLine(to: CGPoint(x: c + 3.5, y: c - 9))
            p.move(to: CGPoint(x: c, y: c - 9)); p.addLine(to: CGPoint(x: c, y: c + 9))
            p.move(to: CGPoint(x: c - 3.5, y: c + 9)); p.addLine(to: CGPoint(x: c + 3.5, y: c + 9))
            stroke(p, width: 1.6, hotspot: CGPoint(x: c, y: c))
        case .crosshair:
            let p = UIBezierPath()
            p.move(to: CGPoint(x: c, y: c - 10)); p.addLine(to: CGPoint(x: c, y: c - 2))
            p.move(to: CGPoint(x: c, y: c + 2)); p.addLine(to: CGPoint(x: c, y: c + 10))
            p.move(to: CGPoint(x: c - 10, y: c)); p.addLine(to: CGPoint(x: c - 2, y: c))
            p.move(to: CGPoint(x: c + 2, y: c)); p.addLine(to: CGPoint(x: c + 10, y: c))
            stroke(p, width: 1.6, hotspot: CGPoint(x: c, y: c))
        case .notAllowed:
            let p = UIBezierPath(ovalIn: CGRect(x: c - 8, y: c - 8, width: 16, height: 16))
            p.move(to: CGPoint(x: c - 5.6, y: c - 5.6)); p.addLine(to: CGPoint(x: c + 5.6, y: c + 5.6))
            stroke(p, width: 2.2, hotspot: CGPoint(x: c, y: c))
        case .resizeHorizontal:
            fill(Self.doubleArrowPath(center: CGPoint(x: c, y: c), angle: 0), hotspot: CGPoint(x: c, y: c))
        case .resizeVertical:
            fill(Self.doubleArrowPath(center: CGPoint(x: c, y: c), angle: .pi / 2), hotspot: CGPoint(x: c, y: c))
        case .resizeDiagonalNWSE:
            fill(Self.doubleArrowPath(center: CGPoint(x: c, y: c), angle: .pi / 4), hotspot: CGPoint(x: c, y: c))
        case .resizeDiagonalNESW:
            fill(Self.doubleArrowPath(center: CGPoint(x: c, y: c), angle: -.pi / 4), hotspot: CGPoint(x: c, y: c))
        case .closedHand:
            fill(Self.fistPath(center: CGPoint(x: c, y: c)), hotspot: CGPoint(x: c, y: c))
        case .pointingHand:
            symbol("hand.point.up.left.fill", pointSize: 19, hotspotFraction: CGPoint(x: 0.36, y: 0.04))
        case .openHand:
            symbol("hand.raised.fill", pointSize: 19, hotspotFraction: CGPoint(x: 0.5, y: 0.5))
        }
    }

    private func fill(_ path: UIBezierPath, hotspot: CGPoint) {
        self.hotspot = hotspot
        outline.path = path.cgPath
        outline.fillColor = Theme.cursorOutline.cgColor
        outline.strokeColor = Theme.cursorOutline.cgColor
        outline.lineWidth = Self.outlineWidth * 2
        shape.path = path.cgPath
        shape.fillColor = Theme.cursorFill.cgColor
        shape.strokeColor = nil
        shape.lineWidth = 0
    }

    private func stroke(_ path: UIBezierPath, width: CGFloat, hotspot: CGPoint) {
        self.hotspot = hotspot
        outline.path = path.cgPath
        outline.fillColor = nil
        outline.strokeColor = Theme.cursorOutline.cgColor
        outline.lineWidth = width + Self.outlineWidth * 2
        shape.path = path.cgPath
        shape.fillColor = nil
        shape.strokeColor = Theme.cursorFill.cgColor
        shape.lineWidth = width
    }

    /// An SF Symbol drawn in black with a white outline, cached per name.
    private func symbol(_ name: String, pointSize: CGFloat, hotspotFraction: CGPoint) {
        let key = "\(name)@\(pointSize)"
        let image: UIImage?
        if let cached = Self.symbolCache[key] {
            image = cached
        } else {
            image = Self.outlinedSymbol(name, pointSize: pointSize)
            if let image { Self.symbolCache[key] = image }
        }
        imageView.image = image
        let size = image?.size ?? .zero
        hotspot = CGPoint(x: size.width * hotspotFraction.x, y: size.height * hotspotFraction.y)
    }

    private static func outlinedSymbol(_ name: String, pointSize: CGFloat) -> UIImage? {
        let config = UIImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
        guard let base = UIImage(systemName: name, withConfiguration: config) else { return nil }
        let white = base.withTintColor(Theme.cursorOutline, renderingMode: .alwaysOriginal)
        let black = base.withTintColor(Theme.cursorFill, renderingMode: .alwaysOriginal)
        let pad = outlineWidth + 1
        let size = CGSize(width: base.size.width + pad * 2, height: base.size.height + pad * 2)
        return UIGraphicsImageRenderer(size: size).image { _ in
            let origin = CGPoint(x: pad, y: pad)
            let steps = 16
            for i in 0..<steps {
                let a = CGFloat(i) / CGFloat(steps) * 2 * .pi
                white.draw(at: CGPoint(x: origin.x + cos(a) * outlineWidth, y: origin.y + sin(a) * outlineWidth))
            }
            black.draw(at: origin)
        }
    }

    // MARK: - Paths

    /// The macOS arrow, about 13 × 20 pt, tip at `origin`.
    private static func arrowPath(origin o: CGPoint) -> UIBezierPath {
        let p = UIBezierPath()
        p.move(to: CGPoint(x: o.x, y: o.y))
        p.addLine(to: CGPoint(x: o.x, y: o.y + 16.6))
        p.addLine(to: CGPoint(x: o.x + 4.1, y: o.y + 12.9))
        p.addLine(to: CGPoint(x: o.x + 7.1, y: o.y + 19.4))
        p.addLine(to: CGPoint(x: o.x + 9.9, y: o.y + 18.2))
        p.addLine(to: CGPoint(x: o.x + 6.9, y: o.y + 11.8))
        p.addLine(to: CGPoint(x: o.x + 12.7, y: o.y + 11.8))
        p.close()
        return p
    }

    /// A double-headed resize arrow rotated by `angle` around `center`.
    private static func doubleArrowPath(center c: CGPoint, angle: CGFloat) -> UIBezierPath {
        let L: CGFloat = 11, h: CGFloat = 6, w: CGFloat = 5, t: CGFloat = 1.5
        let p = UIBezierPath()
        p.move(to: CGPoint(x: -L, y: 0))
        p.addLine(to: CGPoint(x: -L + h, y: -w))
        p.addLine(to: CGPoint(x: -L + h, y: -t))
        p.addLine(to: CGPoint(x: L - h, y: -t))
        p.addLine(to: CGPoint(x: L - h, y: -w))
        p.addLine(to: CGPoint(x: L, y: 0))
        p.addLine(to: CGPoint(x: L - h, y: w))
        p.addLine(to: CGPoint(x: L - h, y: t))
        p.addLine(to: CGPoint(x: -L + h, y: t))
        p.addLine(to: CGPoint(x: -L + h, y: w))
        p.close()
        p.apply(CGAffineTransform(rotationAngle: angle))
        p.apply(CGAffineTransform(translationX: c.x, y: c.y))
        return p
    }

    /// A closed (grabbing) hand: a palm with four knuckles and a thumb.
    private static func fistPath(center c: CGPoint) -> UIBezierPath {
        let p = UIBezierPath(roundedRect: CGRect(x: c.x - 7.5, y: c.y - 2, width: 15, height: 10.5), cornerRadius: 4)
        for (i, dy) in [1.0, -0.6, -0.6, 1.0].enumerated() {
            let x = c.x - 5.6 + CGFloat(i) * 3.7
            p.append(UIBezierPath(ovalIn: CGRect(x: x - 2.4, y: c.y - 4.4 + dy, width: 4.8, height: 4.8)))
        }
        p.append(UIBezierPath(ovalIn: CGRect(x: c.x - 10, y: c.y - 1, width: 5.2, height: 6.5)))
        p.usesEvenOddFillRule = false
        return p
    }
}
