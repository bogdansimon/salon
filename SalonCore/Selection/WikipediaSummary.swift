import Foundation

/// Fills in a description when the museum has none: Wikidata id → English
/// Wikipedia article → its REST summary.
public struct WikipediaSummary: Sendable {
    private let http: HTTPClient

    public init(http: HTTPClient) { self.http = http }

    public func summary(forWikidataID id: String) async -> String? {
        do {
            let entities = try await http.json(WBEntities.self, from: .make("https://www.wikidata.org/w/api.php", [
                "action": "wbgetentities", "format": "json", "ids": id, "props": "sitelinks", "sitefilter": "enwiki",
            ]))
            guard let title = entities.entities[id]?.sitelinks?["enwiki"]?.title else { return nil }
            let path = title.replacingOccurrences(of: " ", with: "_")
                .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))) ?? title
            let summary = try await http.json(RESTSummary.self, from: URL(string: "https://en.wikipedia.org/api/rest_v1/page/summary/\(path)")!)
            return Text.clean(summary.extract)
        } catch {
            return nil
        }
    }

    /// Returns the artwork with `summary` filled from Wikipedia when it was missing.
    public func enrich(_ artwork: Artwork) async -> Artwork {
        guard artwork.summary == nil, let id = artwork.wikidataID, let text = await summary(forWikidataID: id) else { return artwork }
        var enriched = artwork
        enriched.summary = text
        enriched.summaryCredit = "Wikipedia"
        return enriched
    }
}

struct RESTSummary: Decodable {
    var extract: String?
}
