import SalonCore
import SwiftUI

/// History & favourites (design/History, HistoryEmpty): a gallery of past works,
/// newest first, grouped by month, with an inspector for the selected one.
struct CollectionWindow: View {
    static let id = "collection"

    enum Filter: String, CaseIterable { case all = "All", kept = "Kept" }

    @Environment(AppModel.self) private var model
    @State private var filter: Filter = .all
    @State private var search = ""
    @State private var selection: UUID?

    var body: some View {
        HStack(spacing: 0) {
            Group {
                if visible.isEmpty {
                    EmptyCollection(filter: filter, searching: !search.isEmpty) { filter = .all }
                } else {
                    Gallery(sections: sections, selection: $selection)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.Palette.paper)

            if let entry = selectedEntry {
                Inspector(entry: entry)
                    .frame(width: Theme.Layout.inspectorWidth)
                    .background(Theme.Palette.surface)
                    .overlay(alignment: .leading) { Rectangle().fill(Theme.Palette.rule).frame(width: Theme.Space.hairline) }
            }
        }
        .frame(minWidth: 820, minHeight: 560)
        .navigationTitle("Collection")
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Show", selection: $filter) {
                    Text("All \(model.history.count)").tag(Filter.all)
                    Text("Kept \(model.keptCount)").tag(Filter.kept)
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
        }
        .searchable(text: $search, placement: .toolbar, prompt: "Title, artist, museum")
        .onAppear { if selection == nil { selection = visible.first?.id } }
        .onChange(of: filter) { selection = visible.first?.id }
    }

    private var visible: [HistoryEntry] {
        let entries = model.history.reversed().filter { filter == .all || $0.isKept }
        guard !search.isEmpty else { return Array(entries) }
        return entries.filter { entry in
            [entry.artwork.title, entry.artwork.artist, entry.artwork.museum].compactMap { $0 }
                .contains { $0.localizedCaseInsensitiveContains(search) }
        }
    }

    private var sections: [(title: String, entries: [HistoryEntry])] {
        var result: [(String, [HistoryEntry])] = []
        for entry in visible {
            let month = entry.shownAt.formatted(.dateTime.month(.wide).year())
            if result.last?.0 == month { result[result.count - 1].1.append(entry) } else { result.append((month, [entry])) }
        }
        return result
    }

    private var selectedEntry: HistoryEntry? {
        selection.flatMap { id in model.history.first { $0.id == id } }
    }
}

private struct Gallery: View {
    @Environment(AppModel.self) private var model
    var sections: [(title: String, entries: [HistoryEntry])]
    @Binding var selection: UUID?

    private let columns = Array(repeating: GridItem(.flexible(minimum: 120), spacing: 24, alignment: .top), count: 4)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ForEach(sections, id: \.title) { section in
                    HStack(alignment: .firstTextBaseline) {
                        Text(section.title).font(Theme.Typeface.section).foregroundStyle(Theme.Palette.ink)
                        Spacer()
                        Text("\(section.entries.count) work\(section.entries.count == 1 ? "" : "s")").labelCaps().monospacedDigit()
                    }
                    .padding(.bottom, Theme.Space.group)
                    .hairline(.bottom)
                    .padding(.top, section.title == sections.first?.title ? 0 : Theme.Space.group)

                    LazyVGrid(columns: columns, alignment: .leading, spacing: 26) {
                        ForEach(section.entries) { entry in
                            Tile(entry: entry, selected: selection == entry.id) { selection = entry.id }
                        }
                    }
                }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 26)
        }
    }
}

private struct Tile: View {
    @Environment(AppModel.self) private var model
    var entry: HistoryEntry
    var selected: Bool
    var action: () -> Void

