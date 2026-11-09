import Foundation

/// Every user setting, in one typed model, saved to settings.json.
/// API keys are never stored here; they live in the Keychain only.
/// Unknown or missing keys fall back to defaults, so old files keep loading.
public struct AppSettings: Codable, Equatable, Sendable {
    // General
    public var changeTime = TimeOfDay(hour: 9, minute: 0)
    public var changeOnWakeIfMissed = true
    public var notifyOnChange = false
    public var nextShortcut: GlobalShortcut? = .defaultNext

    // Artwork
    public var objectTypes: Set<ObjectType> = [.painting]
    public var highlightsOnly = true
    public var differentArtworkPerDisplay = false
    public var matStyle: MatStyle = .auto
    public var matMargin: MatMargin = .flush
    /// Keep the work above the Dock instead of letting the Dock sit over it.
    public var avoidDock = false
    public var alwaysUseMat = false

    // Sources: absent means "use the source's default".
    public var sourceEnabled: [SourceID: Bool] = [:]

    // Storage
    public var cacheLimitMB = 1024

    public init() {}

    public func isEnabled(_ source: ArtSource) -> Bool {
        sourceEnabled[source.id] ?? source.info.enabledByDefault
    }

    private enum CodingKeys: String, CodingKey {
        case changeTime, changeOnWakeIfMissed, notifyOnChange, nextShortcut, objectTypes, highlightsOnly,
             differentArtworkPerDisplay, matStyle, matMargin, avoidDock, alwaysUseMat, sourceEnabled, cacheLimitMB
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        changeTime = (try? c.decode(TimeOfDay.self, forKey: .changeTime)) ?? d.changeTime
        changeOnWakeIfMissed = (try? c.decode(Bool.self, forKey: .changeOnWakeIfMissed)) ?? d.changeOnWakeIfMissed
        notifyOnChange = (try? c.decode(Bool.self, forKey: .notifyOnChange)) ?? d.notifyOnChange
        nextShortcut = c.contains(.nextShortcut) ? try? c.decode(GlobalShortcut?.self, forKey: .nextShortcut) : d.nextShortcut
        objectTypes = (try? c.decode(Set<ObjectType>.self, forKey: .objectTypes)) ?? d.objectTypes
        highlightsOnly = (try? c.decode(Bool.self, forKey: .highlightsOnly)) ?? d.highlightsOnly
        differentArtworkPerDisplay = (try? c.decode(Bool.self, forKey: .differentArtworkPerDisplay)) ?? d.differentArtworkPerDisplay
        matStyle = (try? c.decode(MatStyle.self, forKey: .matStyle)) ?? d.matStyle
        matMargin = (try? c.decode(MatMargin.self, forKey: .matMargin)) ?? d.matMargin
        avoidDock = (try? c.decode(Bool.self, forKey: .avoidDock)) ?? d.avoidDock
        alwaysUseMat = (try? c.decode(Bool.self, forKey: .alwaysUseMat)) ?? d.alwaysUseMat
        sourceEnabled = (try? c.decode([String: Bool].self, forKey: .sourceEnabled))
            .map { Dictionary(uniqueKeysWithValues: $0.map { (SourceID($0.key), $0.value) }) } ?? d.sourceEnabled
        cacheLimitMB = (try? c.decode(Int.self, forKey: .cacheLimitMB)) ?? d.cacheLimitMB
        if objectTypes.isEmpty { objectTypes = d.objectTypes }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(changeTime, forKey: .changeTime)
        try c.encode(changeOnWakeIfMissed, forKey: .changeOnWakeIfMissed)
        try c.encode(notifyOnChange, forKey: .notifyOnChange)
        try c.encode(nextShortcut, forKey: .nextShortcut)
        try c.encode(objectTypes.sorted { $0.rawValue < $1.rawValue }, forKey: .objectTypes)
        try c.encode(highlightsOnly, forKey: .highlightsOnly)
        try c.encode(differentArtworkPerDisplay, forKey: .differentArtworkPerDisplay)
        try c.encode(matStyle, forKey: .matStyle)
        try c.encode(matMargin, forKey: .matMargin)
        try c.encode(avoidDock, forKey: .avoidDock)
        try c.encode(alwaysUseMat, forKey: .alwaysUseMat)
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
