import UIKit
import WebKit

/// A full browser window laid out like Chrome on the Mac: the tab strip lives in the title bar,
/// a toolbar with the omnibox sits below it, then the page. The window's traffic lights stay on
/// the left of the strip; empty strip is the drag handle.
final class BrowserWindowContent: UIView, WindowContent {

    let app: DeskApp = .browser
    var windowTitle: String { active?.title ?? DeskApp.browser.title }
    var onTitleChange: ((String) -> Void)?
    var drawsOwnTitleBar: Bool { true }

    private(set) var tabs: [BrowserTab] = []
    private(set) var activeIndex = 0
    private var closedURLs: [URL] = []

    private weak var desktop: DesktopViewController?
    private let focusGroup = FocusGroup()
    private var isWindowFocused = false

    // Chrome
    private let tabStrip = TabStripView()
    private let toolbar = UIView()
    private let toolbarHairline = UIView()
    private let backButton = BrowserIconButton(symbol: "arrow.left", pointSize: 15)
    private let forwardButton = BrowserIconButton(symbol: "arrow.right", pointSize: 15)
    private let reloadButton = BrowserIconButton(symbol: "arrow.clockwise", pointSize: 14)
    private let omnibox = OmniboxView()
    private let menuButton = BrowserIconButton(symbol: "ellipsis", pointSize: 15)
    private let progressBar = UIView()
    private let pageContainer = UIView()
    private let suggestions = OmniboxSuggestionsView()
    private let findBar = FindBarView()
    private lazy var tooltips = BrowserTooltipPresenter(host: self)

    private let suggestionFetcher = SearchSuggestionFetcher()
    private var suggestionQuery = ""
    private var progressShown = false
    private var saveTimer: Timer?
    private var notificationTokens: [NSObjectProtocol] = []

    static let tabStripHeight: CGFloat = Theme.titleBarHeight
    static let toolbarHeight: CGFloat = 44
    static var chromeHeight: CGFloat { tabStripHeight + toolbarHeight }

    private static let sessionFile = "browser-session"
    private struct Session: Codable { var urls: [String]; var active: Int }

    // MARK: - Init

