import Foundation

enum Text {
    /// Turns museum HTML snippets into plain text: drops tags, decodes common entities,
    /// collapses whitespace. Returns nil for empty results.
    static func plain(_ html: String?) -> String? {
        guard var text = html else { return nil }
        text = text.replacingOccurrences(of: "</p>\\s*<p[^>]*>", with: "\n\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        let entities = ["&amp;": "&", "&quot;": "\"", "&#39;": "’", "&apos;": "’", "&nbsp;": " ", "&lt;": "<", "&gt;": ">"]
        for (entity, value) in entities { text = text.replacingOccurrences(of: entity, with: value) }
        text = text.replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    /// Non-empty trimmed string or nil.
    static func clean(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Splits "Vincent van Gogh (Dutch, 1853–1890)" into name and details.
    /// Handles the Art Institute's newline form ("Name\nDutch, 1853–1890") too.
    static func splitArtist(_ display: String?) -> (name: String?, details: String?) {
        guard let display = clean(display) else { return (nil, nil) }
        if let newline = display.firstIndex(of: "\n") {
            return (clean(String(display[..<newline])), clean(String(display[display.index(after: newline)...])))
        }
        if let open = display.firstIndex(of: "("), display.hasSuffix(")") {
            let name = clean(String(display[..<open]))
            let details = clean(String(display[display.index(after: open)..<display.index(before: display.endIndex)]))
            return (name, details)
        }
        return (display, nil)
    }

    /// Extracts the Q-id from a Wikidata URL such as https://www.wikidata.org/wiki/Q18689458.
    static func wikidataID(from value: String?) -> String? {
        guard let value, let range = value.range(of: "Q[0-9]+$", options: .regularExpression) else { return nil }
        return String(value[range])
    }
}
