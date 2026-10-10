import SwiftUI
import Monitors

public struct BarRootView: View {
    @EnvironmentObject private var config: ConfigLoader
    let monitorID: Int

    public init(monitorID: Int) {
        self.monitorID = monitorID
    }

    private var cfg: NanoConfig { config.config }

    public var body: some View {
        // Derived once per body pass — style construction parses colors/strings.
        let bar = BarStyle(cfg.bar)
        let pos = cfg.bar.resolvedPosition
        let gap = CGFloat(cfg.pill.gap)
        Group {
            if pos.isHorizontal {
                horizontalLayout(bar: bar, pos: pos, gap: gap)
            } else {
                sidebarLayout(bar: bar, pos: pos, gap: gap)
            }
        }
        .environment(\.monitorID, monitorID)
        .environment(\.pillStyle, PillStyle(cfg.pill))
        .environment(\.barPosition, pos)
    }

    private var workspaces: some View {
        WorkspaceBarView(mode: cfg.workspaces.resolvedMode)
    }

    // MARK: - Horizontal layout (top / bottom)

    private func horizontalLayout(bar: BarStyle, pos: BarPosition, gap: CGFloat) -> some View {
        VStack(spacing: 0) {
            if pos == .bottom { Spacer(minLength: 0) }
            HStack(spacing: gap) {
                workspaces
                Spacer(minLength: 0)
                DownloadsPillView()
            }
            .padding(bar.padding)
            .frame(minHeight: bar.minHeight)
            .background(barBackground(bar: bar, position: pos))
            .padding(bar.margin)
            if pos == .top { Spacer(minLength: 0) }
        }
    }

    // MARK: - Sidebar layout (left / right)

    private func sidebarLayout(bar: BarStyle, pos: BarPosition, gap: CGFloat) -> some View {
        HStack(spacing: 0) {
            if pos == .right { Spacer(minLength: 0) }
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: gap) {
                    workspaces
                }
                .padding(bar.padding)
                Spacer(minLength: 0)
                HStack(spacing: gap) {
                    Spacer(minLength: 0)
                    DownloadsPillView()
                }
                .padding(bar.padding)
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
        let shadowY: CGFloat = position == .top ? Theme.barShadowY : (position == .bottom ? -Theme.barShadowY : 0)
        ZStack {
            switch bar.background {
            case .none:              Color.clear
            case .blur:              shape.fill(bar.blurMaterial.swiftUIMaterial)
            case let .color(color):  shape.fill(color)
            }
            if bar.border {
                shape.strokeBorder(bar.borderColor, lineWidth: bar.borderWidth)
            }
        }
        .shadow(color: bar.shadow ? .black.opacity(Theme.barShadowOpacity) : .clear,
                radius: Theme.barShadowRadius, x: shadowX, y: shadowY)
    }
}
