import AppKit
import SalonCore

/// Downsampled images for the card, tiles and inspector, decoded off the main thread.
@MainActor
final class Thumbnails {
    static let shared = Thumbnails()
    private let cache = NSCache<NSString, NSImage>()

    func image(for file: URL?, maxPixelSize: Int) async -> NSImage? {
        guard let file else { return nil }
        let key = "\(file.lastPathComponent)@\(maxPixelSize)" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        let cgImage = await Task.detached(priority: .userInitiated) {
            ImageInspector.image(at: file, maxPixelSize: maxPixelSize)
        }.value
        guard let cgImage else { return nil }
        let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        cache.setObject(image, forKey: key)
        return image
    }

    func removeAll() { cache.removeAllObjects() }
}
