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
                VStack(alignment: .leading, spacing: Theme.Space.tight) {
                    Text(artist)
                        .font(Theme.Typeface.artist)
                        .tracking(Theme.Tracking.artist)
                        .textCase(.uppercase)
                        .foregroundStyle(Theme.Palette.ink2)
                    if let details = artwork.artistDetails {
                        Text(details).font(Theme.Typeface.metadata).foregroundStyle(Theme.Palette.ink3)
                    }
                }
            }
            title
            VStack(alignment: .leading, spacing: 0) {
                if let line = [artwork.medium, artwork.dimensions].compactMap({ $0 }).joined(separator: " · ").nilIfEmpty {
                    Text(line)
                }
                Text(artwork.museum)
            }
            .font(Theme.Typeface.metadata)
            .lineSpacing(Theme.LineSpacing.metadata)
            .foregroundStyle(Theme.Palette.ink3)
        }
        .textSelection(.enabled)
    }

    private var title: some View {
        var text = AttributedString(artwork.title)
        text.foregroundColor = Theme.Palette.ink
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
        }
    }

    private func label(for url: URL) -> String {
        if url.host?.contains("wikipedia.org") == true { return "Read on Wikipedia" }
        if artwork.sourceID == .wikidata { return "View at the museum" }
        return "View at \(source?.info.shortName ?? artwork.museum)"
    }
}

/// Wikipedia text is CC BY-SA, so it is credited where it's shown.
struct SummaryCredit: View {
    var artwork: Artwork

    var body: some View {
        if artwork.summaryCredit == "Wikipedia" {
            Text("From Wikipedia · CC BY-SA").labelCaps()
        }
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
