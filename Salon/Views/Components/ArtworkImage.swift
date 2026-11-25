import AppKit
import SalonCore
import SwiftUI

/// A work, fitted inside `maxSize`, never cropped or rounded, with the UI shadow.
/// Loads a downsampled copy of the cached original.
struct ArtworkImage: View {
    var file: URL?
    var maxSize: CGSize
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: maxSize.width, maxHeight: maxSize.height)
                    .workShadow()
            } else {
                MissingImage(size: CGSize(width: maxSize.height * 0.8, height: maxSize.height))
            }
        }
        .task(id: file) {
            image = await Thumbnails.shared.image(for: file, maxPixelSize: Int(max(maxSize.width, maxSize.height) * 2))
        }
    }
}

/// A work that opens full size in Quick Look when clicked. A small ⤢ badge on
/// hover says so; the pointer stays an arrow, as on any Mac button.
struct PreviewableArtwork: View {
    var file: URL?
    var title: String
    var maxSize: CGSize
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            if let file { ImagePreview.shared.show(file, title: title) }
        } label: {
            ArtworkImage(file: file, maxSize: maxSize)
                .overlay(alignment: .topTrailing) {
                    if hovering, file != nil {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(6)
                            .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
                            .padding(8)
                            .transition(.opacity)
                    }
                }
        }
        .buttonStyle(.plain)
        .disabled(file == nil)
        .onHover { hover in withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) { hovering = hover } }
        .hoverTip("View full size", .insideBottom)
        .accessibilityLabel("View full size")
    }
}

/// Stand-in when the image isn't cached (e.g. evicted from an old history item).
struct MissingImage: View {
    var size: CGSize

    var body: some View {
        Rectangle()
            .strokeBorder(Theme.Palette.rule, lineWidth: 1)
            .frame(width: size.width, height: size.height)
            .overlay {
                Image(systemName: "photo")
                    .foregroundStyle(Theme.Palette.ink3)
                    .accessibilityLabel("Image not cached")
            }
    }
}

/// The wall label shared by the card and the inspector: artist, title, date, medium, museum.
struct WallLabel: View {
    var artwork: Artwork

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.labelLines) {
            if let artist = artwork.artist {
                let details = ArtistDetails(artwork.artistDetails)
                VStack(alignment: .leading, spacing: Theme.Space.tight) {
                    // "REMBRANDT (1606–1669)": only the name is the link.
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        WikipediaLink(url: artwork.artistWikipediaURL) {
                            artistText(artist)
                                .underline(artwork.artistWikipediaURL != nil, color: Theme.Palette.rule)
                                .textCase(.uppercase)
                                .foregroundStyle(Theme.Palette.ink2)
                        }
                        if let lifespan = details.lifespan {
                            artistText(" (\(lifespan))")
                                .textCase(.uppercase)
                                .foregroundStyle(Theme.Palette.ink3)
                                .fixedSize()
                        }
                    }
                    if let nationality = details.nationality {
                        Text(nationality).font(Theme.Typeface.metadata).foregroundStyle(Theme.Palette.ink3)
                    }
                }
            }
            WikipediaLink(url: artwork.titleWikipediaURL) { title }
            VStack(alignment: .leading, spacing: 0) {
                if let line = [artwork.medium, artwork.dimensions].compactMap({ $0 }).joined(separator: " · ").nilIfEmpty {
                    // Wrap in full: the self-sizing popover otherwise cuts this to one line.
                    Text(line).fixedSize(horizontal: false, vertical: true)
                }
                WikipediaLink(url: artwork.museumWikipediaURL) {
                    Text(artwork.museum).underline(artwork.museumWikipediaURL != nil, color: Theme.Palette.rule)
                }
            }
            .font(Theme.Typeface.metadata)
            .lineSpacing(Theme.LineSpacing.metadata)
            .foregroundStyle(Theme.Palette.ink3)
        }
        .textSelection(.enabled)
    }

    private func artistText(_ text: String) -> Text {
        Text(text).font(Theme.Typeface.artist).tracking(Theme.Tracking.artist)
    }

    private var title: some View {
        var text = AttributedString(artwork.title)
        text.foregroundColor = Theme.Palette.ink
        if artwork.titleWikipediaURL != nil {
            // Underline the title only, not the date after it.
            text.underlineStyle = Text.LineStyle(pattern: .solid, color: Theme.Palette.rule)
        }
        if let date = artwork.date {
            var suffix = AttributedString(", \(date)")
            suffix.foregroundColor = Theme.Palette.ink2
            text += suffix
        }
        return Text(text)
            .font(Theme.Typeface.workTitle)
            .lineSpacing(Theme.LineSpacing.workTitle)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Wraps a wall-label line in a link to its English Wikipedia page, when there is one.
private struct WikipediaLink<Label: View>: View {
    var url: URL?
    @ViewBuilder var label: Label

    var body: some View {
        if let url {
            Link(destination: url) { label }
                .buttonStyle(.plain)
                .linkCursor()
                .hoverTip("Open on Wikipedia")
        } else {
            label
        }
    }
}

/// "View at the Rijksmuseum ↗": an underlined, quiet link.
struct MuseumLink: View {
    var artwork: Artwork
    var source: ArtSource?

    var body: some View {
        if let url = artwork.objectURL {
            Link(destination: url) {
                Text(label(for: url) + " ↗")
                    .font(Theme.Typeface.link)
                    .underline(color: Theme.Palette.rule)
                    .foregroundStyle(Theme.Palette.ink2)
            }
            .buttonStyle(.plain)
            .linkCursor()
            .hoverTip("Open \(url.host ?? "the museum’s page") in your browser")
        }
    }

    private func label(for url: URL) -> String {
        if url.host?.contains("wikipedia.org") == true { return "Read on Wikipedia" }
        if artwork.sourceID == .wikidata { return "View at the museum" }
        return "View at \(source?.info.shortName ?? artwork.museum)"
    }
}

/// "From Wikipedia": where a description came from, when not the museum itself.
struct SummaryCredit: View {
    var artwork: Artwork

    var body: some View {
        if let credit = artwork.summaryCredit {
            // Links to the article: the text is CC BY-SA, and this is its attribution.
            if let url = artwork.summaryURL {
                Link(destination: url) {
                    Text("From \(credit)").labelCaps().underline(color: Theme.Palette.rule)
                }
                .buttonStyle(.plain)
                .linkCursor()
                .hoverTip("Open on Wikipedia")
            } else {
                Text("From \(credit)").labelCaps()
            }
        }
    }
}

extension View {
    /// The pointing hand while the pointer is over a link.
    func linkCursor() -> some View { modifier(LinkCursor()) }
}

private struct LinkCursor: ViewModifier {
    @State private var pushed = false

    func body(content: Content) -> some View {
        if #available(macOS 15, *) {
            // Owned by SwiftUI, so it survives a hover tip appearing on top of the link
            // (that redraw reset the pushed cursor back to the arrow).
            content.pointerStyle(.link)
        } else {
            content
                .onHover { hovering in
                    guard hovering != pushed else { return }
                    hovering ? NSCursor.pointingHand.push() : NSCursor.pop()
                    pushed = hovering
                }
                // A card can change under a still pointer; don't leave the hand behind.
                .onDisappear { if pushed { NSCursor.pop(); pushed = false } }
        }
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
