import AppKit
import SwiftUI
import Widgets
import Monitors

@MainActor
final class BarPanel: NSPanel {
    let associatedScreen: NSScreen
    private var menuBarVisible = false
    private var fullscreenHidden = false
    private let barPosition: BarPosition
    /// True when the system menu bar auto-hides (no strip reserved in
    /// visibleFrame). Only then does the top bar swap places with the menu bar.
    private let menuBarAutoHides: Bool

    init(screen: NSScreen, monitorID: Int) {
        self.associatedScreen = screen
        let pos = ConfigLoader.shared.config.bar.resolvedPosition
        self.barPosition = pos
        self.menuBarAutoHides = screen.frame.maxY == screen.visibleFrame.maxY
        let frame    = BarPanel.barFrame(for: screen, position: pos)
        let regionStore = InteractiveRegionStore()
        let rootView = BarRootView(monitorID: monitorID)
            .environmentObject(ConfigLoader.shared)
            .onPreferenceChange(InteractiveRegionKey.self) { rects in
                // Delivered on the main thread; fires per frame during pill
                // animations — avoid allocating a Task per change.
                MainActor.assumeIsolated {
                    regionStore.rects = rects
                }
            }
        let hosting  = PassThroughHostingView(rootView: rootView, regionStore: regionStore)

        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        // ARC owns the panel via AppDelegate.barPanels — without this, close()
        // performs an AppKit release ARC doesn't balance (over-release crash on reinit).
        isReleasedWhenClosed = false

        // Panel has a fixed frame — disable SwiftUI's per-frame sizeThatFits computation.
        // Without this, NSHostingView.layout() calls _sizeThatFits on every display cycle
        // which traverses the entire view graph (StackLayout, ViewThatFits, GeometryReaders).
        hosting.sizingOptions = []
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = CGColor(red: 0, green: 0, blue: 0, alpha: 0)

        level                       = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue - 1)
        collectionBehavior          = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        isMovableByWindowBackground = false
        isOpaque                    = false
        backgroundColor             = .clear
        hasShadow                   = false
        // ignoresMouseEvents stays false (default) — panel stays in the
        // compositor's live compositing chain so glassEffect() samples live
        // desktop content. PassThroughHostingView.hitTest() handles per-pixel
        // pass-through for non-interactive areas.
        contentView                 = hosting
    }

    func adjustForMenuBar(visible: Bool) {
        // With a persistently visible menu bar the top bar sits below it and
        // never swaps places with it — reacting to the global menu-bar
        // shown/hidden events (they also fire on fullscreen transitions) would
        // latch the bar hidden with no event to ever revive it.
        guard barPosition == .top, menuBarAutoHides else { return }
        guard visible != menuBarVisible else { return }
        menuBarVisible = visible
        guard !fullscreenHidden else { return }
        var target = BarPanel.barFrame(for: associatedScreen, position: barPosition)
        if visible { target.origin.y = associatedScreen.frame.maxY }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = Theme.menuBarAnimDuration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            animator().setFrame(target, display: true)
            animator().alphaValue = visible ? 0 : 1
        }
    }

    func setFullscreenHidden(_ hidden: Bool) {
        guard hidden != fullscreenHidden else { return }
        fullscreenHidden = hidden
        let targetAlpha: CGFloat = (hidden || menuBarVisible) ? 0 : 1
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = Theme.menuBarAnimDuration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            animator().alphaValue = targetAlpha
        }
    }

    static func barFrame(for screen: NSScreen, position: BarPosition) -> CGRect {
        let sf = screen.frame
        let menuBarH = sf.maxY - screen.visibleFrame.maxY
        let config = ConfigLoader.shared.config
        switch position {
        case .left, .right:
            let width = sidebarWidth(config)
            return CGRect(
                x: position == .left ? sf.minX : sf.maxX - width,
                y: sf.minY,
                width:  width,
                height: sf.height - menuBarH
            )
        case .top:
            // menuBarH is 0 when the menu bar auto-hides (bar takes its place);
            // otherwise the bar sits below the persistent menu bar.
            let height = horizontalBarHeight(config)
            return CGRect(
                x: sf.minX,
                y: sf.maxY - menuBarH - height,
                width:  sf.width,
                height: height
            )
        case .bottom:
            // visibleFrame.minY is above a persistent bottom Dock, so the bar
            // sits on top of it rather than underneath.
            return CGRect(
                x: sf.minX,
                y: screen.visibleFrame.minY,
                width:  sf.width,
                height: horizontalBarHeight(config)
            )
        }
    }

    /// Panel height derived from the same config values that size the SwiftUI
    /// content (BarRootView.horizontalLayout), so growing the bar can't clip it.
    private static func horizontalBarHeight(_ config: NanoConfig) -> CGFloat {
        let bar = config.bar
        let contentHeight = max(bar.minHeight, config.pill.height + bar.padding.top + bar.padding.bottom)
        // Plus transparent, click-through room for the downloads pill to expand into.
        return CGFloat(contentHeight + bar.margin.top + bar.margin.bottom) + Theme.shadowOverflow
            + Theme.downloadsListMaxHeight + 1
    }

    private static func sidebarWidth(_ config: NanoConfig) -> CGFloat {
        let margin = config.bar.margin
        return Theme.sidebarContainerWidth + CGFloat(margin.left + margin.right) + Theme.shadowOverflow
            + Theme.downloadsListMaxWidth
    }
}
