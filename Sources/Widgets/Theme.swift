import SwiftUI

public enum Theme {
    // MARK: - Colors
    public static let labelColor: Color = .primary
    public static let grey:       Color = .secondary

    // MARK: - Layout
    public static let barContainerHeight: CGFloat = 50
    public static let sidebarContainerWidth: CGFloat = 72
    public static let itemGap: CGFloat = 4
    public static let appIconSize: CGFloat = 16
    public static let labelSize: CGFloat = 12
    /// Extra window height below the bar for shadow rendering; content stays pinned to top.
    public static let shadowOverflow: CGFloat = 14

    // MARK: - Bar shadow
    public static let barShadowOpacity: Double  = 0.3
    public static let barShadowRadius:  CGFloat = 8
    public static let barShadowY:       CGFloat = 4

    // MARK: - Animations
    public static let menuBarAnimDuration: Double    = 0.25
    public static let springIconHover:     Animation = .spring(response: 0.2, dampingFraction: 0.7)
    public static let springLabelHover:    Animation = .spring(response: 0.3, dampingFraction: 0.75)

    /// Parses `#RRGGBB` / `#RRGGBBAA` (leading `#` optional) into a Color.
    public static func color(hex: String?) -> Color? {
        guard let hex else { return nil }
        let h = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
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
