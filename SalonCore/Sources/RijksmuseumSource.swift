import Foundation

extension SourceID {
    public static let rijksmuseum = SourceID("rijks")
}

/// Rijksmuseum Data Services (no key). The old key-based API is gone (HTTP 410);
/// the new search is Linked Art with forward-only paging, so we cache the ~5,000
/// painting ids and refresh them monthly. Prints (390k) are too many to cache,
/// so this source offers paintings only, and it has no quality flag.
public struct RijksmuseumSource: ArtSource {
    public let id = SourceID.rijksmuseum
    public let info = SourceInfo(
        name: "Rijksmuseum",
        shortName: "the Rijksmuseum",
        supportedTypes: [.painting],
        hasQualityFlag: false,
        credit: "Data Services · public-domain images",
        homepage: URL(string: "https://data.rijksmuseum.nl/")!
    )

    private static let searchURL = URL.make("https://data.rijksmuseum.nl/search/collection", ["type": "painting", "imageAvailable": "true"])
    private static let maxPages = 200
    private let http: HTTPClient
    private let catalog: CatalogCache<String>

    public init(http: HTTPClient, store: CatalogStore) {
        self.http = http
        self.catalog = CatalogCache(name: "rijksmuseum-paintings", store: store, maxAge: 30 * 24 * 3600)
    }

    public func randomArtwork(for query: ArtworkQuery) async throws -> Artwork {
        guard query.objectTypes.contains(.painting) else { throw SourceError.noMatchingWorks }
        let ids = try await catalog.entries { try await fetchAllIDs() }
        let unseen = ids.filter { !query.excludedIDs.contains(Self.artworkID(for: $0)) }

        for objectURL in unseen.shuffled().prefix(ArtworkQuery.maxDraws) {
            guard let url = URL(string: objectURL) else { continue }
            let object = try await http.json(LinkedArtObject.self, from: url, headers: ["Accept": "application/ld+json"])
            if let artwork = object.artwork(id: Self.artworkID(for: objectURL)) { return artwork }
        }
        throw SourceError.noMatchingWorks
    }

    public func healthCheck(apiKey: String?) async throws {
        _ = try await http.json(LinkedArtPage.self, from: Self.searchURL)
    }

    /// Walks the search pages (100 ids each) to the end.
    func fetchAllIDs() async throws -> [String] {
        var ids: [String] = []
        var next: URL? = Self.searchURL
        var pages = 0
        while let url = next, pages < Self.maxPages {
            let page = try await http.json(LinkedArtPage.self, from: url)
            ids += page.orderedItems.map(\.id)
            next = page.next.flatMap { URL(string: $0.id) }
            pages += 1
        }
        return ids
    }

    /// "https://id.rijksmuseum.nl/200105887" → "rijks:200105887"
    static func artworkID(for objectURL: String) -> String {
        "rijks:" + (objectURL.split(separator: "/").last.map(String.init) ?? objectURL)
    }
}

struct LinkedArtPage: Decodable {
    struct Ref: Decodable { var id: String }
    var orderedItems: [Ref]
    var next: Ref?
}

/// Just enough of the Linked Art model to build a wall label.
/// Getty AAT ids used: 300388277 English, 300404670 name, 300048722 description,
/// 300435429 material statement, 300435430 dimensions statement, 300435417 creator.
struct LinkedArtObject: Decodable {
    var identified_by: [LANode]?
    var referred_to_by: [LANode]?
    var subject_of: [LANode]?
    var produced_by: LANode?

    func artwork(id: String) -> Artwork? {
        guard let image = imageURL else { return nil }
        let objectNumber = identified_by?.first { $0.type == "Identifier" }?.content
        return Artwork(
            id: id,
            sourceID: .rijksmuseum,
            title: englishTitle ?? "Untitled",
            artist: creator,
            date: produced_by?.timespan?.identified_by?.first { $0.isEnglish }?.content,
            medium: statement(LA.material).map { $0.prefix(1).uppercased() + $0.dropFirst() },
            dimensions: statement(LA.dimensions) { $0.contains("height") },
            museum: "Rijksmuseum, Amsterdam",
            summary: englishDescription,
            objectURL: objectNumber.flatMap { URL(string: "https://www.rijksmuseum.nl/en/collection/\($0)") },
            imageURL: image
        )
    }

    /// The public-domain IIIF image (iiif.micr.io), full size.
    private var imageURL: URL? {
        for subject in subject_of ?? [] {
            for carrier in subject.digitally_carried_by ?? [] {
                let licence = carrier.referred_to_by?.compactMap(\.content).joined() ?? ""
                guard licence.contains("publicdomain") else { continue }
                if let point = carrier.access_point?.first(where: { $0.id?.contains("iiif") == true })?.id {
                    return URL(string: point)
                }
            }
        }
        return nil
    }

    private var englishTitle: String? {
        // Prefer the curated short title in the English "brief text", then any English name.
        let brief = subject_of?.first { $0.isEnglish && $0.part != nil }?
            .part?.flatMap { $0.part ?? [] }.first { $0.type == "Name" }?.content
        return Text.clean(brief) ?? identified_by?.first { $0.type == "Name" && $0.isEnglish }?.content
    }

    private var englishDescription: String? {
        let part = subject_of?.first { $0.isEnglish && $0.part != nil }?
            .part?.first { $0.isClassified(LA.description) }?.content
        return Text.clean(part)
    }

    private var creator: String? {
        let statements = (produced_by?.part ?? [produced_by].compactMap { $0 })
            .flatMap { $0.referred_to_by ?? [] }
        let name = statements.first { $0.isClassified(LA.creator) && $0.isEnglish }?.content
        // "Henriëtte Ronner (mentioned on object)" → "Henriëtte Ronner"
        return Text.clean(name?.replacingOccurrences(of: "\\s*\\([^)]*\\)$", with: "", options: .regularExpression))
    }

    private func statement(_ aat: String, where match: (String) -> Bool = { _ in true }) -> String? {
        referred_to_by?.first { $0.isClassified(aat) && $0.isEnglish && match($0.content ?? "") }?.content
    }
}

enum LA {
    static let english = "300388277"
    static let description = "300048722"
    static let material = "300435429"
    static let dimensions = "300435430"
    static let creator = "300435417"
}

/// A generic Linked Art node; the format nests the same shapes everywhere.
final class LANode: Decodable {
    struct Ref: Decodable { var id: String? }
    struct Span: Decodable { var identified_by: [LANode]? }

    var id: String?
    var type: String?
    var content: String?
    var classified_as: [Ref]?
    var language: [Ref]?
    var part: [LANode]?
    var referred_to_by: [LANode]?
    var digitally_carried_by: [LANode]?
    var access_point: [Ref]?
    var timespan: Span?

    var isEnglish: Bool { language?.contains { $0.id?.hasSuffix(LA.english) == true } ?? false }
    func isClassified(_ aat: String) -> Bool { classified_as?.contains { $0.id?.hasSuffix(aat) == true } ?? false }
}
