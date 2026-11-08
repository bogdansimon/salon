import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum TestImages {
    static func solid(width: Int, height: Int, red: Double, green: Double, blue: Double) -> CGImage? {
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.setFillColor(CGColor(srgbRed: red, green: green, blue: blue, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    /// A small-file JPEG of the given pixel size (solid colour compresses to almost nothing).
    static func jpegData(width: Int, height: Int) -> Data {
        let image = solid(width: width, height: height, red: 0.5, green: 0.45, blue: 0.3)!
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.3] as CFDictionary)
        CGImageDestinationFinalize(destination)
        return data as Data
    }
}
