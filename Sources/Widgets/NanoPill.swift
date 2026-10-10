import SwiftUI

// MARK: - GlassVariant

/// Liquid Glass effect variant (macOS 26+).
/// Named GlassVariant to avoid shadowing SwiftUI's Glass type.
/// Raw values are the config tokens.
public enum GlassVariant: String, Sendable, Equatable {
    case regular
    case clear
    case identity
}

// MARK: - BlurAppearance

/// Blur appearance: material + specular overlay + drop shadow.
/// Used by the `.blur` variant and as the pre-macOS 26 liquidGlass fallback.
public struct BlurAppearance: Sendable, Equatable {
    /// Raw values are the config tokens.
    public enum Material: String, Sendable, Equatable {
        case regular, thin, ultraThin

        public var swiftUIMaterial: SwiftUI.Material {
            switch self {
            case .thin:      return .thinMaterial
            case .ultraThin: return .ultraThinMaterial
            case .regular:   return .regularMaterial
            }
        }
    }

    public let material: Material
    public let specular: Bool   // white gradient overlay
    public let shadow:   Bool

    public init(material: Material = .regular, specular: Bool = true, shadow: Bool = false) {
        self.material = material
        self.specular = specular
        self.shadow   = shadow
    }
}

// MARK: - PillStyle

/// Global pill appearance, injected via @Environment(\.pillStyle).
/// The host builds it from config (see AppearanceStyles.swift).
public struct PillStyle: Sendable, Equatable {
    /// Raw values are the config tokens.
    public enum Variant: String, Sendable, Equatable { case liquidGlass, blur, solid, none }

    public let variant:       Variant
    public let height:        CGFloat
    public let minWidth:      CGFloat
    public let cornerRadius:  CGFloat
    public let fontSize:      CGFloat
    public let iconSize:      CGFloat
    public let gap:           CGFloat
    public let border:        Bool
    public let borderWidth:   CGFloat
    public let borderColor:   Color
    public let glassDefault:  GlassVariant
    public let glassHover:    GlassVariant
    public let glassToggled:  GlassVariant
    public let blur:          BlurAppearance  // .blur variant + pre-26 liquidGlass fallback
    public let solidColor:    Color           // fill color for .solid variant
    public let solidShadow:   Bool            // drop shadow for .solid variant

    public init(
        variant:      Variant,
        height:       CGFloat,
        minWidth:     CGFloat,
        cornerRadius: CGFloat,
        fontSize:     CGFloat,
        iconSize:     CGFloat,
        gap:          CGFloat,
        border:       Bool,
        borderWidth:  CGFloat,
        borderColor:  Color,
        glassDefault: GlassVariant,
        glassHover:   GlassVariant,
        glassToggled: GlassVariant,
        blur:         BlurAppearance,
        solidColor:   Color,
        solidShadow:  Bool
    ) {
        self.variant      = variant
        self.height       = height
        self.minWidth     = minWidth
        self.cornerRadius = cornerRadius
        self.fontSize     = fontSize
        self.iconSize     = iconSize
        self.gap          = gap
        self.border       = border
        self.borderWidth  = borderWidth
        self.borderColor  = borderColor
        self.glassDefault = glassDefault
        self.glassHover   = glassHover
        self.glassToggled = glassToggled
        self.blur         = blur
        self.solidColor   = solidColor
        self.solidShadow  = solidShadow
    }
}

// MARK: - Environment key

private struct PillStyleKey: EnvironmentKey {
    static let defaultValue = PillStyle.default
}

public extension EnvironmentValues {
    var pillStyle: PillStyle {
        get { self[PillStyleKey.self] }
        set { self[PillStyleKey.self] = newValue }
    }
}

// MARK: - nanoPill modifier

public extension View {
    /// `intrinsic` skips the pill's own padding and size constraints so the
    /// content (which then owns its padding and frame) can animate the glass.
    func nanoPill(focused: Bool = false, hovered: Bool = false, fixedHeight: Bool = true, intrinsic: Bool = false) -> some View {
        modifier(NanoPillModifier(focused: focused, hovered: hovered, fixedHeight: fixedHeight, intrinsic: intrinsic))
    }
}

public struct NanoPillModifier: ViewModifier {
    public let focused:     Bool
    public let hovered:     Bool
    public let fixedHeight: Bool
    public let intrinsic:   Bool
    @Environment(\.pillStyle) private var pillStyle

