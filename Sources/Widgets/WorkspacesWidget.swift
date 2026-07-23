import AppKit
import Foundation
import Monitors
import os
import SwiftUI

private let log = Logger(subsystem: "com.nanobar.NanoBar", category: "workspaces")

// MARK: - AeroSpace client

private struct TimeoutError: Error {}

/// Process isn't Sendable, but the timeout path must terminate it from another
/// task. NSTask's run/terminate/isRunning are thread-safe.
private final class ProcessBox: @unchecked Sendable {
    let process = Process()

    func terminateIfRunning() {
        if process.isRunning { process.terminate() }
    }
}

private final class AeroSpaceClient: @unchecked Sendable {
    static let shared = AeroSpaceClient()
    private init() {}

    private static let binaryPaths = [
        "/opt/homebrew/bin/aerospace",
        "/usr/local/bin/aerospace",
        "/usr/bin/aerospace",
    ]

    private static let binaryURL: URL? = binaryPaths
        .map { URL(fileURLWithPath: $0) }
        .first { FileManager.default.isExecutableFile(atPath: $0.path) }

    // The list formats are load-bearing: parseWorkspaceList/parseWindowList are
    // written against exactly these column layouts.
    func listWorkspaces() async throws -> String {
        try await run(args: ["list-workspaces", "--all", "--format", "%{workspace} %{monitor-id} %{workspace-is-focused}"])
    }

    func listWindows() async throws -> String {
        try await run(args: ["list-windows", "--all", "--format", "%{window-id} %{workspace} %{app-name}"])
    }

    func focusWorkspace(_ id: String) {
        Task { try? await run(args: ["workspace", id]) }
    }

    func focusWindow(_ windowID: Int) {
        Task { try? await run(args: ["focus", "--window-id", "\(windowID)"]) }
    }

    func run(args: [String]) async throws -> String {
        guard let url = Self.binaryURL else { throw CocoaError(.fileNoSuchFile) }
        let box = ProcessBox()
        return try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { continuation in
                    let process = box.process
                    process.executableURL = url
                    process.arguments = args
                    let pipe = Pipe()
                    process.standardOutput = pipe
                    // Null device, not an unread Pipe — a full ~64KB stderr
                    // buffer would block the child forever.
                    process.standardError = FileHandle.nullDevice
                    do    { try process.run() }
                    catch { continuation.resume(throwing: error); return }
                    // Drain stdout continuously, then reap. Reading only after
                    // termination deadlocks once output exceeds the pipe buffer.
                    DispatchQueue.global().async {
                        let data = pipe.fileHandleForReading.readDataToEndOfFile()
                        process.waitUntilExit()
                        continuation.resume(returning: String(data: data, encoding: .utf8) ?? "")
                    }
                }
            }
            group.addTask {
                try await Task.sleep(for: .seconds(30))
                throw TimeoutError()
            }
            do {
                let result = try await group.next() ?? ""
                group.cancelAll()
                return result
            } catch {
                // Kill the child on timeout so it can't linger; the resulting
                // EOF unblocks the reader task.
                box.terminateIfRunning()
                group.cancelAll()
                throw error
            }
        }
    }
}

// MARK: - Data types

private struct WorkspaceState: Sendable, Equatable {
    /// Max app icons shown per workspace pill.
    static let maxWindowIcons = 5

    let id: String
    let isFocused: Bool
    let windows: [WindowInfo]
    let monitorID: Int

    init(id: String, isFocused: Bool, windows: [WindowInfo], monitorID: Int) {
        self.id = id
        self.isFocused = isFocused
        self.windows = Array(windows.prefix(Self.maxWindowIcons))
        self.monitorID = monitorID
    }

    /// Copy with selected fields replaced; routes through init to keep the icon cap.
    func with(isFocused: Bool? = nil, windows: [WindowInfo]? = nil) -> WorkspaceState {
        WorkspaceState(
            id: id,
            isFocused: isFocused ?? self.isFocused,
            windows: windows ?? self.windows,
            monitorID: monitorID
        )
    }

    /// Empty unfocused workspaces are dropped from the bar.
    var isVisible: Bool { !windows.isEmpty || isFocused }
}

private struct WindowInfo: Sendable, Equatable {
    let windowID: Int
    let appName: String
}

// MARK: - App icon cache

/// Caches NSWorkspace icon lookups by app name — the running-applications scan
/// is linear and would otherwise re-run on every pill render.
@MainActor
private enum AppIconCache {
    /// Values cache both hits and misses (nil) — an unresolved name would
    /// otherwise rescan runningApplications on every render.
    private static var icons: [String: NSImage?] = [:]

