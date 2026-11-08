import Foundation

extension SourceID {
    public static let wikidata = SourceID("wikidata")
}

/// "The world": famous paintings from any museum, including those with no open API
/// (Louvre, Prado, Uffizi…), via Wikidata + Wikimedia Commons.
///
/// The SPARQL query takes 30–60 s and sometimes fails, so the list is downloaded
/// at most weekly and kept on failure. Picking from it is instant. The quality
/// signal is the number of Wikipedia language editions (sitelinks).
public struct WikidataSource: ArtSource {
    public let id = SourceID.wikidata
    public let info = SourceInfo(
        name: "Wikidata & Wikimedia Commons",
        shortName: "Wikimedia Commons",
        supportedTypes: [.painting],
        hasQualityFlag: true,
        credit: "CC0 data · public-domain images",
        homepage: URL(string: "https://www.wikidata.org/")!
    )

    /// "Highlights only": a Wikipedia article in at least this many languages (~700 works).
    static let highlightSitelinks = 15
    /// Floor for the whole catalogue (~1,660 works). Lower floors return so many rows
    /// that the query service cuts the response off at its 60 s limit.
    static let catalogueSitelinks = 10
    static let sparql = """
    SELECT ?p ?img ?sl WHERE {
      ?p wdt:P31 wd:Q3305213; wdt:P18 ?img; wikibase:sitelinks ?sl .
      FILTER(?sl >= \(catalogueSitelinks))
    }
    """

    private let http: HTTPClient
    private let catalog: CatalogCache<WikidataCatalogEntry>

    public init(http: HTTPClient, store: CatalogStore) {
        self.http = http
        self.catalog = CatalogCache(name: "wikidata-paintings", store: store, maxAge: 7 * 24 * 3600)
    }

    public func randomArtwork(for query: ArtworkQuery) async throws -> Artwork {
        guard query.objectTypes.contains(.painting) else { throw SourceError.noMatchingWorks }
        let entries = try await catalog.entries { try await fetchCatalog() }
        let minimum = query.highlightsOnly ? Self.highlightSitelinks : Self.catalogueSitelinks
        let candidates = entries.filter { $0.sitelinks >= minimum && !query.excludedIDs.contains("wikidata:\($0.id)") }

        for entry in candidates.shuffled().prefix(ArtworkQuery.maxDraws) {
            if let artwork = try await artwork(for: entry) { return artwork }
        }
        throw SourceError.noMatchingWorks
    }

    public func healthCheck(apiKey: String?) async throws {
        _ = try await http.data(for: URLRequest(url: .make("https://www.wikidata.org/w/api.php", ["action": "query", "meta": "siteinfo", "format": "json"])))
    }

    public func warmUp() async {
        _ = try? await catalog.entries { try await fetchCatalog() }
    }

    func fetchCatalog() async throws -> [WikidataCatalogEntry] {
        var request = URLRequest(url: .make("https://query.wikidata.org/sparql", ["format": "json", "query": Self.sparql]))
        request.timeoutInterval = 90
        let result = try await http.json(SPARQLResult.self, from: request)
        return result.results.bindings.compactMap { row in
            guard let id = Text.wikidataID(from: row.p.value), let sitelinks = Int(row.sl.value),
                  let file = row.img.value.components(separatedBy: "Special:FilePath/").last?.removingPercentEncoding
            else { return nil }
            return WikidataCatalogEntry(id: id, imageFile: file, sitelinks: sitelinks)
        }
    }

    /// Entity → labels → Commons image info. Nil when the image isn't public domain.
    func artwork(for entry: WikidataCatalogEntry) async throws -> Artwork? {
        let entity = try await http.json(WBEntities.self, from: .make("https://www.wikidata.org/w/api.php", [
            "action": "wbgetentities", "format": "json", "ids": entry.id,
            "props": "labels|claims|sitelinks", "languages": "en", "sitefilter": "enwiki",
        ])).entities[entry.id]
        guard let entity else { return nil }

        let creatorID = entity.itemID("P170"), collectionID = entity.itemID("P195"), materialID = entity.itemID("P186")
        let labelIDs = [creatorID, collectionID, materialID].compactMap { $0 }
        let labels = labelIDs.isEmpty ? [:] : try await http.json(WBEntities.self, from: .make("https://www.wikidata.org/w/api.php", [
            "action": "wbgetentities", "format": "json", "ids": labelIDs.joined(separator: "|"), "props": "labels", "languages": "en",
        ])).entities.compactMapValues(\.englishLabel)

        guard let image = try await commonsImage(file: entry.imageFile) else { return nil }
        let enwiki = entity.sitelinks?["enwiki"]?.title
        return Artwork(
            id: "wikidata:\(entry.id)",
            sourceID: .wikidata,
            title: entity.englishLabel ?? "Untitled",
            artist: creatorID.flatMap { labels[$0] },
            date: entity.year("P571"),
            medium: materialID.flatMap { labels[$0] }.map { $0.prefix(1).uppercased() + $0.dropFirst() },
            dimensions: entity.dimensions,
            museum: collectionID.flatMap { labels[$0] } ?? "Wikimedia Commons",
            objectURL: entity.string("P973").flatMap(URL.init(string:))
                ?? enwiki.flatMap { URL(string: "https://en.wikipedia.org/wiki/\($0.replacingOccurrences(of: " ", with: "_"))") },
            wikidataID: entry.id,
            imageURL: image.url,
            reportedPixelSize: image.size
        )
    }

