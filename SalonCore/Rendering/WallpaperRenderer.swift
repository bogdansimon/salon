import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Draws the final wallpaper for one display: the artwork full-bleed, or hung on
/// a mat. Nothing else is ever drawn: no text, no logo.
public enum WallpaperRenderer {
    public struct Display: Sendable {
        /// Native pixel size.
        public var size: PixelSize
        /// Menu-bar height in pixels (excluded from the mat's visible frame).
        public var topInset: Double
        /// Dock height in pixels, when the work should stay clear of it; otherwise 0.
        public var bottomInset: Double
        /// Points → pixels, for scaling the shadow.
        public var backingScale: Double

        public init(size: PixelSize, topInset: Double, bottomInset: Double = 0, backingScale: Double) {
            self.size = size
            self.topInset = topInset
            self.bottomInset = bottomInset
            self.backingScale = backingScale
        }
    }

    public struct Options: Sendable {
        public var alwaysMat: Bool
        public var margin: MatMargin
        public var matColor: SRGBColor

        public init(alwaysMat: Bool, margin: MatMargin, matColor: SRGBColor) {
            self.alwaysMat = alwaysMat
            self.margin = margin
            self.matColor = matColor
        }
    }

    public static func render(_ image: CGImage, on display: Display, options: Options) -> CGImage? {
        let canvas = display.size
        let imageSize = PixelSize(width: image.width, height: image.height)
        guard let context = CGContext(data: nil, width: canvas.width, height: canvas.height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        let bounds = CGRect(x: 0, y: 0, width: canvas.width, height: canvas.height)

        switch WallpaperLayout.presentation(image: imageSize, display: canvas, alwaysMat: options.alwaysMat) {
        case .fullBleed:
            let scale = WallpaperLayout.fillScale(image: imageSize, display: canvas)
            let size = CGSize(width: Double(image.width) * scale, height: Double(image.height) * scale)
            context.draw(image, in: CGRect(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2,
                                           width: size.width, height: size.height))
        case .mat:
            context.setFillColor(options.matColor.cgColor)
            context.fill(bounds)
            let topLeft = WallpaperLayout.matRect(image: imageSize, canvas: canvas, topInset: display.topInset,
                                                     bottomInset: display.bottomInset, margin: options.margin)
            // CoreGraphics' origin is bottom-left.
            let rect = CGRect(x: topLeft.minX, y: bounds.height - topLeft.maxY, width: topLeft.width, height: topLeft.height)
            for layer in WallpaperLayout.shadow {
                context.saveGState()
                context.setShadow(offset: CGSize(width: 0, height: -layer.offsetY * display.backingScale),
                                  blur: layer.blur * display.backingScale,
                                  color: CGColor(gray: 0, alpha: layer.opacity))
                context.setFillColor(options.matColor.cgColor)
                context.fill(rect)
                context.restoreGState()
            }
            context.draw(image, in: rect)
        }
        return context.makeImage()
    }

    public static func writeJPEG(_ image: CGImage, to url: URL, quality: Double = 0.92) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
    }
}

extension SRGBColor {
    public var cgColor: CGColor {
        CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, components: [red, green, blue, 1])!
    }
}
