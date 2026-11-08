import Foundation

/// A chosen work whose full image is on disk and big enough.
public struct PickedArtwork: Sendable {
    public var artwork: Artwork
    public var imageFile: URL
    public var pixelSize: PixelSize
}

/// Picks today's work: a random enabled source, then a random qualifying work from
/// it. Fully random, no taste weighting. Falls back to the other sources when one
/// fails, rejects images below the resolution threshold, never repeats a work.
public struct ArtworkPicker: Sendable {
    /// Images must be at least this long on their long side. The Art Institute and
    /// the Smithsonian serve exactly 3000 px, so it is inclusive.
    public static let minimumLongSide = 3000
    /// Reject extreme shapes (handscrolls, friezes): longer side over 3× the shorter.
    /// On a mat they would hang as a sliver.
    public static let maxAspectRatio = 3.0
    /// How many works to try from one source before moving to the next.
    static let attemptsPerSource = 3
    static let downloadTimeout: TimeInterval = 120

    public struct Request: Sendable {
        public var objectTypes: Set<ObjectType>
        public var highlightsOnly: Bool
        public var enabledSources: Set<SourceID>
        public var excludedIDs: Set<String>
        public var apiKeys: [SourceID: String]
        /// Try this source first (e.g. "Try Again"); otherwise the order is random.
        public var preferredSource: SourceID?
        /// Leave these out (e.g. "Use Another Museum").
        public var avoidedSources: Set<SourceID>
        /// Skip sources currently marked failing, unless nothing else is left.
        public var failingSources: Set<SourceID>

        public init(
            objectTypes: Set<ObjectType>, highlightsOnly: Bool, enabledSources: Set<SourceID>,
            excludedIDs: Set<String>, apiKeys: [SourceID: String] = [:], preferredSource: SourceID? = nil,
            avoidedSources: Set<SourceID> = [], failingSources: Set<SourceID> = []
        ) {
            self.objectTypes = objectTypes
            self.highlightsOnly = highlightsOnly
            self.enabledSources = enabledSources
            self.excludedIDs = excludedIDs
            self.apiKeys = apiKeys
            self.preferredSource = preferredSource
            self.avoidedSources = avoidedSources
            self.failingSources = failingSources
        }
    }

    public typealias HealthReporter = @Sendable (SourceID, HealthEvent) async -> Void
    public typealias StartReporter = @Sendable (SourceID) async -> Void

    private let sources: [ArtSource]
    private let http: HTTPClient
    private let cache: ImageCache
    private let minimumLongSide: Int

    public init(sources: [ArtSource], http: HTTPClient, cache: ImageCache, minimumLongSide: Int = ArtworkPicker.minimumLongSide) {
        self.sources = sources
        self.http = http
        self.cache = cache
        self.minimumLongSide = minimumLongSide
    }

    /// The order sources will be tried in.
    func candidateOrder(for request: Request) -> [ArtSource] {
        let usable = sources.filter {
            request.enabledSources.contains($0.id)
                && !request.avoidedSources.contains($0.id)
                && !$0.info.supportedTypes.isDisjoint(with: request.objectTypes)
                && (!$0.info.requiresAPIKey || !(request.apiKeys[$0.id] ?? "").isEmpty)
        }
        let healthy = usable.filter { !request.failingSources.contains($0.id) }
        var order = (healthy.isEmpty ? usable : healthy).shuffled()
        if let preferred = request.preferredSource, let index = order.firstIndex(where: { $0.id == preferred }) {
            order.insert(order.remove(at: index), at: 0)
        }
        return order
    }

    public func pick(_ request: Request, onStart: StartReporter = { _ in }, report: HealthReporter = { _, _ in }) async throws -> PickedArtwork {
        let order = candidateOrder(for: request)
        guard !order.isEmpty else { throw SourceError.noMatchingWorks }

        var excluded = request.excludedIDs
        var lastError: Error = SourceError.noMatchingWorks

        for source in order {
            await onStart(source.id)
            for _ in 0..<Self.attemptsPerSource {
                let started = Date()
                // Health latency measures the API, not the (often large) image download.
                var apiLatency: TimeInterval { Date().timeIntervalSince(started) }
                var measured: TimeInterval?
                do {
                    let query = ArtworkQuery(objectTypes: request.objectTypes, highlightsOnly: request.highlightsOnly,
                                             excludedIDs: excluded, apiKey: request.apiKeys[source.id])
                    let artwork = try await source.randomArtwork(for: query)
                    measured = apiLatency
                    excluded.insert(artwork.id)
                    let picked = try await download(artwork)
                    await report(source.id, .success(latency: measured ?? apiLatency))
                    return picked
                } catch let error as SourceError where error.isWorkUnsuitable {
                    // The work's fault, not the source's: draw another from the same source.
                    lastError = error
                } catch SourceError.noMatchingWorks {
                    // Nothing unseen matches the filters here; not a health problem.
                    lastError = SourceError.noMatchingWorks
                    break
                } catch {
                    lastError = error
                    await report(source.id, .failure(error: error, latency: measured ?? apiLatency))
                    break
                }
            }
        }
        throw SourceError.allSourcesFailed(lastError: (lastError as? LocalizedError)?.errorDescription ?? "\(lastError)")
    }

    /// Downloads (or reuses) the full image and checks its real size.
    public func download(_ artwork: Artwork) async throws -> PickedArtwork {
        if let reported = artwork.reportedPixelSize {
            try checkSuitable(reported)
        }
        let file: URL
        if let cached = cache.cachedFile(for: artwork.id) {
            file = cached
        } else {
            var request = URLRequest(url: artwork.imageURL)
            request.timeoutInterval = Self.downloadTimeout
            artwork.imageRequestHeaders?.forEach { request.setValue($1, forHTTPHeaderField: $0) }
            file = try cache.store(try await http.data(for: request), for: artwork.id)
        }
        guard let size = ImageInspector.pixelSize(of: file) else {
            try? FileManager.default.removeItem(at: file)
            throw SourceError.unsupportedImage
        }
        do {
            try checkSuitable(size)
        } catch {
            try? FileManager.default.removeItem(at: file)
            throw error
        }
        return PickedArtwork(artwork: artwork, imageFile: file, pixelSize: size)
    }

    private func checkSuitable(_ size: PixelSize) throws {
        guard size.longSide >= minimumLongSide else { throw SourceError.imageTooSmall(size) }
        let shortSide = max(min(size.width, size.height), 1)
        guard Double(size.longSide) / Double(shortSide) <= Self.maxAspectRatio else { throw SourceError.unsuitableShape(size) }
    }
}
