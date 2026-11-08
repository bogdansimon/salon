import SalonCore
import SwiftUI

/// The museum card (design/Main, states 1–3): the work on its plate, then the wall
/// label read top to bottom, the description and the museum link.
struct MuseumCard: View {
    @Environment(AppModel.self) private var model
    var entry: HistoryEntry

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Theme.Palette.mat
                ArtworkImage(file: model.imageFile(for: entry), maxSize: Theme.Layout.cardWorkMax)
            }
            .frame(height: Theme.Layout.cardPlateHeight)

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
                    ScrollView { paragraph }
                        .frame(maxHeight: min(fullHeight, Theme.Layout.expandedDescription))
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
                // Measure the natural height once to decide whether "More" is needed.
                paragraph.fixedSize(horizontal: false, vertical: true).hidden()
                    .background(GeometryReader { proxy in Color.clear.onAppear { fullHeight = proxy.size.height } })
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
