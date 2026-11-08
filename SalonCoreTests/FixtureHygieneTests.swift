import XCTest

/// Guards the public repo: recorded fixtures must never carry API keys or personal paths.
/// If this fails, run `python3 scripts/scrub-fixtures.py`.
final class FixtureHygieneTests: XCTestCase {
    private func fixtureTexts() throws -> [(String, String)] {
        let urls = try FileManager.default.contentsOfDirectory(at: Fixtures.directory, includingPropertiesForKeys: nil)
        XCTAssertFalse(urls.isEmpty)
        return try urls.map { ($0.lastPathComponent, try String(contentsOf: $0, encoding: .utf8)) }
    }

    func testNoAPIKeysInURLs() throws {
        let pattern = try NSRegularExpression(pattern: "(?i)[?&](api_key|apikey|wskey|key|access_token)=(?!REDACTED)[^&\"\\s]+")
        for (name, text) in try fixtureTexts() {
            let hit = pattern.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
            XCTAssertNil(hit, "\(name) contains an API key in a URL")
        }
    }

    func testNoAPIKeysInFieldsOrHeaders() throws {
        let pattern = try NSRegularExpression(pattern: "(?i)\"(api_key|apikey|wskey|x-api-key|authorization)\"\\s*:\\s*\"(?!REDACTED)[^\"]+\"")
        for (name, text) in try fixtureTexts() {
            XCTAssertNil(pattern.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)), "\(name) contains a key field")
        }
    }

    func testNoDemoOrPersonalKeys() throws {
        for (name, text) in try fixtureTexts() {
            XCTAssertFalse(text.contains("DEMO_KEY"), "\(name) contains DEMO_KEY")
        }
    }

    func testNoPersonalPaths() throws {
        for (name, text) in try fixtureTexts() {
            XCTAssertNil(text.range(of: "/Users/[A-Za-z0-9._-]+", options: .regularExpression), "\(name) contains a home path")
        }
    }
}
