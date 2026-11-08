import SalonCore
import SwiftUI

struct GeneralSettings: View {
    @Environment(AppModel.self) private var model
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var launchError: String?

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
                if LaunchAtLogin.needsApproval {
                    SettingRow(title: "Needs approval", help: "Allow Salon in System Settings › General › Login Items.") {
                        Button("Open Login Items…") { LaunchAtLogin.openLoginItemsSettings() }
                    }
                }
                if let launchError {
                    Text(launchError).font(Theme.Typeface.help).foregroundStyle(Theme.Palette.healthBad)
                }
            }

            Section("Daily change") {
                SettingRow(title: "Hang a new work at", help: "Every day at this time, the wallpaper changes once.") {
                    DatePicker("", selection: timeBinding, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .datePickerStyle(.field)
                }
                Toggle(isOn: $model.settings.changeOnWakeIfMissed) {
                    Text("Also change on wake if a day was missed")
                    Text("For days when your Mac was asleep or off at the change time.")
                }
                Toggle(isOn: $model.settings.notifyOnChange) {
                    Text("Notify when the painting changes")
                    Text("A quiet notification with the title and artist.")
                }
            }

            Section("Keyboard") {
                SettingRow(title: "Next work", help: "A global shortcut — works from any app.") {
                    ShortcutRecorder(shortcut: $model.settings.nextShortcut)
                }
            }
        }
        .settingsForm()
    }

    private var timeBinding: Binding<Date> {
        Binding {
            Calendar.current.date(bySettingHour: model.settings.changeTime.hour, minute: model.settings.changeTime.minute, second: 0, of: Date()) ?? Date()
        } set: { date in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            model.settings.changeTime = TimeOfDay(hour: parts.hour ?? 9, minute: parts.minute ?? 0)
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LaunchAtLogin.set(enabled)
            launchError = nil
        } catch {
            launchError = "Couldn’t change Login Items: \(error.localizedDescription)"
        }
        launchAtLogin = LaunchAtLogin.isEnabled
    }
}

/// Click, then press the new shortcut. Esc cancels, Delete clears.
struct ShortcutRecorder: View {
    @Binding var shortcut: GlobalShortcut?
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: Theme.Space.group) {
            Button(recording ? "Type shortcut…" : (shortcut?.displayString ?? "Record Shortcut")) {
                recording ? stop() : start()
            }
            .font(Theme.Typeface.body.monospacedDigit())
            .frame(minWidth: 120)
            if shortcut != nil && !recording {
                Button { shortcut = nil } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.Palette.ink3)
                    .accessibilityLabel("Clear shortcut")
            }
        }
        .onDisappear(perform: stop)
    }

    private func start() {
        recording = true
        HotKeyCenter.shared.unregister()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handle(event)
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if recording { HotKeyCenter.shared.register(shortcut) }
        recording = false
    }

    private func handle(_ event: NSEvent) {
        switch Int(event.keyCode) {
        case 53: stop()                                   // Esc
        case 51, 117: shortcut = nil; stop()              // Delete, Forward Delete
        default:
            var modifiers: GlobalShortcut.Modifiers = []
            let flags = event.modifierFlags
            if flags.contains(.command) { modifiers.insert(.command) }
            if flags.contains(.option) { modifiers.insert(.option) }
            if flags.contains(.control) { modifiers.insert(.control) }
            if flags.contains(.shift) { modifiers.insert(.shift) }
            // Require ⌘, ⌥ or ⌃ so a plain key never becomes global.
            guard !modifiers.subtracting(.shift).isEmpty, let key = event.charactersIgnoringModifiers?.uppercased(), !key.isEmpty else { return }
            shortcut = GlobalShortcut(keyCode: Int(event.keyCode), key: key, modifiers: modifiers)
            stop()
        }
    }
}