    /// Commons original, or a ≤4096 px rendition when the original is larger.
    private func commonsImage(file: String) async throws -> (url: URL, size: PixelSize)? {
        let response = try await http.json(CommonsQuery.self, from: .make("https://commons.wikimedia.org/w/api.php", [
            "action": "query", "format": "json", "prop": "imageinfo", "iiprop": "url|size|extmetadata",
            "iiextmetadatafilter": "LicenseShortName", "iiurlwidth": "4096", "titles": "File:\(file)",
        ]))
        guard let info = response.query.pages.values.first?.imageinfo?.first else { return nil }
        let licence = info.extmetadata?.LicenseShortName?.value.lowercased() ?? ""
        guard licence.contains("public domain") || licence.contains("cc0") || licence.hasPrefix("pd") else { return nil }

        if let thumb = info.thumburl.flatMap(URL.init(string:)), let w = info.thumbwidth, let h = info.thumbheight, w < info.width {
            return (thumb, PixelSize(width: w, height: h))
        }
        guard let url = URL(string: info.url) else { return nil }
        return (url, PixelSize(width: info.width, height: info.height))
    }
}

public struct WikidataCatalogEntry: Codable, Hashable, Sendable {
    public var id: String
    public var imageFile: String
    public var sitelinks: Int
}

struct SPARQLResult: Decodable {
    struct Value: Decodable { var value: String }
    struct Row: Decodable { var p: Value; var img: Value; var sl: Value }
    struct Results: Decodable { var bindings: [Row] }
    var results: Results
}

struct WBEntities: Decodable {
    var entities: [String: WBEntity]
}

struct WBEntity: Decodable {
    struct Label: Decodable { var value: String }
    struct Sitelink: Decodable { var title: String }
    struct Claim: Decodable {
        struct Snak: Decodable { var datavalue: DataValue? }
        var mainsnak: Snak
    }
    enum DataValue: Decodable {
        case item(String), string(String), time(String), quantity(amount: String, unit: String), other

        private enum Keys: String, CodingKey { case value, type }
        private struct ItemValue: Decodable { var id: String }
        private struct TimeValue: Decodable { var time: String }
        private struct QuantityValue: Decodable { var amount: String; var unit: String }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: Keys.self)
            switch try container.decode(String.self, forKey: .type) {
            case "wikibase-entityid": self = .item(try container.decode(ItemValue.self, forKey: .value).id)
            case "string": self = .string(try container.decode(String.self, forKey: .value))
            case "time": self = .time(try container.decode(TimeValue.self, forKey: .value).time)
            case "quantity":
                let q = try container.decode(QuantityValue.self, forKey: .value)
                self = .quantity(amount: q.amount, unit: q.unit)
            default: self = .other
            }
        }
    }

    var labels: [String: Label]?
    var claims: [String: [Claim]]?
    var sitelinks: [String: Sitelink]?

    var englishLabel: String? { labels?["en"]?.value }

    private func values(_ property: String) -> [DataValue] {
        (claims?[property] ?? []).compactMap(\.mainsnak.datavalue)
    }

    func itemID(_ property: String) -> String? {
        for case .item(let id) in values(property) { return id }
        return nil
    }

    func string(_ property: String) -> String? {
        for case .string(let value) in values(property) { return value }
        return nil
    }

    /// "+1658-00-00T00:00:00Z" → "1658"
    func year(_ property: String) -> String? {
        for case .time(let time) in values(property) {
            let digits = time.dropFirst().prefix { $0 != "-" }
            if let year = Int(digits) { return String(year) }
        }
        return nil
    }

    /// Height (P2048) × width (P2049), when both are in centimetres (Q174728).
    var dimensions: String? {
        func cm(_ property: String) -> String? {
            for case .quantity(let amount, let unit) in values(property) where unit.hasSuffix("Q174728") {
                return amount.hasPrefix("+") ? String(amount.dropFirst()) : amount
            }
            return nil
        }
        guard let h = cm("P2048"), let w = cm("P2049") else { return nil }
        return "\(h) × \(w) cm"
    }
}

struct CommonsQuery: Decodable {
    struct ExtValue: Decodable { var value: String }
    struct ExtMetadata: Decodable { var LicenseShortName: ExtValue? }
    struct ImageInfo: Decodable {
        var url: String
        var width: Int
        var height: Int
        var thumburl: String?
        var thumbwidth: Int?
        var thumbheight: Int?
        var extmetadata: ExtMetadata?
    }
    struct Page: Decodable { var imageinfo: [ImageInfo]? }
    struct Query: Decodable { var pages: [String: Page] }
    var query: Query
}
