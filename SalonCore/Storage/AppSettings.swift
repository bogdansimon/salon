import Foundation

/// Every user setting, in one typed model, saved to settings.json.
/// API keys are never stored here; they live in the Keychain only.
/// Unknown or missing keys fall back to defaults, so old files keep loading.
public struct AppSettings: Codable, Equatable, Sendable {
    // General
    public var changeFrequency: ChangeFrequency = .daily
    /// What Resume goes back to after a pause.
    public var resumeFrequency: ChangeFrequency = .daily
    public var changeTime = TimeOfDay(hour: 9, minute: 0)
    public var notifyOnChange = false
    public var nextShortcut: GlobalShortcut? = .defaultNext

    // Artwork
    public var objectTypes: Set<ObjectType> = [.painting]
    public var highlightsOnly = true
    public var matStyle: MatStyle = .auto
    public var matMargin: MatMargin = .flush
    /// Keep the work above the Dock instead of letting the Dock sit over it.
    public var avoidDock = true
    /// Keep the work below the menu bar instead of letting the menu bar sit over its top.
    public var avoidMenuBar = true
    public var workFit: WorkFit = .auto

    // Sources: absent means "use the source's default".
    public var sourceEnabled: [SourceID: Bool] = [:]

    // Storage
    public var cacheLimitMB = 1024

    public init() {}

    /// The settings the wallpaper is drawn with. With "Fill screen" the mat options
    /// are hidden, so a work too small to fill falls back to the default mat.
    public var forRendering: AppSettings {
        guard workFit == .fill else { return self }
        var settings = self
        let defaults = AppSettings()
        settings.matStyle = defaults.matStyle
        settings.matMargin = defaults.matMargin
        settings.avoidDock = defaults.avoidDock
        settings.avoidMenuBar = defaults.avoidMenuBar
        return settings
    }

    public var changeSchedule: ChangeSchedule { ChangeSchedule(frequency: changeFrequency, time: changeTime) }

    public func isEnabled(_ source: ArtSource) -> Bool {
        sourceEnabled[source.id] ?? source.info.enabledByDefault
    }

    private enum CodingKeys: String, CodingKey {
        case changeFrequency, resumeFrequency, changeTime, notifyOnChange, nextShortcut, objectTypes, highlightsOnly,
             matStyle, matMargin, avoidDock, avoidMenuBar, workFit, alwaysUseMat, sourceEnabled, cacheLimitMB
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        changeFrequency = (try? c.decode(ChangeFrequency.self, forKey: .changeFrequency)) ?? d.changeFrequency
        resumeFrequency = (try? c.decode(ChangeFrequency.self, forKey: .resumeFrequency)) ?? d.resumeFrequency
        if resumeFrequency == .never { resumeFrequency = d.resumeFrequency }
        changeTime = (try? c.decode(TimeOfDay.self, forKey: .changeTime)) ?? d.changeTime
        notifyOnChange = (try? c.decode(Bool.self, forKey: .notifyOnChange)) ?? d.notifyOnChange
        nextShortcut = c.contains(.nextShortcut) ? try? c.decode(GlobalShortcut?.self, forKey: .nextShortcut) : d.nextShortcut
        objectTypes = (try? c.decode(Set<ObjectType>.self, forKey: .objectTypes)) ?? d.objectTypes
        highlightsOnly = (try? c.decode(Bool.self, forKey: .highlightsOnly)) ?? d.highlightsOnly
        matStyle = (try? c.decode(MatStyle.self, forKey: .matStyle)) ?? d.matStyle
        matMargin = (try? c.decode(MatMargin.self, forKey: .matMargin)) ?? d.matMargin
        avoidDock = (try? c.decode(Bool.self, forKey: .avoidDock)) ?? d.avoidDock
        avoidMenuBar = (try? c.decode(Bool.self, forKey: .avoidMenuBar)) ?? d.avoidMenuBar
        // Older files had an "Always use mat" switch; on means "Whole work".
        let legacyAlwaysMat = (try? c.decode(Bool.self, forKey: .alwaysUseMat)) ?? false
        workFit = (try? c.decode(WorkFit.self, forKey: .workFit)) ?? (legacyAlwaysMat ? .whole : d.workFit)
        sourceEnabled = (try? c.decode([String: Bool].self, forKey: .sourceEnabled))
            .map { Dictionary(uniqueKeysWithValues: $0.map { (SourceID($0.key), $0.value) }) } ?? d.sourceEnabled
        cacheLimitMB = (try? c.decode(Int.self, forKey: .cacheLimitMB)) ?? d.cacheLimitMB
        if objectTypes.isEmpty { objectTypes = d.objectTypes }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(changeFrequency, forKey: .changeFrequency)
        try c.encode(resumeFrequency, forKey: .resumeFrequency)
        try c.encode(changeTime, forKey: .changeTime)
        try c.encode(notifyOnChange, forKey: .notifyOnChange)
        try c.encode(nextShortcut, forKey: .nextShortcut)
        try c.encode(objectTypes.sorted { $0.rawValue < $1.rawValue }, forKey: .objectTypes)
        try c.encode(highlightsOnly, forKey: .highlightsOnly)
        try c.encode(matStyle, forKey: .matStyle)
        try c.encode(matMargin, forKey: .matMargin)
        try c.encode(avoidDock, forKey: .avoidDock)
        try c.encode(avoidMenuBar, forKey: .avoidMenuBar)
        try c.encode(workFit, forKey: .workFit)
        try c.encode(Dictionary(uniqueKeysWithValues: sourceEnabled.map { ($0.key.rawValue, $0.value) }), forKey: .sourceEnabled)
        try c.encode(cacheLimitMB, forKey: .cacheLimitMB)
    }
}

public struct TimeOfDay: Codable, Equatable, Sendable {
    public var hour: Int
    public var minute: Int

    public init(hour: Int, minute: Int) {
        self.hour = hour
        self.minute = minute
    }
}

/// A global shortcut as a Carbon virtual key code plus modifier flags.
public struct GlobalShortcut: Codable, Equatable, Sendable {
    public struct Modifiers: OptionSet, Codable, Equatable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let command = Modifiers(rawValue: 1 << 0)
        public static let option = Modifiers(rawValue: 1 << 1)
        public static let control = Modifiers(rawValue: 1 << 2)
        public static let shift = Modifiers(rawValue: 1 << 3)
    }

    public var keyCode: Int
    public var key: String
    public var modifiers: Modifiers

    public init(keyCode: Int, key: String, modifiers: Modifiers) {
        self.keyCode = keyCode
        self.key = key
        self.modifiers = modifiers
    }

    /// ⌃⌥⌘N, as in the General settings design. 45 is kVK_ANSI_N.
    public static let defaultNext = GlobalShortcut(keyCode: 45, key: "N", modifiers: [.control, .option, .command])

    /// "⌃⌥⌘N"
    public var displayString: String {
        var text = ""
        if modifiers.contains(.control) { text += "⌃" }
        if modifiers.contains(.option) { text += "⌥" }
        if modifiers.contains(.shift) { text += "⇧" }
        if modifiers.contains(.command) { text += "⌘" }
        return text + key.uppercased()
    }
}
