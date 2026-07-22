import SwiftUI
import Monitors

// Reports whether center widgets fit on the right side of the built-in bar.
private struct CenterFitsRightKey: PreferenceKey {
    static let defaultValue = true
    static func reduce(value: inout Bool, nextValue: () -> Bool) { value = nextValue() }
}

public struct BarRootView: View {
    @EnvironmentObject private var config: ConfigLoader
    let isBuiltIn: Bool
    let monitorID: Int
    @State private var centerFitsRight = true

    public init(isBuiltIn: Bool, monitorID: Int) {
        self.isBuiltIn = isBuiltIn
        self.monitorID = monitorID
    }

    private var cfg: NanoConfig { config.config }

    public var body: some View {
        // Derived once per body pass — style construction parses colors/strings.
        let bar = BarStyle(cfg.bar)
        let pos = cfg.bar.resolvedPosition
        Group {
            if pos == .top {
                topLayout(bar: bar)
            } else {
                sidebarLayout(bar: bar, pos: pos)
            }
        }
        .environment(\.monitorID, monitorID)
        .environment(\.pillStyle, PillStyle(cfg.pill))
        .environment(\.barPosition, pos)
    }

    // MARK: - Top bar layout

    private func topLayout(bar: BarStyle) -> some View {
        VStack(spacing: 0) {
            Group {
                if isBuiltIn { builtIn(bar: bar) } else { external(bar: bar) }
            }
            .frame(minHeight: bar.minHeight)
            .background(barBackground(bar: bar, position: .top))
            .padding(bar.margin)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Sidebar layout (left / right)

    @ViewBuilder private func sidebarLayout(bar: BarStyle, pos: BarPosition) -> some View {
        let allWidgets = cfg.widgets.left + cfg.widgets.center + cfg.widgets.right
        HStack(spacing: 0) {
            if pos == .right { Spacer(minLength: 0) }
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: Theme.itemGap) {
                    zoneWidgets(allWidgets)
                }
                .padding(bar.padding)
                Spacer(minLength: 0)
            }
            .frame(width: Theme.sidebarContainerWidth, alignment: .leading)
            .background(barBackground(bar: bar, position: pos))
            .padding(bar.margin)
            if pos == .left { Spacer(minLength: 0) }
        }
    }

    // MARK: - Bar background

    @ViewBuilder private func barBackground(bar: BarStyle, position: BarPosition) -> some View {
        let shape = RoundedRectangle(cornerRadius: bar.cornerRadius, style: .continuous)
        let shadowX: CGFloat = position == .left ? Theme.barShadowY : (position == .right ? -Theme.barShadowY : 0)
        let shadowY: CGFloat = position == .top ? Theme.barShadowY : 0
        ZStack {
            switch bar.background {
            case .none:              Color.clear
            case .blur:              shape.fill(.regularMaterial)
            case let .color(color):  shape.fill(color)
            }
            if bar.border {
                shape.strokeBorder(bar.borderColor, lineWidth: bar.borderWidth)
            }
        }
        .shadow(color: bar.shadow ? .black.opacity(Theme.barShadowOpacity) : .clear,
                radius: Theme.barShadowRadius, x: shadowX, y: shadowY)
    }

    // MARK: - Widget dispatch

    @ViewBuilder
    private func widgetView(for id: String) -> some View {
        switch id {
        case "workspaces":
            WorkspaceBarView(mode: cfg.workspaces.resolvedMode)
        default:
            EmptyView()  // Unknown IDs: silently skip.
        }
    }

    @ViewBuilder
    private func zoneWidgets(_ ids: [String]) -> some View {
        ForEach(ids, id: \.self) { id in
            widgetView(for: id)
        }
    }

    // MARK: - Built-in layout (notch avoidance)

    private func builtIn(bar: BarStyle) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: Theme.itemGap) {
                zoneWidgets(cfg.widgets.left)
                Spacer(minLength: 0)
                if !centerFitsRight {
                    zoneWidgets(cfg.widgets.center)
                }
            }
            .padding(bar.padding)

            Spacer().frame(width: Theme.notchWidth)

            HStack(spacing: Theme.itemGap) {
                Spacer(minLength: 0)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: Theme.itemGap) {
                        zoneWidgets(cfg.widgets.center)
                        zoneWidgets(cfg.widgets.right)
                    }
                    .preference(key: CenterFitsRightKey.self, value: true)

                    HStack(spacing: Theme.itemGap) {
                        zoneWidgets(cfg.widgets.right)
                    }
                    .preference(key: CenterFitsRightKey.self, value: false)
                }
            }
            .padding(bar.padding)
            .onPreferenceChange(CenterFitsRightKey.self) { centerFitsRight = $0 }
        }
    }

    // MARK: - External layout (center widgets centered)

    private func external(bar: BarStyle) -> some View {
        ZStack {
            zoneWidgets(cfg.widgets.center)
            HStack(spacing: Theme.itemGap) {
                zoneWidgets(cfg.widgets.left)
                Spacer()
            }
            HStack(spacing: Theme.itemGap) {
                Spacer()
                zoneWidgets(cfg.widgets.right)
            }
        }
        .padding(bar.padding)
    }
}
