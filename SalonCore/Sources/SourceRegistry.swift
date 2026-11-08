import Foundation

/// Every source Salon knows. To add a museum: write `<Name>Source.swift` and add it here.
public enum SourceRegistry {
    public static func all(http: HTTPClient, catalogs: CatalogStore) -> [ArtSource] {
        [
            MetSource(http: http),
            ArtInstituteSource(http: http),
            ClevelandSource(http: http),
            RijksmuseumSource(http: http, store: catalogs),
            SMKSource(http: http),
            WikidataSource(http: http, store: catalogs),
            SmithsonianSource(http: http),
        ]
    }
}
