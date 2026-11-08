import Foundation

extension SourceID {
    public static let smithsonian = SourceID("si")
}

/// Smithsonian Open Access (CC0). Needs a free api.data.gov key, stored in the
/// Keychain; off by default. Images top out at 3000 px. No quality flag.
public struct SmithsonianSource: ArtSource {
    public let id = SourceID.smithsonian
    public let info = SourceInfo(
        name: "Smithsonian Open Access",
        shortName: "the Smithsonian",
        supportedTypes: [.painting, .print, .drawing],
        hasQualityFlag: false,
        requiresAPIKey: true,
        apiKeyHelp: "Get a free key at api.data.gov/signup",
        credit: "api.data.gov · CC0",
        homepage: URL(string: "https://www.si.edu/openaccess")!,
        enabledByDefault: false
    )

    private static let base = "https://api.si.edu/openaccess/api/v1.0/search"
    private let http: HTTPClient

    public init(http: HTTPClient) { self.http = http }

    public func randomArtwork(for query: ArtworkQuery) async throws -> Artwork {
        guard let key = query.apiKey, !key.isEmpty else { throw SourceError.missingAPIKey }
        let types = query.objectTypes.intersection(info.supportedTypes).map(Self.objectType(for:))
        guard let type = types.randomElement() else { throw SourceError.noMatchingWorks }

        let total = try await search(type: type, start: 0, key: key).response.rowCount
        guard total > 0 else { throw SourceError.noMatchingWorks }

        for _ in 0..<ArtworkQuery.maxDraws {
            let result = try await search(type: type, start: Random.index(below: total), key: key)
            guard let row = result.response.rows.first, !query.excludedIDs.contains("si:\(row.id)") else { continue }
            if let artwork = row.artwork { return artwork }
        }
        throw SourceError.noMatchingWorks
    }

    public func healthCheck(apiKey: String?) async throws {
        guard let key = apiKey, !key.isEmpty else { throw SourceError.missingAPIKey }
        _ = try await search(type: "Paintings", start: 0, key: key)
    }

    private func search(type: String, start: Int, key: String) async throws -> SISearch {
        let q = "online_media_type:\"Images\" AND object_type:\"\(type)\""
        return try await http.json(SISearch.self, from: .make(Self.base, ["q": q, "rows": "1", "start": String(start), "api_key": key]))
    }

    static func objectType(for type: ObjectType) -> String {
        switch type {
        case .painting: "Paintings"
        case .print: "Prints"
        case .drawing: "Drawings"
        }
    }
}

struct SISearch: Decodable {
    struct Response: Decodable { var rowCount: Int; var rows: [SIRow] }
    var response: Response
}

struct SIRow: Decodable {
    struct Labelled: Decodable { var label: String?; var content: String? }
    struct Freetext: Decodable {
        var name: [Labelled]?
        var date: [Labelled]?
        var physicalDescription: [Labelled]?
        var notes: [Labelled]?
    }
    struct Resource: Decodable { var label: String?; var url: String?; var dimensions: String? }
    struct Media: Decodable { var usage: [String: String]?; var resources: [Resource]? }
    struct OnlineMedia: Decodable { var media: [Media]? }
    struct Descriptive: Decodable { var record_link: String?; var data_source: String?; var online_media: OnlineMedia? }
    struct Content: Decodable { var freetext: Freetext?; var descriptiveNonRepeating: Descriptive? }

    var id: String
    var title: String?
    var content: Content

    var artwork: Artwork? {
        let descriptive = content.descriptiveNonRepeating
        guard let media = descriptive?.online_media?.media?.first, media.usage?["access"] == "CC0",
              let jpeg = media.resources?.first(where: { $0.label == "High-resolution JPEG" }),
              let url = jpeg.url.flatMap(URL.init(string:)) else { return nil }
        let free = content.freetext
        let artist = Self.splitArtist(free?.name?.first?.content)
        return Artwork(
            id: "si:\(id)",
            sourceID: .smithsonian,
            title: Text.clean(title) ?? "Untitled",
            artist: artist.name,
            artistDetails: artist.details,
            date: Text.clean(free?.date?.first?.content),
            medium: Text.clean(free?.physicalDescription?.first { $0.label == "Medium" }?.content),
            dimensions: Self.metric(free?.physicalDescription?.first { $0.label == "Dimensions" }?.content),
            museum: Text.clean(descriptive?.data_source) ?? "Smithsonian Institution",
            summary: Text.plain(free?.notes?.first?.content),
            objectURL: descriptive?.record_link.flatMap(URL.init(string:)),
            imageURL: url,
            reportedPixelSize: Self.size(jpeg.dimensions)
        )
    }

    /// "Abraham Walkowitz, American, b. Tyumen, Russia, 1878–1965" → name + rest.
    static func splitArtist(_ value: String?) -> (name: String?, details: String?) {
        guard let value = Text.clean(value), let comma = value.firstIndex(of: ",") else { return (Text.clean(value), nil) }
        return (Text.clean(String(value[..<comma])), Text.clean(String(value[value.index(after: comma)...])))
    }

    /// "14 1/8 x 11 1/8 in. (35.8 x 28.1 cm)" → "35.8 × 28.1 cm"
    static func metric(_ value: String?) -> String? {
        guard let value = Text.clean(value) else { return nil }
        if let range = value.range(of: "\\(([^()]*cm)\\)", options: .regularExpression) {
            return String(value[range].dropFirst().dropLast()).replacingOccurrences(of: " x ", with: " × ")
        }
        return value
    }

    /// "3000x1970" → PixelSize
    static func size(_ value: String?) -> PixelSize? {
        let parts = (value ?? "").split(separator: "x").compactMap { Int($0) }
        return parts.count == 2 ? PixelSize(width: parts[0], height: parts[1]) : nil
    }
}
