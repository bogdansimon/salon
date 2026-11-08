import XCTest
@testable import SalonCore

/// The full-bleed vs mat decision on a 16:10 display (MacBook-style 2880×1800).
final class WallpaperLayoutTests: XCTestCase {
    private let display = PixelSize(width: 2880, height: 1800) // 16:10

    /// Large enough sources so upscaling never interferes with the crop rule.
    private func work(_ w: Int, _ h: Int) -> PixelSize { PixelSize(width: w * 1000, height: h * 1000) }

    func testSixteenByTenLandscapeIsFullBleed() {
        XCTAssertEqual(WallpaperLayout.cropFraction(image: work(16, 10), display: display), 0, accuracy: 1e-9)
        XCTAssertEqual(WallpaperLayout.presentation(image: work(16, 10), display: display, alwaysMat: false), .fullBleed)
    }

    func testThreeByTwoLandscapeIsFullBleed() {
        // 1 - 1.5/1.6 = 6.25% crop
        XCTAssertEqual(WallpaperLayout.cropFraction(image: work(3, 2), display: display), 0.0625, accuracy: 1e-9)
        XCTAssertEqual(WallpaperLayout.presentation(image: work(3, 2), display: display, alwaysMat: false), .fullBleed)
    }

    func testFourByThreeLandscapeGoesOnMat() {
        // 1 - (4/3)/1.6 = 16.7% crop: over the 12% threshold.
        XCTAssertEqual(WallpaperLayout.cropFraction(image: work(4, 3), display: display), 1 - (4.0 / 3.0) / 1.6, accuracy: 1e-9)
        XCTAssertEqual(WallpaperLayout.presentation(image: work(4, 3), display: display, alwaysMat: false), .mat)
    }

    func testThreeByFourPortraitGoesOnMat() {
        // 1 - 0.75/1.6 = 53% crop
        XCTAssertGreaterThan(WallpaperLayout.cropFraction(image: work(3, 4), display: display), 0.5)
        XCTAssertEqual(WallpaperLayout.presentation(image: work(3, 4), display: display, alwaysMat: false), .mat)
    }

    func testSquareGoesOnMat() {
        // 1 - 1/1.6 = 37.5% crop
        XCTAssertEqual(WallpaperLayout.cropFraction(image: work(1, 1), display: display), 0.375, accuracy: 1e-9)
        XCTAssertEqual(WallpaperLayout.presentation(image: work(1, 1), display: display, alwaysMat: false), .mat)
    }

    func testThresholdBoundaryIsInclusive() {
        // Exactly 12% crop stays full-bleed.
        let ratio = 1.6 * (1 - WallpaperLayout.fullBleedCropThreshold)
        let image = PixelSize(width: Int((ratio * 10_000).rounded(.up)), height: 10_000)
        XCTAssertLessThanOrEqual(WallpaperLayout.cropFraction(image: image, display: display), WallpaperLayout.fullBleedCropThreshold + 1e-4)
        XCTAssertEqual(WallpaperLayout.presentation(image: image, display: display, alwaysMat: false), .fullBleed)
    }

    func testAlwaysUseMatOverridesFullBleed() {
        XCTAssertEqual(WallpaperLayout.presentation(image: work(16, 10), display: display, alwaysMat: true), .mat)
    }

    func testTooSmallForFullBleedGoesOnMat() {
        // 16:10 but would need 1.44× upscaling on a 5K display.
        let fiveK = PixelSize(width: 5120, height: 3200)
        XCTAssertEqual(WallpaperLayout.presentation(image: PixelSize(width: 3552, height: 2220), display: fiveK, alwaysMat: false), .mat)
    }

    func testMatRectFollowsTheDesign() {
        let canvas = PixelSize(width: 2880, height: 1800)
        let rect = WallpaperLayout.matRect(image: work(3, 4), canvas: canvas, topInset: 74, margin: .medium)
        let visible = 1800.0 - 74
        XCTAssertEqual(rect.height, (visible * 0.76).rounded(), accuracy: 1)
        XCTAssertEqual(rect.midX, 1440, accuracy: 1, "centred horizontally")
        let top = rect.minY - 74, bottom = 1800 - rect.maxY
        XCTAssertEqual(bottom / top, 1.15, accuracy: 0.01, "hung slightly above centre")
    }

    func testMatRectCapsWideWorksAtEightyPercentWidth() {
        let canvas = PixelSize(width: 2880, height: 1800)
        let rect = WallpaperLayout.matRect(image: PixelSize(width: 30_000, height: 10_000), canvas: canvas, topInset: 0, margin: .small)
        XCTAssertEqual(rect.width, 2880 * 0.8, accuracy: 1)
    }

    func testMatRectNeverUpscalesSmallSources() {
        let canvas = PixelSize(width: 5120, height: 2880)
        let small = PixelSize(width: 1500, height: 2000)
        let rect = WallpaperLayout.matRect(image: small, canvas: canvas, topInset: 0, margin: .small)
        XCTAssertEqual(rect.size, CGSize(width: 1500, height: 2000))
    }

    func testRendererProducesDisplaySizedImage() throws {
        let image = try XCTUnwrap(TestImages.solid(width: 300, height: 400, red: 0.6, green: 0.4, blue: 0.2))
        let display = WallpaperRenderer.Display(size: PixelSize(width: 640, height: 400), topInset: 12, backingScale: 2)
        let options = WallpaperRenderer.Options(alwaysMat: false, margin: .medium, matColor: RGBColor(hex: "#E9E4DA")!)
        let output = try XCTUnwrap(WallpaperRenderer.render(image, on: display, options: options))
        XCTAssertEqual(output.width, 640)
        XCTAssertEqual(output.height, 400)
    }
}
