import XCTest
@testable import SalonCore

final class ArtworkPickerTests: XCTestCase {
    private var cacheDirectory: URL!

    override func setUp() {
        cacheDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: cacheDirectory)
    }

    private func request(enabled: Set<SourceID>, excluded: Set<String> = []) -> ArtworkPicker.Request {
        ArtworkPicker.Request(objectTypes: [.painting], highlightsOnly: true, enabledSources: enabled, excludedIDs: excluded)
    }

    func testFallsBackWhenASourceFails() async throws {
        let http = FixtureHTTPClient()
        http.on("good.example/", data: TestImages.jpegData(width: 3200, height: 2000))
        let broken = StubSource(id: SourceID("broken"), error: .http(status: 503))
        let good = StubSource(id: SourceID("good"), sizes: [PixelSize(width: 3200, height: 2000)])
        let picker = ArtworkPicker(sources: [broken, good], http: http, cache: ImageCache(directory: cacheDirectory))
        let events = EventLog()

        let picked = try await picker.pick(request(enabled: [broken.id, good.id])) { id, event in await events.add(id, event) }

        XCTAssertEqual(picked.artwork.sourceID, good.id)
        XCTAssertEqual(picked.pixelSize, PixelSize(width: 3200, height: 2000))
        let log = await events.entries
        XCTAssertTrue(log.contains { $0.0 == good.id && $0.1 == "success" })
    }

    func testRejectsImagesBelowThreshold() async throws {
        let http = FixtureHTTPClient()
        http.on("good.example/", data: TestImages.jpegData(width: 2400, height: 1600))
        // The source doesn't report a size, so the picker must check the download.
        let source = StubSource(id: SourceID("good"), sizes: [nil, nil, nil])
        let picker = ArtworkPicker(sources: [source], http: http, cache: ImageCache(directory: cacheDirectory))

        do {
            _ = try await picker.pick(request(enabled: [source.id]))
            XCTFail("Expected failure")
        } catch SourceError.allSourcesFailed(let last) {
            XCTAssertTrue(last.contains("too small"), last)
        }
        XCTAssertEqual(ImageCache(directory: cacheDirectory).fileCount, 0, "rejected downloads are deleted")
    }

    func testReportedSmallSizeSkipsDownload() async throws {
        let http = FixtureHTTPClient()
        let small = PixelSize(width: 795, height: 1024)
        let source = StubSource(id: SourceID("good"), sizes: Array(repeating: small, count: ArtworkPicker.attemptsPerSource))
        let picker = ArtworkPicker(sources: [source], http: http, cache: ImageCache(directory: cacheDirectory))
        _ = try? await picker.pick(request(enabled: [source.id]))
        XCTAssertTrue(http.requests.isEmpty)
    }

    func testThreeThousandPixelsIsAccepted() async throws {
        let http = FixtureHTTPClient()
        http.on("good.example/", data: TestImages.jpegData(width: 3000, height: 2348))
        let source = StubSource(id: SourceID("good"), sizes: [PixelSize(width: 3000, height: 2348)])
        let picker = ArtworkPicker(sources: [source], http: http, cache: ImageCache(directory: cacheDirectory))
        let picked = try await picker.pick(request(enabled: [source.id]))
        XCTAssertEqual(picked.pixelSize.longSide, 3000)
    }

    func testPassesShownWorksToSources() async throws {
        let http = FixtureHTTPClient()
        http.on("good.example/", data: TestImages.jpegData(width: 3200, height: 2000))
        let source = StubSource(id: SourceID("good"), sizes: [PixelSize(width: 3200, height: 2000)])
        let picker = ArtworkPicker(sources: [source], http: http, cache: ImageCache(directory: cacheDirectory))
        _ = try await picker.pick(request(enabled: [source.id], excluded: ["good:old"]))
        let seen = await source.lastExcluded
        XCTAssertEqual(seen, ["good:old"])
    }

    func testDisabledAndUnsupportedSourcesAreSkipped() {
        let paintings = StubSource(id: SourceID("a"), sizes: [])
        let printsOnly = StubSource(id: SourceID("b"), sizes: [], types: [.print])
        let disabled = StubSource(id: SourceID("c"), sizes: [])
        let picker = ArtworkPicker(sources: [paintings, printsOnly, disabled], http: FixtureHTTPClient(), cache: ImageCache(directory: cacheDirectory))
        let order = picker.candidateOrder(for: request(enabled: [paintings.id, printsOnly.id]))
        XCTAssertEqual(order.map(\.id), [paintings.id])
    }

    func testFailingSourcesAreSkippedUnlessNothingElseIsLeft() {
        let a = StubSource(id: SourceID("a"), sizes: []), b = StubSource(id: SourceID("b"), sizes: [])
        let picker = ArtworkPicker(sources: [a, b], http: FixtureHTTPClient(), cache: ImageCache(directory: cacheDirectory))
        var req = request(enabled: [a.id, b.id])
        req.failingSources = [a.id]
        XCTAssertEqual(picker.candidateOrder(for: req).map(\.id), [b.id])
        req.failingSources = [a.id, b.id]
        XCTAssertEqual(Set(picker.candidateOrder(for: req).map(\.id)), [a.id, b.id])
    }

    func testKeyedSourceWithoutKeyIsSkipped() {
        let keyed = StubSource(id: SourceID("k"), sizes: [], needsKey: true)
        let picker = ArtworkPicker(sources: [keyed], http: FixtureHTTPClient(), cache: ImageCache(directory: cacheDirectory))
        XCTAssertTrue(picker.candidateOrder(for: request(enabled: [keyed.id])).isEmpty)
    }
}

/// A source that hands out numbered works with the given reported sizes, or fails.
actor StubSource: ArtSource {
    nonisolated let id: SourceID
    nonisolated let info: SourceInfo
    private var sizes: [PixelSize?]
    private let error: SourceError?
    private var counter = 0
    private(set) var lastExcluded: Set<String> = []

    init(id: SourceID, sizes: [PixelSize?] = [], error: SourceError? = nil, types: Set<ObjectType> = [.painting], needsKey: Bool = false) {
        self.id = id
        self.sizes = sizes
        self.error = error
        self.info = SourceInfo(name: id.rawValue, shortName: id.rawValue, supportedTypes: types, hasQualityFlag: true,
                               requiresAPIKey: needsKey, credit: "", homepage: URL(string: "https://example.org")!)
    }

    func randomArtwork(for query: ArtworkQuery) async throws -> Artwork {
        lastExcluded = query.excludedIDs
        if let error { throw error }
        counter += 1
        let size = sizes.isEmpty ? nil : sizes.removeFirst()
        return Artwork(id: "\(id.rawValue):\(counter)", sourceID: id, title: "Work \(counter)", museum: "Stub",
                       imageURL: URL(string: "https://\(id.rawValue).example/\(counter).jpg")!, reportedPixelSize: size)
    }

    func healthCheck(apiKey: String?) async throws {}
}

actor EventLog {
    private(set) var entries: [(SourceID, String)] = []
    func add(_ id: SourceID, _ event: HealthEvent) {
        switch event {
        case .success: entries.append((id, "success"))
        case .failure: entries.append((id, "failure"))
        }
    }
}
