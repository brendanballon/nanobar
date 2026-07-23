import AppKit
import Carbon
import Widgets
import Monitors

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var barPanels: [BarPanel] = []
    private var fullscreenObservers: [Any] = []
    private var fullscreenCheckWork: DispatchWorkItem?
    private var fullscreenRecheckCount = 0
    private var statusItem: NSStatusItem?
    private var barGeometry: BarGeometry?

    /// Config values the NSPanel frame is derived from (see BarPanel.barFrame).
    /// A change to any of them requires a panel rebuild — SwiftUI content
    /// updates via @Published, but the panel frame is fixed at init.
    private struct BarGeometry: Equatable {
        let position:   BarPosition
        let minHeight:  Double
        let margin:     SideInsets
        let padding:    SideInsets
        let pillHeight: Double

        init(_ config: NanoConfig) {
            position   = config.bar.resolvedPosition
            minHeight  = config.bar.minHeight
            margin     = config.bar.margin
            padding    = config.bar.padding
            pillHeight = config.pill.height
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        ConfigLoader.shared.loadOrCreate()
        applyTheme(ConfigLoader.shared.config.resolvedTheme)
        barGeometry = BarGeometry(ConfigLoader.shared.config)
        // Appearance/widget changes propagate via @Published config. The theme
        // needs explicit re-application, and a frame-affecting change needs a
        // panel rebuild — the NSPanel frame is derived from the config at init.
        ConfigLoader.shared.onReload = { [weak self] in
            guard let self else { return }
            let config = ConfigLoader.shared.config
            self.applyTheme(config.resolvedTheme)
            let geometry = BarGeometry(config)
            if geometry != self.barGeometry {
                self.barGeometry = geometry
                self.reinit()
            }
        }
        reinit()

        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)

        installMenuBarCarbonHandler()
        installFullscreenObservers()
        installStatusItem()
    }

    // MARK: - Reinit

    /// Full reinit: tears down panels, then rebuilds from current config.
    /// Called on first launch and on screen configuration changes.
    private func reinit() {
        barPanels.forEach { $0.close() }
        barPanels.removeAll()
        setupBars()
    }

    private func applyTheme(_ theme: AppTheme) {
        switch theme {
        case .system: NSApp.appearance = nil
        case .light:  NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:   NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    // MARK: - Bar setup

    private func setupBars() {
        for (index, screen) in NSScreen.screens.enumerated() {
            let panel = BarPanel(screen: screen, monitorID: index + 1)
            panel.orderFront(nil)
            barPanels.append(panel)
        }
        scheduleFullscreenCheck(after: 0)
    }

    @objc private func screensChanged() {
        reinit()
    }

    // MARK: - Auto-hide menu bar detection via Carbon

    private func installMenuBarCarbonHandler() {
        var specs = [
            EventTypeSpec(eventClass: OSType(kEventClassMenu), eventKind: UInt32(kEventMenuBarShown)),
            EventTypeSpec(eventClass: OSType(kEventClassMenu), eventKind: UInt32(kEventMenuBarHidden))
        ]
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, event, userData) -> OSStatus in
                guard let event, let userData else { return noErr }
                let shown    = GetEventKind(event) == UInt32(kEventMenuBarShown)
                let delegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
                Task { @MainActor in delegate.handleMenuBarVisibility(visible: shown) }
                return noErr
            },
            specs.count,
            &specs,
            selfPtr,
            nil as UnsafeMutablePointer<EventHandlerRef?>?
        )
    }

    private func handleMenuBarVisibility(visible: Bool) {
        barPanels.forEach { $0.adjustForMenuBar(visible: visible) }
    }

    // MARK: - Fullscreen detection

    private func installFullscreenObservers() {
        let ws = NSWorkspace.shared.notificationCenter
        let handler: @Sendable (Notification) -> Void = { [weak self] _ in
            Task { @MainActor [weak self] in self?.scheduleFullscreenCheck() }
        }
        fullscreenObservers = [
            ws.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification,      object: nil, queue: nil, using: handler),
            ws.addObserver(forName: NSWorkspace.didActivateApplicationNotification,    object: nil, queue: nil, using: handler),
            ws.addObserver(forName: NSWorkspace.didDeactivateApplicationNotification,  object: nil, queue: nil, using: handler),
        ]
    }

    /// Exit-fullscreen notifications fire at the start of the space transition,
    /// so a check can run while the departing window still covers the screen.
    /// A few bounded catch-up re-checks recover from that; re-polling forever
    /// would scan the global window list every 2s for the whole fullscreen session.
    private static let maxFullscreenRechecks = 3
    private static let fullscreenRecheckDelay: TimeInterval = 2.0

    private func scheduleFullscreenCheck(after delay: TimeInterval = 0.6) {
        fullscreenRecheckCount = 0
        enqueueFullscreenCheck(after: delay)
    }

    private func enqueueFullscreenCheck(after delay: TimeInterval) {
        fullscreenCheckWork?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.checkFullscreenState() }
        fullscreenCheckWork = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func checkFullscreenState() {
        // Snapshot main-thread data, then do the expensive window list query off-main.
        let primaryH = NSScreen.screens.first?.frame.height ?? 0
        let targets = barPanels.map { (panel: $0, sf: $0.associatedScreen.frame) }
        Task(priority: .userInitiated) {
            let results = await Task.detached(priority: .userInitiated) {
                // The window list is global — query and parse it once, then test
                // each screen against it, instead of re-querying per monitor.
                let windowRects = AppDelegate.fullscreenCandidateRects(primaryH: primaryH)
                return targets.map { (panel, sf) in
                    (panel, AppDelegate.screenHasFullscreenWindow(sf: sf, windowRects: windowRects))
                }
            }.value
            for (panel, hidden) in results { panel.setFullscreenHidden(hidden) }
            // While any panel is hidden, re-check a bounded number of times to
            // catch a mid-transition snapshot; steady-state hidden panels are
            // revived by the workspace observers, not by polling.
            if results.contains(where: { $0.1 }), fullscreenRecheckCount < Self.maxFullscreenRechecks {
                fullscreenRecheckCount += 1
                enqueueFullscreenCheck(after: Self.fullscreenRecheckDelay)
            }
        }
    }

    // MARK: - Status item

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "square.grid.3x1.below.line.grid.1x2", accessibilityDescription: "NanoBar")
        item.button?.image?.isTemplate = true
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Quit NanoBar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
    }

    /// Cocoa-coordinate rects of normal-layer on-screen windows — the only
    /// candidates that can be fullscreen windows.
    nonisolated private static func fullscreenCandidateRects(primaryH: CGFloat) -> [CGRect] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return [] }
        return list.compactMap { info in
            guard let layer = info[kCGWindowLayer as String] as? Int, layer <= 0 else { return nil }
            guard let boundsDict = info[kCGWindowBounds as String] as? NSDictionary else { return nil }
            var cgRect = CGRect.zero
            guard CGRectMakeWithDictionaryRepresentation(boundsDict, &cgRect) else { return nil }
            return CGRect(x: cgRect.minX, y: primaryH - cgRect.maxY, width: cgRect.width, height: cgRect.height)
        }
    }

    /// A fullscreen window can report a height short of the screen by up to the
    /// menu-bar/notch strip during transitions.
    nonisolated private static let fullscreenHeightTolerance: CGFloat = 50

    nonisolated private static func screenHasFullscreenWindow(sf: CGRect, windowRects: [CGRect]) -> Bool {
        windowRects.contains { rect in
            rect.width  == sf.width
                && rect.minX   == sf.minX
                && rect.minY   == sf.minY
                && rect.height >= sf.height - fullscreenHeightTolerance
        }
    }

}
