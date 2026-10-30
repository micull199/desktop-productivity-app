import UIKit

/// Draws the desktop's mouse cursor. It is always the top-most view on the external display.
final class CursorView: UIView {

    var style: CursorStyle = .arrow {
        didSet { if style != oldValue { render() } }
    }

    /// Offset from the view's origin to the point that represents the cursor's hot spot.
    private(set) var hotspot = CGPoint.zero

    private let shape = CAShapeLayer()
    private let outline = CAShapeLayer()
    private let imageView = UIImageView()

    override init(frame: CGRect) {
        super.init(frame: CGRect(x: 0, y: 0, width: 32, height: 32))
        isUserInteractionEnabled = false
        layer.addSublayer(outline)
        layer.addSublayer(shape)
        addSubview(imageView)
        imageView.contentMode = .center
        imageView.frame = bounds
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.45
        layer.shadowRadius = 1.5
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

    private func render() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        isHidden = style == .hidden
        imageView.image = nil
        imageView.transform = .identity
        shape.path = nil
        outline.path = nil

        switch style {
        case .arrow, .hidden:
            let path = UIBezierPath()
            path.move(to: CGPoint(x: 1, y: 1))
            path.addLine(to: CGPoint(x: 1, y: 19))
            path.addLine(to: CGPoint(x: 5.6, y: 15))
            path.addLine(to: CGPoint(x: 8.6, y: 22.4))
            path.addLine(to: CGPoint(x: 11.6, y: 21.1))
            path.addLine(to: CGPoint(x: 8.6, y: 14))
            path.addLine(to: CGPoint(x: 14.6, y: 14))
            path.close()
            fill(path, hotspot: CGPoint(x: 1, y: 1))
        case .iBeam:
            let path = UIBezierPath()
            // top serif
            path.move(to: CGPoint(x: 6, y: 2)); path.addLine(to: CGPoint(x: 14, y: 2))
            // stem
            path.move(to: CGPoint(x: 10, y: 2)); path.addLine(to: CGPoint(x: 10, y: 22))
            // bottom serif
            path.move(to: CGPoint(x: 6, y: 22)); path.addLine(to: CGPoint(x: 14, y: 22))
            stroke(path, hotspot: CGPoint(x: 10, y: 12))
        case .crosshair:
            let path = UIBezierPath()
            path.move(to: CGPoint(x: 12, y: 2)); path.addLine(to: CGPoint(x: 12, y: 22))
            path.move(to: CGPoint(x: 2, y: 12)); path.addLine(to: CGPoint(x: 22, y: 12))
            stroke(path, hotspot: CGPoint(x: 12, y: 12))
        case .pointingHand:
            symbol("hand.point.up.left.fill", hotspot: CGPoint(x: 11, y: 6))
        case .openHand:
            symbol("hand.raised.fill", hotspot: CGPoint(x: 16, y: 16))
        case .closedHand:
            symbol("hand.raised.fingers.spread.fill", hotspot: CGPoint(x: 16, y: 16))
        case .notAllowed:
            symbol("circle.slash", hotspot: CGPoint(x: 16, y: 16))
        case .resizeHorizontal:
            symbol("arrow.left.and.right", hotspot: CGPoint(x: 16, y: 16))
        case .resizeVertical:
            symbol("arrow.up.and.down", hotspot: CGPoint(x: 16, y: 16))
        case .resizeDiagonalNWSE:
            symbol("arrow.up.left.and.arrow.down.right", hotspot: CGPoint(x: 16, y: 16))
        case .resizeDiagonalNESW:
            symbol("arrow.up.right.and.arrow.down.left", hotspot: CGPoint(x: 16, y: 16))
        }
    }

    private func fill(_ path: UIBezierPath, hotspot: CGPoint) {
        self.hotspot = hotspot
        outline.path = path.cgPath
        outline.fillColor = UIColor.white.cgColor
        outline.strokeColor = UIColor.white.cgColor
        outline.lineWidth = 3
        outline.lineJoin = .round
        shape.path = path.cgPath
        shape.fillColor = UIColor.black.cgColor
        shape.strokeColor = nil
    }

    private func stroke(_ path: UIBezierPath, hotspot: CGPoint) {
        self.hotspot = hotspot
        outline.path = path.cgPath
        outline.fillColor = nil
        outline.strokeColor = UIColor.white.cgColor
        outline.lineWidth = 4
        outline.lineCap = .round
        shape.path = path.cgPath
        shape.fillColor = nil
        shape.strokeColor = UIColor.black.cgColor
        shape.lineWidth = 1.8
        shape.lineCap = .round
    }

    private func symbol(_ name: String, hotspot: CGPoint) {
        self.hotspot = hotspot
        let config = UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold)
        imageView.image = UIImage(systemName: name, withConfiguration: config)?
            .withTintColor(.black, renderingMode: .alwaysOriginal)
        imageView.layer.shadowColor = UIColor.white.cgColor
        imageView.layer.shadowOpacity = 1
        imageView.layer.shadowRadius = 1.2
        imageView.layer.shadowOffset = .zero
    }
}
