import SwiftUI

public enum Theme {
    // MARK: - Colors (light / dark pairs — pick based on @Environment(\.colorScheme))
    public static let labelColor: Color = .primary
    public static let grey:       Color = .secondary

    public static let iconColorLight:     Color = Color(red: 0.50,  green: 0.18,  blue: 0.72)   // purple
    public static let iconColorDark:      Color = Color(red: 0.867, green: 0.714, blue: 0.949)  // lavender
    public static let spotifyActiveLight: Color = Color(red: 0.02,  green: 0.52,  blue: 0.42)   // teal
    public static let spotifyActiveDark:  Color = Color(red: 0.710, green: 0.918, blue: 0.843)  // mint
    public static let volumeColorLight:   Color = Color(red: 0.18,  green: 0.40,  blue: 0.72)   // steel blue
    public static let volumeColorDark:    Color = Color(red: 0.682, green: 0.776, blue: 0.910)  // powder blue
    public static let calendarColorLight: Color = Color(red: 0.78,  green: 0.14,  blue: 0.28)   // crimson
    public static let calendarColorDark:  Color = Color(red: 1.000, green: 0.702, blue: 0.757)  // rose
    public static let keyboardColorLight: Color = iconColorLight
    public static let keyboardColorDark:  Color = iconColorDark
    public static let batteryGreenLight:  Color = Color(red: 0.08,  green: 0.58,  blue: 0.08)   // forest green
    public static let batteryGreenDark:   Color = Color(red: 0.710, green: 0.918, blue: 0.843)  // mint
    public static let batteryYellowLight: Color = Color(red: 0.65,  green: 0.48,  blue: 0.00)   // dark amber
    public static let batteryYellowDark:  Color = Color(red: 1.000, green: 0.961, blue: 0.729)  // pale yellow
    public static let batteryOrangeLight: Color = Color(red: 0.78,  green: 0.38,  blue: 0.00)   // dark orange
    public static let batteryOrangeDark:  Color = Color(red: 1.000, green: 0.820, blue: 0.659)  // peach
    public static let batteryRedLight:    Color = Color(red: 0.78,  green: 0.08,  blue: 0.08)   // dark red
    public static let batteryRedDark:     Color = Color(red: 1.000, green: 0.702, blue: 0.757)  // rose
    public static let tmuxColorLight:     Color = Color(red: 0.08,  green: 0.52,  blue: 0.08)   // forest green
    public static let tmuxColorDark:      Color = Color(red: 0.678, green: 0.918, blue: 0.686)  // mint-green
    public static let pomodoroWorkLight:  Color = Color(red: 0.80,  green: 0.08,  blue: 0.08)   // dark red
    public static let pomodoroWorkDark:   Color = Color(red: 1.000, green: 0.420, blue: 0.420)  // soft red
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
