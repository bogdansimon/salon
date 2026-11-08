import Foundation

extension SourceID {
    public static let smk = SourceID("smk")
}

/// SMK – National Gallery of Denmark (no key, public domain). No highlight flag;
/// with "highlights only" on we use "has been in an exhibition" as a stand-in.
public struct SMKSource: ArtSource {
    public let id = SourceID.smk
    public let info = SourceInfo(
        name: "SMK – National Gallery of Denmark",
        shortName: "SMK",
        supportedTypes: [.painting, .print, .drawing],
        hasQualityFlag: false,
        credit: "Open API · public-domain images",
        homepage: URL(string: "https://open.smk.dk/en")!
    )

    private static let base = "https://api.smk.dk/api/v1/art/search/"
    /// Results fetched per random draw, so the exhibition filter has something to choose from.
    private static let batch = 10
    private let http: HTTPClient

    public init(http: HTTPClient) { self.http = http }

    public func randomArtwork(for query: ArtworkQuery) async throws -> Artwork {
        let types = query.objectTypes.intersection(info.supportedTypes).map(\.rawValue)
        guard let type = types.randomElement() else { throw SourceError.noMatchingWorks }

        let total = try await search(type: type, offset: 0, rows: 0).found
        guard total > 0 else { throw SourceError.noMatchingWorks }

        for _ in 0..<ArtworkQuery.maxDraws {
            let page = try await search(type: type, offset: Random.index(below: max(total - Self.batch, 1)), rows: Self.batch)
            let candidates = (page.items ?? []).filter {
                !query.excludedIDs.contains("smk:\($0.object_number)") && (!query.highlightsOnly || $0.hasExhibitionHistory)
            }
            if let artwork = candidates.shuffled().lazy.compactMap(\.artwork).first { return artwork }
        }
        throw SourceError.noMatchingWorks
    }

    public func healthCheck(apiKey: String?) async throws {
        _ = try await search(type: "painting", offset: 0, rows: 0)
    }

    private func search(type: String, offset: Int, rows: Int) async throws -> SMKSearch {
        let filters = "[has_image:true],[public_domain:true],[object_names:\(type)]"
        let url = URL.make(Self.base, ["keys": "*", "filters": filters, "offset": String(offset), "rows": String(rows), "lang": "en"])
        return try await http.json(SMKSearch.self, from: url)
    }
}

struct SMKSearch: Decodable {
    var found: Int
    var items: [SMKItem]?
}

struct SMKItem: Decodable {
    struct Title: Decodable { var title: String? }
    struct Production: Decodable {
        var creator_forename: String?
        var creator_surname: String?
        var creator: String?
        var creator_nationality: String?
        var creator_date_of_birth: String?
        var creator_date_of_death: String?
    }
    struct ProductionDate: Decodable { var period: String? }
    struct Dimension: Decodable { var type: String?; var value: String?; var unit: String?; var part: String? }
    struct Exhibition: Decodable { var exhibition: String? }

    var object_number: String
    var titles: [Title]?
    var production: [Production]?
    var production_date: [ProductionDate]?
    var techniques: [String]?
    var dimensions: [Dimension]?
    var exhibitions: [Exhibition]?
    var frontend_url: String?
    var image_native: String?
    var image_iiif_id: String?
    var image_width: Int?
    var image_height: Int?
    var public_domain: Bool?

    var hasExhibitionHistory: Bool { !(exhibitions ?? []).isEmpty }

    /// Long side requested from SMK's IIIF server: enough for 5K, and ~3× faster than the native original.
    static let maxLongSide = 5120

    var artwork: Artwork? {
        guard public_domain == true, let (image, size) = imageAndSize else { return nil }
        let maker = production?.first
        return Artwork(
            id: "smk:\(object_number)",
            sourceID: .smk,
            title: Text.clean(titles?.first?.title) ?? "Untitled",
            artist: maker.flatMap(Self.name(of:)),
            artistDetails: maker.flatMap(Self.details(of:)),
            date: Text.clean(production_date?.first?.period),
            medium: Text.clean(techniques?.first),
            dimensions: netDimensions,
            museum: "SMK – National Gallery of Denmark, Copenhagen",
            objectURL: frontend_url.flatMap(URL.init(string:)),
            imageURL: image,
            reportedPixelSize: size
        )
    }

    /// IIIF capped at `maxLongSide` when available, else the native file.
    private var imageAndSize: (URL, PixelSize?)? {
        let native = image_width.flatMap { w in image_height.map { PixelSize(width: w, height: $0) } }
        if let iiif = Text.clean(image_iiif_id), let size = native, size.longSide > Self.maxLongSide,
           let url = URL(string: "\(iiif)/full/!\(Self.maxLongSide),\(Self.maxLongSide)/0/default.jpg") {
            let scale = Double(Self.maxLongSide) / Double(size.longSide)
            return (url, PixelSize(width: Int((Double(size.width) * scale).rounded()), height: Int((Double(size.height) * scale).rounded())))
        }
        return image_native.flatMap(URL.init(string:)).map { ($0, native) }
    }

    /// "Kristian Zahrtmann" from forename + surname; falls back to "Surname, Forename".
    static func name(of maker: Production) -> String? {
        if let fore = Text.clean(maker.creator_forename), let sur = Text.clean(maker.creator_surname) { return "\(fore) \(sur)" }
        return Text.clean(maker.creator)
    }

    /// "Danish, 1843–1917"
    static func details(of maker: Production) -> String? {
        let born = maker.creator_date_of_birth?.prefix(4)
        let died = maker.creator_date_of_death?.prefix(4)
        let years = born.map { b in died.map { "\(b)–\($0)" } ?? "born \(b)" }
        let parts = [Text.clean(maker.creator_nationality), years].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    /// Unframed ("Netto") height × width in cm.
    private var netDimensions: String? {
        let net = (dimensions ?? []).filter { $0.part == "Netto" || $0.part == nil }
        guard let h = net.first(where: { $0.type == "height" })?.value,
              let w = net.first(where: { $0.type == "width" })?.value else { return nil }
        return "\(h) × \(w) cm"
    }
}
