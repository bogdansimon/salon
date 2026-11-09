import AppKit
import SalonCore

/// Renders artworks at each display's native resolution and sets them as the
/// desktop picture. macOS crossfades the change itself.
@MainActor
final class WallpaperService {
    struct Assignment {
        var screen: NSScreen
        var imageFile: URL
        var palette: ArtworkPalette
    }

    private let directory: URL
    /// Renders files but leaves the desktop alone (debug screenshot mode).
    private let dryRun: Bool

    init(directory: URL, dryRun: Bool = false) {
        self.directory = directory
        self.dryRun = dryRun
    }

    /// Renders and sets one image per screen. Returns the written file names.
    func apply(_ assignments: [Assignment], settings: AppSettings) async throws -> [String] {
        let dark = NSApp.effectiveAppearance.isDark
        var written: [String] = []
        for assignment in assignments {
            let display = Self.displayInfo(for: assignment.screen, avoidDock: settings.avoidDock)
            let options = WallpaperRenderer.Options(
                alwaysMat: settings.alwaysUseMat,
                margin: settings.matMargin,
                matColor: PaletteRules.matColor(style: settings.matStyle, edge: assignment.palette.edge, darkAppearance: dark)
            )
            // A fresh file name each time: macOS caches desktop pictures by URL.
            let output = directory.appendingPathComponent("\(UUID().uuidString).jpg")
            let source = assignment.imageFile
            try await Task.detached(priority: .userInitiated) {
                let maxSide = max(display.size.width, display.size.height) * 2
                guard let image = ImageInspector.image(at: source, maxPixelSize: maxSide),
                      let rendered = WallpaperRenderer.render(image, on: display, options: options) else {
                    throw SourceError.unsupportedImage
                }
                try WallpaperRenderer.writeJPEG(rendered, to: output)
            }.value
            if !dryRun { try NSWorkspace.shared.setDesktopImageURL(output, for: assignment.screen, options: [
                .imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue,
                .allowClipping: true,
            ]) }
            written.append(output.lastPathComponent)
        }
        cleanUp(keeping: Set(written))
        return written
    }

    /// Puts the already-rendered files on the active Space. `setDesktopImageURL`
    /// only changes the Space that is active at the time (there is no public
    /// all-Spaces API), so this runs at launch and on every Space switch.
    /// `fileNames` are in `NSScreen.screens` order, as `apply` returns them.
    func hangOnActiveSpace(_ fileNames: [String]) {
        guard !dryRun, !fileNames.isEmpty else { return }
        for (index, screen) in NSScreen.screens.enumerated() {
            let file = directory.appendingPathComponent(fileNames[index % fileNames.count])
            guard FileManager.default.fileExists(atPath: file.path),
                  NSWorkspace.shared.desktopImageURL(for: screen)?.standardizedFileURL != file.standardizedFileURL else { continue }
            try? NSWorkspace.shared.setDesktopImageURL(file, for: screen, options: [
                .imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue,
                .allowClipping: true,
            ])
        }
    }

    /// Removes rendered wallpapers that are no longer on screen.
    func cleanUp(keeping: Set<String>) {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for file in files where !keeping.contains(file.lastPathComponent) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    static func displayInfo(for screen: NSScreen, avoidDock: Bool) -> WallpaperRenderer.Display {
        let scale = screen.backingScaleFactor
        let size = PixelSize(width: Int(screen.frame.width * scale), height: Int(screen.frame.height * scale))
        // Menu bar: the gap between the top of the screen and the top of the visible frame.
        let menuBar = max(0, screen.frame.maxY - screen.visibleFrame.maxY) * scale
        // Dock (when it sits at the bottom and isn't hidden): the gap below the visible frame.
        let dock = avoidDock ? max(0, screen.visibleFrame.minY - screen.frame.minY) * scale : 0
        return WallpaperRenderer.Display(size: size, topInset: menuBar, bottomInset: dock, backingScale: scale)
    }

    /// A small render for the live preview in Settings › Artwork.
    nonisolated static func preview(of image: CGImage, size: PixelSize, palette: ArtworkPalette, settings: AppSettings, dark: Bool) -> CGImage? {
        let display = WallpaperRenderer.Display(size: size, topInset: Double(size.height) * 0.03,
                                                bottomInset: settings.avoidDock ? Double(size.height) * 0.07 : 0,
                                                backingScale: Double(size.width) / 1440)
        let options = WallpaperRenderer.Options(alwaysMat: settings.alwaysUseMat, margin: settings.matMargin,
                                                matColor: PaletteRules.matColor(style: settings.matStyle, edge: palette.edge, darkAppearance: dark))
        return WallpaperRenderer.render(image, on: display, options: options)
    }
}
