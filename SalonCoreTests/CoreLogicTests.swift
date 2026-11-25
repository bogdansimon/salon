import XCTest
@testable import SalonCore

final class ScheduleTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Amsterdam")!
        return calendar
    }()

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    private func schedule(_ frequency: ChangeFrequency = .daily, _ hour: Int = 9, _ minute: Int = 0) -> ChangeSchedule {
        ChangeSchedule(frequency: frequency, time: TimeOfDay(hour: hour, minute: minute), calendar: calendar)
    }

    func testDueWhenNeverChanged() {
        XCTAssertTrue(schedule().isChangeDue(lastChange: nil, now: date(8, 8)))
    }

    func testNotDueBeforeTodaysTimeIfChangedYesterdayAfterTime() {
        XCTAssertFalse(schedule().isChangeDue(lastChange: date(7, 9, 5), now: date(8, 8, 59)))
    }

    func testDueAfterTodaysTime() {
        XCTAssertTrue(schedule().isChangeDue(lastChange: date(7, 9, 5), now: date(8, 9, 0)))
    }

    func testMissedDaysAfterSleepAreDue() {
        XCTAssertTrue(schedule().isChangeDue(lastChange: date(4, 9), now: date(8, 7)))
    }

    func testChangeByHandRestartsTheCount() {
        // Next pressed at 08:00, before the 09:00 change: the next one is tomorrow.
        XCTAssertEqual(schedule().dueDate(lastChange: date(8, 8)), date(9, 9))
        XCTAssertEqual(schedule(.weekly).dueDate(lastChange: date(11, 15)), date(18, 9))
    }

    func testFrequencies() {
        XCTAssertEqual(schedule(.everyTwoDays, 9, 30).dueDate(lastChange: date(8, 9, 30)), date(10, 9, 30))
        XCTAssertEqual(schedule(.weekly).dueDate(lastChange: date(2, 9)), date(9, 9))
        XCTAssertEqual(schedule(.monthly).dueDate(lastChange: date(8, 9)),
                       calendar.date(from: DateComponents(year: 2026, month: 12, day: 8, hour: 9)))
    }

    func testMonthlyFromTheLastDayOfAMonth() {
        let jan31 = calendar.date(from: DateComponents(year: 2027, month: 1, day: 31, hour: 9))!
        XCTAssertEqual(schedule(.monthly).dueDate(lastChange: jan31),
                       calendar.date(from: DateComponents(year: 2027, month: 2, day: 28, hour: 9)))
    }

    func testPausedIsNeverDue() {
        XCTAssertNil(schedule(.never).dueDate(lastChange: date(1, 9)))
        XCTAssertFalse(schedule(.never).isChangeDue(lastChange: date(1, 9), now: date(30, 9)))
    }

    func testNotBeforeHoldsBackAnOverdueChange() {
        // Resumed at 15:00 on the 8th after a long pause: wait for 09:00 on the 9th.
        let s = schedule()
        XCTAssertFalse(s.isChangeDue(lastChange: date(1, 9), notBefore: date(9, 9), now: date(8, 18)))
        XCTAssertTrue(s.isChangeDue(lastChange: date(1, 9), notBefore: date(9, 9), now: date(9, 9)))
    }

    func testNextTime() {
        XCTAssertEqual(schedule(.daily, 9, 30).nextTime(after: date(8, 8)), date(8, 9, 30))
        XCTAssertEqual(schedule(.daily, 9, 30).nextTime(after: date(8, 10)), date(9, 9, 30))
    }

    func testBackoff() {
        XCTAssertEqual(RetryBackoff.delay(afterFailures: 1), 15 * 60)
        XCTAssertEqual(RetryBackoff.delay(afterFailures: 2), 30 * 60)
        XCTAssertEqual(RetryBackoff.delay(afterFailures: 4), 2 * 3600)
        XCTAssertEqual(RetryBackoff.delay(afterFailures: 10), 4 * 3600)
    }
}

