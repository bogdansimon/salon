import AppKit
import SalonCore
import SwiftUI

/// The popover is the app: the museum card in one of its states.
struct PopoverView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The card's natural height, measured inside the scroll view.
    @State private var cardHeight: CGFloat?

    /// Room for the card under the menu bar, leaving the toolbar and a margin on screen.
    private var maxCardHeight: CGFloat {
        (NSScreen.main?.visibleFrame.height ?? 900) - Theme.Layout.toolbarButton - 48
    }

    var body: some View {
        VStack(spacing: 0) {
            // The card scrolls as a whole once it's taller than the screen (a long
            // description opened with More); the toolbar stays put below it.
            ScrollView {
                card.onGeometryChange(for: CGFloat.self) { $0.size.height } action: { cardHeight = $0 }
            }
            .scrollBounceBehavior(.basedOnSize)
            // An explicit height: in the self-sizing popover a ScrollView without one collapses.
            .frame(height: cardHeight.map { min($0, maxCardHeight) })
            CardToolbar()
        }
        .frame(width: Theme.Layout.popoverWidth)
        .background(Theme.Palette.surface)
        .background(ActivateWhenShown())
        .environment(\.showsTooltips, false)
        .animation(reduceMotion ? nil : Theme.Motion.cardCrossfade, value: model.phase)
        .animation(reduceMotion ? nil : Theme.Motion.cardCrossfade, value: model.current?.id)
    }

    private var card: some View {
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
    }
}

/// Makes Salon the active app each time the card opens. Only the active app may
/// change the pointer, so without this the links' hand appeared only after a first click.
private struct ActivateWhenShown: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { WindowWatcher() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    final class WindowWatcher: NSView {
        private var observer: NSObjectProtocol?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observer.map(NotificationCenter.default.removeObserver)
            observer = nil
            guard let window else { return }
            observer = NotificationCenter.default.addObserver(
                forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main
            ) { [weak window] _ in
                guard let window, window.occlusionState.contains(.visible) else { return }
                NSApp.activate()
                window.makeKey()
            }
        }
    }
}

/// Next · Save · Pause · Collection · Settings
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
            .hoverTip(nextHelp)

            if model.phase.isFailed == false {
                Button { if let entry { withAnimation(Theme.Motion.keep) { model.toggleKeep(entry) } } } label: {
                    Label(kept ? "Saved" : "Save", systemImage: kept ? "bookmark.fill" : "bookmark")
                }
                .buttonStyle(ToolbarButtonStyle(tint: kept ? accent : Theme.Palette.ink))
                .background(RoundedRectangle(cornerRadius: Theme.Radius.button).fill(kept ? Theme.Palette.accentSoft(entry?.palette) : .clear))
                .disabled(busy || entry == nil)
                .opacity(busy ? 0.4 : 1)
                .accessibilityValue(kept ? "Saved" : "Not saved")
                .hoverTip(kept ? "Remove from your saved works" : "Save this work to your collection")
            }

            Spacer()

            Button { model.togglePause() } label: { Image(systemName: model.isPaused ? "play" : "pause") }
                .buttonStyle(ToolbarButtonStyle(tint: Theme.Palette.ink2))
                .hoverTip(model.isPaused ? "Resume changing: \(model.settings.resumeFrequency.title.lowercased())" : "Pause changing")
                .accessibilityLabel(model.isPaused ? "Resume changing" : "Pause changing")
            Button { open(window: true) } label: { Image(systemName: "rectangle.stack") }
                .buttonStyle(ToolbarButtonStyle(tint: Theme.Palette.ink2))
                .hoverTip("Collection")
                .accessibilityLabel("Collection")
            Button { open(window: false) } label: { Image(systemName: "slider.horizontal.3") }
                .buttonStyle(ToolbarButtonStyle(tint: Theme.Palette.ink2))
                .hoverTip("Settings")
                .accessibilityLabel("Settings")
        }
        .buttonStyle(ToolbarButtonStyle())
        .padding(.horizontal, Theme.Space.group)
        .padding(.vertical, 6)
        .hairline(.top)
    }

    private var nextHelp: String {
        let shortcut = model.settings.nextShortcut.map { " (\($0.displayString))" } ?? ""
        return "Hang a new work now" + shortcut
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
