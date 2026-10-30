import UIKit
import WebKit

/// A full browser window: tab strip, toolbar with address bar, find bar and the page.
final class BrowserWindowContent: UIView, WindowContent {

    let app: DeskApp = .browser
    var windowTitle: String { tabs.indices.contains(activeIndex) ? tabs[activeIndex].title : "Browser" }
    var onTitleChange: ((String) -> Void)?

    private(set) var tabs: [BrowserTab] = []
    private(set) var activeIndex = 0
    private var closedURLs: [URL] = []

    private weak var desktop: DesktopViewController?
    private let focusGroup = FocusGroup()

    private let tabStrip = TabStripView()
    private let toolbar = UIView()
    private let backButton = DeskButton(symbol: "chevron.left", style: .toolbar)
    private let forwardButton = DeskButton(symbol: "chevron.right", style: .toolbar)
    private let reloadButton = DeskButton(symbol: "arrow.clockwise", style: .toolbar)
    private let homeButton = DeskButton(symbol: "house", style: .toolbar)
    private let omnibox = DeskTextField()
    private let progressBar = UIView()
    private let pageContainer = UIView()

    private let findBar = UIView()
    private let findField = DeskTextField()
    private let findStatus = UILabel()
    private let findClose = DeskButton(symbol: "xmark", style: .toolbar)
    private var findVisible = false

    private var saveTimer: Timer?

    private static let sessionFile = "browser-session"
    private struct Session: Codable { var urls: [String]; var active: Int }

    init(desktop: DesktopViewController) {
        self.desktop = desktop
        super.init(frame: .zero)
        backgroundColor = Theme.windowBackground
        addSubview(tabStrip)
        addSubview(toolbar)
        addSubview(pageContainer)
        addSubview(findBar)
        toolbar.addSubview(progressBar)

        tabStrip.onSelect = { [weak self] i in self?.select(i) }
        tabStrip.onClose = { [weak self] i in self?.closeTab(at: i) }
        tabStrip.onNewTab = { [weak self] in self?.openTab(url: nil) }
        tabStrip.onTabContextMenu = { [weak self] i, p in self?.showTabMenu(index: i, at: p) }

        toolbar.backgroundColor = Theme.titleBarBackgroundInactive
        for b in [backButton, forwardButton, reloadButton, homeButton] {
            b.iconPointSize = 14
            toolbar.addSubview(b)
        }
        backButton.onTap = { [weak self] in self?.active?.goBack() }
        forwardButton.onTap = { [weak self] in self?.active?.goForward() }
        reloadButton.onTap = { [weak self] in
            guard let self, let tab = self.active else { return }
            if tab.isLoading { tab.stop() } else { tab.reload() }
        }
        homeButton.onTap = { [weak self] in self?.active?.loadStartPage() }

        omnibox.placeholder = "Search or enter website name"
        omnibox.leadingSymbol = "magnifyingglass"
        omnibox.textAlignment = .left
        omnibox.selectsAllOnFocus = true
        omnibox.focusGroup = focusGroup
        omnibox.font = Theme.font(13.5)
        omnibox.onSubmit = { [weak self] text in
            guard let self, !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
            self.active?.load(URLGuess.resolve(text))
            self.focusGroup.blur()
        }
        omnibox.onEscape = { [weak self] in
            guard let self else { return }
            self.omnibox.replaceAll(with: self.active?.displayURL ?? "")
            self.focusGroup.blur()
        }
        toolbar.addSubview(omnibox)

        progressBar.backgroundColor = Theme.accent
        progressBar.isHidden = true

        findBar.backgroundColor = Theme.titleBarBackground
        findBar.layer.cornerRadius = 10
        findBar.layer.borderWidth = 0.5
        findBar.layer.borderColor = Theme.border.cgColor
        findBar.applyPanelShadow(radius: 12, opacity: 0.4)
        findBar.isHidden = true
        findField.placeholder = "Find in page"
        findField.leadingSymbol = "magnifyingglass"
        findField.focusGroup = focusGroup
        findField.onChange = { [weak self] _ in self?.runFind(backwards: false) }
        findField.onSubmit = { [weak self] _ in self?.runFind(backwards: InputRouter.shared.modifiers.contains(.shift)) }
        findField.onEscape = { [weak self] in self?.hideFind() }
        findStatus.font = Theme.font(12)
        findStatus.textColor = Theme.secondaryText
        findClose.iconPointSize = 11
        findClose.onTap = { [weak self] in self?.hideFind() }
        findBar.addSubview(findField)
        findBar.addSubview(findStatus)
        findBar.addSubview(findClose)

        restoreSession()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        tabStrip.frame = CGRect(x: 0, y: 0, width: bounds.width, height: 34)
        toolbar.frame = CGRect(x: 0, y: 34, width: bounds.width, height: 44)
        let y: CGFloat = 8
        backButton.frame = CGRect(x: 8, y: y, width: 30, height: 28)
        forwardButton.frame = CGRect(x: 40, y: y, width: 30, height: 28)
        reloadButton.frame = CGRect(x: 76, y: y, width: 30, height: 28)
        homeButton.frame = CGRect(x: bounds.width - 40, y: y, width: 30, height: 28)
        let omniWidth = min(bounds.width - 170, 920)
        omnibox.frame = CGRect(x: max(116, (bounds.width - omniWidth) / 2), y: 7, width: omniWidth, height: 30)
        progressBar.frame = CGRect(x: 0, y: 42, width: bounds.width * (active?.progress ?? 0), height: 2)
        pageContainer.frame = CGRect(x: 0, y: 78, width: bounds.width, height: bounds.height - 78)
        active?.contentView.frame = pageContainer.bounds
        findBar.frame = CGRect(x: bounds.width - 372, y: 86, width: 360, height: 44)
        findField.frame = CGRect(x: 8, y: 7, width: 236, height: 30)
        findStatus.frame = CGRect(x: 250, y: 7, width: 74, height: 30)
        findClose.frame = CGRect(x: 326, y: 10, width: 26, height: 24)
    }

