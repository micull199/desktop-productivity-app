import UIKit
import WebKit

/// One tab: a web view plus observable navigation state, favicon and history recording.
@MainActor
final class BrowserTab: NSObject {

    static let chromeUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36"
    static let safariUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15"
    /// Kept for callers that referenced the old name.
    static var desktopUserAgent: String { safariUserAgent }

    /// User agent for new tabs given the current settings; `nil` keeps WebKit's mobile default.
    static var userAgent: String? {
        let s = Settings.shared
        guard s.desktopWebsites else { return nil }
        return s.identifyAsChrome ? chromeUserAgent : safariUserAgent
    }

    /// Base URL of the new-tab page. A real https origin so WebKit accepts it, favicons and
    /// absolute links resolve, and `isStartPage` can be derived from the host.
    static let startPageURL = URL(string: "https://newtab.deskmode.local/")!

    static func isStartPageURL(_ url: URL?) -> Bool {
        url?.host?.lowercased() == startPageURL.host
    }

    let id = UUID()
    let webView: WKWebView
    let contentView: WebContentView

    private(set) var title: String = "New Tab"
    private(set) var url: URL?
    private(set) var isLoading = false
    private(set) var progress: Double = 0
    private(set) var canGoBack = false
    private(set) var canGoForward = false
    private(set) var isStartPage = true
    private(set) var favicon: UIImage?
    private var faviconHost: String?
    /// The address that failed to load while the error page is showing, so the omnibox keeps it.
    private var errorURL: URL?

    var onChange: (() -> Void)?
    var onOpenNewTab: ((URL?, WKWebViewConfiguration?) -> WKWebView?)?
    var onAlert: ((String) -> Void)?

    private var observers: [NSKeyValueObservation] = []