final class HealthTests: XCTestCase {
    func testStatusTransitions() {
        var health = SourceHealth()
        XCTAssertEqual(health.status, .unknown)
        health.recordSuccess(latency: 0.4)
        XCTAssertEqual(health.status, .healthy)
        health.recordSuccess(latency: 9)
        XCTAssertEqual(health.status, .degraded, "slow answers degrade")
        health.recordFailure(SourceError.http(status: 500))
        XCTAssertEqual(health.status, .degraded)
        health.recordFailure(SourceError.http(status: 500))
        health.recordFailure(SourceError.http(status: 500))
        XCTAssertEqual(health.status, .failing)
        health.recordSuccess(latency: 0.3)
        XCTAssertEqual(health.status, .healthy)
        XCTAssertNil(health.lastError)
    }
}

final class SettingsTests: XCTestCase {
    func testEmptyFileGivesDefaults() throws {
        let settings = try JSONDecoder.salon.decode(AppSettings.self, from: Data("{}".utf8))
        XCTAssertEqual(settings, AppSettings())
        XCTAssertEqual(settings.objectTypes, [.painting])
        XCTAssertTrue(settings.highlightsOnly)
        XCTAssertEqual(settings.changeFrequency, .daily)
        XCTAssertFalse(settings.notifyOnChange)
        XCTAssertFalse(settings.alwaysUseMat)
        XCTAssertEqual(settings.matStyle, .auto)
        XCTAssertEqual(settings.matMargin, .flush)
        XCTAssertFalse(settings.avoidDock)
        XCTAssertEqual(settings.nextShortcut?.displayString, "⌃⌥⌘N")
    }

    func testRoundTrip() throws {
        var settings = AppSettings()
        settings.matStyle = .custom(SRGBColor(hex: "#336699")!)
        settings.objectTypes = [.painting, .drawing]
        settings.sourceEnabled = [.rijksmuseum: false]
        settings.nextShortcut = nil
        let decoded = try JSONDecoder.salon.decode(AppSettings.self, from: JSONEncoder.salon.encode(settings))
        XCTAssertEqual(decoded, settings)
    }

    func testSettingsNeverContainAPIKeys() throws {
        let json = String(decoding: try JSONEncoder.salon.encode(AppSettings()), as: UTF8.self).lowercased()
        XCTAssertNil(json.range(of: "api_?key|token|secret", options: .regularExpression), "API keys belong in the Keychain only")
    }
}

final class PaletteTests: XCTestCase {
    func testOKLabRoundTrip() {
        let color = SRGBColor(hex: "#7A5C22")!
        XCTAssertEqual(color.oklab.rgb.hex, "#7A5C22")
    }

    func testDarkPaintingGetsDeepMatLighterThanEdge() {
        let umber = SRGBColor(hex: "#1E150F")!
        let mat = PaletteRules.autoMat(edge: umber).oklch
        XCTAssertEqual(mat.l, 0.30, accuracy: 0.005)
        XCTAssertLessThanOrEqual(mat.c, 0.035 + 1e-6)
    }

    func testBrightPaintingGetsLightMat() {
        let sky = SRGBColor(hex: "#A8BFCD")!
        let mat = PaletteRules.autoMat(edge: sky).oklch
        XCTAssertTrue((0.88...0.92).contains(mat.l))
    }

    func testNeutralMatFollowsAppearance() {
        XCTAssertEqual(PaletteRules.matColor(style: .neutral, edge: .init(red: 0, green: 0, blue: 0), darkAppearance: true).hex, "#2B2825")
        XCTAssertEqual(PaletteRules.matColor(style: .neutral, edge: .init(red: 0, green: 0, blue: 0), darkAppearance: false).hex, "#E9E4DA")
    }

