import Foundation

// MARK: - AppTheme

/// Controls the app-wide color scheme. Persisted as `theme` in the config file.
public enum AppTheme: String, Sendable {
    case system
    case light
    case dark
}

// MARK: - BarPosition

/// Where the bar appears on screen. Persisted as `bar-position`.
public enum BarPosition: String, Sendable {
    case top, left, right
}

// MARK: - WorkspaceMode

/// Workspaces widget display mode — when a workspace pill expands to show
/// its app icons. Persisted as `workspaces-mode`.
public enum WorkspaceMode: String, Sendable {
    /// Every workspace always shows its icons.
    case expanded
    /// Labels only, never any icons.
    case collapsed
    /// Icons appear while the pill is hovered.
    case expandOnHover
    /// The focused workspace shows its icons.
    case expandOnActive
    /// Icons on hover or on the focused workspace.
    case expandOnHoverAndActive
}

// MARK: - SideInsets

/// Four-sided inset. Configured as a base key (`bar-padding = 8`) plus
/// optional per-side overrides (`bar-padding-left = 12`).
public struct SideInsets: Sendable, Equatable {
    public let top: Double
    public let right: Double
    public let bottom: Double
    public let left: Double

    public init(all: Double = 0) { top = all; right = all; bottom = all; left = all }

    public init(top: Double, right: Double, bottom: Double, left: Double) {
        self.top = top
        self.right = right
        self.bottom = bottom
        self.left = left
    }
}

// MARK: - BorderConfig

/// Border configured as `…-border = true/false` plus optional
/// `…-border-width` and `…-border-color` keys.
public struct BorderConfig: Sendable, Equatable {
    public var enabled: Bool
    public var width:   Double  = 0.75
    /// Hex string like "#FFFFFF59"; nil = adaptive default color.
    public var color:   String? = nil

    public static let defaultColor = "#FFFFFF59"

    public init(enabled: Bool, width: Double = 0.75, color: String? = nil) {
        self.enabled = enabled
        self.width = width
        self.color = color
    }
}

// MARK: - Config model

/// The full NanoBar configuration, built from flat `key = value` pairs.
/// Every key is optional — a missing file or empty dictionary yields defaults.
public struct NanoConfig: Sendable {

    // MARK: Nested types

    public struct WorkspacesConfig: Sendable {
        /// "expanded" | "collapsed" | "expandOnHover" | "expandOnActive" | "expandOnHoverAndActive"
        public var mode: String = "expandOnHoverAndActive"

        /// Parsed `mode` string. Falls back to `.expandOnHoverAndActive` for unrecognized values.
        public var resolvedMode: WorkspaceMode {
            WorkspaceMode(rawValue: mode) ?? .expandOnHoverAndActive
        }

        public init() {}
    }

    public struct BarConfig: Sendable {
        /// "none" | "blur" | "color:#RRGGBBAA"
        public var background:   String       = "none"
        /// Material for the blur background: "regular" | "thin" | "ultraThin"
        public var blurMaterial: String       = "regular"
        public var minHeight:    Double       = 30
        public var cornerRadius: Double       = 0
        public var shadow:       Bool         = false
        /// "top" | "left" | "right"
        public var position:     String       = "top"
        /// Gap between screen edge and bar background.
        public var margin:       SideInsets   = SideInsets()
        /// Gap between bar background edge and pill widgets.
        public var padding:      SideInsets   = SideInsets(all: 8)
        public var border:       BorderConfig = BorderConfig(enabled: false)

        /// Parsed `position` string. Falls back to `.top` for unrecognized values.
        public var resolvedPosition: BarPosition {
            BarPosition(rawValue: position) ?? .top
        }

        public init() {}
    }

    public struct PillConfig: Sendable {
        /// "liquidGlass" | "blur" | "solid" | "none"
        public var style:        String       = "blur"
        public var height:       Double       = 30
        public var minWidth:     Double       = 30
        public var cornerRadius: Double       = 15
        public var border:       BorderConfig = BorderConfig(enabled: true)
        /// Glass effect per interaction state (liquidGlass style):
        /// "regular" | "clear" | "identity"
        public var glassDefault: String       = "clear"
        public var glassHover:   String       = "regular"
        public var glassToggled: String       = "regular"
        /// Blur appearance — used by the blur style, and as the pre-macOS 26
        /// fallback for liquidGlass. material: "regular" | "thin" | "ultraThin"
        public var blurMaterial: String       = "regular"
        public var blurSpecular: Bool         = true
        public var blurShadow:   Bool         = false
        /// Fill color for the solid style, e.g. "#1C1C1ECC".
        public var solidColor:   String       = "#1C1C1ECC"
        public var solidShadow:  Bool         = false

        public init() {}
    }

    // MARK: Properties

    /// "system" | "light" | "dark"
    public var theme:      String           = "system"
    public var bar:        BarConfig        = .init()
    public var pill:       PillConfig       = .init()
    public var workspaces: WorkspacesConfig = .init()

    /// Parsed `theme` string. Falls back to `.system` for unrecognized values.
    public var resolvedTheme: AppTheme {
        AppTheme(rawValue: theme) ?? .system
    }

    // MARK: Defaults

    public static let defaults = NanoConfig()

    public init() {}

    // MARK: Init from flat key-value pairs

