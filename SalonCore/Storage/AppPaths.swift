import Foundation

/// Everything Salon writes lives under ~/Library/Application Support/Salon/.
public struct AppPaths: Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    /// ~/Library/Application Support/Salon
    public static var standard: AppPaths {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return AppPaths(root: support.appendingPathComponent("Salon", isDirectory: true))
    }

    public var settings: URL { root.appendingPathComponent("settings.json") }
    public var history: URL { root.appendingPathComponent("history.json") }
    /// Every artwork id ever shown; survives "Clear History" so works never repeat.
    public var shown: URL { root.appendingPathComponent("shown.json") }
    public var health: URL { root.appendingPathComponent("health.json") }
    public var state: URL { root.appendingPathComponent("state.json") }
    public var images: URL { root.appendingPathComponent("Images", isDirectory: true) }
    public var wallpapers: URL { root.appendingPathComponent("Wallpapers", isDirectory: true) }
    public var catalogs: URL { root.appendingPathComponent("Catalogs", isDirectory: true) }

    public func createDirectories() {
        for url in [root, images, wallpapers, catalogs] {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }
}

/// A Codable value stored as one JSON file, written atomically.
public struct JSONFile<Value: Codable>: Sendable {
    public let url: URL

    public init(_ url: URL) { self.url = url }

    public func load() -> Value? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder.salon.decode(Value.self, from: data)
    }

    public func save(_ value: Value) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder.salon.encode(value).write(to: url, options: .atomic)
        } catch {
            NSLog("Salon: couldn’t save \(url.lastPathComponent): \(error)")
        }
    }
}