    // MARK: - Tabs

    var active: BrowserTab? { tabs.indices.contains(activeIndex) ? tabs[activeIndex] : nil }

    @discardableResult
    func openTab(url: URL?, configuration: WKWebViewConfiguration? = nil, select: Bool = true) -> BrowserTab {
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
        tab.contentView.onInteraction = { [weak self] in self?.focusGroup.blur() }
        tabs.append(tab)
        if configuration != nil { tab.expectExternalLoad(url) }      // WebKit drives this load (window.open)
        else if let url { tab.load(url) }
        else { tab.loadStartPage() }
        if select { self.select(tabs.count - 1, focusOmnibox: url == nil) } else { refreshChrome() }
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
        if focusOmnibox { focusGroup.focus(omnibox) } else { focusGroup.blur() }
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

    private func tabDidChange(_ tab: BrowserTab) {
        if tab === active { refreshChrome() }
        else { tabStripRefresh() }
        scheduleSave()
    }

    private func tabStripRefresh() {
        tabStrip.update(titles: tabs.map { $0.title }, loading: tabs.map { $0.isLoading }, activeIndex: activeIndex)
    }

    private func refreshChrome() {
        tabStripRefresh()
        guard let tab = active else { return }
        backButton.isEnabled = tab.canGoBack
        forwardButton.isEnabled = tab.canGoForward
        reloadButton.symbolName = tab.isLoading ? "xmark" : "arrow.clockwise"
        if !omnibox.isFocused { omnibox.replaceAll(with: tab.displayURL) }
        progressBar.isHidden = !tab.isLoading || tab.progress >= 1
        onTitleChange?(windowTitle)
        setNeedsLayout()
    }

    // MARK: - Find

    private func showFind() {
        findVisible = true
        findBar.isHidden = false
        findStatus.text = ""
        focusGroup.focus(findField)
        findField.selectAll()
    }

    private func hideFind() {
        guard findVisible else { return }
        findVisible = false
        findBar.isHidden = true
        if focusGroup.current === findField { focusGroup.blur() }
    }

    private func runFind(backwards: Bool) {
        guard let tab = active else { return }
        let text = findField.text
        guard !text.isEmpty else { findStatus.text = ""; return }
        tab.find(text, backwards: backwards) { [weak self] found in
            self?.findStatus.text = found ? "" : "Not found"
            self?.findStatus.textColor = found ? Theme.secondaryText : Theme.destructive
        }
    }

    // MARK: - Context menus

    private func showTabMenu(index: Int, at point: CGPoint) {
        guard let desktop, tabs.indices.contains(index) else { return }
        let tab = tabs[index]
        let items: [MenuItem] = [
            MenuItem(title: "Reload", symbol: "arrow.clockwise") { tab.reload() },
            MenuItem(title: "Duplicate Tab", symbol: "plus.square.on.square") { [weak self] in
                if let url = tab.url, !tab.isStartPage { self?.openTab(url: url) } else { self?.openTab(url: nil) }
            },
            .separator,
            MenuItem(title: "Close Tab", symbol: "xmark") { [weak self] in self?.closeTab(at: index) },
            MenuItem(title: "Close Other Tabs", isEnabled: tabs.count > 1) { [weak self] in
                guard let self else { return }
                for i in self.tabs.indices.reversed() where i != index { self.closeTab(at: i) }
            }
        ]
        desktop.presentContextMenu(items: items, at: tabStrip.convert(point, to: desktop.view))
    }

    private func showPageMenu(_ info: WebContentView.ContextInfo, at point: CGPoint) {
        guard let desktop, let tab = active else { return }
        var items: [MenuItem] = []
        if let link = URL(string: info.link), !info.link.isEmpty {
            items.append(MenuItem(title: "Open Link in New Tab", symbol: "plus.rectangle.on.rectangle") { [weak self] in self?.openTab(url: link, select: false) })
            items.append(MenuItem(title: "Open Link in New Window", symbol: "macwindow") { [weak self] in self?.desktop?.open(.browser, forceNew: true, url: link) })
            items.append(MenuItem(title: "Copy Link", symbol: "link") { [weak self] in UIPasteboard.general.string = link.absoluteString; self?.desktop?.showToast("Link copied") })
            items.append(.separator)
        }
        if let image = URL(string: info.image), !info.image.isEmpty {
            items.append(MenuItem(title: "Open Image in New Tab", symbol: "photo") { [weak self] in self?.openTab(url: image, select: false) })
            items.append(MenuItem(title: "Copy Image Address") { [weak self] in UIPasteboard.general.string = image.absoluteString; self?.desktop?.showToast("Copied") })
            items.append(.separator)
        }
        if !info.selection.isEmpty {
            let snippet = info.selection.count > 28 ? String(info.selection.prefix(28)) + "…" : info.selection
            items.append(MenuItem(title: "Copy “\(snippet)”", symbol: "doc.on.doc") { [weak self] in UIPasteboard.general.string = info.selection; self?.desktop?.showToast("Copied") })
            items.append(MenuItem(title: "Search for “\(snippet)”", symbol: "magnifyingglass") { [weak self] in
                self?.openTab(url: Settings.shared.searchEngine.searchURL(for: info.selection))
            })
            items.append(.separator)
        }
        if info.editable {
            items.append(MenuItem(title: "Paste", symbol: "doc.on.clipboard") { [weak self] in
                guard let s = UIPasteboard.general.string else { return }
                self?.active?.webView.evaluateJavaScript("window.__dm && window.__dm.paste(\(Self.jsString(s)))")
            })
            items.append(.separator)
        }
        items.append(MenuItem(title: "Back", symbol: "chevron.left", isEnabled: tab.canGoBack) { tab.goBack() })
        items.append(MenuItem(title: "Forward", symbol: "chevron.right", isEnabled: tab.canGoForward) { tab.goForward() })
        items.append(MenuItem(title: "Reload", symbol: "arrow.clockwise") { tab.reload() })
        items.append(.separator)
        items.append(MenuItem(title: "Copy Page Address", symbol: "link", isEnabled: tab.url != nil) { [weak self] in
            UIPasteboard.general.string = tab.url?.absoluteString; self?.desktop?.showToast("Copied")
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

    func contentDidFocus() {}
    func contentDidBlur() { focusGroup.blur() }

    func windowWillClose() {
        saveTimer?.invalidate()
        saveSession()
        for tab in tabs { tab.webView.stopLoading() }
    }

    func handleMenuAction(_ action: MenuAction) -> Bool {
        switch action {
        case .newTab: openTab(url: nil)
        case .closeTab: if tabs.count > 1 { closeTab(at: activeIndex) } else { return false }
        case .reopenClosedTab: reopenClosedTab()
        case .openLocation: focusGroup.focus(omnibox)
        case .reload: active?.reload()
        case .back: active?.goBack()
        case .forward: active?.goForward()
        case .zoomIn: adjustZoom(0.1)
        case .zoomOut: adjustZoom(-0.1)
        case .zoomReset: active?.webView.pageZoom = 1
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
        guard let wv = active?.webView else { return }
        wv.pageZoom = min(3, max(0.5, (wv.pageZoom * 10).rounded() / 10 + delta))
        desktop?.showToast("Zoom \(Int((wv.pageZoom * 100).rounded()))%")
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
            case "l": focusGroup.focus(omnibox); return true
            case "r": active?.reload(); return true
            case "f": showFind(); return true
            case "g": runFind(backwards: event.shift); return true
            case "[": if event.shift { selectRelative(-1) } else { active?.goBack() }; return true
            case "]": if event.shift { selectRelative(1) } else { active?.goForward() }; return true
            case "=", "+": adjustZoom(0.1); return true
            case "-": adjustZoom(-0.1); return true
            case "0": active?.webView.pageZoom = 1; return true
            case "1", "2", "3", "4", "5", "6", "7", "8":
                if let n = Int(event.letter), tabs.indices.contains(n - 1) { select(n - 1) }
                return true
            case "9": select(tabs.count - 1); return true
            default: break
            }
        }
        if event.isDown, event.control, event.isTab { selectRelative(event.shift ? -1 : 1); return true }
        if event.isDown, event.isEscape, focusGroup.current == nil {
            if findVisible { hideFind(); return true }
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
