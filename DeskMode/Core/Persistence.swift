import Foundation

/// Tiny JSON file store in the app's Documents directory.
enum Persistence {

    static func url(for name: String) -> URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent(name).appendingPathExtension("json")
    }

    static func load<T: Decodable>(_ type: T.Type, from name: String) -> T? {
        guard let data = try? Data(contentsOf: url(for: name)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(T.self, from: data)
    }

    static func save<T: Encodable>(_ value: T, to name: String) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(value) else { return }
        try? data.write(to: url(for: name), options: .atomic)
    }

    /// True when a store with this name has been written before.
    static func exists(_ name: String) -> Bool {
        FileManager.default.fileExists(atPath: url(for: name).path)
    }

    static func remove(_ name: String) {
        try? FileManager.default.removeItem(at: url(for: name))
    }

    /// Loads a store, or decodes it with a fallback type and converts (for schema migrations).
    static func load<T: Codable, Legacy: Decodable>(_ type: T.Type, from name: String,
                                                       migratingFrom legacy: Legacy.Type,
                                                       _ convert: (Legacy) -> T) -> T? {
        if let value = load(T.self, from: name) { return value }
        guard let old = load(Legacy.self, from: name) else { return nil }
        let converted = convert(old)
        save(converted, to: name)
        return converted
    }
}
