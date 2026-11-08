import Foundation

/// One work of art as Salon knows it, normalised across every source.
public struct Artwork: Codable, Hashable, Identifiable, Sendable {
    /// Globally unique: "<source>:<source-specific id>", e.g. "met:436535".
    public var id: String
    public var sourceID: SourceID
    public var title: String
    public var artist: String?
    /// Nationality and life dates, e.g. "Dutch, 1632–1675".
    public var artistDetails: String?
    public var date: String?
    public var medium: String?
    public var dimensions: String?
    /// The holding museum, e.g. "Rijksmuseum, Amsterdam".
    public var museum: String
    /// Description / "did you know" text, plain text.
    public var summary: String?
    /// Where `summary` came from when it is not the museum itself (e.g. "Wikipedia").
    public var summaryCredit: String?
    public var objectURL: URL?
    /// Wikidata Q-id, e.g. "Q18689458".
    public var wikidataID: String?
    public var imageURL: URL
    /// Extra headers some image hosts require (e.g. the Art Institute's AIC-User-Agent).
    public var imageRequestHeaders: [String: String]?
    /// Pixel size reported by the source before download, when it knows it.
    public var reportedPixelSize: PixelSize?

    public init(
        id: String, sourceID: SourceID, title: String, artist: String? = nil,
        artistDetails: String? = nil, date: String? = nil, medium: String? = nil,
        dimensions: String? = nil, museum: String, summary: String? = nil,
        summaryCredit: String? = nil, objectURL: URL? = nil, wikidataID: String? = nil,
        imageURL: URL, imageRequestHeaders: [String: String]? = nil,
        reportedPixelSize: PixelSize? = nil
    ) {
        self.id = id
        self.sourceID = sourceID
        self.title = title
        self.artist = artist
        self.artistDetails = artistDetails
        self.date = date
        self.medium = medium
        self.dimensions = dimensions
        self.museum = museum
        self.summary = summary
        self.summaryCredit = summaryCredit
        self.objectURL = objectURL
        self.wikidataID = wikidataID
        self.imageURL = imageURL
        self.imageRequestHeaders = imageRequestHeaders
        self.reportedPixelSize = reportedPixelSize
    }
}

public struct PixelSize: Codable, Hashable, Sendable {
    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    public var longSide: Int { max(width, height) }
    public var aspectRatio: Double { height == 0 ? 0 : Double(width) / Double(height) }
}

/// The kinds of object a person can ask for in Settings › Artwork.
public enum ObjectType: String, Codable, CaseIterable, Hashable, Sendable {
    case painting, print, drawing

    public var displayName: String {
        switch self {
        case .painting: "Paintings"
        case .print: "Prints"
        case .drawing: "Drawings"
        }
    }
}