    static func makeConfiguration(base: WKWebViewConfiguration? = nil) -> WKWebViewConfiguration {
        let config = base ?? WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.preferences.isElementFullscreenEnabled = true
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        config.defaultWebpagePreferences.preferredContentMode = Settings.shared.desktopWebsites ? .desktop : .recommended
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        let controller = config.userContentController
        controller.removeAllUserScripts()
        controller.addUserScript(WKUserScript(source: BrowserScripts.bridge, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        controller.addUserScript(WKUserScript(source: BrowserScripts.style, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        return config
    }

    init(configuration: WKWebViewConfiguration? = nil) {
        let config = BrowserTab.makeConfiguration(base: configuration)
        webView = WKWebView(frame: .zero, configuration: config)
        contentView = WebContentView(webView: webView)
        super.init()
        webView.customUserAgent = BrowserTab.userAgent
        webView.allowsBackForwardNavigationGestures = false
        webView.allowsLinkPreview = false
        webView.navigationDelegate = self
        webView.uiDelegate = self
        if #available(iOS 16.4, *) { webView.isInspectable = true }

        observers = [
            webView.observe(\.title, options: [.new]) { [weak self] wv, _ in
                MainActor.assumeIsolated { self?.updateTitle(wv.title) }
            },
            webView.observe(\.url, options: [.new]) { [weak self] wv, _ in
                MainActor.assumeIsolated { self?.urlDidChange(wv.url) }
            },
            webView.observe(\.estimatedProgress, options: [.new]) { [weak self] wv, _ in
                MainActor.assumeIsolated { self?.progress = wv.estimatedProgress; self?.onChange?() }
            },
            webView.observe(\.isLoading, options: [.new]) { [weak self] wv, _ in
                MainActor.assumeIsolated { self?.isLoading = wv.isLoading; self?.onChange?() }
            },
            webView.observe(\.canGoBack, options: [.new]) { [weak self] wv, _ in
                MainActor.assumeIsolated { self?.canGoBack = wv.canGoBack; self?.onChange?() }
            },
            webView.observe(\.canGoForward, options: [.new]) { [weak self] wv, _ in
                MainActor.assumeIsolated { self?.canGoForward = wv.canGoForward; self?.onChange?() }
            }
        ]
    }

    private func updateTitle(_ t: String?) {
        if isStartPage { title = "New Tab" }
        else if let t, !t.isEmpty { title = t }
        else if let host = url?.host { title = host }
        if let url, !isStartPage { BrowserHistory.shared.updateTitle(for: url, title: title) }
        onChange?()
    }

    private func urlDidChange(_ new: URL?) {
        if Self.isStartPageURL(new) {
            isStartPage = true
            url = nil
        } else if let errorURL, new == nil || new?.absoluteString == "about:blank" {
            url = errorURL
        } else {
            url = new
        }
        refreshFavicon()
        onChange?()
    }

    /// Picks the cached favicon for the current host immediately and fetches it if unknown.
    private func refreshFavicon(fetch: Bool = false) {
        guard !isStartPage, let host = url?.host, let scheme = url?.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            favicon = nil
            faviconHost = nil
            return
        }
        if host != faviconHost {
            faviconHost = host
            favicon = FaviconCache.shared.cached(for: host)
        }
        guard fetch, favicon == nil else { return }
        FaviconCache.shared.fetch(host: host, scheme: scheme) { [weak self] image in
            guard let self, self.faviconHost == host, let image else { return }
            self.favicon = image
            self.onChange?()
        }
    }

    // MARK: - Navigation

    var isSecure: Bool { url?.scheme?.lowercased() == "https" }

    func load(_ url: URL) {
        isStartPage = false
        errorURL = nil
        webView.load(URLRequest(url: url))
        self.url = url
        title = url.host ?? url.absoluteString
        refreshFavicon()
        onChange?()
    }

    /// Used when WebKit itself performs the first load (popup windows).
    func expectExternalLoad(_ url: URL?) {
        isStartPage = false
        self.url = url
        title = url?.host ?? "Loading…"
        refreshFavicon()
        onChange?()
    }

    func loadStartPage() {
        isStartPage = true
        title = "New Tab"
        url = nil
        favicon = nil
        faviconHost = nil
        errorURL = nil
        webView.loadHTMLString(StartPage.html(bookmarks: BrowserBookmarks.shared.items), baseURL: Self.startPageURL)
        onChange?()
    }

    func reload() {
        if isStartPage { loadStartPage() } else { webView.reload() }
    }

    func stop() { webView.stopLoading() }
    func goBack() { webView.goBack() }
    func goForward() { webView.goForward() }

    var displayURL: String {
        guard !isStartPage, let url else { return "" }
        return url.absoluteString
    }

    func find(_ text: String, backwards: Bool, completion: @escaping (Bool) -> Void) {
        guard !text.isEmpty else { completion(false); return }
        let config = WKFindConfiguration()
        config.backwards = backwards
        config.caseSensitive = false
        config.wraps = true
        webView.find(text, configuration: config) { result in
            completion(result.matchFound)
        }
    }
}

// MARK: - WKNavigationDelegate

extension BrowserTab: WKNavigationDelegate {

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let url = navigationAction.request.url
        // Links that target a new window arrive with no target frame.
        if navigationAction.targetFrame == nil, let url {
            _ = onOpenNewTab?(url, nil)
            decisionHandler(.cancel)
            return
        }
        if let scheme = url?.scheme?.lowercased(), !["http", "https", "about", "data", "blob", "file"].contains(scheme) {
            // Custom schemes (mailto:, tel:, app links) cannot be handled on the external display.
            onAlert?("Links of type “\(scheme):” are not supported in DeskMode.")
            decisionHandler(.cancel)
            return
        }
        // A user-initiated navigation to a site with an installed app is a universal link: WebKit
        // would hand it to that app and iOS would leave the desktop. Re-issuing the same request
        // ourselves keeps it in this tab, because programmatic loads never open other apps.
        if navigationAction.navigationType == .linkActivated,
           navigationAction.targetFrame?.isMainFrame == true,
           let url, let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" {
            isStartPage = false
            decisionHandler(.cancel)
            webView.load(navigationAction.request)
            return
        }
        if navigationAction.navigationType != .other, !Self.isStartPageURL(url) {
            isStartPage = false
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        if let u = webView.url {
            if Self.isStartPageURL(u) { isStartPage = true }
            else if u.absoluteString != "about:blank" { isStartPage = false; errorURL = nil }
        }
        onChange?()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        updateTitle(webView.title)
        if !isStartPage, errorURL == nil, let url = webView.url, !Self.isStartPageURL(url) {
            BrowserHistory.shared.record(url: url, title: webView.title ?? title)
            refreshFavicon(fetch: true)
        }
        onChange?()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        let nsError = error as NSError
        guard nsError.code != NSURLErrorCancelled else { return }
        let failedString = (nsError.userInfo[NSURLErrorFailingURLStringErrorKey] as? String) ?? url?.absoluteString ?? ""
        let failedURL = URL(string: failedString)
        // The new-tab page is local HTML; it must never be replaced by an error page.
        guard !isStartPage, !Self.isStartPageURL(failedURL), !failedString.isEmpty else { return }
        errorURL = failedURL
        title = failedURL?.host ?? title
        webView.loadHTMLString(StartPage.errorHTML(message: error.localizedDescription, url: failedString), baseURL: nil)
        onChange?()
    }
}

// MARK: - WKUIDelegate

extension BrowserTab: WKUIDelegate {

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        onOpenNewTab?(navigationAction.request.url, configuration)
    }

    func webViewDidClose(_ webView: WKWebView) {}

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        onAlert?(message)
        completionHandler()
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        onAlert?(message)
        completionHandler(true)
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
        onAlert?(prompt)
        completionHandler(defaultText)
    }
}