    init(desktop: DesktopViewController) {
        self.desktop = desktop
        super.init(frame: .zero)
        backgroundColor = Theme.windowBackground
        addSubview(tabStrip)
        addSubview(toolbar)
        addSubview(pageContainer)
        addSubview(findBar)
        addSubview(suggestions)
        toolbar.addSubview(toolbarHairline)
        toolbar.addSubview(progressBar)

        configureTabStrip()
        configureToolbar()
        configureOmnibox()
        configureFindBar()
        observeStores()
        restoreSession()
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit {
        for t in notificationTokens { NotificationCenter.default.removeObserver(t) }
    }

    private func configureTabStrip() {
        tabStrip.onSelect = { [weak self] i in self?.select(i) }
        tabStrip.onClose = { [weak self] i in self?.closeTab(at: i) }
        tabStrip.onNewTab = { [weak self] in self?.openTab(url: nil) }
        tabStrip.onTabContextMenu = { [weak self] i, p in self?.showTabMenu(index: i, at: p) }
        tabStrip.onButtonHover = { [weak self] b, h in self?.tooltips.hover(b, text: b.tooltip, hovering: h) }
    }

    private func configureToolbar() {
        toolbar.backgroundColor = Theme.titleBarBackgroundInactive
        toolbarHairline.backgroundColor = Theme.hairlineDark
        for b in [backButton, forwardButton, reloadButton, menuButton] {
            toolbar.addSubview(b)
            b.onHover = { [weak self] btn, h in self?.tooltips.hover(btn, text: btn.tooltip, hovering: h) }
        }
        backButton.tooltip = "Click to go back (⌘[)"
        forwardButton.tooltip = "Click to go forward (⌘])"
        reloadButton.tooltip = "Reload this page (⌘R)"
        menuButton.tooltip = "Customise and control Chrome"
        menuButton.glyphRotation = .pi / 2
        backButton.onTap = { [weak self] in self?.active?.goBack() }
        forwardButton.onTap = { [weak self] in self?.active?.goForward() }
        reloadButton.onTap = { [weak self] in
            guard let self, let tab = self.active else { return }
            if tab.isLoading { tab.stop() } else { tab.reload() }
        }
        menuButton.onTap = { [weak self] in self?.showMainMenu() }
        toolbar.addSubview(omnibox)

        progressBar.backgroundColor = Theme.accent
        progressBar.alpha = 0
        progressBar.isUserInteractionEnabled = false
    }

    private func configureOmnibox() {
        omnibox.focusGroup = focusGroup
        omnibox.onButtonHover = { [weak self] b, h in self?.tooltips.hover(b, text: b.tooltip, hovering: h) }
        omnibox.onTextChange = { [weak self] text in self?.queryChanged(text) }
        omnibox.onArrow = { [weak self] delta in
            guard let self, !self.suggestions.isHidden else { return }
            if let s = self.suggestions.moveSelection(delta) { self.omnibox.setText(s.fillText) }
            else { self.omnibox.setText(self.suggestionQuery) }
        }
        omnibox.onSubmit = { [weak self] text in
            guard let self else { return }
            let url: URL?
            if let i = self.suggestions.selectedIndex, !self.suggestions.isHidden, self.suggestions.items.indices.contains(i) {
                url = self.suggestions.items[i].url
            } else {
                let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
                url = t.isEmpty ? nil : URLGuess.resolve(t)
            }
            guard let url else { return }
            self.navigate(to: url)
            self.focusGroup.blur()
        }
        omnibox.onEscape = { [weak self] in
            guard let self else { return }
            self.omnibox.restoreDisplay()
            self.focusGroup.blur()
        }
        omnibox.onFocusChange = { [weak self] focused in
            guard let self else { return }
            if !focused { self.hideSuggestions() }
        }
        omnibox.onToggleBookmark = { [weak self] in self?.toggleBookmark() }

        suggestions.isHidden = true
        suggestions.alpha = 0
        suggestions.onSelect = { [weak self] i in
            guard let self, self.suggestions.items.indices.contains(i) else { return }
            self.navigate(to: self.suggestions.items[i].url)
            self.focusGroup.blur()
        }
    }

    private func configureFindBar() {
        findBar.field.focusGroup = focusGroup
        findBar.field.onChange = { [weak self] _ in self?.runFind(backwards: false) }
        findBar.field.onSubmit = { [weak self] _ in self?.runFind(backwards: InputRouter.shared.modifiers.contains(.shift)) }
        findBar.field.onEscape = { [weak self] in self?.hideFind() }
        findBar.onNext = { [weak self] in self?.runFind(backwards: false) }
        findBar.onPrevious = { [weak self] in self?.runFind(backwards: true) }
        findBar.onClose = { [weak self] in self?.hideFind() }
        findBar.onButtonHover = { [weak self] b, h in self?.tooltips.hover(b, text: b.tooltip, hovering: h) }
    }

    private func observeStores() {
        let center = NotificationCenter.default
        notificationTokens.append(center.addObserver(forName: .browserBookmarksDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshChrome() }
        })
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = bounds.width
        tabStrip.frame = CGRect(x: 0, y: 0, width: w, height: Self.tabStripHeight)
        toolbar.frame = CGRect(x: 0, y: Self.tabStripHeight, width: w, height: Self.toolbarHeight)
        toolbarHairline.frame = CGRect(x: 0, y: Self.toolbarHeight - Theme.Size.hairline, width: w, height: Theme.Size.hairline)

        let b = Theme.Size.control
        let by = (Self.toolbarHeight - b) / 2
        backButton.frame = CGRect(x: Theme.Space.s, y: by, width: b, height: b)
        forwardButton.frame = CGRect(x: backButton.frame.maxX + Theme.Space.xs, y: by, width: b, height: b)
        reloadButton.frame = CGRect(x: forwardButton.frame.maxX + Theme.Space.xs, y: by, width: b, height: b)
        menuButton.frame = CGRect(x: w - Theme.Space.s - b, y: by, width: b, height: b)
        let omniX = reloadButton.frame.maxX + Theme.Space.m
        let omniH = Theme.Size.controlLarge
        omnibox.frame = CGRect(x: omniX, y: (Self.toolbarHeight - omniH) / 2, width: max(120, menuButton.frame.minX - Theme.Space.m - omniX), height: omniH)

        progressBar.frame = CGRect(x: 0, y: Self.toolbarHeight - 2, width: progressBar.frame.width, height: 2)

        let top = Self.chromeHeight
        pageContainer.frame = CGRect(x: 0, y: top, width: w, height: max(0, bounds.height - top))
        active?.contentView.frame = pageContainer.bounds

        let suggestFrame = CGRect(x: omniX, y: top - Theme.Space.xs, width: omnibox.frame.width, height: suggestions.preferredHeight)
        if !suggestions.isHidden, suggestions.frame.width == suggestFrame.width, suggestions.frame.minX == suggestFrame.minX {
            Theme.Motion.animate(Theme.Motion.fast) { self.suggestions.frame = suggestFrame; self.suggestions.layoutIfNeeded() }
        } else {
            suggestions.frame = suggestFrame
        }

        findBar.frame = CGRect(x: w - FindBarView.size.width - Theme.Space.l, y: top + Theme.Space.s, width: FindBarView.size.width, height: FindBarView.size.height)
    }

