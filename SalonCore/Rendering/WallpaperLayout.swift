import CoreGraphics
import Foundation

/// Every tunable wallpaper number lives here. Values follow design/Mat.dc.html.
public enum WallpaperLayout {
    // MARK: Full-bleed vs mat

    /// Max share of the artwork that "fill" may crop away before we switch to the mat.
    public static let fullBleedCropThreshold = 0.12
    /// Max upscale allowed for full-bleed; beyond it the work goes on the mat
    /// ("never stretched past its source resolution", with a little tolerance).
    public static let maxFullBleedUpscale = 1.15

    // MARK: Mat geometry

    /// The work's width is also capped at this share of the screen width.
    public static let maxWidthShare = 0.80
    /// Bottom gap = 1.15 × top gap: hung slightly above centre, at eye line.
    public static let bottomToTopGapRatio = 1.15

    // MARK: Mat shadow (points; scaled by the display's backing scale)

    public struct ShadowLayer: Sendable {
        public var offsetY: CGFloat
        public var blur: CGFloat
        public var opacity: CGFloat
    }

    public static let shadow: [ShadowLayer] = [
        ShadowLayer(offsetY: 1, blur: 2, opacity: 0.24),
        ShadowLayer(offsetY: 12, blur: 32, opacity: 0.20),
    ]

    // MARK: Decision

    public enum Presentation: Equatable, Sendable { case fullBleed, mat }

    /// Share of the artwork's area that aspect-fill would crop away on this display.
    public static func cropFraction(image: PixelSize, display: PixelSize) -> Double {
        let imageRatio = image.aspectRatio, displayRatio = display.aspectRatio
        guard imageRatio > 0, displayRatio > 0 else { return 0 }
        return 1 - min(imageRatio / displayRatio, displayRatio / imageRatio)
    }

    /// How much aspect-fill would have to enlarge the image to cover the display.
    public static func fillScale(image: PixelSize, display: PixelSize) -> Double {
        guard image.width > 0, image.height > 0 else { return .infinity }
        return max(Double(display.width) / Double(image.width), Double(display.height) / Double(image.height))
    }

    public static func presentation(image: PixelSize, display: PixelSize, alwaysMat: Bool) -> Presentation {
        if alwaysMat { return .mat }
        if cropFraction(image: image, display: display) > fullBleedCropThreshold { return .mat }
        if fillScale(image: image, display: display) > maxFullBleedUpscale { return .mat }
        return .fullBleed
    }

    // MARK: Placement

    /// Where the work hangs on the mat, in pixels with a top-left origin.
    /// - Parameters:
    ///   - canvas: the display in pixels.
    ///   - topInset: pixels taken by the menu bar (excluded from the visible frame).
    ///   - margin: Small / Medium / Large.
    public static func matRect(image: PixelSize, canvas: PixelSize, topInset: Double, margin: MatMargin) -> CGRect {
        let visibleHeight = Double(canvas.height) - topInset
        var height = visibleHeight * margin.heightShare
        var width = height * image.aspectRatio
        let maxWidth = Double(canvas.width) * maxWidthShare
        if width > maxWidth {
            width = maxWidth
            height = width / image.aspectRatio
        }
        // Too-small sources: the margin grows instead of the image upscaling.
        if width > Double(image.width) {
            width = Double(image.width)
            height = Double(image.height)
        }
        let gap = visibleHeight - height
        let top = gap / (1 + bottomToTopGapRatio)
        return CGRect(x: ((Double(canvas.width) - width) / 2).rounded(),
                      y: (topInset + top).rounded(),
                      width: width.rounded(), height: height.rounded())
    }
}

/// Settings › Artwork › Margin.
public enum MatMargin: String, Codable, CaseIterable, Sendable {
    case small, medium, large

    /// The work's height as a share of the visible screen height.
    public var heightShare: Double {
        switch self {
        case .small: 0.84
        case .medium: 0.76
        case .large: 0.66
        }
    }

    public var displayName: String {
        switch self {
        case .small: "Small"
        case .medium: "Medium"
        case .large: "Large"
        }
    }
}

/// Settings › Artwork › Mat colour.
public enum MatStyle: Codable, Hashable, Sendable {
    case auto
    case neutral
    case custom(SRGBColor)
}
