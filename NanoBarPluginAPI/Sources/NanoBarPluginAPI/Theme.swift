import AppKit
import SwiftUI

public enum Theme {
    // MARK: - Colors (adaptive — correct on dark, light, and liquid glass)
    public static let iconColor: Color     = adaptive(
        light: Color(red: 0.50, green: 0.18, blue: 0.72),  // purple
        dark:  Color(red: 0.867, green: 0.714, blue: 0.949) // lavender
    )
    public static let labelColor: Color    = .primary
    public static let grey: Color          = .secondary

    public static let spotifyActive: Color = adaptive(
        light: Color(red: 0.02, green: 0.52, blue: 0.42),   // teal
        dark:  Color(red: 0.710, green: 0.918, blue: 0.843) // mint
    )
    public static let spotifyPaused: Color = .secondary
    public static let volumeColor: Color   = adaptive(
        light: Color(red: 0.18, green: 0.40, blue: 0.72),   // steel blue
        dark:  Color(red: 0.682, green: 0.776, blue: 0.910) // powder blue
    )
    public static let calendarColor: Color = adaptive(
        light: Color(red: 0.78, green: 0.14, blue: 0.28),   // crimson
        dark:  Color(red: 1.000, green: 0.702, blue: 0.757) // rose
    )
    public static let keyboardColor: Color = adaptive(
        light: Color(red: 0.50, green: 0.18, blue: 0.72),   // purple
        dark:  Color(red: 0.867, green: 0.714, blue: 0.949) // lavender
    )

    public static let batteryGreen: Color  = adaptive(
        light: Color(red: 0.08, green: 0.58, blue: 0.08),   // forest green
        dark:  Color(red: 0.710, green: 0.918, blue: 0.843) // mint
    )
    public static let batteryYellow: Color = adaptive(
        light: Color(red: 0.65, green: 0.48, blue: 0.00),   // dark amber
        dark:  Color(red: 1.000, green: 0.961, blue: 0.729) // pale yellow
    )
    public static let batteryOrange: Color = adaptive(
        light: Color(red: 0.78, green: 0.38, blue: 0.00),   // dark orange
        dark:  Color(red: 1.000, green: 0.820, blue: 0.659) // peach
    )
    public static let batteryRed: Color    = adaptive(
        light: Color(red: 0.78, green: 0.08, blue: 0.08),   // dark red
        dark:  Color(red: 1.000, green: 0.702, blue: 0.757) // rose
    )

    public static let tmuxColor:          Color = adaptive(
        light: Color(red: 0.08, green: 0.52, blue: 0.08),   // forest green
        dark:  Color(red: 0.678, green: 0.918, blue: 0.686) // mint-green
    )
    public static let pomodoroWorkColor:  Color = adaptive(
        light: Color(red: 0.80, green: 0.08, blue: 0.08),   // dark red
        dark:  Color(red: 1.000, green: 0.420, blue: 0.420) // soft red
    )
    public static let pomodoroBreakColor: Color = spotifyActive

    // MARK: - Named color hex strings (light / dark)
    // Values are derived from the float constants above. Update both if you change a color.
    public static let calendarColorLight  = "#C72447FF"
    public static let calendarColorDark   = "#FFB3C1FF"
    public static let keyboardColorLight  = "#802EB8FF"
    public static let keyboardColorDark   = "#DDB6F2FF"
    public static let spotifyActiveLight  = "#05856BFF"
    public static let spotifyActiveDark   = "#B5EAD7FF"
    public static let volumeColorLight    = "#2E66B8FF"
    public static let volumeColorDark     = "#AEC6E8FF"
    public static let batteryGreenLight   = "#149414FF"
    public static let batteryGreenDark    = "#B5EAD7FF"
    public static let batteryYellowLight  = "#A67A00FF"
    public static let batteryYellowDark   = "#FFF5BAFF"
    public static let batteryOrangeLight  = "#C76100FF"
    public static let batteryOrangeDark   = "#FFD1A8FF"
    public static let batteryRedLight     = "#C71414FF"
    public static let batteryRedDark      = "#FFB3C1FF"
    public static let tmuxColorLight      = "#148514FF"
    public static let tmuxColorDark       = "#ADEAAFFF"
    public static let pomodoroWorkLight   = "#CC1414FF"
    public static let pomodoroWorkDark    = "#FF6B6BFF"
    // pomodoroBreak = spotifyActive

