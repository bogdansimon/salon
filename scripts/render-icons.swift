#!/usr/bin/env swift
// Renders the app icon PNGs from design/Icons.dc.html ("a frame, hung on a wire")
// into Salon/Resources/Assets.xcassets/AppIcon.appiconset.
//
//   swift scripts/render-icons.swift
import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "Salon/Resources/Assets.xcassets/AppIcon.appiconset")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

/// Draws the light icon on a 1024 canvas (824 body, per Apple's macOS grid), scaled to `size`.
func render(size: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    let s = CGFloat(size) / 1024
    ctx.scaleBy(x: s, y: s)
    // Flip to a top-left origin so the numbers read like the design.
    ctx.translateBy(x: 0, y: 1024)
    ctx.scaleBy(x: 1, y: -1)

    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let mask = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)

    // Soft drop shadow under the body.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 10), blur: 28, color: color(0x221F1A, 0.25).cgColor)
    ctx.addPath(mask)
    ctx.setFillColor(color(0xD3C8B3).cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    // Plaster wall lit from above.
    ctx.saveGState()
    ctx.addPath(mask)
    ctx.clip()
    let wall = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [color(0xE2D9C8).cgColor, color(0xD3C8B3).cgColor] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(wall, start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 924), options: [])
    let light = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [color(0xFFF4D6, 0.75).cgColor, color(0xFFF4D6, 0).cgColor] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(light, startCenter: CGPoint(x: 512, y: 100), startRadius: 0, endCenter: CGPoint(x: 512, y: 100), endRadius: 520, options: [])

    // Design coordinates are on a 260 pt icon; the body here is 824 px from (100, 100).
    let k: CGFloat = 824 / 260
    func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: 100 + x * k, y: 100 + y * k) }

    // Wire and nail.
    ctx.setStrokeColor(color(0x5E5446).cgColor)
    ctx.setLineWidth(2.4 * k)
    ctx.move(to: p(130, 46)); ctx.addLine(to: p(84, 92))
    ctx.move(to: p(130, 46)); ctx.addLine(to: p(176, 92))
    ctx.strokePath()
    ctx.setFillColor(color(0x6B5432).cgColor)
    let nail = p(130, 46)
    ctx.fillEllipse(in: CGRect(x: nail.x - 4.5 * k, y: nail.y - 4.5 * k, width: 9 * k, height: 9 * k))

    // Frame (moulding, 132 × 150, hung 20 below centre), mat (9 inset) and painting (12 inset).
    let origin = p(64, 75)
    let frameRect = CGRect(x: origin.x, y: origin.y, width: 132 * k, height: 150 * k)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 40), blur: 70, color: color(0x3C2C14, 0.32).cgColor)
    let moulding = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [color(0x8A6E40).cgColor, color(0x5F4A28).cgColor] as CFArray, locations: [0, 1])!
    ctx.addRect(frameRect)
    ctx.clip()
    ctx.drawLinearGradient(moulding, start: CGPoint(x: frameRect.minX, y: frameRect.minY), end: CGPoint(x: frameRect.maxX, y: frameRect.maxY), options: [])
    ctx.restoreGState()
    let matRect = frameRect.insetBy(dx: 9 * k, dy: 9 * k)
    ctx.setFillColor(color(0xF0EADD).cgColor)
    ctx.fill(matRect)
    let paint = matRect.insetBy(dx: 12 * k, dy: 12 * k)
    ctx.setFillColor(color(0x9F9479).cgColor)
    ctx.fill(CGRect(x: paint.minX, y: paint.minY, width: paint.width, height: paint.height * 0.30))
    ctx.setFillColor(color(0xC9A545).cgColor)
    ctx.fill(CGRect(x: paint.minX, y: paint.minY + paint.height * 0.30, width: paint.width, height: paint.height * 0.26))
    ctx.setFillColor(color(0x40598A).cgColor)
    ctx.fill(CGRect(x: paint.minX, y: paint.minY + paint.height * 0.56, width: paint.width, height: paint.height * 0.44))
    ctx.restoreGState()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

var images: [[String: String]] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        try render(size: points * scale).write(to: output.appendingPathComponent(name))
        images.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": name])
    }
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys]).write(to: output.appendingPathComponent("Contents.json"))
print("Wrote \(images.count) icons to \(output.path)")
