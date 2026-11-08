import SalonCore
import SwiftUI

/// The popover is the app: the museum card in one of its states.
struct PopoverView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch model.phase {
                case .loading(let sourceName):
                    LoadingCard(sourceName: sourceName, nextNumber: (model.current?.number ?? 0) + 1)
                case .failed(let sourceID, let message):
                    ErrorCard(sourceName: sourceID.flatMap { model.source($0)?.info.name }, message: message, retryMinutes: model.retryMinutes)
                case .idle:
                    if let entry = model.current {
                        MuseumCard(entry: entry).id(entry.id)
                    } else {
                        LoadingCard(sourceName: nil, nextNumber: 1)
                    }
                }
            }
            .transition(.opacity)
            CardToolbar()
        }
        .frame(width: Theme.Layout.popoverWidth)
        .background(Theme.Palette.surface)
        .animation(reduceMotion ? nil : Theme.Motion.cardCrossfade, value: model.phase)
        .animation(reduceMotion ? nil : Theme.Motion.cardCrossfade, value: model.current?.id)
    }
}

/// Next · Keep · History · Settings
struct CardToolbar: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        let busy = model.phase != .idle
        let entry = model.current
        let kept = entry?.isKept ?? false
        let accent = Theme.Palette.accent(entry?.palette)

        HStack(spacing: 2) {
            Button { model.next() } label: {
                Label("Next", systemImage: "arrow.right").labelStyle(.titleAndIcon)
            }
            .disabled(busy)
            .opacity(busy ? 0.4 : 1)

            if model.phase.isFailed == false {
                Button { if let entry { withAnimation(Theme.Motion.keep) { model.toggleKeep(entry) } } } label: {
                    Label(kept ? "Kept" : "Keep", systemImage: kept ? "bookmark.fill" : "bookmark")
                }
                .buttonStyle(ToolbarButtonStyle(tint: kept ? accent : Theme.Palette.ink))
                .background(RoundedRectangle(cornerRadius: Theme.Radius.button).fill(kept ? Theme.Palette.accentSoft(entry?.palette) : .clear))
                .disabled(busy || entry == nil)
                .opacity(busy ? 0.4 : 1)
                .accessibilityValue(kept ? "Kept" : "Not kept")
            }

            Spacer()

            Button { open(window: true) } label: { Image(systemName: "rectangle.stack") }
                .buttonStyle(ToolbarButtonStyle(tint: Theme.Palette.ink2))
                .help("History")
                .accessibilityLabel("History")
            Button { open(window: false) } label: { Image(systemName: "slider.horizontal.3") }
                .buttonStyle(ToolbarButtonStyle(tint: Theme.Palette.ink2))
                .help("Settings")
                .accessibilityLabel("Settings")
        }
        .buttonStyle(ToolbarButtonStyle())
        .padding(.horizontal, Theme.Space.group)
        .padding(.vertical, 6)
        .hairline(.top)
    }

    private func open(window collection: Bool) {
        NSApp.activate(ignoringOtherApps: true)
        if collection { openWindow(id: CollectionWindow.id) } else { openSettings() }
    }
}

extension AppModel.Phase {
    var isLoading: Bool { if case .loading = self { true } else { false } }
    var isFailed: Bool { if case .failed = self { true } else { false } }
}
