import UIKit
import WebKit
import ObjectiveC

/// The window on the external display.
///
/// External screens report `UIScreen.scale == 1`, so on a 4K monitor the desktop is drawn through a
/// 2× transform (see `ScaledHostViewController`). Layers would normally rasterise at 1× and be
/// magnified, which looks soft. `contentScale` records the factor and every view that joins this
/// window is given a matching `contentScaleFactor`, so text, symbols and shapes rasterise at the
/// display's real pixel density. Web views are excluded: `WebContentView` counter-transforms them
/// so WebKit renders straight to pixels.
final class DesktopWindow: UIWindow {

    var contentScale: CGFloat = 1 {
        didSet {
            guard contentScale != oldValue else { return }
            rootViewController?.view.applyDesktopContentScale(contentScale)
        }
    }
}

extension UIView {

    /// Installs the hook that keeps `contentScaleFactor` in step with `DesktopWindow.contentScale`
    /// for every view added to that window. UIKit resets the factor to the screen scale (1) whenever
    /// a view moves to a window, so the only reliable place to set it is right after that.
    static let installDesktopContentScaleHook: Void = {
        guard let original = class_getInstanceMethod(UIView.self, #selector(UIView.didMoveToWindow)),
              let replacement = class_getInstanceMethod(UIView.self, #selector(UIView.dm_didMoveToWindow)) else { return }
        method_exchangeImplementations(original, replacement)
    }()

    @objc fileprivate func dm_didMoveToWindow() {
        dm_didMoveToWindow() // the original implementation, after swizzling
        guard let scale = (window as? DesktopWindow)?.contentScale, scale != 1 else { return }
        applyDesktopContentScale(scale, recursive: false)
    }

    private var isWebContent: Bool {
        var v: UIView? = self
        while let cur = v {
            if cur is WKWebView { return true }
            v = cur.superview
        }
        return false
    }

    /// Rasterise this view (and optionally its subtree) at `scale` pixels per point.
    func applyDesktopContentScale(_ scale: CGFloat, recursive: Bool = true) {
        if isWebContent { return }
        if contentScaleFactor != scale { contentScaleFactor = scale }
        if layer.rasterizationScale != scale { layer.rasterizationScale = scale }
        for sub in layer.sublayers ?? [] where sub.delegate == nil {
            if sub.contentsScale != scale { sub.contentsScale = scale }
            if sub.rasterizationScale != scale { sub.rasterizationScale = scale }
        }
        if recursive {
            for v in subviews { v.applyDesktopContentScale(scale) }
        }
    }
}
