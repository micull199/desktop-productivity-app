import Foundation
import Combine

enum SearchEngine: String, CaseIterable, Codable {
    case google, duckduckgo, bing

    var title: String {
        switch self {
        case .google: return "Google"
        case .duckduckgo: return "DuckDuckGo"
        case .bing: return "Bing"
        }
    }

    func searchURL(for query: String) -> URL {
        let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        switch self {
        case .google: return URL(string: "https://www.google.com/search?q=\(q)")!
        case .duckduckgo: return URL(string: "https://duckduckgo.com/?q=\(q)")!
        case .bing: return URL(string: "https://www.bing.com/search?q=\(q)")!
        }
    }
}

enum Wallpaper: String, CaseIterable, Codable {
    case sonoma, midnight, sunrise, graphite

    var title: String { rawValue.capitalized }
}

/// User preferences, persisted in `UserDefaults`.
@MainActor
final class Settings: ObservableObject {

    static let shared = Settings()

    @Published var cursorSpeed: CGFloat { didSet { save() } }
    @Published var naturalScrolling: Bool { didSet { save() } }
    @Published var invertMouseY: Bool { didSet { save() } }
    @Published var dimPhoneWhenConnected: Bool { didSet { save() } }
    @Published var phoneAsTrackpad: Bool { didSet { save() } }
    @Published var searchEngine: SearchEngine { didSet { save() } }
    @Published var desktopWebsites: Bool { didSet { save() } }
    /// Identify to websites as desktop Google Chrome (otherwise Safari on a Mac). Applies to new tabs.
    @Published var identifyAsChrome: Bool { didSet { save() } }
    @Published var wallpaper: Wallpaper { didSet { save() } }
    @Published var showClockSeconds: Bool { didSet { save() } }
    @Published var trackpadSensitivity: CGFloat { didSet { save() } }

    private let defaults = UserDefaults.standard
    private var loading = true

    private init() {
        let d = UserDefaults.standard
        cursorSpeed = d.object(forKey: "cursorSpeed") as? CGFloat ?? 1.4
        naturalScrolling = d.object(forKey: "naturalScrolling") as? Bool ?? true
        invertMouseY = d.object(forKey: "invertMouseY") as? Bool ?? false
        dimPhoneWhenConnected = d.object(forKey: "dimPhoneWhenConnected") as? Bool ?? true
        phoneAsTrackpad = d.object(forKey: "phoneAsTrackpad") as? Bool ?? true
        searchEngine = SearchEngine(rawValue: d.string(forKey: "searchEngine") ?? "") ?? .google
        desktopWebsites = d.object(forKey: "desktopWebsites") as? Bool ?? true
        identifyAsChrome = d.object(forKey: "identifyAsChrome") as? Bool ?? true
        wallpaper = Wallpaper(rawValue: d.string(forKey: "wallpaper") ?? "") ?? .sonoma
        showClockSeconds = d.object(forKey: "showClockSeconds") as? Bool ?? false
        trackpadSensitivity = d.object(forKey: "trackpadSensitivity") as? CGFloat ?? 2.2
        loading = false
    }

    private func save() {
        guard !loading else { return }
        defaults.set(cursorSpeed, forKey: "cursorSpeed")
        defaults.set(naturalScrolling, forKey: "naturalScrolling")
        defaults.set(invertMouseY, forKey: "invertMouseY")
        defaults.set(dimPhoneWhenConnected, forKey: "dimPhoneWhenConnected")
        defaults.set(phoneAsTrackpad, forKey: "phoneAsTrackpad")
        defaults.set(searchEngine.rawValue, forKey: "searchEngine")
        defaults.set(desktopWebsites, forKey: "desktopWebsites")
        defaults.set(identifyAsChrome, forKey: "identifyAsChrome")
        defaults.set(wallpaper.rawValue, forKey: "wallpaper")
        defaults.set(showClockSeconds, forKey: "showClockSeconds")
        defaults.set(trackpadSensitivity, forKey: "trackpadSensitivity")
    }

    func resetToDefaults() {
        cursorSpeed = 1.4
        naturalScrolling = true
        invertMouseY = false
        dimPhoneWhenConnected = true
        phoneAsTrackpad = true
        searchEngine = .google
        identifyAsChrome = true
        desktopWebsites = true
        wallpaper = .sonoma
        showClockSeconds = false
        trackpadSensitivity = 2.2
    }
}
