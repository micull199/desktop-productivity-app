import UIKit
import WebKit

/// Hosts a `WKWebView` inside a desktop window and bridges the virtual cursor and keyboard
/// into the page through `BrowserScripts.bridge`.
final class WebContentView: UIView, PointerTarget, KeyTarget {

    let webView: WKWebView
    weak var desktop: DesktopViewController?

    /// Called with the link / image / selection under the cursor after a right-click.
    var onContextMenu: ((ContextInfo, CGPoint) -> Void)?
    /// Called on any mouse-down so the owning window can move keyboard focus to the page.
    var onInteraction: (() -> Void)?

    struct ContextInfo: Decodable {
        var link: String
        var image: String
        var selection: String
        var editable: Bool
    }

    private var cssCursor: CursorStyle = .arrow
    private var moveInFlight = false
    private var pendingMove: CGPoint?
    private var lastLocal = CGPoint.zero

    init(webView: WKWebView) {
        self.webView = webView
        super.init(frame: .zero)
        addSubview(webView)
        webView.scrollView.indicatorStyle = .white
        webView.scrollView.showsVerticalScrollIndicator = true
        webView.isOpaque = true
        webView.backgroundColor = .white
    }

    required init?(coder: NSCoder) { fatalError() }

    /// User-chosen zoom (⌘+ / ⌘−). WKWebView's `pageZoom` also carries the desktop's pixel scale.
    var userZoom: CGFloat = 1 { didSet { applyZoom() } }

    /// 2 on a 4K monitor: the desktop is drawn through a 2× transform, so the web view is given
    /// twice the bounds and the inverse transform. Its net transform is identity, WebKit renders
    /// straight to pixels, and `pageZoom` doubles so the page keeps the same CSS layout width.
    private var pixelScale: CGFloat { (window as? DesktopWindow)?.contentScale ?? 1 }

    override func layoutSubviews() {
        super.layoutSubviews()
        let s = pixelScale
        webView.transform = .identity
        webView.bounds = CGRect(x: 0, y: 0, width: bounds.width * s, height: bounds.height * s)
        webView.center = CGPoint(x: bounds.midX, y: bounds.midY)
        if s != 1 { webView.transform = CGAffineTransform(scaleX: 1 / s, y: 1 / s) }
        applyZoom()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        setNeedsLayout()
    }

    private func applyZoom() {
        let z = userZoom * pixelScale
        if webView.pageZoom != z { webView.pageZoom = z }
    }

    // MARK: - Helpers

    private func pagePoint(_ local: CGPoint) -> CGPoint {
        // The page's CSS pixel coordinates equal the web view's local coordinates divided by zoom.
        let zoom = webView.pageZoom == 0 ? 1 : webView.pageZoom
        let p = convert(local, to: webView)
        return CGPoint(x: p.x / zoom, y: p.y / zoom)
    }

    private func js(_ script: String, completion: ((Any?) -> Void)? = nil) {
        webView.evaluateJavaScript(script) { result, _ in completion?(result) }
    }

