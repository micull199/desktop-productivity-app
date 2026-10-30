import Foundation

/// One visited page. Most recent first in `BrowserHistory.entries`.
struct HistoryEntry: Codable, Equatable {
    var url: String
    var title: String
    var visitedAt: Date
}

struct Bookmark: Codable, Equatable {
    var url: String
    var title: String
    /// Host used to look up the favicon.
    var host: String
}

extension Notification.Name {
    static let browserHistoryDidChange = Notification.Name("DeskBrowserHistoryDidChange")
    static let browserBookmarksDidChange = Notification.Name("DeskBrowserBookmarksDidChange")
}

/// Browsing history shared by every browser window. Persisted as JSON, capped at 500 entries.
@MainActor
final class BrowserHistory {

    static let shared = BrowserHistory()
    static let capacity = 500
    private static let file = "browser-history"

    private(set) var entries: [HistoryEntry]
    private var saveTimer: Timer?

    private init() {
        entries = Persistence.load([HistoryEntry].self, from: Self.file) ?? []
    }

    /// Records a visit. A page already in history moves to the top.
    func record(url: URL, title: String) {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https", !BrowserTab.isStartPageURL(url) else { return }
        let key = url.absoluteString
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        entries.removeAll { $0.url == key }
        entries.insert(HistoryEntry(url: key, title: cleanTitle.isEmpty ? (url.host ?? key) : cleanTitle, visitedAt: Date()), at: 0)
        if entries.count > Self.capacity { entries.removeLast(entries.count - Self.capacity) }
        scheduleSave()
        NotificationCenter.default.post(name: .browserHistoryDidChange, object: nil)
    }

    /// Updates the stored title once the page has finished loading.
    func updateTitle(for url: URL, title: String) {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, let i = entries.firstIndex(where: { $0.url == url.absoluteString }), entries[i].title != t else { return }
        entries[i].title = t
        scheduleSave()
    }

    func recent(_ count: Int) -> [HistoryEntry] { Array(entries.prefix(count)) }

    /// Entries matching the omnibox text: URL prefixes rank first, then title / URL substrings.
    func matches(_ query: String, limit: Int) -> [HistoryEntry] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }
        var prefix: [HistoryEntry] = []
        var contains: [HistoryEntry] = []
        var seenHosts = Set<String>()
        for e in entries {
            let lower = e.url.lowercased()
            let bare = Self.bareURL(lower)
            if bare.hasPrefix(q) || lower.hasPrefix(q) {
                // One row per host for prefix matches keeps the list useful ("goo" → google.com once).
                let host = URL(string: e.url)?.host ?? e.url
                if seenHosts.insert(host).inserted { prefix.append(e) }
            } else if e.title.lowercased().contains(q) || bare.contains(q) {
                contains.append(e)
            }
            if prefix.count >= limit { break }
        }
        return Array((prefix + contains).prefix(limit))
    }

    func clear() {
        entries = []
        scheduleSave()
        NotificationCenter.default.post(name: .browserHistoryDidChange, object: nil)
    }

    /// "https://www.example.com/x" → "example.com/x"
    static func bareURL(_ url: String) -> String {
        var s = url
        for p in ["https://", "http://"] where s.hasPrefix(p) { s.removeFirst(p.count) }
        if s.hasPrefix("www.") { s.removeFirst(4) }
        if s.hasSuffix("/") { s.removeLast() }
        return s
    }

    private func scheduleSave() {
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                Persistence.save(self.entries, to: Self.file)
            }
        }
    }
}

/// Bookmarks shared by every browser window. Drive the new-tab page and the ⋮ menu.
@MainActor
final class BrowserBookmarks {

    static let shared = BrowserBookmarks()
    private static let file = "browser-bookmarks"

    private(set) var items: [Bookmark]

    private init() {
        items = Persistence.load([Bookmark].self, from: Self.file) ?? []
    }

    func isBookmarked(_ url: URL?) -> Bool {
        guard let key = url?.absoluteString else { return false }
        return items.contains { $0.url == key }
    }

    /// Adds or removes the bookmark. Returns the new state.
    @discardableResult
    func toggle(url: URL, title: String) -> Bool {
        let key = url.absoluteString
        let nowBookmarked: Bool
        if let i = items.firstIndex(where: { $0.url == key }) {
            items.remove(at: i)
            nowBookmarked = false
        } else {
            let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
            items.append(Bookmark(url: key, title: t.isEmpty ? (url.host ?? key) : t, host: url.host ?? ""))
            nowBookmarked = true
        }
        Persistence.save(items, to: Self.file)
        NotificationCenter.default.post(name: .browserBookmarksDidChange, object: nil)
        return nowBookmarked
    }

    func remove(url: String) {
        items.removeAll { $0.url == url }
        Persistence.save(items, to: Self.file)
        NotificationCenter.default.post(name: .browserBookmarksDidChange, object: nil)
    }
}