    public init(_ v: [String: String]) {
        theme           = v["theme"]           ?? theme
        workspaces.mode = v["workspaces-mode"] ?? workspaces.mode

        bar.background   = v["bar-background"]                ?? bar.background
        bar.blurMaterial = v["bar-blur-material"]             ?? bar.blurMaterial
        bar.minHeight    = Self.double(v["bar-min-height"])    ?? bar.minHeight
        bar.cornerRadius = Self.double(v["bar-corner-radius"]) ?? bar.cornerRadius
        bar.shadow       = Self.bool(v["bar-shadow"])          ?? bar.shadow
        bar.position     = v["bar-position"]                  ?? bar.position
        bar.margin       = Self.insets(v, "bar-margin",  base: bar.margin)
        bar.padding      = Self.insets(v, "bar-padding", base: bar.padding)
        bar.border       = Self.border(v, "bar-border",  base: bar.border)

        pill.style        = v["pill-style"]                     ?? pill.style
        pill.height       = Self.double(v["pill-height"])        ?? pill.height
        pill.minWidth     = Self.double(v["pill-min-width"])     ?? pill.minWidth
        pill.cornerRadius = Self.double(v["pill-corner-radius"]) ?? pill.cornerRadius
        pill.border       = Self.border(v, "pill-border", base: pill.border)
        pill.glassDefault = v["pill-glass-default"]             ?? pill.glassDefault
        pill.glassHover   = v["pill-glass-hover"]               ?? pill.glassHover
        pill.glassToggled = v["pill-glass-toggled"]             ?? pill.glassToggled
        pill.blurMaterial = v["pill-blur-material"]             ?? pill.blurMaterial
        pill.blurSpecular = Self.bool(v["pill-blur-specular"])   ?? pill.blurSpecular
        pill.blurShadow   = Self.bool(v["pill-blur-shadow"])     ?? pill.blurShadow
        pill.solidColor   = v["pill-solid-color"]               ?? pill.solidColor
        pill.solidShadow  = Self.bool(v["pill-solid-shadow"])    ?? pill.solidShadow
    }

    // MARK: Value parsing helpers

    private static func double(_ s: String?) -> Double? {
        s.flatMap(Double.init)
    }

    private static func bool(_ s: String?) -> Bool? {
        switch s {
        case "true":  return true
        case "false": return false
        default:      return nil
        }
    }

    /// Base key sets all sides; `-top/-right/-bottom/-left` suffixes override.
    private static func insets(_ v: [String: String], _ key: String, base: SideInsets) -> SideInsets {
        let all = double(v[key])
        return SideInsets(
            top:    double(v["\(key)-top"])    ?? all ?? base.top,
            right:  double(v["\(key)-right"])  ?? all ?? base.right,
            bottom: double(v["\(key)-bottom"]) ?? all ?? base.bottom,
            left:   double(v["\(key)-left"])   ?? all ?? base.left
        )
    }

    private static func border(_ v: [String: String], _ key: String, base: BorderConfig) -> BorderConfig {
        var border = base
        border.enabled = bool(v[key])          ?? base.enabled
        border.width   = double(v["\(key)-width"]) ?? base.width
        border.color   = v["\(key)-color"]     ?? base.color
        return border
    }

    // MARK: Reference config template

    /// Written on first launch as documentation — every key commented out.
    public static let referenceConfig = """
        # NanoBar configuration — plain `key = value` lines.
        # Every key is optional; the app runs on defaults without this file.
        # Lines starting with # are comments; trailing " # …" comments are stripped.

        # ── Workspaces (AeroSpace) ────────────────────────────────────────────────────
        # When a workspace pill expands to show its app icons:
        #   expanded | collapsed | expandOnHover | expandOnActive | expandOnHoverAndActive
        # workspaces-mode = expandOnHoverAndActive

        # ── App ───────────────────────────────────────────────────────────────────────
        # theme = system                     # system | light | dark

        # ── Bar ───────────────────────────────────────────────────────────────────────
        # bar-position = top                 # top | left | right
        # bar-background = none              # none | blur | color:#RRGGBBAA
        # bar-blur-material = regular        # regular | thin | ultraThin (blur background)
        # bar-min-height = 30
        # bar-corner-radius = 0
        # bar-shadow = false
        #
        # bar-margin = 0                     # screen edge → bar; per-side overrides:
        # bar-margin-top = 0
        # bar-margin-right = 0
        # bar-margin-bottom = 0
        # bar-margin-left = 0
        #
        # bar-padding = 8                    # bar edge → pills; per-side overrides:
        # bar-padding-top = 8
        # bar-padding-right = 8
        # bar-padding-bottom = 8
        # bar-padding-left = 8
        #
        # bar-border = false
        # bar-border-width = 0.75
        # bar-border-color = #FFFFFF59

        # ── Pill ──────────────────────────────────────────────────────────────────────
        # pill-style = blur                  # liquidGlass | blur | solid | none
        # pill-height = 30
        # pill-min-width = 30
        # pill-corner-radius = 15
        # pill-border = true
        # pill-border-width = 0.75
        # pill-border-color = #FFFFFF47     # unset = adaptive
        #
        # pill-glass-default = clear         # regular | clear | identity
        # pill-glass-hover = regular
        # pill-glass-toggled = regular
        #
        # pill-blur-material = regular       # regular | thin | ultraThin
        # pill-blur-specular = true
        # pill-blur-shadow = false
        #
        # pill-solid-color = #1C1C1ECC
        # pill-solid-shadow = false
        """
}
