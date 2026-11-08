import Foundation

/// An sRGB colour with 0…1 components, plus OKLab/OKLCH conversions
/// (Björn Ottosson's OKLab, https://bottosson.github.io/posts/oklab/).
public struct SRGBColor: Codable, Hashable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// "#7A5C22" or "7A5C22".
    public init?(hex: String) {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        self.init(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
    }

    public var hex: String {
        func byte(_ v: Double) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(red), byte(green), byte(blue))
    }
}

public struct OKLCH: Hashable, Sendable {
    public var l: Double
    public var c: Double
    /// Hue in degrees.
    public var h: Double

    public init(l: Double, c: Double, h: Double) {
        self.l = l
        self.c = c
        self.h = h
    }
}

public struct OKLab: Hashable, Sendable {
    public var l: Double
    public var a: Double
    public var b: Double

    public var lch: OKLCH {
        let c = (a * a + b * b).squareRoot()
        var h = atan2(b, a) * 180 / .pi
        if h < 0 { h += 360 }
        return OKLCH(l: l, c: c, h: h)
    }
}

extension OKLCH {
    public var lab: OKLab {
        let radians = h * .pi / 180
        return OKLab(l: l, a: c * cos(radians), b: c * sin(radians))
    }

    public var rgb: SRGBColor { lab.rgb }
}

extension SRGBColor {
    public var oklab: OKLab {
        func linear(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        let r = linear(red), g = linear(green), b = linear(blue)
        let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
        return OKLab(
            l: 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
            a: 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
            b: 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
        )
    }

    public var oklch: OKLCH { oklab.lch }
}

extension OKLab {
    /// Back to sRGB, clamped into gamut.
    public var rgb: SRGBColor {
        let l_ = l + 0.3963377774 * a + 0.2158037573 * b
        let m_ = l - 0.1055613458 * a - 0.0638541728 * b
        let s_ = l - 0.0894841775 * a - 1.2914855480 * b
        let l3 = l_ * l_ * l_, m3 = m_ * m_ * m_, s3 = s_ * s_ * s_
        func gamma(_ v: Double) -> Double {
            let c = min(max(v, 0), 1)
            return c <= 0.0031308 ? 12.92 * c : 1.055 * pow(c, 1 / 2.4) - 0.055
        }
        return SRGBColor(
            red: gamma(4.0767416621 * l3 - 3.3077115913 * m3 + 0.2309699292 * s3),
            green: gamma(-1.2684380046 * l3 + 2.6097574011 * m3 - 0.3413193965 * s3),
            blue: gamma(-0.0041960863 * l3 - 0.7034186147 * m3 + 1.7076147010 * s3)
        )
    }
}
