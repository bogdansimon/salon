import SalonCore
import SwiftUI

/// The museum card (design/Main, states 1–3): the work on its plate, then the wall
/// label read top to bottom, the description and the museum link.
struct MuseumCard: View {
    @Environment(AppModel.self) private var model
    var entry: HistoryEntry
    /// Width ÷ height of the work; from the source's reported size, else from the loaded image.
    @State private var loadedAspect: Double?

    private var aspect: Double? {
        loadedAspect ?? entry.artwork.reportedPixelSize.map(\.aspectRatio).flatMap { $0 > 0 ? $0 : nil }
    }

    /// The work fitted whole inside the card's box; the plate grows to hold it.
    private var workSize: CGSize {
        let box = Theme.Layout.cardWorkMax
        guard let aspect else { return CGSize(width: box.height * 0.8, height: box.height) }
        let width = min(box.width, box.height * aspect)
        return CGSize(width: width.rounded(), height: (width / aspect).rounded())
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Theme.Palette.mat
                ArtworkImage(file: model.imageFile(for: entry), maxSize: workSize) { loadedAspect = $0 }
            }
            .frame(height: max(Theme.Layout.cardPlateHeight, workSize.height + 2 * Theme.Layout.cardPlateInset))

            VStack(alignment: .leading, spacing: Theme.Space.labelLines) {
                HStack {
                    Text(DateText.hung(entry.shownAt))
                    Spacer()
                    Text("No. \(entry.number)").monospacedDigit()
                }
                .labelCaps()

                WallLabel(artwork: entry.artwork)

                if let summary = entry.artwork.summary {
                    Hairline()
                    DescriptionText(text: summary)
                    SummaryCredit(artwork: entry.artwork)
                }

                MuseumLink(artwork: entry.artwork, source: model.source(entry.artwork.sourceID))
                    .padding(.bottom, Theme.Space.labelLines + 2)
            }
            .padding(.horizontal, Theme.Space.card)
            .padding(.top, Theme.Space.row)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Five lines with a fade and "More"; expanded, it scrolls inside the card.
struct DescriptionText: View {
    var text: String
    @State private var expanded = false
    @State private var fullHeight: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var needsMore: Bool { fullHeight > Theme.Layout.collapsedDescription + 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Group {
                if expanded {
                    // An explicit height: the popover sizes to its content, and a ScrollView
                    // with only a max height reports ~0 there, so the text vanished.
                    ScrollView { paragraph.fixedSize(horizontal: false, vertical: true) }
                        .frame(height: min(fullHeight, Theme.Layout.expandedDescription))
                } else {
                    paragraph
                        .frame(height: needsMore ? Theme.Layout.collapsedDescription : nil, alignment: .top)
                        .clipped()
                        .mask {
                            LinearGradient(stops: [.init(color: .black, location: needsMore ? 0.62 : 1), .init(color: .clear, location: 1)],
                                           startPoint: .top, endPoint: .bottom)
                        }
                }
            }
            .background {
                // Measure the natural height to decide whether "More" is needed and how tall to open.
                paragraph.fixedSize(horizontal: false, vertical: true).hidden()
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { fullHeight = $0 }
            }

            if needsMore {
                Button {
                    withAnimation(reduceMotion ? nil : Theme.Motion.moreLess) { expanded.toggle() }
                } label: {
                    HStack(spacing: Theme.Space.iconLabel) {
                        Text(expanded ? "Less" : "More")
                        Image(systemName: expanded ? "chevron.up" : "chevron.down").imageScale(.small)
                    }
                    .font(Theme.Typeface.link)
                    .foregroundStyle(Theme.Palette.ink2)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var paragraph: some View {
        Text(text)
            .font(Theme.Typeface.description)
            .lineSpacing(Theme.LineSpacing.description)
            .foregroundStyle(Theme.Palette.ink2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
    }
}
