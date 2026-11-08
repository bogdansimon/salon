import AppKit
import Observation
import SalonCore

/// The app's single source of truth: settings, history, health and the current
/// work, plus every user action. Views observe it; services do the platform work.
@MainActor
@Observable
final class AppModel {
    enum Phase: Equatable {
        case idle
        case loading(sourceName: String?)
        case failed(sourceID: SourceID?, message: String)
    }

    // MARK: State

    var settings: AppSettings { didSet { settingsChanged(from: oldValue) } }
    private(set) var history: [HistoryEntry]
    private(set) var health: [SourceID: SourceHealth]
    private(set) var phase: Phase = .idle
    private(set) var lastHealthCheck: Date?
    private(set) var cacheBytes: Int64 = 0
    private(set) var cacheCount = 0

    let sources: [ArtSource]

    // MARK: Plumbing

    @ObservationIgnored private let paths: AppPaths
    @ObservationIgnored private var state: AppState
    @ObservationIgnored private var shownIDs: Set<String>
    @ObservationIgnored private let picker: ArtworkPicker
    @ObservationIgnored private let cache: ImageCache
    @ObservationIgnored private let wikipedia: WikipediaSummary
    @ObservationIgnored private let wallpaper: WallpaperService
    @ObservationIgnored private let scheduler = Scheduler()
    @ObservationIgnored private let keychain = KeychainStore.standard
    @ObservationIgnored private var consecutiveFailures = 0
    @ObservationIgnored private var isChanging = false
    @ObservationIgnored private var rerenderTask: Task<Void, Never>?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    init(paths: AppPaths = .standard, dryRun: Bool = false) {
        paths.createDirectories()
        self.paths = paths
        let http = URLSessionHTTPClient()
        self.sources = SourceRegistry.all(http: http, catalogs: FileCatalogStore(directory: paths.catalogs))
        self.cache = ImageCache(directory: paths.images)
        self.picker = ArtworkPicker(sources: sources, http: http, cache: cache)
        self.wikipedia = WikipediaSummary(http: http)
        self.wallpaper = WallpaperService(directory: paths.wallpapers, dryRun: dryRun)

        let history = JSONFile<[HistoryEntry]>(paths.history).load() ?? []
        settings = JSONFile<AppSettings>(paths.settings).load() ?? AppSettings()
        self.history = history
        state = JSONFile<AppState>(paths.state).load() ?? AppState()
        shownIDs = JSONFile<Set<String>>(paths.shown).load() ?? Set(history.map(\.artwork.id))
        let storedHealth = JSONFile<[String: SourceHealth]>(paths.health).load() ?? [:]
        health = Dictionary(uniqueKeysWithValues: storedHealth.map { (SourceID($0.key), $0.value) })
    }