    static func icon(for appName: String) -> NSImage? {
        if let cached = icons[appName] { return cached }
        let icon = NSWorkspace.shared.runningApplications
            .first { $0.localizedName == appName }?.icon
        icons[appName] = .some(icon)
        return icon
    }

    static func evict(_ appName: String) {
        icons[appName] = nil
    }
}

// MARK: - Live state

@MainActor
private final class WorkspacesState: ObservableObject {
    static let shared = WorkspacesState()

    /// Window-focus (F) events arriving right after a workspace switch are
    /// echoes of the switch itself — ignore them within this window.
    private static let focusEchoWindow: TimeInterval = 0.15

    @Published var states: [WorkspaceState] = []

    private var cachedStates: [WorkspaceState] = []
    private var lastWorkspaceChangeTime: Date = .distantPast
    nonisolated(unsafe) private var appObservers: [NSObjectProtocol] = []

    private let notifySocketPath = "/tmp/nanobar-notify.sock"
    private var notifySource: DispatchSourceRead?
    private var serverFD: Int32 = -1

    init() {
        Task { await fetchAndNotify() }
        startNotifySocket()
        let center = NSWorkspace.shared.notificationCenter
        appObservers = [
            center.addObserver(
                forName: NSWorkspace.didTerminateApplicationNotification,
                object: nil, queue: .main
            ) { [weak self] notification in
                guard let name = Self.appName(from: notification) else { return }
                MainActor.assumeIsolated {
                    AppIconCache.evict(name)
                    self?.removeApp(named: name)
                }
            },
            // A fresh launch invalidates a cached icon miss — the app may have
            // been looked up before NSWorkspace registered it.
            center.addObserver(
                forName: NSWorkspace.didLaunchApplicationNotification,
                object: nil, queue: .main
            ) { notification in
                guard let name = Self.appName(from: notification) else { return }
                MainActor.assumeIsolated { AppIconCache.evict(name) }
            },
        ]
    }

    deinit {
        appObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        notifySource?.cancel()
        if serverFD >= 0 { close(serverFD) }
        // Don't unlink the socket path here — startNotifySocket() handles cleanup on
        // next bind, and unlinking here would destroy a socket created by a newer instance.
    }

