import XCTest
@testable import SalonCore

/// Each adapter against recorded, scrubbed responses (no live calls).
final class SourceAdapterTests: XCTestCase {
    private let paintings = ArtworkQuery(objectTypes: [.painting], highlightsOnly: true)

    func testMet() async throws {
        let http = FixtureHTTPClient()
        http.on("/v1.1/search", fixture: "met_search.json")
        http.on("/v1/objects/", fixture: "met_object.json")

        let artwork = try await MetSource(http: http).randomArtwork(for: paintings)

        XCTAssertEqual(artwork.id, "met:436535")
        XCTAssertEqual(artwork.title, "Wheat Field with Cypresses")
        XCTAssertEqual(artwork.artist, "Vincent van Gogh")
        XCTAssertEqual(artwork.date, "1889")
        XCTAssertEqual(artwork.dimensions, "73.2 × 93.4 cm")
        XCTAssertEqual(artwork.wikidataID, "Q18689458")
        XCTAssertEqual(artwork.imageURL.host, "images.metmuseum.org")
        XCTAssertNil(artwork.summary, "The Met has no descriptions; Wikipedia fills them in later")
        let search = try XCTUnwrap(http.requestURLs().first)
        XCTAssertTrue(search.contains("isHighlight=true"))
        XCTAssertTrue(search.contains("medium=Paintings"))
    }

    func testArtInstitute() async throws {
        let http = FixtureHTTPClient()
        http.on("api.artic.edu/api/v1/artworks/search", fixture: "aic_search.json")

        let artwork = try await ArtInstituteSource(http: http).randomArtwork(for: paintings)

        XCTAssertEqual(artwork.id, "aic:28560")
        XCTAssertEqual(artwork.title, "The Bedroom")
        XCTAssertEqual(artwork.artist, "Vincent van Gogh")
        XCTAssertEqual(artwork.artistDetails, "Dutch, 1853–1890")
        XCTAssertEqual(artwork.dimensions, "73.6 × 92.3 cm")
        XCTAssertEqual(artwork.reportedPixelSize?.longSide, 3000, "IIIF is capped at 3000 px")
        XCTAssertTrue(artwork.imageURL.absoluteString.hasSuffix("/full/3000,/0/default.jpg"))
        XCTAssertEqual(artwork.imageRequestHeaders?["AIC-User-Agent"], SalonHTTP.userAgent)
        let summary = try XCTUnwrap(artwork.summary)
        XCTAssertFalse(summary.contains("<p>"), "HTML is stripped")
        XCTAssertTrue(summary.hasPrefix("Perhaps the most famous depiction of a bedroom"))
    }

    func testArtInstituteSendsHighlightFilter() async throws {
        let http = FixtureHTTPClient()
        http.on("api.artic.edu", fixture: "aic_search.json")
        _ = try await ArtInstituteSource(http: http).randomArtwork(for: paintings)
        let body = try XCTUnwrap(http.requests.first?.httpBody.flatMap { String(data: $0, encoding: .utf8) })
        XCTAssertTrue(body.contains("is_boosted"))
        XCTAssertTrue(body.contains("is_public_domain"))
    }

    func testCleveland() async throws {
        let http = FixtureHTTPClient()
        http.on("openaccess-api.clevelandart.org", fixture: "cma_search.json")

        let artwork = try await ClevelandSource(http: http).randomArtwork(for: paintings)

        XCTAssertEqual(artwork.id, "cma:135382")
        XCTAssertEqual(artwork.title, "The Red Kerchief")
        XCTAssertEqual(artwork.artist, "Claude Monet")
        XCTAssertEqual(artwork.artistDetails, "French, 1840–1926")
        XCTAssertEqual(artwork.medium, "Oil on fabric")
        XCTAssertEqual(artwork.dimensions, "99 × 79.8 cm")
        XCTAssertEqual(artwork.reportedPixelSize, PixelSize(width: 2732, height: 3400))
        XCTAssertTrue(artwork.summary?.hasPrefix("Madame Monet’s red cape") ?? false, "did_you_know is preferred")
        XCTAssertTrue(http.requestURLs().first?.contains("highlight=1") ?? false)
    }

    func testRijksmuseumWalksCatalogueThenParsesLinkedArt() async throws {
        let http = FixtureHTTPClient()
        http.on("pageToken=", fixture: "rijks_search_last.json")
        http.on("data.rijksmuseum.nl/search/collection", fixture: "rijks_search_first.json")
        http.on("id.rijksmuseum.nl/", fixture: "rijks_object.json")
        let store = MemoryCatalogStore()

        let source = RijksmuseumSource(http: http, store: store)
        let ids = try await source.fetchAllIDs()
        XCTAssertGreaterThan(ids.count, 100, "first page (100) plus the last page")

        let artwork = try await source.randomArtwork(for: paintings)
        XCTAssertEqual(artwork.title, "Cat at Play")
        XCTAssertEqual(artwork.artist, "Henriëtte Ronner")
        XCTAssertEqual(artwork.medium, "Oil on panel")
        XCTAssertEqual(artwork.date, "c. 1860 - c. 1878")
        XCTAssertEqual(artwork.objectURL?.absoluteString, "https://www.rijksmuseum.nl/en/collection/SK-A-3089")
        XCTAssertEqual(artwork.imageURL.host, "iiif.micr.io")
        XCTAssertTrue(artwork.summary?.hasPrefix("A young cat plays with dominoes") ?? false)
        XCTAssertNotNil(store.files["rijksmuseum-paintings"], "catalogue is cached")
    }

