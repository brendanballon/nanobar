import AppKit
import Foundation
import Monitors
import SwiftUI

// MARK: - AeroSpace client

private struct TimeoutError: Error {}

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
        return try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { continuation in
                    let process = Process()
                    process.executableURL = url
                    process.arguments = args
                    let pipe = Pipe()
                    process.standardOutput = pipe
                    process.standardError  = Pipe()
                    process.terminationHandler = { _ in
                        let data = pipe.fileHandleForReading.readDataToEndOfFile()
                        continuation.resume(returning: String(data: data, encoding: .utf8) ?? "")
                    }
                    do    { try process.run() }
                    catch { continuation.resume(throwing: error) }
                }
            }
            group.addTask {
                try await Task.sleep(for: .seconds(30))
                throw TimeoutError()
            }
            let result = try await group.next() ?? ""
            group.cancelAll()
            return result
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
    private static var icons: [String: NSImage] = [:]

    static func icon(for appName: String) -> NSImage? {
        if let cached = icons[appName] { return cached }
        let icon = NSWorkspace.shared.runningApplications
            .first { $0.localizedName == appName }?.icon
        if let icon { icons[appName] = icon }
        return icon
    }

    static func evict(_ appName: String) {
        icons[appName] = nil
    }
}

// MARK: - Live state

@MainActor
private final class WorkspacesState: ObservableObject, @unchecked Sendable {
    static let shared = WorkspacesState()

    @Published var states: [WorkspaceState] = []

    private var cachedStates: [WorkspaceState] = []
    private var lastWorkspaceChangeTime: Date = .distantPast
    nonisolated(unsafe) private var appTerminationObserver: NSObjectProtocol?

    private let notifySocketPath = "/tmp/nanobar-notify.sock"
    private var notifySource: DispatchSourceRead?
    private var serverFD: Int32 = -1

    init() {
        Task { await fetchAndNotify() }
        startNotifySocket()
        appTerminationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let name = app.localizedName else { return }
            MainActor.assumeIsolated {
                AppIconCache.evict(name)
                self?.removeApp(named: name)
            }
        }
    }

    deinit {
        appTerminationObserver.map { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        notifySource?.cancel()
        if serverFD >= 0 { close(serverFD) }
        // Don't unlink the socket path here — startNotifySocket() handles cleanup on
        // next bind, and unlinking here would destroy a socket created by a newer instance.
    }

    // MARK: - Notify socket

    private func startNotifySocket() {
        unlink(notifySocketPath)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return }
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
        guard bindOK == 0, listen(fd, 5) == 0 else { close(fd); return }
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
            guard Date().timeIntervalSince(lastWorkspaceChangeTime) > 0.15 else { return }
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
            WorkspaceState(
                id: ws.id,
                isFocused: ws.id == next ? true : (ws.id == prev ? false : ws.isFocused),
                windows: ws.windows,
                monitorID: ws.monitorID
            )
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
            .map { ws in
                WorkspaceState(
                    id: ws.id,
                    isFocused: ws.isFocused,
                    windows: ws.windows.filter { $0.appName != name },
                    monitorID: ws.monitorID
                )
            }
            .filter { !$0.windows.isEmpty || $0.isFocused }
        updateAndPublish(updated)
    }

    // MARK: - Single-subprocess partial fetches

    private func fetchWindowsOnly(animated: Bool = true) async {
        guard let winOut = try? await AeroSpaceClient.shared.listWindows() else { return }

        let wsWindows = parseWindowList(winOut)
        let knownIDs  = Set(cachedStates.map { $0.id })
        let fallbackMonitorID = cachedStates.first { $0.isFocused }?.monitorID ?? 1

        var updated = cachedStates
            .map { ws in
                WorkspaceState(
                    id: ws.id,
                    isFocused: ws.isFocused,
                    windows: wsWindows[ws.id] ?? [],
                    monitorID: ws.monitorID
                )
            }
            .filter { !$0.windows.isEmpty || $0.isFocused }

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
        } catch { return [] }
    }

    // MARK: - Parsing / assembly helpers

    /// Assembles sorted workspace states, dropping empty unfocused workspaces.
    private func buildStates(
        monitor: [String: Int],
        focused: [String: Bool],
        windowsByWS: [String: [WindowInfo]]
    ) -> [WorkspaceState] {
        monitor.keys.sorted().compactMap { wsID in
            let windows = windowsByWS[wsID] ?? []
            let isFocused = focused[wsID] ?? false
            guard !windows.isEmpty || isFocused else { return nil }
            return WorkspaceState(id: wsID, isFocused: isFocused, windows: windows, monitorID: monitor[wsID]!)
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
            withAnimation(.spring(response: 0.2, dampingFraction: 0.85)) {
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
                // Sidebar always uses the expanding layout regardless of mode.
                mode: barPosition == .top ? mode : .clampAndExpand,
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
        case .labelsOnly:     return false
        case .activeIcons:    return state.isFocused
        case .clampAndExpand: return isHovered || state.isFocused
        }
    }

    private var hoverAnimation: Animation {
        mode == .clampAndExpand ? Theme.springLabelHover : .easeInOut(duration: 0.15)
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
                switch mode {
                case .labelsOnly:
                    EmptyView()
                case .activeIcons:
                    if showsIcons {
                        icons(transition: .opacity)
                    }
                case .clampAndExpand:
                    if showsIcons, !state.windows.isEmpty {
                        HStack(spacing: 4) {
                            icons(transition: .scale(scale: 0.4).combined(with: .opacity))
                        }
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
                .interactiveRegion()
                .onHover { isHovered = $0 }
                .onTapGesture {
                    AeroSpaceClient.shared.focusWindow(window.windowID)
                }
        }
    }
}
