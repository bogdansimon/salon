import Foundation

/// Identifies a source. Each adapter declares its own constant in an extension.
public struct SourceID: RawRepresentable, Codable, Hashable, Sendable, Comparable {
    public var rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public static func < (lhs: SourceID, rhs: SourceID) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Static facts about a source, shown in Settings and About.
public struct SourceInfo: Sendable {
    public var name: String
    /// Shown on the card while loading: "Fetching from The Met".
    public var shortName: String
    public var supportedTypes: Set<ObjectType>
    /// True when the source has a real quality flag ("highlight", "boosted"…).
    public var hasQualityFlag: Bool
    public var requiresAPIKey: Bool
    public var apiKeyHelp: String?
    public var credit: String
    public var homepage: URL
    public var enabledByDefault: Bool

    public init(
        name: String, shortName: String, supportedTypes: Set<ObjectType>, hasQualityFlag: Bool,
        requiresAPIKey: Bool = false, apiKeyHelp: String? = nil, credit: String, homepage: URL,
        enabledByDefault: Bool = true
    ) {
        self.name = name
        self.shortName = shortName
        self.supportedTypes = supportedTypes
        self.hasQualityFlag = hasQualityFlag
        self.requiresAPIKey = requiresAPIKey
        self.apiKeyHelp = apiKeyHelp
        self.credit = credit
        self.homepage = homepage
        self.enabledByDefault = enabledByDefault
    }
}

/// What the picker asks a source for.
public struct ArtworkQuery: Sendable {
    public var objectTypes: Set<ObjectType>
    public var highlightsOnly: Bool
    /// Ids already shown; a source must not return one of these.
    public var excludedIDs: Set<String>
    public var apiKey: String?

    public init(objectTypes: Set<ObjectType>, highlightsOnly: Bool, excludedIDs: Set<String> = [], apiKey: String? = nil) {
        self.objectTypes = objectTypes
        self.highlightsOnly = highlightsOnly
        self.excludedIDs = excludedIDs
        self.apiKey = apiKey
    }
}

/// One museum (or aggregator). Adding a source = one new file conforming to this,
/// plus one line in `SourceRegistry`.
public protocol ArtSource: Sendable {
    var id: SourceID { get }
    var info: SourceInfo { get }

    /// A random, public-domain, not-yet-shown work matching the query.
    /// Image size is verified later by the picker after download.
    func randomArtwork(for query: ArtworkQuery) async throws -> Artwork

    /// A cheap call proving the API answers (used by "Check All Now").
    func healthCheck(apiKey: String?) async throws

    /// Prepares slow resources (e.g. downloads a catalogue) in the background, so a pick never waits on them.
    func warmUp() async
}

extension ArtSource {
    public func warmUp() async {}
}

public enum SourceError: Error, Equatable, LocalizedError {
    case badResponse
    case http(status: Int)
    case decoding(String)
    case missingAPIKey
    case noMatchingWorks
    case notPublicDomain
    case imageTooSmall(PixelSize)
    case unsuitableShape(PixelSize)
    case unsupportedImage
    case allSourcesFailed(lastError: String)

    public var errorDescription: String? {
        switch self {
        case .badResponse: "The server sent an unexpected response."
        case .http(let status) where status == 401 || status == 403: "Key rejected (\(status))."
        case .http(let status): "The server answered with error \(status)."
        case .decoding: "The response couldn’t be read."
        case .missingAPIKey: "Needs an API key."
        case .noMatchingWorks: "No unseen works match the current filters."
        case .notPublicDomain: "The work isn’t public domain."
        case .imageTooSmall(let size): "Image too small (\(size.width)×\(size.height))."
        case .unsuitableShape(let size): "Too long and narrow for a wallpaper (\(size.width)×\(size.height))."
        case .unsupportedImage: "The image couldn’t be decoded."
        case .allSourcesFailed(let last): "Every enabled museum failed. Last error: \(last)"
        }
    }
}

extension SourceError {
    /// The work can't be used (too small, odd shape), but the source itself is fine.
    var isWorkUnsuitable: Bool {
        switch self {
        case .imageTooSmall, .unsuitableShape: true
        default: false
        }
    }
}

extension ArtworkQuery {
    /// How many random draws a source makes before giving up on finding an unseen work.
    static let maxDraws = 6
}

enum Random {
    /// A uniformly random index in 0..<count. Separate so the intent reads clearly at call sites.
    static func index(below count: Int) -> Int { Int.random(in: 0..<max(count, 1)) }
}
