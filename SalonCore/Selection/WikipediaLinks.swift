import Foundation

/// Finds the English Wikipedia pages for a work's artist and title, so the wall
/// label can link them. A wrong link is worse than none, so every match is checked:
///
/// - Artist: a Wikidata person whose occupation is an artist's and whose life
///   dates agree with the museum's ("Dutch, 1632–1675" → born 1632, died 1675).
/// - Work: a Wikidata item by that same artist whose title matches; when several
///   match, only the one whose year also matches.
///
/// When the source already gives the work's Wikidata id, both come straight from it.
public struct WikipediaLinks: Sendable {
    private let http: HTTPClient
    private static let api = "https://www.wikidata.org/w/api.php"
    /// Short, so a slow Wikidata never holds up a wallpaper change for long.
    private static let timeout: TimeInterval = 8

    public init(http: HTTPClient) { self.http = http }

    /// Returns the artwork with `artistWikipediaURL` / `titleWikipediaURL` filled where
    /// a page was found. A work matched by search also gets its `wikidataID`, which lets
    /// `WikipediaSummary` fill a missing description.
    public func enrich(_ artwork: Artwork) async -> Artwork {
        var result = artwork
        do {
            if let id = artwork.wikidataID {
                guard let work = try await entities([id])[id] else { return result }
                result.titleWikipediaURL = work.englishWikipediaURL
                if Self.isNamedArtist(artwork.artist), let creatorID = work.itemID("P170"),
                   let creator = try await entities([creatorID])[creatorID], creator.isHuman {
                    result.artistWikipediaURL = creator.englishWikipediaURL
                }
                return result
            }

            guard let name = artwork.artist, let (artistID, artist) = try await findArtist(name: name, details: artwork.artistDetails) else {
                return result
            }
            result.artistWikipediaURL = artist.englishWikipediaURL
            if let (workID, work) = try await findWork(title: artwork.title, year: Self.firstYear(in: artwork.date), artistID: artistID) {
                result.titleWikipediaURL = work.englishWikipediaURL
                result.wikidataID = workID
            }
        } catch {
            // Network trouble: keep whatever was found so far.
        }
        return result
    }

    // MARK: Artist

    func findArtist(name: String, details: String?) async throws -> (String, WBEntity)? {
        guard Self.isNamedArtist(name) else { return nil }
        let hits = try await get(WBSearch.self, [
            "action": "wbsearchentities", "format": "json", "language": "en", "uselang": "en",
            "type": "item", "limit": "10", "search": name,
        ]).search.map(\.id)
        guard !hits.isEmpty else { return nil }
        let found = try await entities(hits)
        let people = hits.compactMap { id in found[id].map { (id, $0) } }
            .filter { $0.1.isHuman && $0.1.isArtist && Self.lifeMatches($0.1, details: details) }
        // Without dates to check, a name shared by two artists (Jan Brueghel the Elder
        // and the Younger) can't be told apart: link neither.
        if Self.years(in: details).isEmpty { return people.count == 1 ? people[0] : nil }
        return people.first
    }

    /// Wikidata occupations that make someone "an artist" for linking purposes.
    static let artistOccupations: Set<String> = [
        "Q1028181", // painter
        "Q483501", // artist
        "Q3391743", // visual artist
        "Q11569986", // printmaker
        "Q15296811", // draftsperson
        "Q329439", // engraver
        "Q10862983", // etcher
        "Q16947657", // lithographer
        "Q1925963", // graphic artist
        "Q644687", // illustrator
        "Q1281618", // sculptor
        "Q33231", // photographer
        "Q42973", // architect
        "Q5322166", // designer
        "Q7541856", // ceramicist
        "Q3303330", // calligrapher
        "Q21550646", // stained-glass artist
    ]

    /// "Workshop of Rubens", "Unknown", "Rembrandt and pupils": not one person to link.
    static func isNamedArtist(_ name: String?) -> Bool {
        guard let name = Text.clean(name)?.lowercased() else { return false }
        let markers = ["unknown", "anonymous", "workshop", "studio of", "follower", "circle of", "school", "attributed",
                       "manner of", "style of", "after ", "copy", "possibly", "probably", " and ", " & ", ";"]
        return !markers.contains { name.contains($0) }
    }

    /// Do the museum's dates fit this person? "Dutch, 1853–1890" must match birth and death
    /// (within 2 years); "active 1650–1670" must fall within the lifetime. No dates: fits.
    static func lifeMatches(_ person: WBEntity, details: String?) -> Bool {
        let years = years(in: details)
        guard let first = years.first else { return true }
        let born = person.year("P569").flatMap { Int($0) }
        let died = person.year("P570").flatMap { Int($0) }
        let lower = details?.lowercased() ?? ""
        if ["active", "fl.", "working", "documented"].contains(where: lower.contains) {
            guard born != nil || died != nil else { return false }
            let from = (born ?? died! - 90) - 2, to = (died ?? born! + 100) + 2
            return years.allSatisfy { (from...to).contains($0) }
        }
        guard let born, abs(first - born) <= 2 else { return false }
        if years.count >= 2 {
            guard let died, abs(years[1] - died) <= 2 else { return false }
        }
        return true
    }