    func start() {
        refreshCacheStats()
        // Download slow catalogues (Rijksmuseum ids, Wikidata list) ahead of the first pick.
        for source in sources where settings.isEnabled(source) {
            Task.detached(priority: .background) { await source.warmUp() }
        }
        HotKeyCenter.shared.onPress = { [weak self] in self?.next() }
        HotKeyCenter.shared.register(settings.nextShortcut)
        scheduler.onDue = { [weak self] in self?.next() }
        scheduler.start(time: settings.changeTime, changeOnWake: settings.changeOnWakeIfMissed) { [weak self] in
            self?.state.lastChange
        }
        // The desktop picture is per Space; follow the user onto Spaces that don't show it yet.
        wallpaper.hangOnActiveSpace(state.currentWallpaperFiles)
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.wallpaper.hangOnActiveSpace(self.state.currentWallpaperFiles)
            }
        })
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleRerender() }
        })
        observers.append(DistributedNotificationCenter.default().addObserver(forName: Notification.Name("AppleInterfaceThemeChangedNotification"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { if self?.settings.matStyle == .neutral { self?.scheduleRerender() } }
        })
    }

    // MARK: Derived

    /// The work on the main display (the one the card shows).
    var current: HistoryEntry? {
        state.currentEntryIDs.first.flatMap { id in history.first { $0.id == id } } ?? history.last
    }

    var keptCount: Int { history.filter(\.isKept).count }

    func source(_ id: SourceID) -> ArtSource? { sources.first { $0.id == id } }

    func healthStatus(_ id: SourceID) -> SourceHealth.Status { health[id]?.status ?? .unknown }

    func imageFile(for entry: HistoryEntry) -> URL? { cache.cachedFile(for: entry.artwork.id) }

    var retryMinutes: Int? { scheduler.retryMinutes }

    // MARK: Actions

    func next() { Task { await change() } }

    func tryAgain() {
        guard case .failed(let sourceID, _) = phase else { return next() }
        Task { await change(preferred: sourceID) }
    }

    func useAnotherMuseum() {
        guard case .failed(let sourceID, _) = phase else { return next() }
        Task { await change(avoiding: sourceID.map { [$0] } ?? []) }
    }

    func toggleKeep(_ entry: HistoryEntry) {
        guard let index = history.firstIndex(where: { $0.id == entry.id }) else { return }
        history[index].keptAt = history[index].isKept ? nil : Date()
        save()
    }

    /// Hangs a work from the collection again (all displays).
    func setAsWallpaper(_ entry: HistoryEntry) async {
        do {
            let file = try await picker.download(entry.artwork).imageFile
            let assignments = NSScreen.screens.map { WallpaperService.Assignment(screen: $0, imageFile: file, palette: entry.palette ?? .fallback) }
            state.currentWallpaperFiles = try await wallpaper.apply(assignments, settings: settings)
            state.currentEntryIDs = [entry.id]
            state.lastChange = Date()
            save()
        } catch {
            phase = .failed(sourceID: entry.artwork.sourceID, message: Self.message(for: error))
        }
    }

    func checkAllSources() async {
        await withTaskGroup(of: (SourceID, HealthEvent).self) { group in
            for source in sources where settings.isEnabled(source) {
                let key = apiKey(for: source.id)
                group.addTask {
                    let started = Date()
                    do {
                        try await source.healthCheck(apiKey: key)
                        return (source.id, .success(latency: Date().timeIntervalSince(started)))
                    } catch {
                        return (source.id, .failure(error: error, latency: Date().timeIntervalSince(started)))
                    }
                }
            }
            for await (id, event) in group { record(id, event) }
        }
        lastHealthCheck = Date()
    }

    func clearCache() {
        cache.clear(protecting: protectedImageIDs)
        Thumbnails.shared.removeAll()
        refreshCacheStats()
    }

    /// Forgets shown works except kept and on-screen ones. Works still never repeat.
    func clearHistory() {
        let onScreen = Set(state.currentEntryIDs)
        history = history.filter { $0.isKept || onScreen.contains($0.id) }
        save()
    }

    func exportKept(as format: FavoritesExporter.Format) throws -> Data {
        try FavoritesExporter.export(history, as: format)
    }

    var historyStart: Date? { history.first?.shownAt }

    // MARK: API keys (Keychain only)

    func apiKey(for id: SourceID) -> String? { keychain.key(for: id) }

    func setAPIKey(_ key: String?, for id: SourceID) {
        keychain.setKey(key?.trimmingCharacters(in: .whitespacesAndNewlines), for: id)
        health[id] = nil
        saveHealth()
    }

    // MARK: Changing the wallpaper

    func change(preferred: SourceID? = nil, avoiding: Set<SourceID> = []) async {
        guard !isChanging else { return }
        isChanging = true
        defer { isChanging = false }

        let screens = NSScreen.screens
        let count = settings.differentArtworkPerDisplay ? max(screens.count, 1) : 1
        phase = .loading(sourceName: nil)

        var picks: [PickedArtwork] = []
        do {
            for _ in 0..<count {
                var request = pickRequest(preferred: preferred, avoiding: avoiding)
                request.excludedIDs.formUnion(picks.map(\.artwork.id))
                let picked = try await picker.pick(request, onStart: { [weak self] id in
                    await self?.showLoading(from: id)
                }, report: { [weak self] id, event in
                    await self?.record(id, event)
                })
                picks.append(picked)
            }
        } catch {
            fail(with: error, source: preferred)
            return
        }

        var entries: [HistoryEntry] = []
        for picked in picks {
            let palette = await Self.palette(of: picked.imageFile)
            let artwork = await wikipedia.enrich(picked.artwork)
            state.shownCount += 1
            entries.append(HistoryEntry(artwork: artwork, shownAt: Date(), number: state.shownCount, palette: palette))
        }

        do {
            let assignments = screens.enumerated().map { index, screen in
                let i = settings.differentArtworkPerDisplay ? index % picks.count : 0
                return WallpaperService.Assignment(screen: screen, imageFile: picks[i].imageFile, palette: entries[i].palette ?? .fallback)
            }
            state.currentWallpaperFiles = try await wallpaper.apply(assignments, settings: settings)
        } catch {
            fail(with: error, source: nil)
            return
        }

        history.append(contentsOf: entries)
        shownIDs.formUnion(entries.map(\.artwork.id))
        state.currentEntryIDs = entries.map(\.id)
        state.lastChange = Date()
        consecutiveFailures = 0
        scheduler.cancelRetry()
        phase = .idle
        save()
        if settings.notifyOnChange, let first = entries.first { ChangeNotifier.post(for: first.artwork) }
        cache.evict(toFit: Int64(settings.cacheLimitMB) * 1_048_576, protecting: protectedImageIDs)
        refreshCacheStats()
    }

    private func pickRequest(preferred: SourceID?, avoiding: Set<SourceID>) -> ArtworkPicker.Request {
        let enabled = Set(sources.filter { settings.isEnabled($0) }.map(\.id))
        var keys: [SourceID: String] = [:]
        for source in sources where source.info.requiresAPIKey { keys[source.id] = apiKey(for: source.id) }
        return ArtworkPicker.Request(
            objectTypes: settings.objectTypes, highlightsOnly: settings.highlightsOnly, enabledSources: enabled,
            excludedIDs: shownIDs, apiKeys: keys, preferredSource: preferred, avoidedSources: avoiding,
            failingSources: Set(health.filter { $0.value.status == .failing }.keys)
        )
    }

    private func showLoading(from id: SourceID) {
        phase = .loading(sourceName: source(id)?.info.shortName)
    }

    private func fail(with error: Error, source: SourceID?) {
        consecutiveFailures += 1
        scheduler.scheduleRetry(afterFailures: consecutiveFailures)
        let failing = source ?? health.filter { $0.value.consecutiveFailures > 0 }.max { ($0.value.lastAttempt ?? .distantPast) < ($1.value.lastAttempt ?? .distantPast) }?.key
        phase = .failed(sourceID: failing, message: Self.message(for: error))
    }

    private func record(_ id: SourceID, _ event: HealthEvent) {
        var entry = health[id] ?? SourceHealth()
        switch event {
        case .success(let latency): entry.recordSuccess(latency: latency)
        case .failure(let error, let latency): entry.recordFailure(error, latency: latency)
        }
        health[id] = entry
        saveHealth()
    }

    // MARK: Settings take effect immediately

    private func settingsChanged(from old: AppSettings) {
        JSONFile<AppSettings>(paths.settings).save(settings)
        if settings.nextShortcut != old.nextShortcut { HotKeyCenter.shared.register(settings.nextShortcut) }
        if settings.changeTime != old.changeTime || settings.changeOnWakeIfMissed != old.changeOnWakeIfMissed {
            scheduler.update(time: settings.changeTime, changeOnWake: settings.changeOnWakeIfMissed)
        }
        if settings.notifyOnChange && !old.notifyOnChange { ChangeNotifier.requestPermission() }
        if settings.matStyle != old.matStyle || settings.matMargin != old.matMargin || settings.alwaysUseMat != old.alwaysUseMat {
            scheduleRerender()
        }
        if settings.differentArtworkPerDisplay != old.differentArtworkPerDisplay {
            // Different works need new picks; the same work just re-renders.
            if settings.differentArtworkPerDisplay && NSScreen.screens.count > 1 { next() } else { scheduleRerender() }
        }
        if settings.cacheLimitMB < old.cacheLimitMB {
            cache.evict(toFit: Int64(settings.cacheLimitMB) * 1_048_576, protecting: protectedImageIDs)
            refreshCacheStats()
        }
    }

    /// Re-renders what's on screen with the current settings (debounced for live controls).
    private func scheduleRerender() {
        rerenderTask?.cancel()
        rerenderTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await self?.rerenderCurrent()
        }
    }

    private func rerenderCurrent() async {
        let entries = state.currentEntryIDs.compactMap { id in history.first { $0.id == id } }
        let available = entries.compactMap { entry in cache.cachedFile(for: entry.artwork.id).map { (entry, $0) } }
        guard !available.isEmpty, !isChanging else { return }
        let assignments = NSScreen.screens.enumerated().map { index, screen in
            let (entry, file) = available[settings.differentArtworkPerDisplay ? index % available.count : 0]
            return WallpaperService.Assignment(screen: screen, imageFile: file, palette: entry.palette ?? .fallback)
        }
        if let files = try? await wallpaper.apply(assignments, settings: settings) {
            state.currentWallpaperFiles = files
            saveState()
        }
    }

    // MARK: Persistence

    private var protectedImageIDs: Set<String> {
        let onScreen = Set(state.currentEntryIDs)
        return Set(history.filter { $0.isKept || onScreen.contains($0.id) }.map(\.artwork.id))
    }

    private func refreshCacheStats() {
        cacheBytes = cache.totalBytes
        cacheCount = cache.fileCount
    }

    private func save() {
        JSONFile<[HistoryEntry]>(paths.history).save(history)
        JSONFile<Set<String>>(paths.shown).save(shownIDs)
        saveState()
    }

    private func saveState() { JSONFile<AppState>(paths.state).save(state) }

    private func saveHealth() {
        JSONFile<[String: SourceHealth]>(paths.health).save(Dictionary(uniqueKeysWithValues: health.map { ($0.key.rawValue, $0.value) }))
    }

    private static func palette(of file: URL) async -> ArtworkPalette {
        await Task.detached(priority: .utility) {
            ImageInspector.image(at: file, maxPixelSize: 256).map(PaletteRules.palette(for:)) ?? .fallback
        }.value
    }

    static func message(for error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut: return "The request timed out."
            case .notConnectedToInternet, .networkConnectionLost: return "You’re offline."
            default: return urlError.localizedDescription
            }
        }
        return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
