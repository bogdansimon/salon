#if DEBUG
import AppKit
import SalonCore
import SwiftUI

/// Debug-only: `Salon --screenshots <dir>` hangs a few works into a scratch data
/// folder (never touching the real desktop or ~/Library data), then renders the
/// real views to PNGs for the README and exits.
@MainActor
enum ScreenshotMode {
    static var outputDirectory: URL? {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: "--screenshots"), args.indices.contains(index + 1) else { return nil }
        return URL(fileURLWithPath: args[index + 1], isDirectory: true)
    }

    static func model(for output: URL) -> AppModel {
        AppModel(paths: AppPaths(root: output.appendingPathComponent("data")), dryRun: true)
    }

    static func run(_ model: AppModel, into output: URL) {
        Task {
            if model.history.count < 4 {
                for _ in 0..<(4 - model.history.count) { await model.change() }
            }
            if let first = model.history.first { model.toggleKeep(first) }
            for (name, dark) in [("light", false), ("dark", true)] {
                await capture(PopoverView(), model: model, width: Theme.Layout.popoverWidth, dark: dark, to: output.appendingPathComponent("popover-\(name).png"))
            }
            await capture(CollectionWindow().frame(width: 1100, height: 720), model: model, width: 1100, dark: false, to: output.appendingPathComponent("collection.png"))
            await capture(ArtworkSettings(), model: model, width: Theme.Layout.settingsWidth, dark: false, to: output.appendingPathComponent("settings-artwork.png"))
            await capture(SourcesSettings(), model: model, width: Theme.Layout.settingsWidth, dark: false, to: output.appendingPathComponent("settings-sources.png"))
            NSApp.terminate(nil)
        }
    }

    private static func capture<V: View>(_ view: V, model: AppModel, width: CGFloat, dark: Bool, to url: URL) async {
        let host = NSHostingView(rootView: view.environment(model).frame(width: width))
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        host.appearance = appearance
        let window = NSWindow(contentRect: CGRect(x: -20_000, y: -20_000, width: width, height: 100), styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = appearance
        window.contentView = host
        window.orderFrontRegardless()
        // Let async thumbnails and layout settle, then size to fit.
        for _ in 0..<3 {
            try? await Task.sleep(for: .milliseconds(700))
            window.setContentSize(host.fittingSize)
        }
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
        window.orderOut(nil)
    }
}
#endif
