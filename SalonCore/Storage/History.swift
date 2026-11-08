import Foundation

/// One hung work. The history file is an array of these, oldest first.
public struct HistoryEntry: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var artwork: Artwork
    public var shownAt: Date
    /// "No. 214": the running count of works shown.
    public var number: Int
    public var keptAt: Date?
    public var palette: ArtworkPalette?

    public var isKept: Bool { keptAt != nil }

    public init(id: UUID = UUID(), artwork: Artwork, shownAt: Date, number: Int, keptAt: Date? = nil, palette: ArtworkPalette? = nil) {
        self.id = id
        self.artwork = artwork
        self.shownAt = shownAt
        self.number = number
        self.keptAt = keptAt
        self.palette = palette
    }
}

/// Persistent bits that aren't settings or history.
public struct AppState: Codable, Sendable {
    /// When the wallpaper last changed (for the daily schedule).
    public var lastChange: Date?
    /// Running count for "No. 214"; never reset, so numbers stay unique.
    public var shownCount = 0
    /// Rendered wallpaper files currently on screen (kept during cleanup).
    public var currentWallpaperFiles: [String] = []
    /// History entries on screen right now; the first is the main display's (shown on the card).
    public var currentEntryIDs: [UUID] = []

    public init() {}

    private enum CodingKeys: String, CodingKey { case lastChange, shownCount, currentWallpaperFiles, currentEntryIDs }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        lastChange = try c.decodeIfPresent(Date.self, forKey: .lastChange)
        shownCount = try c.decodeIfPresent(Int.self, forKey: .shownCount) ?? 0
        currentWallpaperFiles = try c.decodeIfPresent([String].self, forKey: .currentWallpaperFiles) ?? []
        currentEntryIDs = try c.decodeIfPresent([UUID].self, forKey: .currentEntryIDs) ?? []
    }
}

/// Kept works out as JSON or CSV (Settings › Storage › Export).
public enum FavoritesExporter {
    public enum Format: String, CaseIterable, Sendable {
        case json, csv
        public var displayName: String { rawValue.uppercased() }
    }

    struct Row: Encodable {
        var title: String
        var artist: String?
        var date: String?
        var museum: String
        var objectURL: String?
        var hungOn: String
        var keptOn: String?
    }

    public static func export(_ entries: [HistoryEntry], as format: Format) throws -> Data {
        let day = ISO8601DateFormatter()
        day.formatOptions = [.withFullDate]
        let rows = entries.filter(\.isKept).map {
            Row(title: $0.artwork.title, artist: $0.artwork.artist, date: $0.artwork.date, museum: $0.artwork.museum,
                objectURL: $0.artwork.objectURL?.absoluteString, hungOn: day.string(from: $0.shownAt),
                keptOn: $0.keptAt.map(day.string(from:)))
        }
        switch format {
        case .json:
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
            return try encoder.encode(rows)
        case .csv:
            let header = "title,artist,date,museum,object_url,hung_on,kept_on"
            let lines = rows.map { row in
                [row.title, row.artist, row.date, row.museum, row.objectURL, row.hungOn, row.keptOn].map { csvField($0) }.joined(separator: ",")
            }
            return Data(([header] + lines).joined(separator: "\n").appending("\n").utf8)
        }
    }

    /// RFC 4180: quote fields containing commas, quotes or newlines; double inner quotes.
    static func csvField(_ value: String?) -> String {
        guard let value else { return "" }
        guard value.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