    // MARK: - Tabs

    var active: BrowserTab? { tabs.indices.contains(activeIndex) ? tabs[activeIndex] : nil }

    @discardableResult
    func openTab(url: URL?, configuration: WKWebViewConfiguration? = nil, select: Bool = true, at index: Int? = nil) -> BrowserTab {
        let tab = BrowserTab(configuration: configuration)
        tab.contentView.desktop = desktop
        tab.onChange = { [weak self, weak tab] in
            guard let self, let tab else { return }
            self.tabDidChange(tab)
        }
        tab.onOpenNewTab = { [weak self] url, config in
            guard let self else { return nil }
            let newTab = self.openTab(url: url, configuration: config, select: true)
            return config == nil ? nil : newTab.webView
        }
        tab.onAlert = { [weak self] message in self?.desktop?.showToast(message) }
        tab.contentView.onContextMenu = { [weak self] info, point in self?.showPageMenu(info, at: point) }
        tab.contentView.onInteraction = { [weak self] in
            guard let self else { return }
            self.focusGroup.blur()
            self.tooltips.cancel()
        }
        let insertAt = index.map { min(max(0, $0), tabs.count) } ?? tabs.count
        tabs.insert(tab, at: insertAt)
        if insertAt <= activeIndex, !tabs.isEmpty, tabs.count > 1 { activeIndex += 1 }
        if configuration != nil { tab.expectExternalLoad(url) }      // WebKit drives this load (window.open)
        else if let url { tab.load(url) }
        else { tab.loadStartPage() }
        if select { self.select(insertAt, focusOmnibox: url == nil) } else { refreshChrome() }
        scheduleSave()
        return tab
    }

    func select(_ index: Int, focusOmnibox: Bool = false) {
        guard tabs.indices.contains(index) else { return }
        if let current = active, current.contentView.superview != nil, index != activeIndex {
            current.contentView.removeFromSuperview()
        }
        activeIndex = index
        let tab = tabs[index]
        if tab.contentView.superview == nil { pageContainer.addSubview(tab.contentView) }
        tab.contentView.frame = pageContainer.bounds
        hideFind()
        if focusOmnibox { omnibox.focus() } else { focusGroup.blur() }
        refreshChrome()
        scheduleSave()
    }

