import Testing
@testable import Monitors

@Suite("ConfigParser")
struct ConfigParserTests {

    @Test("parses key = value lines, skipping comments and blanks")
    func basicParsing() {
        let raw = """
            # full-line comment
            theme = dark

            bar-position = left
            """
        let values = ConfigParser.parse(raw)
        #expect(values == ["theme": "dark", "bar-position": "left"])
    }

    @Test("strips trailing comments but keeps leading-# hex values")
    func trailingComments() {
        let raw = """
            theme = light   # system | light | dark
            pill-solid-color = #2F3031CC
            bar-border-color = #FFFFFF59  # adaptive if unset
            """
        let values = ConfigParser.parse(raw)
        #expect(values["theme"] == "light")
        #expect(values["pill-solid-color"] == "#2F3031CC")
        #expect(values["bar-border-color"] == "#FFFFFF59")
    }

    @Test("ignores malformed lines and empty values")
    func malformedLines() {
        let raw = """
            no equals sign here
            = value-without-key
            empty-value =
            valid = yes
            """
        let values = ConfigParser.parse(raw)
        #expect(values == ["valid": "yes"])
    }
}

@Suite("NanoConfig")
struct NanoConfigTests {

    private func config(_ raw: String) -> NanoConfig {
        NanoConfig(ConfigParser.parse(raw))
    }

    // MARK: - Workspaces

    @Test("workspaces-mode decoded")
    func workspacesModeDecoded() {
        #expect(config("workspaces-mode = collapsed").workspaces.mode == "collapsed")
        #expect(config("workspaces-mode = expandOnHover").workspaces.resolvedMode == .expandOnHover)
    }

    @Test("workspaces-mode defaults to expandOnHoverAndActive")
    func workspacesModeDefault() {
        #expect(config("").workspaces.resolvedMode == .expandOnHoverAndActive)
    }

    @Test("resolvedMode falls back to expandOnHoverAndActive for unrecognized string")
    func resolvedModeFallback() {
        #expect(config("workspaces-mode = bogus").workspaces.resolvedMode == .expandOnHoverAndActive)
    }

    // MARK: - Bar

    @Test("resolvedPosition parses left and falls back to top for unrecognized string")
    func resolvedPositionParsing() {
        #expect(config("bar-position = left").bar.resolvedPosition == .left)
        #expect(config("bar-position = middle").bar.resolvedPosition == .top)
    }

    @Test("insets: base key sets all sides, per-side keys override")
    func insetsParsing() {
        let c = config("""
            bar-padding = 4
            bar-padding-left = 12
            """)
        #expect(c.bar.padding == SideInsets(top: 4, right: 4, bottom: 4, left: 12))
    }

    @Test("insets: per-side key alone overrides only that side of the default")
    func insetsPartialOverride() {
        let c = config("bar-margin-top = 6")
        #expect(c.bar.margin == SideInsets(top: 6, right: 0, bottom: 0, left: 0))
    }

    @Test("bar blur material decoded, defaults to regular")
    func barBlurMaterial() {
        #expect(config("bar-blur-material = thin").bar.blurMaterial == "thin")
        #expect(config("").bar.blurMaterial == "regular")
    }

    @Test("border keys decoded")
    func borderParsing() {
        let c = config("""
            bar-border = true
            bar-border-width = 1.5
            bar-border-color = #FF0000
            """)
        #expect(c.bar.border == BorderConfig(enabled: true, width: 1.5, color: "#FF0000"))
    }

    // MARK: - Pill

    @Test("glass effect keys decoded, defaults applied when absent")
    func glassEffectParsing() {
        let c = config("""
            pill-glass-default = regular
            pill-glass-hover = identity
            """)
        #expect(c.pill.glassDefault == "regular")
        #expect(c.pill.glassHover   == "identity")
        #expect(c.pill.glassToggled == "regular")
    }

    @Test("blur keys decoded")
    func blurKeysParsing() {
        let c = config("""
            pill-blur-material = thin
            pill-blur-specular = false
            pill-blur-shadow = true
            """)
        #expect(c.pill.blurMaterial == "thin")
        #expect(c.pill.blurSpecular == false)
        #expect(c.pill.blurShadow   == true)
    }

    @Test("numeric keys accept ints and doubles")
    func numericParsing() {
        let c = config("""
            pill-height = 28
            pill-corner-radius = 14.5
            pill-min-width = 40
            """)
        #expect(c.pill.height == 28)
        #expect(c.pill.cornerRadius == 14.5)
        #expect(c.pill.minWidth == 40)
    }

    @Test("pill min-width defaults to 30")
    func pillMinWidthDefault() {
        #expect(config("").pill.minWidth == 30)
    }

    // MARK: - Theme

    @Test("theme decoded, defaults to system")
    func themeParsing() {
        #expect(config("theme = dark").theme == "dark")
        #expect(config("").theme == "system")
    }

    @Test("resolvedTheme parses valid values and falls back to system")
    func resolvedTheme() {
        #expect(config("theme = light").resolvedTheme == .light)
        #expect(config("theme = dark").resolvedTheme == .dark)
        #expect(config("theme = sepia").resolvedTheme == .system)
        #expect(config("").resolvedTheme == .system)
    }

    // MARK: - Reference config

    @Test("reference config parses to pure defaults (everything commented)")
    func referenceConfigIsAllDefaults() {
        #expect(ConfigParser.parse(NanoConfig.referenceConfig).isEmpty)
    }
}