    nonisolated private static func appName(from notification: Notification) -> String? {
        (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.localizedName
    }

    // MARK: - Notify socket

    private func startNotifySocket() {
        unlink(notifySocketPath)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            log.error("notify socket: socket() failed (errno \(errno)) — bar will not live-update")
            return
        }
        serverFD = fd
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        notifySocketPath.withCString { cStr in
            withUnsafeMutablePointer(to: &addr.sun_path) {
                _ = strncpy(UnsafeMutableRawPointer($0).assumingMemoryBound(to: CChar.self), cStr, 104)
            }
        }
        let bindOK = withUnsafePointer(to: addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindOK == 0, listen(fd, 5) == 0 else {
            log.error("notify socket: bind/listen failed (errno \(errno)) — bar will not live-update")
            close(fd)
            serverFD = -1
            return
        }
        // Run on main queue so the handler is @MainActor-compatible.
        // accept()+read() on a local domain socket are instant — safe on main.
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
        source.setEventHandler { [weak self] in
            let clientFD = accept(fd, nil, nil)
            guard clientFD >= 0 else { return }
            var buf = [UInt8](repeating: 0, count: 64)
            let n = read(clientFD, &buf, buf.count - 1)
            close(clientFD)
            let msg = n > 0
                ? String(bytes: buf.prefix(n), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                : ""
            Task { @MainActor in await self?.handleMessage(msg) }
        }
        source.resume()
        notifySource = source
    }

    // MARK: - Message routing
    //
    //   W <prev> <next>  — workspace focus changed
    //   F                — window-level focus changed
    //   M                — focused monitor changed
    //   (anything else)  — full refresh

    private func handleMessage(_ msg: String) async {
        let parts = msg.split(separator: " ", maxSplits: 2).map(String.init)
        switch parts.first {
        case "W":
            guard parts.count == 3 else { await fetchAndNotify(); return }
            lastWorkspaceChangeTime = Date()
            applyFocusChange(prev: parts[1], next: parts[2])
            await fetchWindowsOnly(animated: false)
        case "F":
            guard Date().timeIntervalSince(lastWorkspaceChangeTime) > Self.focusEchoWindow else { return }
            await fetchWindowsOnly()
        case "M":
            await fetchWorkspacesOnly()
        default:
            await fetchAndNotify()
        }
    }

    // MARK: - Zero-subprocess cache mutations

    private func applyFocusChange(prev: String, next: String) {
        var updated = cachedStates.map { ws in
            ws.id == next ? ws.with(isFocused: true)
                : ws.id == prev ? ws.with(isFocused: false)
                : ws
        }
        if !updated.contains(where: { $0.id == next }) {
            let monitorID = cachedStates.first { $0.id == prev }?.monitorID ?? 1
            updated.append(WorkspaceState(id: next, isFocused: true, windows: [], monitorID: monitorID))
            updated.sort { $0.id < $1.id }
        }
        updateAndPublish(updated)
    }

    private func removeApp(named name: String) {
        let updated = cachedStates
            .map { ws in ws.with(windows: ws.windows.filter { $0.appName != name }) }
            .filter(\.isVisible)
        updateAndPublish(updated)
    }

    // MARK: - Single-subprocess partial fetches

    private func fetchWindowsOnly(animated: Bool = true) async {
        guard let winOut = try? await AeroSpaceClient.shared.listWindows() else { return }

        let wsWindows = parseWindowList(winOut)
        let knownIDs  = Set(cachedStates.map { $0.id })
        let fallbackMonitorID = cachedStates.first { $0.isFocused }?.monitorID ?? 1

        var updated = cachedStates
            .map { ws in ws.with(windows: wsWindows[ws.id] ?? []) }
            .filter(\.isVisible)

        for wsID in wsWindows.keys where !knownIDs.contains(wsID) {
            updated.append(WorkspaceState(
                id: wsID, isFocused: false,
                windows: wsWindows[wsID]!,
                monitorID: fallbackMonitorID
            ))
        }
        updated.sort { $0.id < $1.id }
        updateAndPublish(updated, animated: animated)
    }

    private func fetchWorkspacesOnly() async {
        guard let wsOut = try? await AeroSpaceClient.shared.listWorkspaces() else { return }

        let (wsMonitor, wsFocused) = parseWorkspaceList(wsOut)
        let windowsByWS = Dictionary(uniqueKeysWithValues: cachedStates.map { ($0.id, $0.windows) })
        updateAndPublish(buildStates(monitor: wsMonitor, focused: wsFocused, windowsByWS: windowsByWS))
    }

    // MARK: - Full fetch (startup + fallback)

    private func fetchAndNotify() async {
        updateAndPublish(await fetchAll())
    }

    private func fetchAll() async -> [WorkspaceState] {
        do {
            async let wsTask  = AeroSpaceClient.shared.listWorkspaces()
            async let winTask = AeroSpaceClient.shared.listWindows()
            let (wsOut, winOut)        = try await (wsTask, winTask)
            let (wsMonitor, wsFocused) = parseWorkspaceList(wsOut)
            return buildStates(monitor: wsMonitor, focused: wsFocused, windowsByWS: parseWindowList(winOut))
        } catch {
            // Keep the last good state — returning [] would blank the whole
            // bar on a transient CLI failure.
            return cachedStates
        }
    }

    // MARK: - Parsing / assembly helpers

    /// Assembles sorted workspace states, dropping empty unfocused workspaces.
    private func buildStates(
        monitor: [String: Int],
        focused: [String: Bool],
        windowsByWS: [String: [WindowInfo]]
    ) -> [WorkspaceState] {
        monitor.keys.sorted().compactMap { wsID in
            let state = WorkspaceState(
                id: wsID,
                isFocused: focused[wsID] ?? false,
                windows: windowsByWS[wsID] ?? [],
                monitorID: monitor[wsID]!
            )
            return state.isVisible ? state : nil
        }
    }

    private func parseWindowList(_ output: String) -> [String: [WindowInfo]] {
        var wsWindows: [String: [WindowInfo]] = [:]
        var seen: Set<String> = []
        for line in output.split(separator: "\n") {
            let parts = line.split(separator: " ", maxSplits: 2)
            guard parts.count == 3 else { continue }
            let wsID    = String(parts[1])
            let appName = String(parts[2])
            let key     = "\(wsID):\(appName)"
            guard seen.insert(key).inserted else { continue }
            wsWindows[wsID, default: []].append(WindowInfo(windowID: Int(parts[0]) ?? 0, appName: appName))
        }
        return wsWindows
    }

    private func parseWorkspaceList(_ output: String) -> (monitor: [String: Int], focused: [String: Bool]) {
        var wsMonitor: [String: Int]  = [:]
        var wsFocused: [String: Bool] = [:]
        for line in output.split(separator: "\n") {
            let parts = line.split(separator: " ", maxSplits: 2)
            guard parts.count >= 2 else { continue }
            let wsID = String(parts[0])
            wsMonitor[wsID] = Int(parts[1]) ?? 1
            wsFocused[wsID] = parts.count > 2 && parts[2].trimmingCharacters(in: .whitespaces) == "true"
        }
        return (wsMonitor, wsFocused)
    }

    private func updateAndPublish(_ newStates: [WorkspaceState], animated: Bool = true) {
        guard newStates != cachedStates else { return }
        cachedStates = newStates
        if animated {
            withAnimation(Theme.springStateChange) {
                states = newStates
            }
        } else {
            states = newStates
        }
    }
}

// MARK: - Root view

struct WorkspaceBarView: View {
    @ObservedObject private var state = WorkspacesState.shared
    @Environment(\.monitorID) private var monitorID
    @Environment(\.barPosition) private var barPosition

    let mode: WorkspaceMode
    @State private var hoveredID: String?

    private var filtered: [WorkspaceState] {
        state.states.filter { $0.monitorID == monitorID }
    }

    var body: some View {
        if barPosition == .top {
            HStack(spacing: Theme.itemGap) { pills }
        } else {
            VStack(spacing: Theme.itemGap) { pills }
        }
    }

    @ViewBuilder private var pills: some View {
        ForEach(filtered, id: \.id) { ws in
            WorkspacePill(
                state: ws,
                mode: mode,
                vertical: barPosition != .top,
                hoveredID: $hoveredID
            )
        }
    }
}

// MARK: - Workspace pill (all modes)

private struct WorkspacePill: View {
    let state: WorkspaceState
    let mode: WorkspaceMode
    let vertical: Bool
    @Binding var hoveredID: String?

    private var isHovered: Bool { hoveredID == state.id }

    private var showsIcons: Bool {
        switch mode {
        case .expanded:               return true
        case .collapsed:              return false
        case .expandOnHover:          return isHovered
        case .expandOnActive:         return state.isFocused
        case .expandOnHoverAndActive: return isHovered || state.isFocused
        }
    }

    private var expandsOnHover: Bool {
        mode == .expandOnHover || mode == .expandOnHoverAndActive
    }

    private var hoverAnimation: Animation {
        expandsOnHover ? Theme.springLabelHover : Theme.easeHover
    }

    var body: some View {
        layout
            .nanoPill(focused: state.isFocused, hovered: isHovered, fixedHeight: !vertical)
            .onHover { hovering in
                withAnimation(hoverAnimation) {
                    hoveredID = hovering ? state.id : nil
                }
            }
            .onTapGesture {
                AeroSpaceClient.shared.focusWorkspace(state.id)
            }
    }

    @ViewBuilder private var layout: some View {
        if vertical {
            VStack(spacing: 4) {
                label
                if showsIcons, !state.windows.isEmpty {
                    VStack(spacing: 6) {
                        icons(transition: .scale(scale: 0.4, anchor: .top).combined(with: .opacity))
                    }
                }
            }
        } else {
            HStack(spacing: 6) {
                label
                if showsIcons, !state.windows.isEmpty {
                    HStack(spacing: 4) {
                        icons(transition: .scale(scale: 0.4).combined(with: .opacity))
                    }
                }
            }
        }
    }

    private var label: some View {
        Text(state.id)
            .font(.system(size: Theme.labelSize, weight: .semibold))
            .foregroundStyle(state.isFocused ? Theme.labelColor : Theme.grey)
            .fixedSize()
    }

    private func icons(transition: AnyTransition) -> some View {
        ForEach(state.windows, id: \.windowID) { window in
            AppIconView(window: window)
                .transition(transition)
        }
    }
}

// MARK: - App icon

private struct AppIconView: View {
    let window: WindowInfo
    @State private var isHovered = false

    var body: some View {
        if let icon = AppIconCache.icon(for: window.appName) {
            Image(nsImage: icon)
                .resizable()
                .frame(width: Theme.appIconSize, height: Theme.appIconSize)
                .scaleEffect(isHovered ? 1.15 : 1.0)
                .animation(Theme.springIconHover, value: isHovered)
                // No interactiveRegion() here — the enclosing pill's region already
                // covers the icons; per-icon GeometryReaders would republish the
                // preference every animation frame for nothing.
                .onHover { isHovered = $0 }
                .onTapGesture {
                    AeroSpaceClient.shared.focusWindow(window.windowID)
                }
        }
    }
}
