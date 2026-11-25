import AppKit
import Quartz

/// Opens a work full size in Quick Look, the preview Finder shows on Space: zoom,
/// full screen and "Open with Preview" come with it.
///
/// It lives at app level, not in a view: the menu-bar card closes as soon as the
/// preview takes focus, and the preview must outlive it.
@MainActor
final class ImagePreview: NSObject, QLPreviewPanelDataSource {
    static let shared = ImagePreview()

    private var item: URL?
    private let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Salon Preview", isDirectory: true)

    var isShowing: Bool { QLPreviewPanel.sharedPreviewPanelExists() && QLPreviewPanel.shared().isVisible }

    func show(_ file: URL, title: String) {
        guard let copy = typedCopy(of: file, title: title), let panel = QLPreviewPanel.shared() else { return }
        item = copy
        panel.dataSource = self
        panel.reloadData()
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
    }

    /// Space in the Collection window: open, or close when already open.
    func toggle(_ file: URL, title: String) {
        if isShowing { QLPreviewPanel.shared().orderOut(nil) } else { show(file, title: title) }
    }

    /// The cache stores images as ".img", which Quick Look can't read as a picture.
    /// A copy named after the work, with the real extension, also gives the preview a proper title.
    private func typedCopy(of file: URL, title: String) -> URL? {
        let fm = FileManager.default
        try? fm.removeItem(at: directory)
        guard (try? fm.createDirectory(at: directory, withIntermediateDirectories: true)) != nil,
              let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        let header = (try? handle.read(upToCount: 12)) ?? Data()
        try? handle.close()

        let name = title.replacingOccurrences(of: "[/:]", with: "-", options: .regularExpression).prefix(80)
        let copy = directory.appendingPathComponent(String(name).isEmpty ? "Artwork" : String(name))
            .appendingPathExtension(Self.fileExtension(for: header))
        return (try? fm.copyItem(at: file, to: copy)) != nil ? copy : nil
    }

    static func fileExtension(for header: Data) -> String {
        let bytes = [UInt8](header)
        if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "png" }
        if bytes.starts(with: [0x49, 0x49, 0x2A, 0x00]) || bytes.starts(with: [0x4D, 0x4D, 0x00, 0x2A]) { return "tiff" }
        if bytes.starts(with: Array("GIF8".utf8)) { return "gif" }
        if bytes.count >= 12, bytes[0..<4].elementsEqual("RIFF".utf8), bytes[8..<12].elementsEqual("WEBP".utf8) { return "webp" }
        return "jpg"
    }

    // MARK: QLPreviewPanelDataSource

    nonisolated func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        MainActor.assumeIsolated { item == nil ? 0 : 1 }
    }

    nonisolated func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        MainActor.assumeIsolated { item as NSURL? }
    }
}
