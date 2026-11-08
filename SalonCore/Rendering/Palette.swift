import CoreGraphics
import Foundation

/// Colours derived from a painting: the auto mat and the UI accent.
/// Rules from design/Mat.dc.html (mat) and design/Tokens.dc.html (accent).
public struct ArtworkPalette: Codable, Hashable, Sendable {
    public var edge: RGBColor
    public var accentLight: RGBColor
    public var accentDark: RGBColor

    public static let fallback = ArtworkPalette(
        edge: RGBColor(hex: "#8F846B")!, accentLight: RGBColor(hex: "#7A5C22")!, accentDark: RGBColor(hex: "#D4B678")!
    )

    public init(edge: RGBColor, accentLight: RGBColor, accentDark: RGBColor) {
        self.edge = edge
        self.accentLight = accentLight
        self.accentDark = accentDark
    }
}

public enum PaletteRules {
    // Mat (Auto)
    static let edgeBand = 0.04
    static let matChromaFactor = 0.35
    static let matMaxChroma = 0.035
    static let darkPaintingL = 0.45
    static let deepMatL = 0.24...0.30
    static let lightMatL = 0.88...0.92
    // Fixed neutral mat
    public static let neutralDark = RGBColor(hex: "#2B2825")!
    public static let neutralLight = RGBColor(hex: "#E9E4DA")!
    // Accent
    static let accentClusters = 5
    static let greyChroma = 0.03
    static let accentLightL = 0.45
    static let accentDarkL = 0.78
    static let accentMaxChroma = 0.08

    /// The mat colour for `style`, given the painting's edge colour and the system appearance.
    public static func matColor(style: MatStyle, edge: RGBColor, darkAppearance: Bool) -> RGBColor {
        switch style {
        case .custom(let color): return color
        case .neutral: return darkAppearance ? neutralDark : neutralLight
        case .auto: return autoMat(edge: edge)
        }
    }

    /// Keep the edge hue, cut chroma, go deep for dark paintings and light otherwise,
    /// picking the end of the range farthest from the edge so the border still reads.
    public static func autoMat(edge: RGBColor) -> RGBColor {
        let lch = edge.oklch
        let range = lch.l < darkPaintingL ? deepMatL : lightMatL
        let mid = (range.lowerBound + range.upperBound) / 2
        let l = lch.l < mid ? range.upperBound : range.lowerBound
        let c = min(lch.c * matChromaFactor, matMaxChroma)
        return OKLCH(l: l, c: c, h: lch.h).rgb
    }

    /// Most common chromatic mid-tone (k-means over the pixels, near-greys skipped),
    /// fixed to the accent lightness for each appearance.
    public static func accent(pixels: [RGBColor]) -> (light: RGBColor, dark: RGBColor)? {
        let samples = pixels.map(\.oklab).filter { $0.lch.c >= greyChroma && (0.2...0.9).contains($0.l) }
        guard samples.count >= accentClusters else { return nil }
        guard let dominant = KMeans.dominantCenter(of: samples, k: accentClusters) else { return nil }
        let lch = dominant.lch
        let c = min(lch.c, accentMaxChroma)
        return (OKLCH(l: accentLightL, c: c, h: lch.h).rgb, OKLCH(l: accentDarkL, c: c, h: lch.h).rgb)
    }

    /// Average colour (in OKLab) of the 4% band around the image's edges.
    public static func edgeColor(pixels: [RGBColor], width: Int, height: Int) -> RGBColor {
        let band = max(1, Int((Double(min(width, height)) * edgeBand).rounded()))
        var sum = (l: 0.0, a: 0.0, b: 0.0), count = 0.0
        for y in 0..<height {
            for x in 0..<width where x < band || y < band || x >= width - band || y >= height - band {
                let lab = pixels[y * width + x].oklab
                sum.l += lab.l; sum.a += lab.a; sum.b += lab.b; count += 1
            }
        }
        guard count > 0 else { return ArtworkPalette.fallback.edge }
        return OKLab(l: sum.l / count, a: sum.a / count, b: sum.b / count).rgb
    }

    /// Edge colour and accent for a decoded image (downsampled to keep this fast).
    public static func palette(for image: CGImage) -> ArtworkPalette {
        guard let (pixels, width, height) = Bitmap.pixels(of: image, maxSide: 64) else { return .fallback }
        let edge = edgeColor(pixels: pixels, width: width, height: height)
        let accent = accent(pixels: pixels)
        return ArtworkPalette(edge: edge,
                              accentLight: accent?.light ?? ArtworkPalette.fallback.accentLight,
                              accentDark: accent?.dark ?? ArtworkPalette.fallback.accentDark)
    }
}

enum KMeans {
    /// Centre of the largest cluster. Deterministic: seeds spread across the lightness range.
    static func dominantCenter(of samples: [OKLab], k: Int, iterations: Int = 12) -> OKLab? {
        let sorted = samples.sorted { $0.l < $1.l }
        var centers: [OKLab] = (0..<k).map { cluster -> OKLab in
            let index: Int = (cluster * 2 + 1) * sorted.count / (2 * k)
            return sorted[min(sorted.count - 1, index)]
        }
        var assignment = [Int](repeating: 0, count: samples.count)
        for _ in 0..<iterations {
            for (i, s) in samples.enumerated() {
                assignment[i] = centers.indices.min { distance(s, centers[$0]) < distance(s, centers[$1]) } ?? 0
            }
            for c in centers.indices {
                let members = samples.indices.filter { assignment[$0] == c }.map { samples[$0] }
                guard !members.isEmpty else { continue }
                let n = Double(members.count)
                centers[c] = OKLab(l: members.map(\.l).reduce(0, +) / n, a: members.map(\.a).reduce(0, +) / n, b: members.map(\.b).reduce(0, +) / n)
            }
        }
        let counts = centers.indices.map { c in assignment.filter { $0 == c }.count }
        guard let best = counts.indices.max(by: { counts[$0] < counts[$1] }) else { return nil }
        return centers[best]
    }

    private static func distance(_ x: OKLab, _ y: OKLab) -> Double {
        let dl = x.l - y.l, da = x.a - y.a, db = x.b - y.b
        return dl * dl + da * da + db * db
    }
}

enum Bitmap {
    /// RGBA8 pixels of `image` scaled so its long side is `maxSide`.
    static func pixels(of image: CGImage, maxSide: Int) -> (pixels: [RGBColor], width: Int, height: Int)? {
        let scale = Double(maxSide) / Double(max(image.width, image.height))
        let width = max(1, Int(Double(image.width) * min(scale, 1)))
        let height = max(1, Int(Double(image.height) * min(scale, 1)))
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(data: &bytes, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let pixels = stride(from: 0, to: bytes.count, by: 4).map {
            RGBColor(red: Double(bytes[$0]) / 255, green: Double(bytes[$0 + 1]) / 255, blue: Double(bytes[$0 + 2]) / 255)
        }
        return (pixels, width, height)
    }
}
