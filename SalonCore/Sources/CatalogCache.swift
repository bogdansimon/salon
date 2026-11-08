import Foundation

/// A downloaded list of candidate works for sources that can't jump to a random
/// item (Rijksmuseum pages forward only; Wikidata's query service is too slow to
/// call per pick). Refreshed when stale; on refresh failure the old list is kept.
public struct Catalog<Entry: Codable & Sendable>: Codable, Sendable {
    public var fetchedAt: Date
    public var entries: [Entry]

    public init(fetchedAt: Date, entries: [Entry]) {
        self.fetchedAt = fetchedAt
        self.entries = entries
    }
}

public protocol CatalogStore: Sendable {
    func load(_ name: String) -> Data?
    func save(_ data: Data, as name: String)
}

/// Files under Application Support/Salon/Catalogs.
public struct FileCatalogStore: CatalogStore {
    private let directory: URL

    public init(directory: URL) { self.directory = directory }

    public func load(_ name: String) -> Data? {
        try? Data(contentsOf: directory.appendingPathComponent("\(name).json"))
    }

    public func save(_ data: Data, as name: String) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: directory.appendingPathComponent("\(name).json"), options: .atomic)
    }
}

/// Loads a catalog from the store, refreshing it when older than `maxAge`.
actor CatalogCache<Entry: Codable & Sendable> {
    private let name: String
    private let store: CatalogStore
    private let maxAge: TimeInterval
    private var cached: Catalog<Entry>?
    /// One refresh at a time: a warm-up and a pick arriving together share it.
    private var inFlight: Task<[Entry], Error>?

    init(name: String, store: CatalogStore, maxAge: TimeInterval) {
        self.name = name
        self.store = store
        self.maxAge = maxAge
    }

    func entries(now: Date = Date(), refresh: @escaping @Sendable () async throws -> [Entry]) async throws -> [Entry] {
        if cached == nil, let data = store.load(name) {
            cached = try? JSONDecoder.salon.decode(Catalog<Entry>.self, from: data)
        }
        if let cached, now.timeIntervalSince(cached.fetchedAt) < maxAge, !cached.entries.isEmpty {
            return cached.entries
        }
        do {
            let task = inFlight ?? Task { try await refresh() }
            inFlight = task
            defer { inFlight = nil }
            let fresh = Catalog(fetchedAt: now, entries: try await task.value)
            guard !fresh.entries.isEmpty else { throw SourceError.noMatchingWorks }
            cached = fresh
            if let data = try? JSONEncoder.salon.encode(fresh) { store.save(data, as: name) }
            return fresh.entries
        } catch {
            // Stale beats nothing: keep serving the old list when the refresh fails.
            if let stale = cached?.entries, !stale.isEmpty { return stale }
            throw error
        }
    }
}