    func testRijksmuseumOffersPaintingsOnly() async {
        let source = RijksmuseumSource(http: FixtureHTTPClient(), store: MemoryCatalogStore())
        do {
            _ = try await source.randomArtwork(for: ArtworkQuery(objectTypes: [.print], highlightsOnly: false))
            XCTFail("Expected noMatchingWorks")
        } catch {
            XCTAssertEqual(error as? SourceError, .noMatchingWorks)
        }
    }

    func testSMKUsesExhibitionHistoryAsHighlight() async throws {
        let http = FixtureHTTPClient()
        http.on("api.smk.dk", fixture: "smk_search.json")

        let artwork = try await SMKSource(http: http).randomArtwork(for: paintings)

        XCTAssertTrue(artwork.id.hasPrefix("smk:"))
        XCTAssertEqual(artwork.museum, "SMK – National Gallery of Denmark, Copenhagen")
        XCTAssertNotNil(artwork.reportedPixelSize)
        let items = try JSONDecoder().decode(SMKSearch.self, from: Fixtures.data("smk_search.json")).items ?? []
        let picked = try XCTUnwrap(items.first { "smk:\($0.object_number)" == artwork.id })
        XCTAssertTrue(picked.hasExhibitionHistory)
    }

    func testSMKArtistDetails() throws {
        let item = try XCTUnwrap(JSONDecoder().decode(SMKSearch.self, from: Fixtures.data("smk_search.json")).items?.first)
        let maker = try XCTUnwrap(item.production?.first)
        XCTAssertNotNil(SMKItem.name(of: maker))
        XCTAssertNotNil(SMKItem.details(of: maker)?.range(of: "[0-9]{4}–[0-9]{4}", options: .regularExpression))
    }

    func testWikidata() async throws {
        let http = FixtureHTTPClient()
        http.on("query.wikidata.org/sparql", fixture: "wikidata_sparql.json")
        http.on("props=labels|claims", fixture: "wikidata_entity.json")
        http.on("wbgetentities", fixture: "wikidata_labels.json")
        http.on("commons.wikimedia.org", fixture: "commons_imageinfo.json")

        let source = WikidataSource(http: http, store: MemoryCatalogStore())
        let catalog = try await source.fetchCatalog()
        XCTAssertEqual(catalog.count, 3)
        XCTAssertTrue(catalog.contains { $0.id == "Q12418" && $0.sitelinks > 100 }, "Mona Lisa")

        let entry = try XCTUnwrap(catalog.first { $0.id == "Q467376" })
        let maybeArtwork = try await source.artwork(for: entry)
        let artwork = try XCTUnwrap(maybeArtwork)
        XCTAssertEqual(artwork.title, "Officer and Laughing Girl")
        XCTAssertEqual(artwork.artist, "Johannes Vermeer")
        XCTAssertEqual(artwork.museum, "The Frick Collection")
        XCTAssertEqual(artwork.date, "1658")
        XCTAssertEqual(artwork.medium, "Oil paint")
        XCTAssertEqual(artwork.dimensions, "50.5 × 46 cm")
        XCTAssertEqual(artwork.reportedPixelSize, PixelSize(width: 4096, height: 4462))
        XCTAssertEqual(artwork.wikidataID, "Q467376")
    }

    func testSmithsonianNeedsKeyAndRejectsSmallImages() async throws {
        let source = SmithsonianSource(http: FixtureHTTPClient())
        do {
            _ = try await source.randomArtwork(for: paintings)
            XCTFail("Expected missingAPIKey")
        } catch {
            XCTAssertEqual(error as? SourceError, .missingAPIKey)
        }

        let row = try XCTUnwrap(JSONDecoder().decode(SISearch.self, from: Fixtures.data("si_search.json")).response.rows.first)
        let artwork = try XCTUnwrap(row.artwork)
        XCTAssertEqual(artwork.artist, "Abraham Walkowitz")
        XCTAssertEqual(artwork.dimensions, "35.8 × 28.1 cm")
        XCTAssertEqual(artwork.museum, "Hirshhorn Museum and Sculpture Garden")
        XCTAssertEqual(artwork.reportedPixelSize, PixelSize(width: 795, height: 1024), "the picker will reject this one")
    }

    func testWikipediaSummaryFillsMissingDescription() async throws {
        let http = FixtureHTTPClient()
        http.on("wbgetentities", fixture: "wikidata_entity.json")
        http.on("en.wikipedia.org/api/rest_v1/page/summary/", fixture: "wikipedia_summary.json")
        let bare = Artwork(id: "x:1", sourceID: .met, title: "Officer and Laughing Girl", museum: "The Frick Collection",
                           wikidataID: "Q467376", imageURL: URL(string: "https://example.org/a.jpg")!)

        let enriched = await WikipediaSummary(http: http).enrich(bare)

        XCTAssertEqual(enriched.summaryCredit, "Wikipedia")
        XCTAssertTrue(enriched.summary?.hasPrefix("Officer and Laughing Girl") ?? false)
        XCTAssertTrue(http.requestURLs().last?.hasSuffix("/Officer_and_Laughing_Girl") ?? false)
    }
}
