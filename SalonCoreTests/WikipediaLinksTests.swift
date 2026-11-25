import XCTest
@testable import SalonCore

final class WikipediaLinksTests: XCTestCase {
    // MARK: Tiny Wikidata replies

    private func item(_ id: String) -> String {
        #"{"mainsnak":{"datavalue":{"type":"wikibase-entityid","value":{"id":"\#(id)"}}}}"#
    }

    private func time(_ year: Int) -> String {
        #"{"mainsnak":{"datavalue":{"type":"time","value":{"time":"+\#(year)-00-00T00:00:00Z"}}}}"#
    }

    private func entity(label: String, aliases: [String] = [], claims: [String: [String]] = [:], enwiki: String? = nil) -> String {
        let aliasJSON = aliases.map { #"{"value":"\#($0)"}"# }.joined(separator: ",")
        let claimJSON = claims.map { #""\#($0.key)":[\#($0.value.joined(separator: ","))]"# }.joined(separator: ",")
        let sitelinks = enwiki.map { #""sitelinks":{"enwiki":{"title":"\#($0)"}},"# } ?? ""
        return #"{\#(sitelinks)"labels":{"en":{"value":"\#(label)"}},"aliases":{"en":[\#(aliasJSON)]},"claims":{\#(claimJSON)}}"#
    }

    private func entities(_ pairs: [(String, String)]) -> Data {
        Data(#"{"entities":{\#(pairs.map { #""\#($0.0)":\#($0.1)"# }.joined(separator: ","))}}"#.utf8)
    }

    private func decode(_ json: String) throws -> WBEntity {
        try JSONDecoder().decode(WBEntity.self, from: Data(json.utf8))
    }

    private var rembrandt: String {
        entity(label: "Rembrandt", claims: ["P31": [item("Q5")], "P106": [item("Q1028181")], "P569": [time(1606)], "P570": [time(1669)]],
               enwiki: "Rembrandt")
    }

    private func artwork(title: String, artist: String?, details: String?, date: String? = nil) -> Artwork {
        Artwork(id: "rijks:1", sourceID: SourceID("rijks"), title: title, artist: artist, artistDetails: details, date: date,
                museum: "Rijksmuseum", imageURL: URL(string: "https://example.org/a.jpg")!)
    }

    // MARK: Search path

    func testLinksArtistAndWorkFoundBySearch() async throws {
        let http = FixtureHTTPClient()
        http.on("wbsearchentities", data: Data(#"{"search":[{"id":"Q5598"},{"id":"Q62743087"}]}"#.utf8))
        http.on("ids=Q5598|Q62743087", data: entities([
            ("Q5598", rembrandt),
            ("Q62743087", entity(label: "Rembrandt van Rijn", claims: ["P31": [item("Q3305213")]])),
        ]))
        http.on("list=search", data: Data(#"{"query":{"search":[{"title":"Q219831"},{"title":"Q119877393"}]}}"#.utf8))
        http.on("ids=Q219831|Q119877393", data: entities([
            ("Q219831", entity(label: "The Night Watch", aliases: ["Night Watch"], claims: ["P170": [item("Q5598")], "P571": [time(1642)]],
                               enwiki: "The Night Watch")),
            ("Q119877393", entity(label: "The Night Watch", claims: ["P170": [item("Q5598")], "P571": [time(1700)]])),
        ]))

        let work = artwork(title: "Night Watch, Militia Company of District II under the Command of Captain Frans Banninck Cocq",
                           artist: "Rembrandt van Rijn", details: "Dutch, 1606–1669", date: "1642")
        let linked = await WikipediaLinks(http: http).enrich(work)

        XCTAssertEqual(linked.artistWikipediaURL?.absoluteString, "https://en.wikipedia.org/wiki/Rembrandt")
        XCTAssertEqual(linked.titleWikipediaURL?.absoluteString, "https://en.wikipedia.org/wiki/The_Night_Watch")
        XCTAssertEqual(linked.wikidataID, "Q219831", "the year picks the original over the copy")
        XCTAssertTrue(http.requestURLs().contains { $0.contains("haswbstatement:P170=Q5598") }, "works are searched by that artist only")
    }

    func testVersionsSharingOneArticleLinkIt() async throws {
        let version = { (year: Int) in self.entity(label: "Sunflowers", claims: ["P170": [self.item("Q5598")], "P571": [self.time(year)]], enwiki: "Sunflowers (Van Gogh series)") }
        let http = FixtureHTTPClient()
        http.on("wbsearchentities", data: Data(#"{"search":[{"id":"Q5598"}]}"#.utf8))
        http.on("ids=Q5598", data: entities([("Q5598", rembrandt)]))
        http.on("list=search", data: Data(#"{"query":{"search":[{"title":"Q1"},{"title":"Q2"}]}}"#.utf8))
        http.on("ids=Q1|Q2", data: entities([("Q1", version(1888)), ("Q2", version(1889))]))

        let linked = await WikipediaLinks(http: http).enrich(artwork(title: "Sunflowers", artist: "Rembrandt", details: nil))

        XCTAssertEqual(linked.titleWikipediaURL?.absoluteString, "https://en.wikipedia.org/wiki/Sunflowers_(Van_Gogh_series)")
    }

    func testNoLinkWhenLifeDatesDisagree() async throws {
        let http = FixtureHTTPClient()
        http.on("wbsearchentities", data: Data(#"{"search":[{"id":"Q5598"}]}"#.utf8))
        http.on("wbgetentities", data: entities([("Q5598", rembrandt)]))

        let linked = await WikipediaLinks(http: http).enrich(artwork(title: "A Mill", artist: "Rembrandt", details: "American, 1950–2010"))

        XCTAssertNil(linked.artistWikipediaURL)
        XCTAssertNil(linked.titleWikipediaURL)
    }

    func testNoArtistLinkWhenTwoArtistsShareTheNameAndThereAreNoDates() async throws {
        let painter = { (born: Int) in self.entity(label: "Jan Brueghel", claims: ["P31": [self.item("Q5")], "P106": [self.item("Q1028181")], "P569": [self.time(born)]], enwiki: "Jan Brueghel \(born)") }
        let http = FixtureHTTPClient()
        http.on("wbsearchentities", data: Data(#"{"search":[{"id":"Q1"},{"id":"Q2"}]}"#.utf8))
        http.on("wbgetentities", data: entities([("Q1", painter(1568)), ("Q2", painter(1601))]))

        let linked = await WikipediaLinks(http: http).enrich(artwork(title: "Flowers", artist: "Jan Brueghel", details: nil))

        XCTAssertNil(linked.artistWikipediaURL)
    }

    func testKnownWikidataIDLinksBothWithoutSearching() async throws {
        let http = FixtureHTTPClient()
        http.on("ids=Q467376", data: entities([("Q467376", entity(label: "Officer and Laughing Girl", claims: ["P170": [item("Q41264")]], enwiki: "Officer and Laughing Girl"))]))
        http.on("ids=Q41264", data: entities([("Q41264", entity(label: "Johannes Vermeer", claims: ["P31": [item("Q5")]], enwiki: "Johannes Vermeer"))]))
        var work = artwork(title: "Officer and Laughing Girl", artist: "Johannes Vermeer", details: "Dutch, 1632–1675")
        work.wikidataID = "Q467376"

        let linked = await WikipediaLinks(http: http).enrich(work)

        XCTAssertEqual(linked.titleWikipediaURL?.absoluteString, "https://en.wikipedia.org/wiki/Officer_and_Laughing_Girl")
        XCTAssertEqual(linked.artistWikipediaURL?.absoluteString, "https://en.wikipedia.org/wiki/Johannes_Vermeer")
        XCTAssertFalse(http.requestURLs().contains { $0.contains("search") })
    }

    func testNetworkFailureLeavesArtworkUnlinked() async {
        let work = artwork(title: "The Night Watch", artist: "Rembrandt", details: nil)
        let linked = await WikipediaLinks(http: FixtureHTTPClient()).enrich(work)
        XCTAssertEqual(linked, work)
    }

    // MARK: Checks

    func testLifeDates() throws {
        let person = try decode(rembrandt)
        XCTAssertTrue(WikipediaLinks.lifeMatches(person, details: "Dutch, Leiden 1606–1669 Amsterdam"))
        XCTAssertTrue(WikipediaLinks.lifeMatches(person, details: "Dutch, 1606/07–1669"))
        XCTAssertTrue(WikipediaLinks.lifeMatches(person, details: "born 1606"))
        XCTAssertTrue(WikipediaLinks.lifeMatches(person, details: "active 1625–1665"))
        XCTAssertTrue(WikipediaLinks.lifeMatches(person, details: "Dutch"))
        XCTAssertFalse(WikipediaLinks.lifeMatches(person, details: "Dutch, 1632–1675"))
        XCTAssertFalse(WikipediaLinks.lifeMatches(person, details: "active 1700–1720"))
    }

    func testTitleMatching() {
        XCTAssertTrue(WikipediaLinks.titleMatches("The Night-Watch", ["Night Watch"]))
        XCTAssertTrue(WikipediaLinks.titleMatches("Night Watch, Militia Company of District II", ["The Night Watch"]))
        XCTAssertTrue(WikipediaLinks.titleMatches("Les Demoiselles d’Avignon", ["Les Demoiselles d'Avignon"]))
        XCTAssertFalse(WikipediaLinks.titleMatches("Portrait of a Woman", ["Portrait of a Man"]))
    }

    func testNamedArtist() {
        XCTAssertTrue(WikipediaLinks.isNamedArtist("Vincent van Gogh"))
        for name in ["Workshop of Rubens", "Unknown artist", "After Raphael", "Rembrandt and pupils", "Circle of Titian", nil] {
            XCTAssertFalse(WikipediaLinks.isNamedArtist(name), name ?? "nil")
        }
    }
}
