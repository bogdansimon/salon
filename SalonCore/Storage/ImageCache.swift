import Foundation
import ImageIO

/// Full-size downloads under Application Support/Salon/Images, one file per artwork.
/// Evicts least-recently-used files over the size limit, never kept works.
public final class ImageCache: @unchecked Sendable {
    public let directory: URL
    private let fileManager = FileManager.default

    public init(directory: URL) {
        self.directory = directory
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    public func fileURL(for artworkID: String) -> URL {
        let safe = artworkID.replacingOccurrences(of: "[^A-Za-z0-9._-]", with: "_", options: .regularExpression)
        return directory.appendingPathComponent(safe).appendingPathExtension("img")
    }

    public func cachedFile(for artworkID: String) -> URL? {
        let url = fileURL(for: artworkID)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        // Touch so LRU eviction sees it as recently used.
        try? fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
        return url
    }

    @discardableResult
    public func store(_ data: Data, for artworkID: String) throws -> URL {
        let url = fileURL(for: artworkID)
        try data.write(to: url, options: .atomic)
        return url
    }

    public var totalBytes: Int64 {
        files().reduce(0) { $0 + $1.size }
    }

    public var fileCount: Int { files().count }

    /// Deletes oldest files until under `limitBytes`, skipping `protectedIDs` (kept works, current wallpaper).
    public func evict(toFit limitBytes: Int64, protecting protectedIDs: Set<String>) {
        let protected = Set(protectedIDs.map { fileURL(for: $0).lastPathComponent })
        var entries = files().sorted { $0.modified < $1.modified }
        var total = entries.reduce(0) { $0 + $1.size }
        while total > limitBytes, let oldest = entries.first {
            entries.removeFirst()
            guard !protected.contains(oldest.url.lastPathComponent) else { continue }
            try? fileManager.removeItem(at: oldest.url)
            total -= oldest.size
        }
    }

    public func clear(protecting protectedIDs: Set<String>) {
        evict(toFit: 0, protecting: protectedIDs)
    }

    private func files() -> [(url: URL, size: Int64, modified: Date)] {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        let urls = (try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys)) ?? []
        return urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
            return (url, Int64(values.fileSize ?? 0), values.contentModificationDate ?? .distantPast)
        }
    }
}

public enum ImageInspector {
    /// Pixel size from the file header, without decoding the image.
    public static func pixelSize(of url: URL) -> PixelSize? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int,
              let height = props[kCGImagePropertyPixelHeight] as? Int else { return nil }
        let orientation = props[kCGImagePropertyOrientation] as? Int ?? 1
        // EXIF orientations 5–8 are rotated 90°.
        return orientation >= 5 ? PixelSize(width: height, height: width) : PixelSize(width: width, height: height)
    }

    /// Decodes the image, downsampling so the long side is at most `maxPixelSize`.
    public static func image(at url: URL, maxPixelSize: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
