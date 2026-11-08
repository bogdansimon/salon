import Foundation

extension SourceID {
    public static let met = SourceID("met")
}

/// The Metropolitan Museum of Art Collection API (no key, CC0).
/// Search moved to the paginated `v1.1/search` on 2026-10-01; objects are still `v1/objects/{id}`.
public struct MetSource: ArtSource {
    public let id = SourceID.met
    public let info = SourceInfo(
        name: "The Metropolitan Museum of Art",
        shortName: "The Met",
        supportedTypes: [.painting, .print, .drawing],
        hasQualityFlag: true,
        credit: "Open Access API · CC0",
        homepage: URL(string: "https://metmuseum.github.io/")!
    )

    private let http: HTTPClient
    private static let base = "https://collectionapi.metmuseum.org/public/collection"

    public init(http: HTTPClient) { self.http = http }

    public func randomArtwork(for query: ArtworkQuery) async throws -> Artwork {
        let mediums = query.objectTypes.intersection(info.supportedTypes).map(Self.medium(for:))
        guard let medium = mediums.randomElement() else { throw SourceError.noMatchingWorks }

        let total = try await search(medium: medium, highlights: query.highlightsOnly, offset: 0).total
        guard total > 0 else { throw SourceError.noMatchingWorks }

        for _ in 0..<ArtworkQuery.maxDraws {
            let page = try await search(medium: medium, highlights: query.highlightsOnly, offset: Random.index(below: total))
            guard let objectID = page.objectIDs?.first, !query.excludedIDs.contains("met:\(objectID)") else { continue }
            let object = try await http.json(MetObject.self, from: .make("\(Self.base)/v1/objects/\(objectID)"))
            guard object.isPublicDomain, let artwork = object.artwork else { continue }
            return artwork
        }
        throw SourceError.noMatchingWorks
    }

    public func healthCheck(apiKey: String?) async throws {
        _ = try await search(medium: "Paintings", highlights: true, offset: 0)
    }

    private func search(medium: String, highlights: Bool, offset: Int) async throws -> MetSearch {
        var query = ["q": "*", "hasImages": "true", "medium": medium, "limit": "1", "offset": String(offset)]
        if highlights { query["isHighlight"] = "true" }
        return try await http.json(MetSearch.self, from: .make("\(Self.base)/v1.1/search", query))
    }

    static func medium(for type: ObjectType) -> String {
        switch type {
        case .painting: "Paintings"
        case .print: "Prints"
        case .drawing: "Drawings"
        }
    }
}

struct MetSearch: Decodable {
    var total: Int
    var objectIDs: [Int]?
}

struct MetObject: Decodable {
    var objectID: Int
    var isPublicDomain: Bool
    var primaryImage: String?
    var title: String?
    var artistDisplayName: String?
    var artistDisplayBio: String?
    var objectDate: String?
    var medium: String?
    var dimensions: String?
    var objectURL: String?
    var objectWikidata_URL: String?

    var artwork: Artwork? {
        guard let image = Text.clean(primaryImage).flatMap(URL.init(string:)) else { return nil }
        return Artwork(
            id: "met:\(objectID)",
            sourceID: .met,
            title: Text.clean(title) ?? "Untitled",
            artist: Text.clean(artistDisplayName),
            artistDetails: Text.clean(artistDisplayBio),
            date: Text.clean(objectDate),
            medium: Text.clean(medium),
            dimensions: Self.metric(dimensions),
            museum: "The Metropolitan Museum of Art, New York",
            objectURL: Text.clean(objectURL).flatMap(URL.init(string:)),
            wikidataID: Text.wikidataID(from: objectWikidata_URL),
            imageURL: image
        )
    }

    /// The Met writes "28 13/16 × 36 3/4 in. (73.2 × 93.4 cm)"; keep the metric part.
    static func metric(_ dimensions: String?) -> String? {
        guard let dimensions = Text.clean(dimensions) else { return nil }
        if let range = dimensions.range(of: "\\(([^()]*cm)\\)", options: .regularExpression) {
            return String(dimensions[range].dropFirst().dropLast())
        }
        return dimensions
    }
}