    func testAccentKeepsHueAndFixesLightness() throws {
        let ochre = Array(repeating: SRGBColor(hex: "#D2AB45")!, count: 40) + Array(repeating: SRGBColor(hex: "#3E5B8E")!, count: 10)
        let accent = try XCTUnwrap(PaletteRules.accent(pixels: ochre))
        XCTAssertEqual(accent.light.oklch.l, 0.45, accuracy: 0.01)
        XCTAssertEqual(accent.dark.oklch.l, 0.78, accuracy: 0.01)
        XCTAssertEqual(accent.light.oklch.h, SRGBColor(hex: "#D2AB45")!.oklch.h, accuracy: 3)
    }

    func testGreyPaintingFallsBackToDefaultAccent() {
        XCTAssertNil(PaletteRules.accent(pixels: Array(repeating: SRGBColor(red: 0.5, green: 0.5, blue: 0.5), count: 100)))
    }
}

final class ExporterTests: XCTestCase {
    func testCSVEscapingAndKeptOnly() throws {
        let artwork = Artwork(id: "met:1", sourceID: .met, title: "Cows, \"Evening\"", artist: "A. Cuyp", museum: "The Met",
                              objectURL: URL(string: "https://example.org/1"), imageURL: URL(string: "https://example.org/1.jpg")!)
        let kept = HistoryEntry(artwork: artwork, shownAt: Date(timeIntervalSince1970: 0), number: 1, keptAt: Date(timeIntervalSince1970: 0))
        let notKept = HistoryEntry(artwork: artwork, shownAt: Date(), number: 2)
        let csv = String(decoding: try FavoritesExporter.export([kept, notKept], as: .csv), as: UTF8.self)
        let lines = csv.split(separator: "\n")
        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(lines[1].hasPrefix("\"Cows, \"\"Evening\"\"\",A. Cuyp,,The Met,https://example.org/1,1970-01-01"))
    }

    func testJSON() throws {
        let artwork = Artwork(id: "met:1", sourceID: .met, title: "T", museum: "M", imageURL: URL(string: "https://example.org/1.jpg")!)
        let entry = HistoryEntry(artwork: artwork, shownAt: Date(), number: 1, keptAt: Date())
        let rows = try JSONSerialization.jsonObject(with: FavoritesExporter.export([entry], as: .json)) as? [[String: Any]]
        XCTAssertEqual(rows?.first?["title"] as? String, "T")
    }
}

final class CatalogCacheTests: XCTestCase {
    func testKeepsStaleListWhenRefreshFails() async throws {
        let store = MemoryCatalogStore()
        let cache = CatalogCache<String>(name: "c", store: store, maxAge: 60)
        let first = try await cache.entries(now: Date(timeIntervalSince1970: 0)) { ["a", "b"] }
        XCTAssertEqual(first, ["a", "b"])
        let later = try await cache.entries(now: Date(timeIntervalSince1970: 3600)) { throw SourceError.http(status: 504) }
        XCTAssertEqual(later, ["a", "b"])
    }

    func testRefreshesWhenStale() async throws {
        let cache = CatalogCache<String>(name: "c", store: MemoryCatalogStore(), maxAge: 60)
        _ = try await cache.entries(now: Date(timeIntervalSince1970: 0)) { ["a"] }
        let fresh = try await cache.entries(now: Date(timeIntervalSince1970: 3600)) { ["b"] }
        XCTAssertEqual(fresh, ["b"])
    }
}

final class TextTests: XCTestCase {
    func testSplitArtist() {
        XCTAssertEqual(Text.splitArtist("Vincent van Gogh (Dutch, 1853–1890)").name, "Vincent van Gogh")
        XCTAssertEqual(Text.splitArtist("Vincent van Gogh (Dutch, 1853–1890)").details, "Dutch, 1853–1890")
        XCTAssertEqual(Text.splitArtist("Georges Seurat\nFrench, 1859–1891").details, "French, 1859–1891")
        XCTAssertNil(Text.splitArtist("Anonymous").details)
    }

    func testPlain() {
        XCTAssertEqual(Text.plain("<p>One &amp; two</p><p>Three</p>"), "One & two\n\nThree")
        XCTAssertNil(Text.plain("<p> </p>"))
    }
}