    var body: some View {
        let accent = Theme.Palette.accent(entry.palette)
        Button(action: action) {
            VStack(alignment: .leading, spacing: 9) {
                ZStack {
                    RoundedRectangle(cornerRadius: Theme.Radius.tileMat).fill(Theme.Palette.matTile)
                    ArtworkImage(file: model.imageFile(for: entry), maxSize: CGSize(width: Theme.Layout.tileWorkMax, height: Theme.Layout.tileWorkMax))
                }
                .frame(height: Theme.Layout.tileMatHeight)
                .overlay {
                    if selected {
                        RoundedRectangle(cornerRadius: Theme.Radius.tileMat + 3).stroke(accent, lineWidth: 2).padding(-3)
                    }
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text(entry.artwork.title)
                        .font(Theme.Typeface.tileTitle)
                        .foregroundStyle(Theme.Palette.ink)
                    HStack(spacing: 5) {
                        if entry.isKept {
                            Image(systemName: "bookmark.fill").imageScale(.small)
                                .foregroundStyle(selected ? accent : Theme.Palette.ink3)
                                .accessibilityLabel("Kept")
                        }
                        Text(entry.artwork.artist ?? entry.artwork.museum)
                            .font(Theme.Typeface.tileArtist)
                            .tracking(Theme.Tracking.tile)
                            .textCase(.uppercase)
                            .foregroundStyle(Theme.Palette.ink3)
                    }
                }
                .lineLimit(1)
                .truncationMode(.tail)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct Inspector: View {
    @Environment(AppModel.self) private var model
    var entry: HistoryEntry
    @State private var working = false

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Theme.Palette.matTile
                ArtworkImage(file: model.imageFile(for: entry), maxSize: Theme.Layout.inspectorWorkMax)
            }
            .frame(height: Theme.Layout.inspectorPlate)

            ScrollView {
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
                        Text(summary)
                            .font(Theme.Typeface.description)
                            .lineSpacing(Theme.LineSpacing.description)
                            .foregroundStyle(Theme.Palette.ink2)
                            .textSelection(.enabled)
                        SummaryCredit(artwork: entry.artwork)
                    }
                    MuseumLink(artwork: entry.artwork, source: model.source(entry.artwork.sourceID))
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            VStack(alignment: .leading, spacing: 10) {
                if let kept = entry.keptAt {
                    Label(DateText.kept(kept), systemImage: "bookmark.fill")
                        .font(Theme.Typeface.metadata)
                        .foregroundStyle(Theme.Palette.accent(entry.palette))
                }
                HStack(spacing: Theme.Space.group) {
                    Button {
                        working = true
                        Task { await model.setAsWallpaper(entry); working = false }
                    } label: {
                        Text("Set as Wallpaper").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.Palette.ink)
                    .disabled(working)
                    Button { model.toggleKeep(entry) } label: {
                        Text(entry.isKept ? "Remove from Kept" : "Keep").frame(maxWidth: .infinity)
                    }
                }
                .controlSize(.large)
            }
            .padding(.horizontal, 22)
            .padding(.top, 14)
            .padding(.bottom, 18)
            .hairline(.top)
        }
    }
}

private struct EmptyCollection: View {
    var filter: CollectionWindow.Filter
    var searching: Bool
    var browseAll: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            HungFrame()
            VStack(spacing: Theme.Space.group) {
                Text(caption).labelCaps()
                Text(title).font(Theme.Typeface.emptyTitle).foregroundStyle(Theme.Palette.ink)
                Text(message)
                    .font(Theme.Typeface.emptyBody)
                    .lineSpacing(Theme.LineSpacing.emptyBody)
                    .foregroundStyle(Theme.Palette.ink2)
                    .multilineTextAlignment(.center)
            }
            if filter == .kept && !searching {
                Button("Browse All Works", action: browseAll)
            }
        }
        .frame(maxWidth: 380)
        .padding(Theme.Space.empty)
    }

    private var caption: String {
        if searching { return "No matches" }
        return filter == .kept ? "Kept · 0 works" : "Collection · 0 works"
    }

    private var title: String {
        if searching { return "Nothing by that name" }
        return filter == .kept ? "Nothing kept yet" : "Nothing hung yet"
    }

    private var message: String {
        if searching { return "Try a title, an artist or a museum." }
        if filter == .kept {
            return "When a work stays with you, press Keep on the menu-bar card. It will hang here, and Salon can show it again whenever you like."
        }
        return "Salon hangs a new work every day. Each one appears here, newest first."
    }
}

/// The empty-state illustration: an empty frame on a wire.
private struct HungFrame: View {
    var body: some View {
        ZStack(alignment: .top) {
            Path { path in
                path.move(to: CGPoint(x: 74, y: 4))
                path.addLine(to: CGPoint(x: 34, y: 30))
                path.move(to: CGPoint(x: 74, y: 4))
                path.addLine(to: CGPoint(x: 114, y: 30))
            }
            .stroke(Theme.Palette.ink3, lineWidth: 1)
            Circle().fill(Theme.Palette.ink3).frame(width: 4.4, height: 4.4).offset(y: 1.8)
            Rectangle()
                .strokeBorder(Theme.Palette.ink3, lineWidth: 1)
                .frame(width: 120, height: 90)
                .overlay { Rectangle().strokeBorder(Theme.Palette.rule, lineWidth: 0.5).padding(9) }
                .offset(y: 30)
        }
        .opacity(0.7)
        .frame(width: 148, height: 120)
        .accessibilityHidden(true)
    }
}
