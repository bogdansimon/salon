import AppKit
import Carbon.HIToolbox
import SalonCore
import ServiceManagement
import UserNotifications

/// Launch at login via SMAppService. The system owns this state, so it's read
/// from there rather than stored in settings.
enum LaunchAtLogin {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }
    static var needsApproval: Bool { SMAppService.mainApp.status == .requiresApproval }

    static func set(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    static func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    private static let defaultAppliedKey = "launchAtLoginDefaultApplied"

    /// On by default: turned on once, on the first launch. If the user turns it off
    /// later, it stays off.
    static func applyDefaultOnce() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: defaultAppliedKey) else { return }
        defaults.set(true, forKey: defaultAppliedKey)
        if SMAppService.mainApp.status == .notRegistered { try? set(true) }
    }
}

/// A system-wide hot key through Carbon's RegisterEventHotKey: works from any app
/// and needs no Accessibility permission.
@MainActor
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    var onPress: (() -> Void)?
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?

    func register(_ shortcut: GlobalShortcut?) {
        unregister()
        guard let shortcut else { return }
        installHandlerIfNeeded()
        let id = EventHotKeyID(signature: OSType(0x53414C4E), id: 1) // "SALN"
        RegisterEventHotKey(UInt32(shortcut.keyCode), Self.carbonModifiers(shortcut.modifiers), id,
                            GetApplicationEventTarget(), 0, &hotKey)
    }

    func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
    }

    private func installHandlerIfNeeded() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { HotKeyCenter.shared.onPress?() } }
            return noErr
        }, 1, &spec, nil, &handler)
    }

    static func carbonModifiers(_ modifiers: GlobalShortcut.Modifiers) -> UInt32 {
        var flags = 0
        if modifiers.contains(.command) { flags |= cmdKey }
        if modifiers.contains(.option) { flags |= optionKey }
        if modifiers.contains(.control) { flags |= controlKey }
        if modifiers.contains(.shift) { flags |= shiftKey }
        return UInt32(flags)
    }
}

/// The optional "painting changed" notification (off by default).
enum ChangeNotifier {
    /// Without a delegate, macOS hides notifications while Salon is the active app
    /// (popover or Settings open). This shows them anyway.
    private final class Presenter: NSObject, UNUserNotificationCenterDelegate {
        func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
            completionHandler([.banner, .list])
        }
    }
    private static let presenter = Presenter()

    static func install() {
        UNUserNotificationCenter.current().delegate = presenter
    }

    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, _ in }
    }

    static func post(for artwork: Artwork) {
        let content = UNMutableNotificationContent()
        content.title = artwork.title
        content.body = [artwork.artist, artwork.date].compactMap { $0 }.joined(separator: ", ")
        let request = UNNotificationRequest(identifier: "salon.change", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
