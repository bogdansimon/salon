import AppKit
import SalonCore
import SwiftUI
import UniformTypeIdentifiers

struct StorageSettings: View {
    @Environment(AppModel.self) private var model
    @State private var confirmClearCache = false
    @State private var confirmClearHistory = false
    @State private var exportFormat: FavoritesExporter.Format = .json
    @State private var exportError: String?

    private let limits = [512, 1024, 2048, 5120]

    var body: some View {
        @Bindable var model = model
        Form {
            Section("Image cache") {
                SettingRow(title: "\(ByteCountFormatter.string(fromByteCount: model.cacheBytes, countStyle: .file)) · \(model.cacheCount) images",
                           help: "Full-size images of recent and kept works. Kept works are never removed.") {
                    Button("Clear Cache…") { confirmClearCache = true }
                }
                Picker("Keep up to", selection: $model.settings.cacheLimitMB) {
                    ForEach(limits, id: \.self) { mb in
                        Text(ByteCountFormatter.string(fromByteCount: Int64(mb) * 1_048_576, countStyle: .memory)).tag(mb)
                    }
                }
                .fixedSize()
            }

            Section("History") {
                SettingRow(title: historySummary, help: "Clearing history keeps your kept works and the cache.") {
                    Button("Clear History…") { confirmClearHistory = true }
                        .disabled(model.history.isEmpty)
                }
            }

            Section("Export") {
                SettingRow(title: "Export kept works", help: "Title, artist, date, museum, object link and the day it was hung.") {
                    HStack {
                        Picker("", selection: $exportFormat) {
                            ForEach(FavoritesExporter.Format.allCases, id: \.self) { Text($0.displayName).tag($0) }
                        }
                        .labelsHidden()
                        .fixedSize()
                        Button("Export…", action: export).disabled(model.keptCount == 0)
                    }
                }
                if let exportError {
                    Text(exportError).font(Theme.Typeface.help).foregroundStyle(Theme.Palette.healthBad)
                }
            }
        }
        .settingsForm()
        .alert("Clear the image cache?", isPresented: $confirmClearCache) {
            Button("Cancel", role: .cancel) {}
            Button("Clear Cache", role: .destructive) { model.clearCache() }
        } message: {
            Text("Downloaded images are removed. Kept works and the current wallpaper stay.")
        }
        .alert("Clear all history?", isPresented: $confirmClearHistory) {
            Button("Cancel", role: .cancel) {}
            Button("Clear History", role: .destructive) { model.clearHistory() }
        } message: {
            Text("Salon will forget the \(model.history.count) works it has shown. Kept works and the image cache stay, and works already shown still won’t repeat.")
        }
    }

    private var historySummary: String {
        let count = "\(model.history.count) work\(model.history.count == 1 ? "" : "s")"
        guard let start = model.historyStart else { return count }
        return "\(count) since \(start.formatted(.dateTime.day().month(.wide).year()))"
    }

    private func export() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Salon kept works.\(exportFormat.rawValue)"
        panel.allowedContentTypes = [exportFormat == .json ? .json : .commaSeparatedText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try model.exportKept(as: exportFormat).write(to: url, options: .atomic)
            exportError = nil
        } catch {
            exportError = "Couldn’t export: \(error.localizedDescription)"
        }
    }
}