    // MARK: - Layout
    public static let barHeight: CGFloat = 30
    public static let barMargin: CGFloat = 8
    public static let barContainerHeight: CGFloat = 50
    public static let itemCorner: CGFloat = barHeight / 2
    public static let itemPadBg: CGFloat = 3
    public static let iconPadLeft: CGFloat = 10
    public static let iconPadRight: CGFloat = 4
    public static let labelPadLeft: CGFloat = 4
    public static let labelPadRight: CGFloat = 10
    public static let iconLabelSpacing: CGFloat = iconPadRight + labelPadLeft
    public static let itemGap: CGFloat = 4
    public static let iconSize: CGFloat = 14
    public static let appIconSize: CGFloat = 16
    public static let nowPlayingIconSize: CGFloat = 12
    public static let labelSize: CGFloat = 12
    public static let notchWidth: CGFloat = 160
    public static let batteryIconWidth: CGFloat = 26
    /// Extra window height below the bar for shadow rendering; content stays pinned to top.
    public static let shadowOverflow: CGFloat = 14

    // MARK: - Battery thresholds
    public static let batteryWarnThreshold: Int = 75
    public static let batteryMedThreshold:  Int = 50
    public static let batteryLowThreshold:  Int = 25

    // MARK: - Bar shadow
    public static let barShadowOpacity: Double  = 0.3
    public static let barShadowRadius:  CGFloat = 8
    public static let barShadowY:       CGFloat = 4

    // MARK: - Animations
    public static let menuBarAnimDuration: Double    = 0.25
    public static let animEase:            Animation = .easeInOut(duration: 0.3)
    public static let animEaseSlow:        Animation = .easeInOut(duration: 0.4)
    public static let springIconHover:     Animation = .spring(response: 0.2, dampingFraction: 0.7)
    public static let springLabelHover:    Animation = .spring(response: 0.3, dampingFraction: 0.75)

    // MARK: - Config helpers

    /// Sentinel TOML value for an auto-generated dark variant: `colorDark = "auto"`.
    public static let darkVariantAuto = "auto"

    /// Resolve a color from TOML config, with optional dark-mode variant.
    ///
    /// Either side may be the `"auto"` sentinel — at most one at a time:
    /// - `darkHex == "auto"`: dark is generated from light.
    /// - `hex == "auto"`: light is generated from dark.
    /// - Both explicit: used as-is.
    /// - No explicit value on either side: returns `fallback`.
    public static func adaptiveColor(hex: String?, darkHex: String?, fallback: Color) -> Color {
        let lightIsAuto = hex      == darkVariantAuto
        let darkIsAuto  = darkHex  == darkVariantAuto

        let explicitLight = lightIsAuto ? nil : hex.flatMap      { $0.isEmpty ? nil : color(hex: $0) }
        let explicitDark  = darkIsAuto  ? nil : darkHex.flatMap  { $0.isEmpty ? nil : color(hex: $0) }

        let lightColor: Color?
        let darkColor:  Color?

        if lightIsAuto, let dark = explicitDark {
            lightColor = generatedComplement(for: dark)
            darkColor  = dark
        } else if darkIsAuto, let light = explicitLight {
            lightColor = light
            darkColor  = generatedComplement(for: light)
        } else {
            lightColor = explicitLight
            darkColor  = explicitDark
        }

        guard let light = lightColor else { return fallback }
        guard let dark  = darkColor  else { return light }
        return adaptive(light: light, dark: dark)
    }