    // MARK: Work

    func findWork(title: String, year: Int?, artistID: String) async throws -> (String, WBEntity)? {
        var hits = try await searchWorks(title, by: artistID)
        let main = Self.mainTitle(title)
        if hits.isEmpty, main != title { hits = try await searchWorks(main, by: artistID) }
        guard !hits.isEmpty else { return nil }

        let found = try await entities(hits)
        let matches = hits.compactMap { id in found[id].map { (id, $0) } }
            .filter { $0.1.itemIDs("P170").contains(artistID) && Self.titleMatches(title, $0.1.englishTitles) }
        if matches.count == 1 { return matches[0] }
        // Versions that share one article (Van Gogh's three "Bedroom"s): any of them links right.
        let pages = Set(matches.map { $0.1.englishWikipediaURL })
        if pages.count == 1, pages.first! != nil { return matches[0] }
        // Several works by the artist share the title (a copy, or many "Portrait of a Man"):
        // only the year can tell them apart.
        guard let year else { return nil }
        let dated = matches.filter { work in work.1.year("P571").flatMap { Int($0) }.map { abs($0 - year) <= 5 } ?? false }
        return dated.count == 1 ? dated[0] : nil
    }

    private func searchWorks(_ title: String, by artistID: String) async throws -> [String] {
        // Drop characters the search treats as operators.
        let text = title.replacingOccurrences(of: "[\"~*?\\\\]", with: " ", options: .regularExpression)
        return try await get(WQuerySearch.self, [
            "action": "query", "format": "json", "list": "search", "srnamespace": "0", "srlimit": "20",
            "srsearch": "\(text) haswbstatement:P170=\(artistID)",
        ]).query.search.map(\.title)
    }

    /// The museum's title matches when it, or its part before a comma, colon or
    /// bracket, equals a Wikidata label or alias (or that label's own main part).
    /// "Night Watch, Militia Company of District II…" matches the alias "Night Watch".
    static func titleMatches(_ title: String, _ labels: [String]) -> Bool {
        let ours = Set([normalize(title), normalize(mainTitle(title))])
        return labels.contains { label in !ours.isDisjoint(with: [normalize(label), normalize(mainTitle(label))]) }
    }

    /// "Night Watch, Militia Company…" → "Night Watch".
    static func mainTitle(_ title: String) -> String {
        let cut = title.range(of: "[,:;(\\[]| – | — | - ", options: .regularExpression)?.lowerBound ?? title.endIndex
        return Text.clean(String(title[..<cut])) ?? title
    }

    /// Lowercase, no accents or punctuation, no leading article: "The Night-Watch" → "night watch".
    static func normalize(_ text: String) -> String {
        var s = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        s = s.replacingOccurrences(of: "[^\\p{L}\\p{N}]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        for article in ["the ", "a ", "an "] where s.hasPrefix(article) { s = String(s.dropFirst(article.count)) }
        return s
    }

    // MARK: Helpers

    /// Every 3–4 digit number: "Dutch, Zundert 1853–1890 Auvers" → [1853, 1890].
    static func years(in text: String?) -> [Int] {
        guard let text else { return [] }
        return text.matches(of: /\d+/).compactMap { $0.output.count >= 3 && $0.output.count <= 4 ? Int($0.output) : nil }
    }

    static func firstYear(in text: String?) -> Int? { years(in: text).first }

    private func entities(_ ids: [String]) async throws -> [String: WBEntity] {
        try await get(WBEntities.self, [
            "action": "wbgetentities", "format": "json", "ids": ids.prefix(50).joined(separator: "|"),
            "props": "labels|aliases|claims|sitelinks", "languages": "en", "sitefilter": "enwiki",
        ]).entities
    }

    private func get<T: Decodable>(_ type: T.Type, _ query: [String: String]) async throws -> T {
        var request = URLRequest(url: .make(Self.api, query))
        request.timeoutInterval = Self.timeout
        return try await http.json(type, from: request)
    }
}

struct WBSearch: Decodable {
    struct Hit: Decodable { var id: String }
    var search: [Hit]
}

struct WQuerySearch: Decodable {
    struct Hit: Decodable { var title: String }
    struct Query: Decodable { var search: [Hit] }
    var query: Query
}

extension WBEntity {
    var isHuman: Bool { itemIDs("P31").contains("Q5") }
    var isArtist: Bool { !WikipediaLinks.artistOccupations.isDisjoint(with: itemIDs("P106")) }

    /// English label plus English aliases.
    var englishTitles: [String] { [englishLabel].compactMap { $0 } + (aliases?["en"] ?? []).map(\.value) }

    var englishWikipediaURL: URL? {
        guard let title = sitelinks?["enwiki"]?.title else { return nil }
        let path = title.replacingOccurrences(of: " ", with: "_")
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?"))) ?? title
        return URL(string: "https://en.wikipedia.org/wiki/\(path)")
    }
}
