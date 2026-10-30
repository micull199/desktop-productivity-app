import UIKit

/// Fetches and caches site favicons by host: in memory, then on disk (Caches/favicons), then
/// `scheme://host/favicon.ico` with a fallback to Google's favicon service.
@MainActor
final class FaviconCache {

    static let shared = FaviconCache()

    /// Globe glyph shown while a favicon is unknown or unavailable.
    static let placeholder: UIImage = {
        UIImage.symbol("globe", size: 13, weight: .regular)?.withTintColor(Theme.secondaryText, renderingMode: .alwaysOriginal) ?? UIImage()
    }()

    private var memory: [String: UIImage] = [:]
    private var failed: Set<String> = []
    private var pending: [String: [(UIImage?) -> Void]] = [:]
    private let directory: URL
    private let session: URLSession

    private init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        directory = caches.appendingPathComponent("favicons", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        config.httpAdditionalHeaders = ["Accept": "image/*,*/*;q=0.8"]
        session = URLSession(configuration: config)
    }

    /// Returns the cached icon without any network access.
    func cached(for host: String) -> UIImage? {
        let key = Self.key(host)
        if let img = memory[key] { return img }
        if let data = try? Data(contentsOf: fileURL(key)), let img = UIImage(data: data, scale: 2) {
            memory[key] = img
            return img
        }
        return nil
    }

    /// Resolves the favicon for `host`, calling `completion` on the main actor (possibly synchronously).
    func fetch(host: String, scheme: String = "https", completion: @escaping (UIImage?) -> Void) {
        let key = Self.key(host)
        guard !key.isEmpty else { completion(nil); return }
        if let img = cached(for: host) { completion(img); return }
        if failed.contains(key) { completion(nil); return }
        if pending[key] != nil { pending[key]?.append(completion); return }
        pending[key] = [completion]

        let primary = URL(string: "\(scheme == "http" ? "http" : "https")://\(host)/favicon.ico")
        let fallback = URL(string: "https://www.google.com/s2/favicons?domain=\(host)&sz=64")
        let candidates = [primary, fallback].compactMap { $0 }
        download(candidates, index: 0) { [weak self] image, data in
            guard let self else { return }
            let waiters = self.pending.removeValue(forKey: key) ?? []
            if let image {
                self.memory[key] = image
                if let data { let url = self.fileURL(key); DispatchQueue.global(qos: .utility).async { try? data.write(to: url, options: .atomic) } }
            } else {
                self.failed.insert(key)
            }
            for w in waiters { w(image) }
        }
    }

    private func download(_ urls: [URL], index: Int, completion: @escaping (UIImage?, Data?) -> Void) {
        guard index < urls.count else { completion(nil, nil); return }
        let task = session.dataTask(with: urls[index]) { data, response, _ in
            var result: (UIImage, Data)?
            if let data, data.count > 16, data.count < 2_000_000,
               let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
               let image = UIImage(data: data) {
                result = (Self.normalise(image), data)
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    if let (image, data) = result { completion(image, data) }
                    else { self.download(urls, index: index + 1, completion: completion) }
                }
            }
        }
        task.resume()
    }

    /// Keeps the first (usually largest) representation and makes it 2× for crisp 16 pt rendering.
    private static func normalise(_ image: UIImage) -> UIImage {
        guard let cg = image.cgImage else { return image }
        return UIImage(cgImage: cg, scale: 2, orientation: .up)
    }

    private func fileURL(_ key: String) -> URL {
        directory.appendingPathComponent(key).appendingPathExtension("img")
    }

    private static func key(_ host: String) -> String {
        host.lowercased().replacingOccurrences(of: "[^a-z0-9.-]", with: "_", options: .regularExpression)
    }
}
