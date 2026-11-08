import Foundation

extension SourceID {
    public static let artInstitute = SourceID("aic")
}

/// Art Institute of Chicago API (no key). Images come from its IIIF server, which
/// serves at most 3000 px on the long side and wants an `AIC-User-Agent` header
/// (without it Cloudflare answers with a challenge page).
public struct ArtInstituteSource: ArtSource {
    public let id = SourceID.artInstitute
    public let info = SourceInfo(
        name: "Art Institute of Chicago",
        shortName: "the Art Institute",
        supportedTypes: [.painting, .print, .drawing],
        hasQualityFlag: true,
        credit: "Public API · CC0 public-domain images",
        homepage: URL(string: "https://api.artic.edu/docs/")!
    )

    static let maxIIIFLongSide = 3000
    private static let searchURL = URL(string: "https://api.artic.edu/api/v1/artworks/search")!
    private static let headers = ["AIC-User-Agent": SalonHTTP.userAgent, "Content-Type": "application/json"]
    private let http: HTTPClient

    public init(http: HTTPClient) { self.http = http }

    public func randomArtwork(for query: ArtworkQuery) async throws -> Artwork {
        let types = query.objectTypes.intersection(info.supportedTypes).map(Self.typeTitle(for:))
        guard !types.isEmpty else { throw SourceError.noMatchingWorks }

        let total = try await search(types: types, highlights: query.highlightsOnly, page: 1).pagination.total
        // The search API stops at 10,000 results.
        let pages = min(total, 10_000)
        guard pages > 0 else { throw SourceError.noMatchingWorks }

        for _ in 0..<ArtworkQuery.maxDraws {
            let result = try await search(types: types, highlights: query.highlightsOnly, page: Random.index(below: pages) + 1)
            guard let item = result.data.first, !query.excludedIDs.contains("aic:\(item.id)") else { continue }
            if let artwork = item.artwork { return artwork }
        }
        throw SourceError.noMatchingWorks
    }

    public func healthCheck(apiKey: String?) async throws {
        _ = try await search(types: ["Painting"], highlights: true, page: 1)
    }

    private func search(types: [String], highlights: Bool, page: Int) async throws -> AICSearch {
        var filters: [[String: Any]] = [
            ["term": ["is_public_domain": true]],
            ["terms": ["artwork_type_title.keyword": types]],
            ["exists": ["field": "image_id"]],
        ]
        if highlights { filters.append(["term": ["is_boosted": true]]) }
        let body: [String: Any] = [
            "query": ["bool": ["filter": filters]],
            "limit": 1,
            "page": page,
            "fields": ["id", "title", "artist_display", "date_display", "medium_display", "dimensions",
                       "image_id", "thumbnail", "description", "short_description", "is_public_domain"],
        ]
        var request = URLRequest(url: Self.searchURL)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        Self.headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        return try await http.json(AICSearch.self, from: request)
    }

    static func typeTitle(for type: ObjectType) -> String {
        switch type {
        case .painting: "Painting"
        case .print: "Print"
        case .drawing: "Drawing and Watercolor"
        }
    }
}

struct AICSearch: Decodable {
    struct Pagination: Decodable { var total: Int }
    var pagination: Pagination
    var data: [AICArtwork]
}

struct AICArtwork: Decodable {
    struct Thumbnail: Decodable { var width: Int?; var height: Int? }
    var id: Int
    var title: String?
    var artist_display: String?
    var date_display: String?
    var medium_display: String?
    var dimensions: String?
    var image_id: String?
    var thumbnail: Thumbnail?
    var description: String?
    var short_description: String?
    var is_public_domain: Bool?

    var artwork: Artwork? {
        guard is_public_domain == true, let imageID = image_id,
              let width = thumbnail?.width, let height = thumbnail?.height else { return nil }
        let size = Self.servedSize(width: width, height: height)
        let sizeSpec = width >= height ? "\(size.width)," : ",\(size.height)"
        let artist = Text.splitArtist(artist_display)
        return Artwork(
            id: "aic:\(id)",
            sourceID: .artInstitute,
            title: Text.clean(title) ?? "Untitled",
            artist: artist.name,
            artistDetails: artist.details,
            date: Text.clean(date_display),
            medium: Text.clean(medium_display),
            dimensions: Self.unframed(dimensions),
            museum: "The Art Institute of Chicago",
            summary: Text.plain(description) ?? Text.plain(short_description),
            objectURL: URL(string: "https://www.artic.edu/artworks/\(id)"),
            imageURL: URL(string: "https://www.artic.edu/iiif/2/\(imageID)/full/\(sizeSpec)/0/default.jpg")!,
            imageRequestHeaders: ["AIC-User-Agent": SalonHTTP.userAgent],
            reportedPixelSize: size
        )
    }

    /// The size the IIIF server will actually hand out: the original, capped at 3000 px long side.
    static func servedSize(width: Int, height: Int) -> PixelSize {
        let cap = ArtInstituteSource.maxIIIFLongSide
        let long = max(width, height)
        guard long > cap else { return PixelSize(width: width, height: height) }
        let scale = Double(cap) / Double(long)
        return PixelSize(width: Int((Double(width) * scale).rounded()), height: Int((Double(height) * scale).rounded()))
    }

    /// "73.6 × 92.3 cm (29 × 36 5/8 in.); Framed: …" → "73.6 × 92.3 cm"
    static func unframed(_ dimensions: String?) -> String? {
        guard let first = Text.clean(dimensions)?.components(separatedBy: ";").first else { return nil }
        return Text.clean(first.components(separatedBy: " (").first)
    }
}
