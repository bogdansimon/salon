import SalonCore
import SwiftUI

struct AboutSettings: View {
    @Environment(AppModel.self) private var model

    static let repository = URL(string: "https://github.com/bogdansimon/salon")!

    var body: some View {
        Form {
            Section {
                HStack(spacing: 22) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 88, height: 88)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Salon").font(Theme.Typeface.display).foregroundStyle(Theme.Palette.ink)
                        Text("Version \(version)").font(Theme.Typeface.metadata).foregroundStyle(Theme.Palette.ink3)
                        Text("A painting a day, from the world’s open collections.")
                            .font(Theme.Typeface.tagline)
                            .foregroundStyle(Theme.Palette.ink2)
                            .padding(.top, 4)
                    }
                }
                .padding(.vertical, Theme.Space.group)
                Link("Source on GitHub ↗", destination: Self.repository).font(Theme.Typeface.link)
            }

            Section {
                ForEach(model.sources, id: \.id) { source in
                    LabeledContent(source.info.name) {
                        Text(source.info.credit).foregroundStyle(Theme.Palette.ink3)
                    }
                    .font(Theme.Typeface.link)
                }
                LabeledContent("Wikipedia") {
                    Text("Descriptions when a museum has none · CC BY-SA").foregroundStyle(Theme.Palette.ink3)
                }
                .font(Theme.Typeface.link)
            } header: {
                Text("With thanks to").labelCaps()
            } footer: {
                Text("Images are shown under each museum’s open-access terms. Salon is a personal project and is not affiliated with any museum.")
                    .font(Theme.Typeface.help)
                    .foregroundStyle(Theme.Palette.ink3)
            }
        }
        .settingsForm()
    }

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }
}
