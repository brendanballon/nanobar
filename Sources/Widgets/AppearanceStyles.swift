import SwiftUI
import Monitors

// MARK: - PillStyle (NanoConfig initialiser + default)

// This extension adds the NanoConfig-backed initialiser and the default,
// making NanoConfig.PillConfig() the single source of truth.
extension PillStyle {
    /// Default style derived from the config schema defaults. Only reached in
    /// SwiftUI previews or isolated tests — BarRootView always injects the
    /// config-derived style into the environment.
    public static let `default` = PillStyle(NanoConfig.PillConfig())

    public init(_ config: NanoConfig.PillConfig) {
        let variant: Variant = {
            switch config.style {
            case "blur":  return .blur
            case "solid": return .solid
            case "none":  return .none
            default:      return .liquidGlass
            }
        }()

        let mapEffect: (String) -> GlassVariant = {
            switch $0 {
            case "regular":  return .regular
            case "identity": return .identity
            default:         return .clear
            }
        }

        self.init(
            variant:      variant,
            height:       CGFloat(config.height),
            minWidth:     CGFloat(config.minWidth),
            cornerRadius: CGFloat(config.cornerRadius),
            border:       config.border.enabled,
            borderWidth:  CGFloat(config.border.width),
            borderColor:  config.border.color.flatMap { Theme.color(hex: $0) },
            glassDefault: mapEffect(config.glassDefault),
            glassHover:   mapEffect(config.glassHover),
            glassToggled: mapEffect(config.glassToggled),
            blur:         BlurAppearance(material: .init(configValue: config.blurMaterial),
                                         specular: config.blurSpecular,
                                         shadow:   config.blurShadow),
            solidColor:   Theme.color(hex: config.solidColor),
            solidShadow:  config.solidShadow
        )
    }
}

// MARK: - BarStyle

/// Bar-level appearance derived from the [bar] config section.
public struct BarStyle: Sendable {
    public enum Background: Sendable {
        case none
        case blur
        case color(Color)
    }
    public let background:   Background
    public let blurMaterial: BlurAppearance.Material
    public let minHeight:    CGFloat
    public let cornerRadius: CGFloat
    public let shadow:       Bool
    public let margin:       EdgeInsets   // screen edge → bar background
    public let padding:      EdgeInsets   // bar background → pill widgets
    public let border:       Bool
    public let borderWidth:  CGFloat
    public let borderColor:  Color

    public init(_ config: NanoConfig.BarConfig) {
        blurMaterial = BlurAppearance.Material(configValue: config.blurMaterial)
        minHeight    = CGFloat(config.minHeight)
        cornerRadius = CGFloat(config.cornerRadius)
        shadow       = config.shadow
        border       = config.border.enabled
        borderWidth  = CGFloat(config.border.width)
        borderColor  = Theme.color(hex: config.border.color ?? BorderConfig.defaultColor) ?? Color.white.opacity(0.35)
        margin  = config.margin.asEdgeInsets
        padding = config.padding.asEdgeInsets
        let raw = config.background.trimmingCharacters(in: .whitespaces)
        if raw == "blur" {
            background = .blur
        } else if raw.lowercased().hasPrefix("color:"), let color = Theme.color(hex: String(raw.dropFirst(6))) {
            background = .color(color)
        } else {
            background = .none
        }
    }
}

private extension SideInsets {
    var asEdgeInsets: EdgeInsets {
        EdgeInsets(top: CGFloat(top), leading: CGFloat(left),
                   bottom: CGFloat(bottom), trailing: CGFloat(right))
    }
}
