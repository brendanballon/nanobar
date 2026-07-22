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

    init(screen: NSScreen, monitorID: Int) {
        self.associatedScreen = screen
        let pos = ConfigLoader.shared.config.bar.resolvedPosition
        self.barPosition = pos
        let frame    = BarPanel.barFrame(for: screen, position: pos)
        let isBuiltIn = screen.localizedName.lowercased().contains("built-in")
        let regionStore = InteractiveRegionStore()
        let rootView = BarRootView(isBuiltIn: isBuiltIn, monitorID: monitorID)
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
        guard barPosition == .top else { return }
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
        switch position {
        case .left:
            return CGRect(
                x: sf.minX,
                y: sf.minY,
                width:  Theme.sidebarContainerWidth + Theme.shadowOverflow,
                height: sf.height - menuBarH
            )
        case .right:
            return CGRect(
                x: sf.maxX - Theme.sidebarContainerWidth - Theme.shadowOverflow,
                y: sf.minY,
                width:  Theme.sidebarContainerWidth + Theme.shadowOverflow,
                height: sf.height - menuBarH
            )
        case .top:
            return CGRect(
                x: sf.minX,
                y: sf.maxY - Theme.barContainerHeight - Theme.shadowOverflow,
                width:  sf.width,
                height: Theme.barContainerHeight + Theme.shadowOverflow
            )
        }
    }
}
