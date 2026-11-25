import SalonCore
import SwiftUI

/// Which collections Salon picks from: a switch per source, nothing else.
/// (Health is still tracked internally: a failing source is skipped for a while.)
struct SourcesSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section {
                ForEach(model.sources, id: \.id) { source in
                    LabeledContent {
                        Toggle("", isOn: enabledBinding(source))
                            .labelsHidden()
                            .toggleStyle(.switch)
                            // At least one collection stays on, or there is nothing to hang.
                            .disabled(isLastEnabled(source))
                            .accessibilityLabel("Use \(source.info.name)")
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(source.info.name).font(Theme.Typeface.body)
                            Link(destination: source.info.website) {
                                Text(displayHost(source.info.website) + " ↗")
                                    .font(Theme.Typeface.help)
                                    .underline(color: Theme.Palette.rule)
                                    .foregroundStyle(Theme.Palette.ink3)
                            }
                            .buttonStyle(.plain)
                            .linkCursor()
                            .help("Open \(displayHost(source.info.website)) in your browser")
                        }
                    }
                }
            } header: {
                Text("Each new work comes from one of the collections you turn on, chosen at random.")
                    .font(Theme.Typeface.help)
                    .foregroundStyle(Theme.Palette.ink3)
                    .textCase(nil)
            }
        }
        .settingsForm()
    }

    /// "metmuseum.org", without "www."
    private func displayHost(_ url: URL) -> String {
        let host = url.host ?? url.absoluteString
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    private func isLastEnabled(_ source: ArtSource) -> Bool {
        model.settings.isEnabled(source) && model.sources.filter { model.settings.isEnabled($0) }.count == 1
    }

    private func enabledBinding(_ source: ArtSource) -> Binding<Bool> {
        Binding {
            model.settings.isEnabled(source)
        } set: { on in
            model.settings.sourceEnabled[source.id] = on
        }
    }
}
