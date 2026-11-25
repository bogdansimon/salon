import Foundation

/// Fills in a description when the museum has none: Wikidata id → English
/// Wikipedia article → its REST summary.
public struct WikipediaSummary: Sendable {
    private let http: HTTPClient

    public init(http: HTTPClient) { self.http = http }

    public func summary(forWikidataID id: String) async -> String? {
        await article(forWikidataID: id)?.text
    }

    /// The summary text and the article it came from.
    func article(forWikidataID id: String) async -> (text: String, url: URL)? {
        do {
            let entities = try await http.json(WBEntities.self, from: .make("https://www.wikidata.org/w/api.php", [
                "action": "wbgetentities", "format": "json", "ids": id, "props": "sitelinks", "sitefilter": "enwiki",
            ]))
            guard let page = entities.entities[id]?.englishWikipediaURL else { return nil }
            let summary = try await http.json(RESTSummary.self, from: URL(string: "https://en.wikipedia.org/api/rest_v1/page/summary/\(page.lastPathComponentEncoded)")!)
            guard let text = Text.clean(summary.extract) else { return nil }
            return (text, page)
        } catch {
            return nil
        }
    }

    /// Returns the artwork with `summary` filled from Wikipedia when it was missing.
    public func enrich(_ artwork: Artwork) async -> Artwork {
        guard artwork.summary == nil, let id = artwork.wikidataID, let found = await article(forWikidataID: id) else { return artwork }
        var enriched = artwork
        enriched.summary = found.text
        enriched.summaryCredit = "Wikipedia"
        enriched.summaryURL = found.url
        return enriched
    }
}

private extension URL {
    /// The last path segment still percent-encoded ("Saul_and_David_(Rembrandt)").
    var lastPathComponentEncoded: String { absoluteString.components(separatedBy: "/").last ?? "" }
}

struct RESTSummary: Decodable {
    var extract: String?
}
