import SwiftUI

// MARK: - GlassVariant

/// Liquid Glass effect variant (macOS 26+).
/// Named GlassVariant to avoid shadowing SwiftUI's Glass type.
public enum GlassVariant: Sendable, Equatable {
    case regular
    case clear
    case identity
}

// MARK: - BlurAppearance

/// One blur parameterization: material + specular overlay + drop shadow.
/// Used both for the standalone `.blur` variant and the pre-macOS 26
/// liquidGlass fallback.
public struct BlurAppearance: Sendable, Equatable {
    public enum Material: Sendable, Equatable { case regular, thin, ultraThin }

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
    public enum Variant: Sendable, Equatable { case liquidGlass, blur, solid, none }

    public let variant:       Variant
    public let height:        CGFloat
    public let cornerRadius:  CGFloat
    public let border:        Bool
    public let borderWidth:   CGFloat
    public let borderColor:   Color?          // nil = adaptive
    public let glassDefault:  GlassVariant
    public let glassHover:    GlassVariant
    public let glassToggled:  GlassVariant
    public let glassFallbackBlur: BlurAppearance  // pre-26 fallback for liquidGlass
    public let blur:              BlurAppearance  // standalone .blur variant
    public let solidColor:        Color?          // fill color for .solid variant; nil = system default
    public let solidShadow:       Bool            // drop shadow for .solid variant

    public init(
        variant:           Variant,
        height:            CGFloat,
        cornerRadius:      CGFloat,
        border:            Bool,
        borderWidth:       CGFloat,
        borderColor:       Color?,
        glassDefault:      GlassVariant,
        glassHover:        GlassVariant,
        glassToggled:      GlassVariant,
        glassFallbackBlur: BlurAppearance = BlurAppearance(shadow: true),
        blur:              BlurAppearance = BlurAppearance(),
        solidColor:        Color? = nil,
        solidShadow:       Bool   = false
    ) {
        self.variant           = variant
        self.height            = height
        self.cornerRadius      = cornerRadius
        self.border            = border
        self.borderWidth       = borderWidth
        self.borderColor       = borderColor
        self.glassDefault      = glassDefault
        self.glassHover        = glassHover
        self.glassToggled      = glassToggled
        self.glassFallbackBlur = glassFallbackBlur
        self.blur              = blur
        self.solidColor        = solidColor
        self.solidShadow       = solidShadow
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
    func nanoPill(focused: Bool = false, hovered: Bool = false, fixedHeight: Bool = true) -> some View {
        modifier(NanoPillModifier(focused: focused, hovered: hovered, fixedHeight: fixedHeight))
    }
}

public struct NanoPillModifier: ViewModifier {
    public let focused:     Bool
    public let hovered:     Bool
    public let fixedHeight: Bool
    @Environment(\.pillStyle) private var pillStyle

    private let iconPadLeft:   CGFloat = 10
    private let labelPadRight: CGFloat = 10

    public init(focused: Bool = false, hovered: Bool = false, fixedHeight: Bool = true) {
        self.focused     = focused
        self.hovered     = hovered
        self.fixedHeight = fixedHeight
    }

    public func body(content: Content) -> some View {
        let activeGlass: GlassVariant = hovered ? pillStyle.glassHover
                                      : focused ? pillStyle.glassToggled
                                      :           pillStyle.glassDefault
        let shape = RoundedRectangle(cornerRadius: pillStyle.cornerRadius, style: .continuous)
        let padded = content
            // Default foreground: .primary adapts to the glass background automatically.
            // Widgets override per-element with .foregroundStyle(customColor) when needed.
            .foregroundStyle(.primary)
            .padding(.leading,  iconPadLeft)
            .padding(.trailing, labelPadRight)
        backgrounded(
            fixedHeight
                ? AnyView(padded.frame(height: pillStyle.height))
                : AnyView(padded.padding(.vertical, (pillStyle.height - Theme.labelSize) / 2)),
            shape: shape,
            activeGlass: activeGlass
        )
        .interactiveRegion()
    }

    @ViewBuilder
    private func backgrounded<V: View>(_ content: V, shape: RoundedRectangle, activeGlass: GlassVariant) -> some View {
        if #available(macOS 26, *) {
            backgroundedLiquidGlass(content, shape: shape, activeGlass: activeGlass)
        } else {
            backgroundedBlur(content, shape: shape)
        }
    }

    @available(macOS 26, *)
    @ViewBuilder
    private func backgroundedLiquidGlass<V: View>(_ content: V, shape: RoundedRectangle, activeGlass: GlassVariant) -> some View {
        switch pillStyle.variant {
        case .liquidGlass:
            let tintOpacity: Double = hovered ? 0.3 : focused ? 0.5 : 0.0
            let glass = tintOpacity > 0
                ? makeGlass(from: activeGlass).tint(.white.opacity(tintOpacity))
                : makeGlass(from: activeGlass)
            content
                .glassEffect(glass, in: shape)
                .overlay { borderOverlay(shape: shape) }
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
        let fill = pillStyle.solidColor ?? Color(red: 0.11, green: 0.11, blue: 0.118, opacity: 0.8)
        content
            .background { shape.fill(fill) }
            .overlay { borderOverlay(shape: shape) }
            .modifier(PillShadow(enabled: pillStyle.solidShadow))
    }

    @ViewBuilder
    private func backgroundedBlur<V: View>(_ content: V, shape: RoundedRectangle) -> some View {
        switch pillStyle.variant {
        case .none:
            content.clipShape(shape)
        case .blur:
            backgroundedMaterial(content, shape: shape, blur: pillStyle.blur)
        case .solid:
            backgroundedSolid(content, shape: shape)
        case .liquidGlass:
            backgroundedMaterial(content, shape: shape, blur: pillStyle.glassFallbackBlur)
        }
    }

    @ViewBuilder
    private func backgroundedMaterial<V: View>(_ content: V, shape: RoundedRectangle, blur: BlurAppearance) -> some View {
        let mat: Material = {
            switch blur.material {
            case .thin:      return .thinMaterial
            case .ultraThin: return .ultraThinMaterial
            case .regular:   return .regularMaterial
            }
        }()
        content
            .background {
                ZStack {
                    shape.fill(mat)
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
            shape.strokeBorder(
                pillStyle.borderColor ?? Color.white.opacity(0.28),
                lineWidth: pillStyle.borderWidth
            )
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
