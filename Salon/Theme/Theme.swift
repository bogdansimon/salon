import AppKit
import SalonCore
import SwiftUI

/// Salon's design tokens ("the exhibition catalogue"), from design/Tokens.dc.html.
/// Views use these and nothing else: no literal fonts, colours or spacing.
enum Theme {
    // MARK: Colour (light / dark)

    enum Palette {
        static let paper = Color(light: 0xF4F0E8, dark: 0x1C1A17)        // window ground, gallery
        static let surface = Color(light: 0xFAF8F3, dark: 0x24211D)      // popover, inspector, grouped boxes
        static let mat = Color(light: 0xECE8E0, dark: 0x1E1C19)          // plate behind the work in the card
        static let matTile = Color(light: 0xE8E3D9, dark: 0x262320)      // collection tiles
        static let ink = Color(light: 0x221F1A, dark: 0xEEE9E0)          // titles, primary text
        static let ink2 = Color(light: 0x5B5449, dark: 0xB8B0A3)         // descriptions, dates
        static let ink3 = Color(light: 0x6E675B, dark: 0x9A9285)         // metadata, help
        static let rule = Color(light: 0xE2DCD0, dark: 0x37322C)         // 0.5 pt hairlines
        static let fill = Color(light: 0xE6E0D5, dark: 0x2F2B26)         // segment track, skeleton
        static let controlOn = Color(light: 0x4A453D, dark: 0xD9D2C6)    // graphite tint for switches, checks
        static let healthOK = Color(light: 0x4F7A55, dark: 0x8DB892)
        static let healthWarn = Color(light: 0x9A6A1F, dark: 0xD6A75A)
        static let healthBad = Color(light: 0xA33F33, dark: 0xE08A7E)    // also destructive text

        /// The runtime accent: a muted tone from the current painting (Kept state, selection only).
        static func accent(_ palette: ArtworkPalette?) -> Color {
            let p = palette ?? .fallback
            return Color(lightRGB: p.accentLight, darkRGB: p.accentDark)
        }

        /// Accent at 10% (light) / 14% (dark).
        static func accentSoft(_ palette: ArtworkPalette?) -> Color {
            let p = palette ?? .fallback
            return Color(lightRGB: p.accentLight, darkRGB: p.accentDark, lightOpacity: 0.10, darkOpacity: 0.14)
        }
    }

    // MARK: Typography (New York for titles, SF for everything else; regular + medium only)

    enum Typeface {
        static let display = Font.system(size: 32, design: .serif)                       // 32/38
        static let workTitle = Font.system(size: 22, design: .serif)                     // 22/27
        static let errorTitle = Font.system(size: 20, design: .serif)                    // 20/25
        static let section = Font.system(size: 17, design: .serif)                       // 17/22
        static let emptyTitle = Font.system(size: 26, design: .serif)                    // 26/32
        static let description = Font.system(size: 14, design: .serif)                   // 14/21
        static let emptyBody = Font.system(size: 15, design: .serif)                     // 15/23
        static let tagline = Font.system(size: 15, design: .serif).italic()
        static let tileTitle = Font.system(size: 13.5, design: .serif)
        static let artist = Font.system(size: 11, weight: .medium)                       // caps, tracking 1.0
        static let label = Font.system(size: 10.5, weight: .medium)                      // caps, tracking 0.95
        static let tileArtist = Font.system(size: 10, weight: .medium)                   // caps, tracking 0.8
        static let body = Font.system(size: 13)                                          // controls, rows
        static let link = Font.system(size: 12.5)
        static let metadata = Font.system(size: 12).monospacedDigit()                    // 12/17
        static let help = Font.system(size: 11.5).monospacedDigit()
    }

    enum Tracking {
        static let artist: CGFloat = 1.0
        static let label: CGFloat = 0.95
        static let tile: CGFloat = 0.8
    }

    enum LineSpacing {
        static let workTitle: CGFloat = 5       // 22 → 27
        static let description: CGFloat = 7     // 14 → 21
        static let metadata: CGFloat = 5        // 12 → 17
        static let emptyBody: CGFloat = 8       // 15 → 23
    }

