import Foundation

/// Debounced search-suggestion lookups for the omnibox. One request in flight at a time; a new
/// query cancels the previous one.
@MainActor
final class SearchSuggestionFetcher {

    static let debounce: TimeInterval = 0.15

    private var timer: Timer?
    private var task: URLSessionDataTask?
    private var generation = 0
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 5
        session = URLSession(configuration: config)
    }

    /// Calls `completion` on the main actor with up to ten suggestions for `query`, or not at
    /// all if a newer query supersedes it.
    func suggestions(for query: String, completion: @escaping ([String]) -> Void) {
        cancel()
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !q.hasPrefix("http://"), !q.hasPrefix("https://") else { return }
        generation += 1
        let gen = generation
        timer = Timer.scheduledTimer(withTimeInterval: Self.debounce, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.request(q, generation: gen, completion: completion) }
        }
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
        task?.cancel()
        task = nil
        generation += 1
    }

    private func request(_ query: String, generation gen: Int, completion: @escaping ([String]) -> Void) {
        var components = URLComponents(string: "https://suggestqueries.google.com/complete/search")!
        components.queryItems = [URLQueryItem(name: "client", value: "firefox"), URLQueryItem(name: "q", value: query)]
        guard let url = components.url else { return }
        let t = session.dataTask(with: url) { [weak self] data, _, error in
            guard error == nil, let data else { return }
            // Response: ["query", ["suggestion", …], …]
            let parsed = (try? JSONSerialization.jsonObject(with: data)) as? [Any]
            let list = (parsed?.dropFirst().first as? [String]) ?? []
            let cleaned = Array(list.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.prefix(10))
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, self.generation == gen else { return }
                    self.task = nil
                    completion(cleaned)
                }
            }
        }
        task = t
        t.resume()
    }
}
