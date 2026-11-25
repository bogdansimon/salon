import Foundation
import ImageIO

/// Full-size downloads under Application Support/Salon/Images, one file per artwork
/// ("aic_154235.jpg").
/// Evicts least-recently-used files over the size limit, never kept works.
public final class ImageCache: @unchecked Sendable {
    public let directory: URL
    private let fileManager = FileManager.default

    public init(directory: URL) {
        self.directory = directory
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        renameLegacyFiles()
    }

    /// "aic_154235": the file name without its extension.
    func baseName(for artworkID: String) -> String {
        artworkID.replacingOccurrences(of: "[^A-Za-z0-9._-]", with: "_", options: .regularExpression)
    }

    public func cachedFile(for artworkID: String) -> URL? {
        guard let url = existingFile(named: baseName(for: artworkID)) else { return nil }
        // Touch so LRU eviction sees it as recently used.
        try? fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
        return url
    }

    /// Saved with the image's real extension (.jpg, .png…), so Finder and Preview open it.
    @discardableResult
    public func store(_ data: Data, for artworkID: String) throws -> URL {
        let base = baseName(for: artworkID)
        if let old = existingFile(named: base) { try? fileManager.removeItem(at: old) }
        let url = directory.appendingPathComponent(base).appendingPathExtension(Self.fileExtension(of: data))
        try data.write(to: url, options: .atomic)
        return url
    }

    private func existingFile(named base: String) -> URL? {
        files().first { $0.url.deletingPathExtension().lastPathComponent == base }?.url
    }

    /// From the file's first bytes (its "signature"); "jpg" when it can't tell.
    static func fileExtension(of data: Data) -> String {
        let head = [UInt8](data.prefix(12))
        func starts(_ bytes: [UInt8], at offset: Int = 0) -> Bool {
            head.count >= offset + bytes.count && Array(head[offset..<offset + bytes.count]) == bytes
        }
        if starts([0xFF, 0xD8, 0xFF]) { return "jpg" }
        if starts([0x89, 0x50, 0x4E, 0x47]) { return "png" }
        if starts([0x49, 0x49, 0x2A, 0x00]) || starts([0x4D, 0x4D, 0x00, 0x2A]) { return "tif" }
        if starts(Array("RIFF".utf8)) && starts(Array("WEBP".utf8), at: 8) { return "webp" }
        if starts(Array("GIF8".utf8)) { return "gif" }
        return "jpg"
    }

    /// Older builds saved every image as ".img", which Finder opens as a disk image.
    private func renameLegacyFiles() {
        let urls = (try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for url in urls where url.pathExtension == "img" {
            let ext = (try? Data(contentsOf: url, options: .mappedIfSafe)).map(Self.fileExtension(of:)) ?? "jpg"
            try? fileManager.moveItem(at: url, to: url.deletingPathExtension().appendingPathExtension(ext))
        }
    }

    public var totalBytes: Int64 {
        files().reduce(0) { $0 + $1.size }
    }

    public var fileCount: Int { files().count }

    /// Deletes oldest files until under `limitBytes`, skipping `protectedIDs` (kept works, current wallpaper).
    public func evict(toFit limitBytes: Int64, protecting protectedIDs: Set<String>) {
        let protected = Set(protectedIDs.map(baseName(for:)))
        var entries = files().sorted { $0.modified < $1.modified }
        var total = entries.reduce(0) { $0 + $1.size }
        while total > limitBytes, let oldest = entries.first {
            entries.removeFirst()
            guard !protected.contains(oldest.url.deletingPathExtension().lastPathComponent) else { continue }
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
