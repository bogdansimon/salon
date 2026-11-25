import Foundation

/// The museum's artist line, split for the wall label: life years go next to the
/// name, the nationality goes under it.
///
///     "Dutch, Zundert 1853–1890 Auvers-sur-Oise" → "1853–1890", "Dutch"
///     "Danish, born 1843"                         → "born 1843", "Danish"
///     "Flemish, active 1620–1650"                 → "active 1620–1650", "Flemish"
///     "Dutch, ca. 1600–1650"                      → "c. 1600–1650", "Dutch"
///     "French"                                    → nil, "French"
public struct ArtistDetails: Equatable, Sendable {
    public var lifespan: String?
    public var nationality: String?

    public init(_ details: String?) {
        guard let details = Text.clean(details) else { return }
        let years = Text.years(in: details)
        guard let first = years.first else {
            nationality = details
            return
        }

        let lower = details.lowercased()
        let range = years.count >= 2 ? "\(first)–\(years[1])" : "\(first)"
        if ["active", "fl.", "working", "documented"].contains(where: lower.contains) {
            lifespan = "active \(range)"
        } else if years.count == 1, lower.contains("born") {
            lifespan = "born \(first)"
        } else if years.count == 1, lower.contains("died") {
            lifespan = "died \(first)"
        } else {
            let circa = lower.contains(/\b(c\.|ca\.?|circa|about)\s*\d/)
            lifespan = (circa ? "c. " : "") + range
        }

        // The nationality is the first part before any date ("Dutch" of "Dutch, Zundert 1853…").
        let head = Text.clean(details.prefix { !$0.isNumber }.split(separator: ",").first.map(String.init))
        let dateWords = ["born", "died", "active", "fl.", "working", "documented", "c.", "ca", "circa", "about"]
        if let head, !dateWords.contains(where: head.lowercased().hasPrefix) {
            nationality = head
        }
    }
}