    func closeTab(at index: Int) {
        guard tabs.indices.contains(index) else { return }
        let tab = tabs.remove(at: index)
        if let url = tab.url, !tab.isStartPage { closedURLs.append(url) }
        tab.contentView.removeFromSuperview()
        tab.webView.stopLoading()
        if tabs.isEmpty {
            scheduleSave()
            windowView?.requestClose()
            return
        }
        let next = min(index == activeIndex ? index : (index < activeIndex ? activeIndex - 1 : activeIndex), tabs.count - 1)
        activeIndex = -1
        select(next)
    }

    private func reopenClosedTab() {
        guard let url = closedURLs.popLast() else { return }
        openTab(url: url)
    }

    private func navigate(to url: URL) {
        if let tab = active { tab.load(url) } else { openTab(url: url) }
    }

    private func tabDidChange(_ tab: BrowserTab) {
        if tab === active { refreshChrome() }
        else { tabStripRefresh() }
        scheduleSave()
    }

    private func tabStripRefresh() {
        tabStrip.update(items: tabs.map { TabStripView.Item(title: $0.title, isLoading: $0.isLoading, favicon: $0.favicon) }, activeIndex: activeIndex)
    }

    private func refreshChrome() {
        tabStripRefresh()
        guard let tab = active else { return }
        backButton.isEnabled = tab.canGoBack
        forwardButton.isEnabled = tab.canGoForward
        reloadButton.symbolName = tab.isLoading ? "xmark" : "arrow.clockwise"
        reloadButton.pointSize = tab.isLoading ? 13 : 14
        reloadButton.tooltip = tab.isLoading ? "Stop loading this page (Esc)" : "Reload this page (⌘R)"
        let mode: OmniboxView.SiteMode
        if tab.isStartPage { mode = .newTab }
        else if tab.isSecure { mode = .secure }
        else if let s = tab.url?.scheme?.lowercased(), s == "file" || s == "about" || s == "data" || s == "blob" { mode = .local }
        else { mode = .insecure }
        omnibox.setURL(tab.displayURL, mode: mode)
        omnibox.isBookmarked = !tab.isStartPage && BrowserBookmarks.shared.isBookmarked(tab.url)
        updateProgress(for: tab)
        onTitleChange?(windowTitle)
        setNeedsLayout()
    }

    // MARK: - Progress

    private func updateProgress(for tab: BrowserTab) {
        let width = bounds.width
        let y = Self.toolbarHeight - 2
        if tab.isLoading, tab.progress < 1 {
            let target = width * CGFloat(max(0.06, tab.progress))
            if !progressShown {
                progressShown = true
                progressBar.layer.removeAllAnimations()
                progressBar.alpha = 1
                progressBar.frame = CGRect(x: 0, y: y, width: min(target, width * 0.06), height: 2)
            }
            Theme.Motion.animate(Theme.Motion.normal) {
                self.progressBar.frame = CGRect(x: 0, y: y, width: max(self.progressBar.frame.width, target), height: 2)
            }
        } else if progressShown {
            progressShown = false
            Theme.Motion.animate(Theme.Motion.fast, animations: {
                self.progressBar.frame = CGRect(x: 0, y: y, width: width, height: 2)
            }) { _ in
                guard !self.progressShown else { return }
                Theme.Motion.animate(Theme.Motion.normal, animations: { self.progressBar.alpha = 0 }) { _ in
                    if !self.progressShown { self.progressBar.frame.size.width = 0 }
                }
            }
        }
    }

    // MARK: - Omnibox suggestions

