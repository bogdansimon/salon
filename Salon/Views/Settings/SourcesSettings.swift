import SalonCore
import SwiftUI

struct SourcesSettings: View {
    @Environment(AppModel.self) private var model
    @State private var checking = false

    var body: some View {
        Form {
            Section {
                ForEach(model.sources, id: \.id) { source in
                    SourceRow(source: source)
                }
            } header: {
                HStack {
                    Text("Salon picks a random enabled collection each day. API keys stay in your Keychain.")
                    Spacer()
                    Text("\(enabledCount) of \(model.sources.count) enabled").monospacedDigit()
                }
                .font(Theme.Typeface.help)
                .foregroundStyle(Theme.Palette.ink3)
                .textCase(nil)
            } footer: {
                HStack {
                    Text(footer).font(Theme.Typeface.help).foregroundStyle(Theme.Palette.ink3)
                    Spacer()
                    Button(checking ? "Checking…" : "Check All Now") {
                        checking = true
                        Task { await model.checkAllSources(); checking = false }
                    }
                    .disabled(checking)
                }
            }
        }
        .settingsForm()
    }

    private var enabledCount: Int { model.sources.filter { model.settings.isEnabled($0) }.count }

    private var footer: String {
        let checked = model.lastHealthCheck.map { "Health checked \($0.formatted(.relative(presentation: .named)))" } ?? "Not checked yet"
        return "\(checked) · a source is skipped after \(SourceHealth.failingAfter) failed fetches"
    }
}

private struct SourceRow: View {
    @Environment(AppModel.self) private var model
    var source: ArtSource
    @State private var editingKey = false
    @State private var draftKey = ""
    @State private var storedKey: String?

    var body: some View {
        let enabled = model.settings.isEnabled(source)
        VStack(alignment: .leading, spacing: Theme.Space.group) {
            HStack(alignment: .top, spacing: Theme.Space.labelLines) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(source.info.name).font(Theme.Typeface.body)
                    Text(subtitle).font(Theme.Typeface.help).foregroundStyle(Theme.Palette.ink3)
                }
                Spacer()
                HealthBadge(status: model.healthStatus(source.id), enabled: enabled)
                Toggle("", isOn: enabledBinding).labelsHidden().toggleStyle(.switch).controlSize(.small)
                    .accessibilityLabel("Use \(source.info.name)")
            }
            if source.info.requiresAPIKey {
                keyField
            }
        }
        .padding(.vertical, 2)
        .onAppear { storedKey = model.apiKey(for: source.id) }
    }

    private var subtitle: String {
        var parts: [String] = []
        let health = model.health[source.id]
        if source.info.requiresAPIKey && (storedKey ?? "").isEmpty {
            parts.append("Needs an API key")
        } else if !source.info.requiresAPIKey {
            parts.append("No key needed")
        }
        if let error = health?.lastError, health?.consecutiveFailures ?? 0 > 0 {
            parts.append(error.trimmingCharacters(in: CharacterSet(charactersIn: ".")))
        }
        parts.append(DateText.lastFetch(health?.lastSuccess))
        if let latency = health?.lastLatency, latency > SourceHealth.slowLatency {
            parts.append("responses over \(Int(SourceHealth.slowLatency)) s")
        }
        if !source.info.hasQualityFlag { parts.append("no quality flag") }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder private var keyField: some View {
        if let key = storedKey, !key.isEmpty, !editingKey {
            HStack(spacing: Theme.Space.group) {
                Text("API key").font(Theme.Typeface.help).foregroundStyle(Theme.Palette.ink3)
                Text(String(repeating: "•", count: 13) + key.suffix(4)).font(Theme.Typeface.help).monospacedDigit()
                Button("Edit…") { draftKey = ""; editingKey = true }.controlSize(.small)
                Spacer()
                Label("Stored in Keychain", systemImage: "lock").font(Theme.Typeface.help).foregroundStyle(Theme.Palette.ink3)
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: Theme.Space.group) {
                    SecureField("Paste a new key", text: $draftKey)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 260)
                    Button("Save") {
                        model.setAPIKey(draftKey, for: source.id)
                        storedKey = model.apiKey(for: source.id)
                        draftKey = ""
                        editingKey = false
                    }
                    .disabled(draftKey.trimmingCharacters(in: .whitespaces).isEmpty)
                    if editingKey {
                        Button("Cancel") { editingKey = false }
                        Button("Remove", role: .destructive) {
                            model.setAPIKey(nil, for: source.id)
                            storedKey = nil
                            editingKey = false
                        }
                    }
                }
                if let help = source.info.apiKeyHelp {
                    Text(help).font(Theme.Typeface.help).foregroundStyle(Theme.Palette.ink3)
                }
            }
        }
    }

    private var enabledBinding: Binding<Bool> {
        Binding {
            model.settings.isEnabled(source)
        } set: { on in
            model.settings.sourceEnabled[source.id] = on
        }
    }
}
