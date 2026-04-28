import AppKit
import SwiftUI
import Testing
@testable import NanoBarPluginAPI

@Suite("Theme.adaptiveColor")
struct ThemeAdaptiveColorTests {

    // MARK: - adaptiveColor(hex:darkHex:fallback:)

    @Test("nil hex returns fallback")
    func nilHexReturnsFallback() {
        let fallback = Color.red
        let result = Theme.adaptiveColor(hex: nil, darkHex: nil, fallback: fallback)
        #expect(hexString(result) == hexString(fallback))
    }

    @Test("empty hex returns fallback")
    func emptyHexReturnsFallback() {
        let fallback = Color.blue
        let result = Theme.adaptiveColor(hex: "", darkHex: nil, fallback: fallback)
        #expect(hexString(result) == hexString(fallback))
    }

    @Test("hex only returns static color")
    func hexOnlyReturnsStaticColor() {
        let result = Theme.adaptiveColor(hex: "#FF0000FF", darkHex: nil, fallback: .blue)
        // Resolves to the same color in both appearances
        let light = resolve(result, isDark: false)
        let dark  = resolve(result, isDark: true)
        #expect(hexString(light) == hexString(dark))
    }

    @Test("empty darkHex returns static color")
    func emptyDarkHexReturnsStaticColor() {
        let result = Theme.adaptiveColor(hex: "#FF0000FF", darkHex: "", fallback: .blue)
        let light = resolve(result, isDark: false)
        let dark  = resolve(result, isDark: true)
        #expect(hexString(light) == hexString(dark))
    }

    @Test("auto darkHex produces different light and dark values")
    func autoDarkHexProducesAdaptiveColor() {
        let result = Theme.adaptiveColor(hex: "#FF0000FF", darkHex: Theme.darkVariantAuto, fallback: .blue)
        let light = resolve(result, isDark: false)
        let dark  = resolve(result, isDark: true)
        #expect(hexString(light) != hexString(dark))
    }

    @Test("explicit darkHex produces adaptive color with correct light and dark")
    func explicitDarkHexProducesAdaptiveColor() {
        let result = Theme.adaptiveColor(hex: "#FF0000FF", darkHex: "#0000FFFF", fallback: .green)
        let light = resolve(result, isDark: false)
        let dark  = resolve(result, isDark: true)
        // Light mode should be red-ish, dark mode should be blue-ish
        let lightNS = NSColor(light).usingColorSpace(.sRGB)!
        let darkNS  = NSColor(dark).usingColorSpace(.sRGB)!
        #expect(lightNS.redComponent   > 0.9)
        #expect(lightNS.blueComponent  < 0.1)
        #expect(darkNS.blueComponent   > 0.9)
        #expect(darkNS.redComponent    < 0.1)
    }

    @Test("invalid darkHex falls back to static base color")
    func invalidDarkHexFallsBackToBase() {
        let result = Theme.adaptiveColor(hex: "#FF0000FF", darkHex: "notahex", fallback: .blue)
        let light = resolve(result, isDark: false)
        let dark  = resolve(result, isDark: true)
        // Both should match the base color since darkHex is invalid
        #expect(hexString(light) == hexString(dark))
    }

    @Test("auto hex generates light from dark")
    func autoHexGeneratesLightFromDark() {
        let result = Theme.adaptiveColor(hex: Theme.darkVariantAuto, darkHex: "#DDB6F2FF", fallback: .blue)
        let light = resolve(result, isDark: false)
        let dark  = resolve(result, isDark: true)
        // Dark mode should match the explicit dark hex
        let darkNS = NSColor(dark).usingColorSpace(.sRGB)!
        #expect(darkNS.redComponent   > 0.85)  // ~0.867 (DDB6F2)
        #expect(darkNS.greenComponent > 0.70)  // ~0.714
        // Light should be different (generated complement)
        #expect(hexString(light) != hexString(dark))
    }

    @Test("auto hex and nil dark returns fallback")
    func autoHexNilDarkReturnsFallback() {
        let fallback = Color.green
        let result = Theme.adaptiveColor(hex: Theme.darkVariantAuto, darkHex: nil, fallback: fallback)
        #expect(hexString(result) == hexString(fallback))
    }

    @Test("both auto returns fallback")
    func bothAutoReturnsFallback() {
        let fallback = Color.green
        let result = Theme.adaptiveColor(
            hex: Theme.darkVariantAuto, darkHex: Theme.darkVariantAuto, fallback: fallback
        )
        #expect(hexString(result) == hexString(fallback))
    }

    // MARK: - isLight

    @Test("white is light")
    func whiteIsLight() {
        #expect(Theme.isLight(Color.white))
    }

    @Test("black is not light")
    func blackIsNotLight() {
        #expect(!Theme.isLight(Color.black))
    }

    @Test("dark purple is not light")
    func darkPurpleIsNotLight() {
        // #7F2EB8 — luminance ≈ 0.055
        let c = Theme.color(hex: "#7F2EB8FF")!
        #expect(!Theme.isLight(c))
    }

