import Foundation

extension SourceID {
    public static let cleveland = SourceID("cma")
}

/// Cleveland Museum of Art Open Access API (no key, CC0). Uses the "print" JPEG
/// (about 3400 px); the "full" rendition is a ~500 MB TIFF.
public struct ClevelandSource: ArtSource {
    public let id = SourceID.cleveland
    public let info = SourceInfo(
        name: "Cleveland Museum of Art",
        shortName: "Cleveland",
        supportedTypes: [.painting, .print, .drawing],
        hasQualityFlag: true,
        credit: "Open Access API · CC0",
        homepage: URL(string: "https://openaccess-api.clevelandart.org/")!
    )

    private static let base = "https://openaccess-api.clevelandart.org/api/artworks/"
    private let http: HTTPClient

    public init(http: HTTPClient) { self.http = http }

    public func randomArtwork(for query: ArtworkQuery) async throws -> Artwork {
        let types = query.objectTypes.intersection(info.supportedTypes).map(Self.type(for:))
        guard let type = types.randomElement() else { throw SourceError.noMatchingWorks }

        let total = try await search(type: type, highlights: query.highlightsOnly, skip: 0).info.total
        guard total > 0 else { throw SourceError.noMatchingWorks }

        for _ in 0..<ArtworkQuery.maxDraws {
            let result = try await search(type: type, highlights: query.highlightsOnly, skip: Random.index(below: total))
            guard let item = result.data.first, !query.excludedIDs.contains("cma:\(item.id)") else { continue }
            if let artwork = item.artwork { return artwork }
        }
        throw SourceError.noMatchingWorks
    }

    public func healthCheck(apiKey: String?) async throws {
        _ = try await search(type: "Painting", highlights: true, skip: 0)
    }

    private func search(type: String, highlights: Bool, skip: Int) async throws -> CMASearch {
        var query = ["type": type, "cc0": "1", "has_image": "1", "limit": "1", "skip": String(skip)]
        if highlights { query["highlight"] = "1" }
        return try await http.json(CMASearch.self, from: .make(Self.base, query))
    }

    static func type(for type: ObjectType) -> String {
        switch type {
        case .painting: "Painting"
        case .print: "Print"
        case .drawing: "Drawing"
        }
    }
}

struct CMASearch: Decodable {
    struct Info: Decodable { var total: Int }
    var info: Info
    var data: [CMAArtwork]
}

struct CMAArtwork: Decodable {
    struct Creator: Decodable { var description: String? }
    struct Image: Decodable { var url: String?; var width: String?; var height: String? }
    struct Images: Decodable { var print: Image?; var web: Image? }

    var id: Int
    var title: String?
    var creation_date: String?
    var technique: String?
    var measurements: String?
    var url: String?
    var wikidata_id: String?
    var did_you_know: String?
    var description: String?
    var share_license_status: String?
    var creators: [Creator]?
    var images: Images?

    var artwork: Artwork? {
        guard share_license_status == "CC0", let image = images?.print,
              let imageURL = image.url.flatMap(URL.init(string:)) else { return nil }
        let artist = Text.splitArtist(creators?.first?.description)
        let size = Int(image.width ?? "").flatMap { w in Int(image.height ?? "").map { PixelSize(width: w, height: $0) } }
        return Artwork(
            id: "cma:\(id)",
            sourceID: .cleveland,
            title: Text.clean(title) ?? "Untitled",
            artist: artist.name,
            artistDetails: artist.details,
            date: Text.clean(creation_date),
            medium: Text.clean(technique).map { $0.prefix(1).uppercased() + $0.dropFirst() },
            dimensions: Self.unframed(measurements),
            museum: "Cleveland Museum of Art",
            summary: Text.plain(did_you_know) ?? Text.plain(description),
            objectURL: Text.clean(url).flatMap(URL.init(string:)),
            wikidataID: Text.wikidataID(from: wikidata_id),
            imageURL: imageURL,
            reportedPixelSize: size
        )
    }

    /// "Framed: … ; Unframed: 99 x 79.8 cm (39 x …)" → "99 × 79.8 cm"
    static func unframed(_ measurements: String?) -> String? {
        guard let text = Text.clean(measurements) else { return nil }
        let part = text.components(separatedBy: ";")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { $0.hasPrefix("Unframed:") } ?? text.components(separatedBy: ";").first ?? text
        let value = part.replacingOccurrences(of: "Unframed:", with: "").components(separatedBy: " (").first
        return Text.clean(value)?.replacingOccurrences(of: " x ", with: " × ")
    }
}