    private let iconPadLeft:   CGFloat = 10
    private let labelPadRight: CGFloat = 10

    public init(focused: Bool = false, hovered: Bool = false, fixedHeight: Bool = true, intrinsic: Bool = false) {
        self.intrinsic   = intrinsic
        self.focused     = focused
        self.hovered     = hovered
        self.fixedHeight = fixedHeight
    }

    public func body(content: Content) -> some View {
        let activeGlass: GlassVariant = hovered ? pillStyle.glassHover
                                      : focused ? pillStyle.glassToggled
                                      :           pillStyle.glassDefault
        let shape = RoundedRectangle(cornerRadius: pillStyle.cornerRadius, style: .continuous)
        if intrinsic {
            backgrounded(content.foregroundStyle(.primary), shape: shape, activeGlass: activeGlass)
                .interactiveRegion()
        } else {
            let padded = content
                // Default foreground: .primary adapts to the glass background automatically.
                // Widgets override per-element with .foregroundStyle(customColor) when needed.
                .foregroundStyle(.primary)
                .padding(.leading,  iconPadLeft)
                .padding(.trailing, labelPadRight)
                .frame(minWidth: pillStyle.minWidth)
            // Concrete branch types (no AnyView) so SwiftUI keeps structural identity.
            Group {
                if fixedHeight {
                    backgrounded(padded.frame(height: pillStyle.height), shape: shape, activeGlass: activeGlass)
                } else {
                    backgrounded(padded.padding(.vertical, (pillStyle.height - pillStyle.fontSize) / 2), shape: shape, activeGlass: activeGlass)
                }
            }
            .interactiveRegion()
        }
    }

    @ViewBuilder
    private func backgrounded<V: View>(_ content: V, shape: RoundedRectangle, activeGlass: GlassVariant) -> some View {
        switch pillStyle.variant {
        case .liquidGlass:
            if #available(macOS 26, *) {
                let tintOpacity: Double = hovered ? 0.3 : focused ? 0.5 : 0.0
                let glass = tintOpacity > 0
                    ? makeGlass(from: activeGlass).tint(.white.opacity(tintOpacity))
                    : makeGlass(from: activeGlass)
                content
                    .glassEffect(glass, in: shape)
                    .overlay { borderOverlay(shape: shape) }
            } else {
                backgroundedMaterial(content, shape: shape, blur: pillStyle.blur)
            }
        case .blur:
            backgroundedMaterial(content, shape: shape, blur: pillStyle.blur)
        case .solid:
            backgroundedSolid(content, shape: shape)
        case .none:
            content.clipShape(shape)
        }
    }

    @available(macOS 26, *)
    private func makeGlass(from variant: GlassVariant) -> Glass {
        switch variant {
        case .regular:  return .regular
        case .clear:    return .clear
        case .identity: return .identity
        }
    }

    @ViewBuilder
    private func backgroundedSolid<V: View>(_ content: V, shape: RoundedRectangle) -> some View {
        content
            .background { shape.fill(pillStyle.solidColor) }
            .overlay { borderOverlay(shape: shape) }
            .modifier(PillShadow(enabled: pillStyle.solidShadow))
    }

    @ViewBuilder
    private func backgroundedMaterial<V: View>(_ content: V, shape: RoundedRectangle, blur: BlurAppearance) -> some View {
        content
            .background {
                ZStack {
                    shape.fill(blur.material.swiftUIMaterial)
                    if blur.specular {
                        shape.fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.18), .clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    }
                }
            }
            .overlay { borderOverlay(shape: shape) }
            .modifier(PillShadow(enabled: blur.shadow))
    }

    @ViewBuilder
    private func borderOverlay(shape: RoundedRectangle) -> some View {
        if pillStyle.border {
            shape.strokeBorder(pillStyle.borderColor, lineWidth: pillStyle.borderWidth)
        }
    }
}

/// Shared drop-shadow spec for solid and blur pill backgrounds.
private struct PillShadow: ViewModifier {
    let enabled: Bool

    func body(content: Content) -> some View {
        content.shadow(color: enabled ? .black.opacity(0.35) : .clear, radius: 6, x: 0, y: 3)
    }
}