    // MARK: Spacing

    enum Space {
        static let iconLabel: CGFloat = 4
        static let group: CGFloat = 8
        static let labelLines: CGFloat = 12
        static let row: CGFloat = 16
        static let card: CGFloat = 20
        static let form: CGFloat = 28
        static let empty: CGFloat = 40
        static let hairline: CGFloat = 0.5
        static let tight: CGFloat = 3
    }

    // MARK: Radii

    enum Radius {
        static let artwork: CGFloat = 0          // never rounded
        static let tileMat: CGFloat = 2
        static let field: CGFloat = 5
        static let button: CGFloat = 7
        static let group: CGFloat = 10
    }

    // MARK: Elevation

    enum Elevation {
        /// Work in the UI: 0 1 2 / 22% and 0 6 18 / 14%.
        struct WorkShadow: ViewModifier {
            func body(content: Content) -> some View {
                content
                    .shadow(color: .black.opacity(0.22), radius: 1, y: 1)
                    .shadow(color: .black.opacity(0.14), radius: 9, y: 6)
            }
        }
    }

    // MARK: Motion (no springs, no bounce)

    enum Motion {
        static let cardCrossfade = Animation.easeInOut(duration: 0.6)
        static let moreLess = Animation.easeOut(duration: 0.25)
        static let keep = Animation.easeInOut(duration: 0.2)
    }

    // MARK: Layout constants from the designs

    enum Layout {
        static let popoverWidth: CGFloat = 360
        static let cardPlateHeight: CGFloat = 236                     // minimum; loading and error plates
        static let cardWorkMax = CGSize(width: 320, height: 288)      // the work, whole, never cropped
        static let cardPlateInset: CGFloat = 20                       // mat above and below the work
        static let errorPlateHeight: CGFloat = 168
        static let collapsedDescription: CGFloat = 105   // five lines
        static let expandedDescription: CGFloat = 240
        static let toolbarButton: CGFloat = 36
        static let tileMatHeight: CGFloat = 156
        static let tileWorkMax: CGFloat = 116
        static let inspectorWidth: CGFloat = 340
        static let inspectorPlate: CGFloat = 248
        static let inspectorWorkMax = CGSize(width: 256, height: 200)
        static let settingsWidth: CGFloat = 600
    }
}

// MARK: - Helpers

extension Color {
    /// A colour that follows the system appearance.
    init(light: UInt32, dark: UInt32) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            NSColor(hex: appearance.isDark ? dark : light)
        })
    }

    init(lightRGB: SRGBColor, darkRGB: SRGBColor, lightOpacity: Double = 1, darkOpacity: Double = 1) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.isDark ? NSColor(rgb: darkRGB, alpha: darkOpacity) : NSColor(rgb: lightRGB, alpha: lightOpacity)
        })
    }
}

extension NSColor {
    convenience init(hex: UInt32, alpha: Double = 1) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }

    convenience init(rgb: SRGBColor, alpha: Double = 1) {
        self.init(srgbRed: rgb.red, green: rgb.green, blue: rgb.blue, alpha: alpha)
    }
}

extension NSAppearance {
    var isDark: Bool { bestMatch(from: [.darkAqua, .aqua]) == .darkAqua }
}

extension View {
    /// Museum wall-label caps: 10.5 medium, uppercase, tracked, ink3.
    func labelCaps(_ color: Color = Theme.Palette.ink3) -> some View {
        font(Theme.Typeface.label).tracking(Theme.Tracking.label).textCase(.uppercase).foregroundStyle(color)
    }

    func workShadow() -> some View { modifier(Theme.Elevation.WorkShadow()) }

    func hairline(_ edge: Edge = .top) -> some View {
        overlay(alignment: edge == .top ? .top : .bottom) {
            Rectangle().fill(Theme.Palette.rule).frame(height: Theme.Space.hairline)
        }
    }
}

/// A 0.5 pt rule.
struct Hairline: View {
    var body: some View {
        Rectangle().fill(Theme.Palette.rule).frame(height: Theme.Space.hairline)
    }
}