    /// Generate a theme-appropriate complement for the opposite appearance mode.
    ///
    /// Works in HSB space:
    /// - Dark base (luminance < 0.3): reduces saturation, cranks brightness toward a light
    ///   pastel suitable for dark mode.
    /// - Light/pastel base (luminance ≥ 0.3): increases saturation, drops brightness toward
    ///   a rich shade suitable for light mode.
    public static func generatedComplement(for baseColor: Color) -> Color {
        guard let ns = NSColor(baseColor).usingColorSpace(.sRGB) else { return baseColor }
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ns.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        let luminance = 0.2126 * ns.redComponent + 0.7152 * ns.greenComponent + 0.0722 * ns.blueComponent
        if luminance < 0.3 {
            // Dark/rich → light pastel for dark mode
            return Color(NSColor(hue: h, saturation: s * 0.45, brightness: min(b * 0.5 + 0.55, 0.97), alpha: a))
        } else {
            // Light/pastel → dark saturated for light mode
            return Color(NSColor(hue: h, saturation: min(s * 1.8, 0.90), brightness: b * 0.45, alpha: a))
        }
    }

    /// Returns true if the color is perceptually light (luminance ≥ 0.3).
    public static func isLight(_ color: Color) -> Bool {
        guard let ns = NSColor(color).usingColorSpace(.sRGB) else { return true }
        return 0.2126 * ns.redComponent + 0.7152 * ns.greenComponent + 0.0722 * ns.blueComponent >= 0.3
    }

    /// Returns an adaptive Color that resolves to `dark` in Dark Mode and `light` in Light Mode.
    /// Uses NSColor's dynamic provider — the same mechanism NSApp.appearance drives —
    /// so colors update on theme switch and respect vibrancy behind glass materials.
    public static func adaptive(light: Color, dark: Color) -> Color {
        Color(NSColor(name: nil, dynamicProvider: { appearance in
            switch appearance.bestMatch(from: [.aqua, .darkAqua]) {
            case .darkAqua: return NSColor(dark)
            default:        return NSColor(light)
            }
        }))
    }

    public static func color(hex: String?) -> Color? {
        guard let hex, hex.hasPrefix("#") else { return nil }
        let h = String(hex.dropFirst())
        guard let value = UInt64(h, radix: 16) else { return nil }
        switch h.count {
        case 6:
            let r = Double((value >> 16) & 0xFF) / 255
            let g = Double((value >>  8) & 0xFF) / 255
            let b = Double( value        & 0xFF) / 255
            return Color(red: r, green: g, blue: b)
        case 8:
            let r = Double((value >> 24) & 0xFF) / 255
            let g = Double((value >> 16) & 0xFF) / 255
            let b = Double((value >>  8) & 0xFF) / 255
            let a = Double( value        & 0xFF) / 255
            return Color(red: r, green: g, blue: b, opacity: a)
        default:
            return nil
        }
    }
}

// MARK: - Color hex encoding

public extension Color {
    /// Encodes the color as an 8-digit hex string `"#RRGGBBAA"` in sRGB.
    ///
    /// Tries direct NSColor → sRGB first (fast path). Falls back to CGColor conversion
    /// so wide-gamut / P3 colors from the system color panel are never silently dropped.
    func toHex8() -> String? {
        let ns = NSColor(self)
        // Fast path: already in (or trivially convertible to) sRGB.
        if let srgb = ns.usingColorSpace(.sRGB) {
            return Self.hexString(srgb)
        }
        // Fallback: go through CGColor for wide-gamut / display-P3 / catalog colors.
        let cg = ns.cgColor
        if let srgbSpace = CGColorSpace(name: CGColorSpace.sRGB),
           let converted = cg.converted(to: srgbSpace, intent: .defaultIntent, options: nil),
           let comps = converted.components, comps.count >= 3 {
            let r = Int((comps[0]                            * 255).rounded())
            let g = Int((comps[1]                            * 255).rounded())
            let b = Int((comps[2]                            * 255).rounded())
            let a = Int(((comps.count >= 4 ? comps[3] : 1)  * 255).rounded())
            return String(format: "#%02X%02X%02X%02X", r, g, b, a)
        }
        return nil
    }

    private static func hexString(_ ns: NSColor) -> String {
        let r = Int((ns.redComponent   * 255).rounded())
        let g = Int((ns.greenComponent * 255).rounded())
        let b = Int((ns.blueComponent  * 255).rounded())
        let a = Int((ns.alphaComponent * 255).rounded())
        return String(format: "#%02X%02X%02X%02X", r, g, b, a)
    }
}
