import Testing
import TOMLKit
@testable import Monitors

@Suite("NanoConfig")
struct NanoConfigTests {

    // MARK: - Workspaces config

    @Test("workspaces mode decoded from [workspaces] section")
    func workspacesModeDecoded() throws {
        let raw = "[workspaces]\nmode = \"labelsOnly\""
        let config = try TOMLDecoder().decode(NanoConfig.self, from: raw)
        #expect(config.workspaces.mode == "labelsOnly")
    }

    @Test("workspaces mode defaults to clampAndExpand when section absent")
    func workspacesModeDefault() throws {
        let config = try TOMLDecoder().decode(NanoConfig.self, from: "")
        #expect(config.workspaces.mode == "clampAndExpand")
    }

    @Test("resolvedMode falls back to clampAndExpand for unrecognized string")
    func resolvedModeFallback() throws {
        let raw = "[workspaces]\nmode = \"bogus\""
        let config = try TOMLDecoder().decode(NanoConfig.self, from: raw)
        #expect(config.workspaces.resolvedMode == .clampAndExpand)
    }

    @Test("resolvedPosition parses left and falls back to top for unrecognized string")
    func resolvedPositionParsing() throws {
        let left = try TOMLDecoder().decode(NanoConfig.self, from: "[bar]\nposition = \"left\"")
        #expect(left.bar.resolvedPosition == .left)
        let bogus = try TOMLDecoder().decode(NanoConfig.self, from: "[bar]\nposition = \"middle\"")
        #expect(bogus.bar.resolvedPosition == .top)
    }

    // MARK: - Glass effect parsing

    @Test("glass effect keys are decoded correctly from TOML")
    func glassConfigEffectParsing() throws {
        let raw = """
            [pill.liquidGlass]
            defaultEffect = "regular"
            hoverEffect   = "identity"
            toggledEffect = "clear"
            """
        let config = try TOMLDecoder().decode(NanoConfig.self, from: raw)
        let glass = config.pill.liquidGlass
        #expect(glass.defaultEffect == "regular")
        #expect(glass.hoverEffect   == "identity")
        #expect(glass.toggledEffect == "clear")
    }

    @Test("glass effect defaults applied when keys absent")
    func glassConfigEffectDefaults() throws {
        let raw = "[pill.liquidGlass]\n"
        let config = try TOMLDecoder().decode(NanoConfig.self, from: raw)
        let glass = config.pill.liquidGlass
        #expect(glass.defaultEffect == "clear")
        #expect(glass.hoverEffect   == "regular")
        #expect(glass.toggledEffect == "regular")
    }

    // MARK: - Theme config

    @Test("theme defaults to system when [app] section absent")
    func themeDefaultsToSystem() throws {
        let config = try TOMLDecoder().decode(NanoConfig.self, from: "")
        #expect(config.app.theme == "system")
    }

    @Test("theme = light decoded from [app] section")
    func themeLightDecoded() throws {
        let raw = "[app]\ntheme = \"light\""
        let config = try TOMLDecoder().decode(NanoConfig.self, from: raw)
        #expect(config.app.theme == "light")
    }

    @Test("theme = dark decoded from [app] section")
    func themeDarkDecoded() throws {
        let raw = "[app]\ntheme = \"dark\""
        let config = try TOMLDecoder().decode(NanoConfig.self, from: raw)
        #expect(config.app.theme == "dark")
    }

    @Test("resolvedTheme returns .system for default config")
    func resolvedThemeDefault() {
        let config = NanoConfig()
        #expect(config.resolvedTheme == .system)
    }

    @Test("resolvedTheme returns .light when theme string is light")
    func resolvedThemeLight() {
        var config = NanoConfig()
        config.app.theme = "light"
        #expect(config.resolvedTheme == .light)
    }

    @Test("resolvedTheme returns .dark when theme string is dark")
    func resolvedThemeDark() {
        var config = NanoConfig()
        config.app.theme = "dark"
        #expect(config.resolvedTheme == .dark)
    }

    @Test("resolvedTheme falls back to .system for unrecognized string")
    func resolvedThemeFallback() {
        var config = NanoConfig()
        config.app.theme = "sepia"
        #expect(config.resolvedTheme == .system)
    }
}