    private func queryChanged(_ text: String) {
        suggestionQuery = text
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            suggestionFetcher.cancel()
            hideSuggestions()
            return
        }
        suggestions.select(nil)
        rebuildSuggestions(searchTerms: [])
        suggestionFetcher.suggestions(for: trimmed) { [weak self] terms in
            guard let self, self.suggestionQuery == text, self.omnibox.hasFocus else { return }
            self.rebuildSuggestions(searchTerms: terms)
        }
    }

    private func rebuildSuggestions(searchTerms: [String]) {
        let text = suggestionQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, omnibox.hasFocus else { return }
        let typedURL = URLGuess.url(from: text)
        var items: [OmniboxSuggestion] = [
            .typed(text: text, url: typedURL ?? Settings.shared.searchEngine.searchURL(for: text), isSearch: typedURL == nil)
        ]
        items += BrowserHistory.shared.matches(text, limit: 3).map { .history($0) }
        let lower = text.lowercased()
        for term in searchTerms where items.count < OmniboxSuggestionsView.maxRows {
            if term.lowercased() != lower { items.append(.search(term)) }
        }
        suggestions.setItems(items)
        showSuggestions()
    }

    private func showSuggestions() {
        setNeedsLayout()
        guard suggestions.isHidden else { return }
        suggestions.isHidden = false
        bringSubviewToFront(suggestions)
        layoutIfNeeded()
        suggestions.transform = CGAffineTransform(translationX: 0, y: -4)
        Theme.Motion.animate(Theme.Motion.fast) {
            self.suggestions.alpha = 1
            self.suggestions.transform = .identity
        }
    }

    private func hideSuggestions() {
        suggestionFetcher.cancel()
        guard !suggestions.isHidden else { return }
        suggestions.select(nil)
        Theme.Motion.animate(Theme.Motion.instant, animations: { self.suggestions.alpha = 0 }) { _ in
            if self.suggestions.alpha == 0 { self.suggestions.isHidden = true }
        }
    }

    // MARK: - Bookmarks

    private func toggleBookmark() {
        guard let tab = active, !tab.isStartPage, let url = tab.url else { return }
        let added = BrowserBookmarks.shared.toggle(url: url, title: tab.title)
        desktop?.showToast(added ? "Bookmark added" : "Bookmark removed")
        refreshChrome()
    }

    // MARK: - Find

    private func showFind() {
        findBar.setResult(found: nil)
        findBar.show()
        bringSubviewToFront(findBar)
        focusGroup.focus(findBar.field)
        findBar.field.selectAll()
    }

    private func hideFind() {
        guard findBar.isShown else { return }
        findBar.hide()
        if focusGroup.current === findBar.field { focusGroup.blur() }
    }

    private func runFind(backwards: Bool) {
        guard let tab = active else { return }
        let text = findBar.field.text
        guard !text.isEmpty else { findBar.setResult(found: nil); return }
        tab.find(text, backwards: backwards) { [weak self] found in
            self?.findBar.setResult(found: found)
        }
    }

    // MARK: - Menus

    private func showMainMenu() {
        guard let desktop else { return }
        let history = BrowserHistory.shared.recent(12)
        let bookmarks = Array(BrowserBookmarks.shared.items.suffix(12).reversed())
        let zoomPercent = Int(((active?.contentView.userZoom ?? 1) * 100).rounded())
        var items: [MenuItem] = [
            MenuItem(title: "New Tab", symbol: "plus.square", shortcut: "⌘T") { [weak self] in self?.openTab(url: nil) },
            MenuItem(title: "New Window", symbol: "macwindow.badge.plus", shortcut: "⌘N") { [weak self] in self?.desktop?.open(.browser, forceNew: true) },
            MenuItem(title: "Reopen Closed Tab", symbol: "arrow.uturn.backward", shortcut: "⇧⌘T", isEnabled: !closedURLs.isEmpty) { [weak self] in self?.reopenClosedTab() },
            .separator,
            MenuItem(title: "History", symbol: "clock", isEnabled: false)
        ]
        if history.isEmpty { items.append(MenuItem(title: "No recent pages", isEnabled: false)) }
        for entry in history {
            items.append(MenuItem(title: Self.menuTitle(entry.title)) { [weak self] in
                if let url = URL(string: entry.url) { self?.navigate(to: url) }
            })
        }
        items.append(.separator)
        items.append(MenuItem(title: "Bookmarks", symbol: "star", isEnabled: false))
        if bookmarks.isEmpty { items.append(MenuItem(title: "No bookmarks yet", isEnabled: false)) }
        for bookmark in bookmarks {
            items.append(MenuItem(title: Self.menuTitle(bookmark.title)) { [weak self] in
                if let url = URL(string: bookmark.url) { self?.navigate(to: url) }
            })
        }
        items.append(.separator)
        items.append(MenuItem(title: "Zoom Out", symbol: "minus.magnifyingglass", shortcut: "⌘−") { [weak self] in self?.adjustZoom(-0.1) })
        items.append(MenuItem(title: "Zoom \(zoomPercent)%", symbol: "1.magnifyingglass", shortcut: "⌘0", isEnabled: zoomPercent != 100) { [weak self] in self?.resetZoom() })
        items.append(MenuItem(title: "Zoom In", symbol: "plus.magnifyingglass", shortcut: "⌘+") { [weak self] in self?.adjustZoom(0.1) })
        items.append(MenuItem(title: "Find…", symbol: "magnifyingglass", shortcut: "⌘F") { [weak self] in self?.showFind() })
        items.append(.separator)
        items.append(MenuItem(title: "Identify as Chrome", isChecked: Settings.shared.identifyAsChrome) { [weak self] in
            Settings.shared.identifyAsChrome.toggle()
            self?.desktop?.showToast(Settings.shared.identifyAsChrome ? "New tabs will identify as Chrome" : "New tabs will identify as Safari")
        })
        items.append(MenuItem(title: "Settings…", symbol: "gearshape", shortcut: "⌘,") { [weak self] in self?.desktop?.open(.settings) })

        let estimatedWidth: CGFloat = 272
        let anchor = menuButton.convert(CGPoint(x: menuButton.bounds.maxX - estimatedWidth, y: menuButton.bounds.maxY + Theme.Space.xs), to: desktop.view)
        desktop.presentContextMenu(items: items, at: anchor)
    }

    private static func menuTitle(_ title: String) -> String {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.count > 44 ? String(t.prefix(43)) + "…" : t
    }

    private func showTabMenu(index: Int, at point: CGPoint) {
        guard let desktop, tabs.indices.contains(index) else { return }
        let tab = tabs[index]
        let items: [MenuItem] = [
            MenuItem(title: "New tab to the right", symbol: "plus.square") { [weak self] in self?.openTab(url: nil, at: index + 1) },
            .separator,
            MenuItem(title: "Reload", symbol: "arrow.clockwise") { tab.reload() },
            MenuItem(title: "Duplicate", symbol: "plus.square.on.square") { [weak self] in
                if let url = tab.url, !tab.isStartPage { self?.openTab(url: url, at: index + 1) } else { self?.openTab(url: nil, at: index + 1) }
            },
            .separator,
            MenuItem(title: "Close", symbol: "xmark", shortcut: "⌘W") { [weak self] in self?.closeTab(at: index) },
            MenuItem(title: "Close other tabs", isEnabled: tabs.count > 1) { [weak self] in
                guard let self else { return }
                for i in self.tabs.indices.reversed() where i != index { self.closeTab(at: i) }
            },
            MenuItem(title: "Close tabs to the right", isEnabled: index < tabs.count - 1) { [weak self] in
                guard let self else { return }
                for i in self.tabs.indices.reversed() where i > index { self.closeTab(at: i) }
            }
        ]
        desktop.presentContextMenu(items: items, at: tabStrip.convert(point, to: desktop.view))
    }

    private func showPageMenu(_ info: WebContentView.ContextInfo, at point: CGPoint) {
        guard let desktop, let tab = active else { return }
        let engine = Settings.shared.searchEngine.title
        var items: [MenuItem] = []
        if let link = URL(string: info.link), !info.link.isEmpty {
            items.append(MenuItem(title: "Open link in new tab", symbol: "plus.rectangle.on.rectangle") { [weak self] in self?.openTab(url: link, select: false, at: self.map { $0.activeIndex + 1 }) })
            items.append(MenuItem(title: "Open link in new window", symbol: "macwindow") { [weak self] in self?.desktop?.open(.browser, forceNew: true, url: link) })
            items.append(.separator)
            items.append(MenuItem(title: "Copy link address", symbol: "link") { [weak self] in UIPasteboard.general.string = link.absoluteString; self?.desktop?.showToast("Link copied") })
            items.append(.separator)
        }
        if let image = URL(string: info.image), !info.image.isEmpty {
            items.append(MenuItem(title: "Open image in new tab", symbol: "photo") { [weak self] in self?.openTab(url: image, select: false) })
            items.append(MenuItem(title: "Copy image address", symbol: "link") { [weak self] in UIPasteboard.general.string = image.absoluteString; self?.desktop?.showToast("Image address copied") })
            items.append(.separator)
        }
        if !info.selection.isEmpty {
            let snippet = info.selection.count > 28 ? String(info.selection.prefix(28)) + "…" : info.selection
            items.append(MenuItem(title: "Copy", symbol: "doc.on.doc", shortcut: "⌘C") { [weak self] in UIPasteboard.general.string = info.selection; self?.desktop?.showToast("Copied") })
            items.append(MenuItem(title: "Search \(engine) for “\(snippet)”", symbol: "magnifyingglass") { [weak self] in
                self?.openTab(url: Settings.shared.searchEngine.searchURL(for: info.selection))
            })
            items.append(.separator)
        }
        if info.editable {
            items.append(MenuItem(title: "Paste", symbol: "doc.on.clipboard", shortcut: "⌘V") { [weak self] in
                guard let s = UIPasteboard.general.string else { return }
                self?.active?.webView.evaluateJavaScript("window.__dm && window.__dm.paste(\(Self.jsString(s)))")
            })
            items.append(.separator)
        }
        items.append(MenuItem(title: "Back", symbol: "arrow.left", shortcut: "⌘[", isEnabled: tab.canGoBack) { tab.goBack() })
        items.append(MenuItem(title: "Forward", symbol: "arrow.right", shortcut: "⌘]", isEnabled: tab.canGoForward) { tab.goForward() })
        items.append(MenuItem(title: "Reload", symbol: "arrow.clockwise", shortcut: "⌘R") { tab.reload() })
        items.append(.separator)
        items.append(MenuItem(title: "Copy page address", symbol: "link", isEnabled: tab.url != nil && !tab.isStartPage) { [weak self] in
            UIPasteboard.general.string = tab.url?.absoluteString; self?.desktop?.showToast("Page address copied")
        })
        desktop.presentContextMenu(items: items, at: point)
    }

    private static func jsString(_ s: String) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: [s])) ?? Data()
        let array = String(data: data, encoding: .utf8) ?? "[\"\"]"
        return String(array.dropFirst().dropLast())
    }

    // MARK: - Session persistence

    private func scheduleSave() {
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.saveSession() }
        }
    }

    private func saveSession() {
        // Only the most recently used browser window is remembered.
        let urls = tabs.map { $0.isStartPage ? "" : ($0.url?.absoluteString ?? "") }
        Persistence.save(Session(urls: urls, active: activeIndex), to: Self.sessionFile)
    }

    private func restoreSession() {
        guard let session = Persistence.load(Session.self, from: Self.sessionFile), !session.urls.isEmpty else { return }
        for u in session.urls {
            openTab(url: u.isEmpty ? nil : URL(string: u), select: false)
        }
        select(min(max(0, session.active), tabs.count - 1), focusOmnibox: active?.isStartPage ?? true)
    }

    // MARK: - WindowContent

    private var windowView: DesktopWindowView? {
        var v: UIView? = superview
        while let cur = v {
            if let w = cur as? DesktopWindowView { return w }
            v = cur.superview
        }
        return nil
    }

    func contentDidFocus() {
        isWindowFocused = true
        applyWindowFocus()
    }

    func contentDidBlur() {
        isWindowFocused = false
        focusGroup.blur()
        tooltips.cancel()
        applyWindowFocus()
    }

    private func applyWindowFocus() {
        tabStrip.isWindowFocused = isWindowFocused
        Theme.Motion.animate(Theme.Motion.fast) {
            self.toolbar.backgroundColor = self.isWindowFocused ? Theme.titleBarBackground : Theme.titleBarBackgroundInactive
        }
    }

    func windowWillClose() {
        saveTimer?.invalidate()
        saveSession()
        suggestionFetcher.cancel()
        for tab in tabs { tab.webView.stopLoading() }
    }

    func handleMenuAction(_ action: MenuAction) -> Bool {
        switch action {
        case .newTab: openTab(url: nil)
        case .closeTab: if tabs.count > 1 { closeTab(at: activeIndex) } else { return false }
        case .reopenClosedTab: reopenClosedTab()
        case .openLocation: omnibox.focus()
        case .reload: active?.reload()
        case .back: active?.goBack()
        case .forward: active?.goForward()
        case .zoomIn: adjustZoom(0.1)
        case .zoomOut: adjustZoom(-0.1)
        case .zoomReset: resetZoom()
        case .find: showFind()
        case .selectAll, .copy, .cut, .paste:
            let letter: String = action == .selectAll ? "a" : action == .copy ? "c" : action == .cut ? "x" : "v"
            let event = KeyEvent(phase: .down, characters: letter, charactersIgnoringModifiers: letter, keyCode: .keyboardA, modifiers: .command, isRepeat: false)
            return handleKey(event)
        default: return false
        }
        return true
    }

    private func adjustZoom(_ delta: CGFloat) {
        guard let wv = active?.contentView else { return }
        wv.userZoom = min(3, max(0.5, (wv.userZoom * 10).rounded() / 10 + delta))
        desktop?.showToast("Zoom \(Int((wv.userZoom * 100).rounded()))%")
    }

    private func resetZoom() {
        guard let wv = active?.contentView, wv.userZoom != 1 else { return }
        wv.userZoom = 1
        desktop?.showToast("Zoom 100%")
    }

    func handleKey(_ event: KeyEvent) -> Bool {
        if event.isDown, event.command {
            switch event.letter {
            case "t":
                if event.option { break }
                if event.shift { reopenClosedTab() } else { openTab(url: nil) }
                return true
            case "w":
                if tabs.count > 1 { closeTab(at: activeIndex); return true }
                return false
            case "l": omnibox.focus(); return true
            case "d": toggleBookmark(); return true
            case "r": active?.reload(); return true
            case "f": showFind(); return true
            case "g": runFind(backwards: event.shift); return true
            case "[": if event.shift { selectRelative(-1) } else { active?.goBack() }; return true
            case "]": if event.shift { selectRelative(1) } else { active?.goForward() }; return true
            case "=", "+": adjustZoom(0.1); return true
            case "-": adjustZoom(-0.1); return true
            case "0": resetZoom(); return true
            case "1", "2", "3", "4", "5", "6", "7", "8":
                if let n = Int(event.letter), tabs.indices.contains(n - 1) { select(n - 1) }
                return true
            case "9": select(tabs.count - 1); return true
            default: break
            }
        }
        if event.isDown, event.control, event.isTab { selectRelative(event.shift ? -1 : 1); return true }
        if event.isDown, event.isEscape, focusGroup.current == nil {
            if findBar.isShown { hideFind(); return true }
            if let tab = active, tab.isLoading { tab.stop(); return true }
        }
        if focusGroup.current != nil { return focusGroup.key(event) }
        return active?.contentView.key(event) ?? false
    }

    private func selectRelative(_ delta: Int) {
        guard !tabs.isEmpty else { return }
        select((activeIndex + delta + tabs.count) % tabs.count)
    }
}