    @Test("light lavender is light")
    func lightLavenderIsLight() {
        // #DDB6F2 — luminance ≈ 0.52
        let c = Theme.color(hex: "#DDB6F2FF")!
        #expect(Theme.isLight(c))
    }

    // MARK: - generatedComplement

    @Test("complement of dark color is lighter")
    func complementOfDarkColorIsLighter() {
        let dark = Theme.color(hex: "#5A2EB8FF")!
        let comp = Theme.generatedComplement(for: dark)
        let darkNS = NSColor(dark).usingColorSpace(.sRGB)!
        let compNS = NSColor(comp).usingColorSpace(.sRGB)!
        let darkLum = 0.2126 * darkNS.redComponent + 0.7152 * darkNS.greenComponent + 0.0722 * darkNS.blueComponent
        let compLum = 0.2126 * compNS.redComponent + 0.7152 * compNS.greenComponent + 0.0722 * compNS.blueComponent
        #expect(compLum > darkLum)
    }

    @Test("complement of light color is darker")
    func complementOfLightColorIsDarker() {
        let light = Theme.color(hex: "#DDB6F2FF")!
        let comp  = Theme.generatedComplement(for: light)
        let lightNS = NSColor(light).usingColorSpace(.sRGB)!
        let compNS  = NSColor(comp).usingColorSpace(.sRGB)!
        let lightLum = 0.2126 * lightNS.redComponent + 0.7152 * lightNS.greenComponent + 0.0722 * lightNS.blueComponent
        let compLum  = 0.2126 * compNS.redComponent  + 0.7152 * compNS.greenComponent  + 0.0722 * compNS.blueComponent
        #expect(compLum < lightLum)
    }

    @Test("auto darkHex: dark is generated from hex (light), dark mode is always lighter for dark base")
    func autoDarkHexGeneratesDarkFromLight() {
        // hex is always the light-mode value; darkHex=auto generates the dark complement
        let result = Theme.adaptiveColor(hex: "#5A2EB8FF", darkHex: Theme.darkVariantAuto, fallback: .green)
        let light = resolve(result, isDark: false)
        let dark  = resolve(result, isDark: true)
        let lightNS = NSColor(light).usingColorSpace(.sRGB)!
        let darkNS  = NSColor(dark).usingColorSpace(.sRGB)!
        let lightLum = 0.2126 * lightNS.redComponent + 0.7152 * lightNS.greenComponent + 0.0722 * lightNS.blueComponent
        let darkLum  = 0.2126 * darkNS.redComponent  + 0.7152 * darkNS.greenComponent  + 0.0722 * darkNS.blueComponent
        // Dark mode complement of a dark base should be lighter
        #expect(darkLum > lightLum)
        // Light mode should match the explicit hex
        let hexNS = NSColor(Theme.color(hex: "#5A2EB8FF")!).usingColorSpace(.sRGB)!
        #expect(abs(lightNS.blueComponent - hexNS.blueComponent) < 0.01)
    }

    @Test("auto darkHex: light hex is always assigned to light mode regardless of luminance")
    func autoAlwaysAssignsHexToLightMode() {
        // Even if hex is a light/pastel color, it should still be the light-mode value
        let result = Theme.adaptiveColor(hex: "#DDB6F2FF", darkHex: Theme.darkVariantAuto, fallback: .green)
        let lightMode = resolve(result, isDark: false)
        let lightNS   = NSColor(lightMode).usingColorSpace(.sRGB)!
        let hexNS     = NSColor(Theme.color(hex: "#DDB6F2FF")!).usingColorSpace(.sRGB)!
        // Light mode should match the hex (DDB6F2)
        #expect(abs(lightNS.redComponent   - hexNS.redComponent)   < 0.01)
        #expect(abs(lightNS.greenComponent - hexNS.greenComponent) < 0.01)
        #expect(abs(lightNS.blueComponent  - hexNS.blueComponent)  < 0.01)
    }

    // MARK: - Helpers

    /// Resolve an adaptive SwiftUI Color to a concrete Color under the given appearance.
    private func resolve(_ color: Color, isDark: Bool) -> Color {
        let appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)!
        var resolved = color
        appearance.performAsCurrentDrawingAppearance {
            if let ns = NSColor(color).usingColorSpace(.sRGB) {
                resolved = Color(ns)
            }
        }
        return resolved
    }

    /// Round-trip a Color through NSColor sRGB → "#RRGGBBAA" for stable comparison.
    private func hexString(_ color: Color) -> String {
        guard let ns = NSColor(color).usingColorSpace(.sRGB) else { return "" }
        let r = Int((ns.redComponent   * 255).rounded())
        let g = Int((ns.greenComponent * 255).rounded())
        let b = Int((ns.blueComponent  * 255).rounded())
        let a = Int((ns.alphaComponent * 255).rounded())
        return String(format: "#%02X%02X%02X%02X", r, g, b, a)
    }
}
