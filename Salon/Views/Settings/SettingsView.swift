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
            .fixedSize(horizontal: false, vertical: true)
    }
}
