import AppKit
import SalonCore
import SwiftUI

/// Native macOS settings: toolbar tabs, grouped forms (design/Settings*).
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings().tabItem { Label("General", systemImage: "gearshape") }
            ArtworkSettings().tabItem { Label("Artwork", systemImage: "photo.artframe") }
            SourcesSettings().tabItem { Label("Sources", systemImage: "building.columns") }
            StorageSettings().tabItem { Label("Storage", systemImage: "internaldrive") }
            AboutSettings().tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: Theme.Layout.settingsWidth)
        .tint(Theme.Palette.controlOn)
    }
}

/// A settings row: title, optional help line, trailing control.
struct SettingRow<Control: View>: View {
    var title: String
    var help: String?
    @ViewBuilder var control: Control

    var body: some View {
        LabeledContent {
            control
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.Typeface.body)
                if let help {
                    Text(help).font(Theme.Typeface.help).foregroundStyle(Theme.Palette.ink3)
                }
            }
        }
    }
}

extension View {
    /// The shared look for every settings tab.
    func settingsForm() -> some View {
        formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(Theme.Palette.paper)
            .background(FocusClearer())
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Text fields keep keyboard focus (the blue highlight) until something else takes it,
/// and the first one is focused when a tab opens. This leaves nothing focused on open
/// and drops focus when you click anywhere that isn't a text field.
private struct FocusClearer: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { Watcher() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    final class Watcher: NSView {
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            guard let window else { return }
            DispatchQueue.main.async { [weak window] in window?.makeFirstResponder(nil) }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak window] event in
                guard let window, event.window === window,
                      let hit = window.contentView?.hitTest(event.locationInWindow),
                      !Self.isTextInput(hit) else { return event }
                window.makeFirstResponder(nil)
                return event
            }
        }

        private static func isTextInput(_ view: NSView) -> Bool {
            var current: NSView? = view
            while let v = current {
                if v is NSText || v is NSTextField || v is NSDatePicker { return true }
                current = v.superview
            }
            return false
        }

        deinit {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }
    }
}