    private static func jsString(_ s: String) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: [s])) ?? Data()
        let array = String(data: data, encoding: .utf8) ?? "[\"\"]"
        return String(array.dropFirst().dropLast())
    }

    // MARK: - PointerTarget

    func pointer(_ event: PointerEvent, local: CGPoint) {
        lastLocal = local
        let p = pagePoint(local)
        switch event.kind {
        case .move:
            sendMove(p)
        case .down(let button):
            onInteraction?()
            let b = button.rawValue
            js("window.__dm && window.__dm.down(\(p.x), \(p.y), \(b), \(event.clickCount), \(event.modifiers.webMask))") { [weak self] result in
                guard let self, button == .right, let json = result as? String, !json.isEmpty,
                      let data = json.data(using: .utf8),
                      let info = try? JSONDecoder().decode(ContextInfo.self, from: data) else { return }
                self.onContextMenu?(info, event.location)
            }
        case .up(let button):
            js("window.__dm && window.__dm.up(\(p.x), \(p.y), \(button.rawValue), \(event.clickCount))")
        case .scroll(let dx, let dy):
            js("window.__dm ? window.__dm.scroll(\(p.x), \(p.y), \(dx), \(dy)) : 'main'") { [weak self] result in
                guard let self, (result as? String) == "main" else { return }
                self.scrollMainDocument(dx: dx, dy: dy)
            }
        }
    }

    private func sendMove(_ p: CGPoint) {
        guard !moveInFlight else { pendingMove = p; return }
        moveInFlight = true
        js("window.__dm ? window.__dm.move(\(p.x), \(p.y)) : 'default'") { [weak self] result in
            guard let self else { return }
            self.moveInFlight = false
            let css = (result as? String) ?? "default"
            let style = CursorStyle.fromCSS(css)
            if style != self.cssCursor {
                self.cssCursor = style
                self.desktop?.refreshCursorStyle(for: self)
            }
            if let next = self.pendingMove {
                self.pendingMove = nil
                self.sendMove(next)
            }
        }
    }

    private func scrollMainDocument(dx: CGFloat, dy: CGFloat) {
        let sv = webView.scrollView
        let s = pixelScale
        let dx = dx * s, dy = dy * s
        var o = sv.contentOffset
        let maxX = max(0, sv.contentSize.width - sv.bounds.width + sv.adjustedContentInset.right)
        let maxY = max(0, sv.contentSize.height - sv.bounds.height + sv.adjustedContentInset.bottom)
        o.x = min(max(-sv.adjustedContentInset.left, o.x + dx), maxX)
        o.y = min(max(-sv.adjustedContentInset.top, o.y + dy), maxY)
        sv.setContentOffset(o, animated: false)
    }

    func pointerExited() {
        js("window.__dm && window.__dm.move(-1, -1)")
        cssCursor = .arrow
    }

    func cursorStyle(at local: CGPoint) -> CursorStyle { cssCursor }

    // MARK: - KeyTarget

    func key(_ event: KeyEvent) -> Bool {
        let phase = event.isDown ? "down" : "up"
        let text = event.isPrintable ? event.characters : ""
        let script = "window.__dm ? window.__dm.key(\(Self.jsString(phase)), \(Self.jsString(event.webKey)), \(Self.jsString(event.webCode)), \(Self.jsString(text)), \(event.modifiers.webMask), \(event.legacyKeyCode), \(event.isRepeat)) : 'unhandled'"
        js(script) { [weak self] result in
            guard let self, let r = result as? String else { return }
            if r.hasPrefix("copy:") {
                let text = String(r.dropFirst(5))
                if !text.isEmpty {
                    UIPasteboard.general.string = text
                    self.desktop?.showToast("Copied")
                }
            } else if r == "paste" {
                if let s = UIPasteboard.general.string {
                    self.js("window.__dm && window.__dm.paste(\(Self.jsString(s)))")
                }
            } else if r == "unhandled", event.isDown {
                self.handleNavigationKey(event)
            }
        }
        return true
    }

    /// Space / arrows / page keys scroll the document when nothing editable is focused.
    private func handleNavigationKey(_ event: KeyEvent) {
        let page = webView.scrollView.bounds.height * 0.85
        switch event.keyCode {
        case .keyboardSpacebar: scrollMainDocument(dx: 0, dy: event.shift ? -page : page)
        case .keyboardPageDown: scrollMainDocument(dx: 0, dy: page)
        case .keyboardPageUp: scrollMainDocument(dx: 0, dy: -page)
        case .keyboardDownArrow: scrollMainDocument(dx: 0, dy: 60)
        case .keyboardUpArrow: scrollMainDocument(dx: 0, dy: -60)
        case .keyboardHome: webView.scrollView.setContentOffset(CGPoint(x: 0, y: -webView.scrollView.adjustedContentInset.top), animated: true)
        case .keyboardEnd: scrollMainDocument(dx: 0, dy: webView.scrollView.contentSize.height)
        default: break
        }
    }
}
