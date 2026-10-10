import AppKit
import Monitors
import SwiftUI
import UniformTypeIdentifiers

// MARK: - DownloadItem

struct DownloadItem: Identifiable, Equatable, Sendable {
    let url: URL
    let date: Date
    let size: Int64?
    let isDirectory: Bool

    var id: URL { url }
    var name: String { url.lastPathComponent }
}

// MARK: - DownloadsState

/// Lists ~/Downloads, newest first. Rescans on demand and whenever the
/// directory changes (vnode watch), so the popover is current when opened.
@MainActor
final class DownloadsState: ObservableObject {
    static let shared = DownloadsState()

    nonisolated static let maxItems = 40
    /// Partial files browsers write while a download is still running.
    nonisolated private static let partialExtensions: Set<String> = ["crdownload", "download", "part", "partial", "opdownload"]

    @Published private(set) var items: [DownloadItem] = []
    @Published private(set) var additions = 0

    private var knownURLs: Set<URL>?

    private let directory = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads")
    private var source: DispatchSourceFileSystemObject?
    private var scanTask: Task<Void, Never>?

    var folderURL: URL { directory }

    private init() {
        refresh()
        startWatching()
    }

    func refresh() {
        scanTask?.cancel()
        let dir = directory
        scanTask = Task {
            let scanned = await Task.detached(priority: .utility) { Self.scan(dir) }.value
            guard !Task.isCancelled else { return }
            let urls = Set(scanned.map(\.url))
            if let knownURLs, !urls.isSubset(of: knownURLs) { additions += 1 }
            knownURLs = urls
            let visible = Array(scanned.prefix(Self.maxItems))
            if visible != items { items = visible }
        }
    }

    /// Moves (or copies) dropped files into Downloads, renaming on name collision.
    func transferIn(_ urls: [URL], copy: Bool) {
        let dir = directory
        Task.detached(priority: .userInitiated) {
            let fm = FileManager.default
            for src in urls {
                // A move within Downloads is a no-op; a copy there still makes a duplicate.
                if !copy, src.deletingLastPathComponent().standardizedFileURL == dir.standardizedFileURL { continue }
                var dest = dir.appendingPathComponent(src.lastPathComponent)
                var n = 2
                while fm.fileExists(atPath: dest.path) {
                    let base = src.deletingPathExtension().lastPathComponent
                    let ext = src.pathExtension
                    dest = dir.appendingPathComponent(ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)")
                    n += 1
                }
                if copy { try? fm.copyItem(at: src, to: dest) } else { try? fm.moveItem(at: src, to: dest) }
            }
            await MainActor.run { DownloadsState.shared.refresh() }
        }
    }

    private func startWatching() {
        let fd = open(directory.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
        src.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.refresh() }
        }
        src.setCancelHandler { close(fd) }
        src.resume()
        source = src
    }

    nonisolated private static func scan(_ dir: URL) -> [DownloadItem] {
        let keys: [URLResourceKey] = [
            .addedToDirectoryDateKey, .contentModificationDateKey, .fileSizeKey, .isDirectoryKey,
        ]
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]
        ) else { return [] }
        let items: [DownloadItem] = urls.compactMap { url in
            guard !partialExtensions.contains(url.pathExtension.lowercased()),
                  let values = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
            let date = values.addedToDirectoryDate ?? values.contentModificationDate ?? .distantPast
            return DownloadItem(url: url, date: date, size: values.fileSize.map(Int64.init),
                                isDirectory: values.isDirectory ?? false)
        }
        return items.sorted { $0.date > $1.date }
    }
}

// MARK: - Pill

/// The pill itself morphs into the list: a hidden copy of the collapsed pill
/// holds its slot in the bar's layout while the visible container animates its
/// frame (and the glass behind it) out into the free space of the panel. The
/// list is laid out once at its final size and merely revealed by the clip, so
/// no AppKit layout happens per animation frame.
public struct DownloadsPillView: View {
    @ObservedObject private var downloads = DownloadsState.shared
    @Environment(\.barPosition) private var barPosition
    @Environment(\.pillStyle) private var pillStyle
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var downloadImpact = 0
    @State private var hovered = false
    @State private var showing = false
    @State private var dropTargeted = false
    @State private var collapsedWidth: CGFloat = 0
    @State private var monitors = ClickMonitors()

    private static let defaultWidth: CGFloat = 360
    private static let minSize = CGSize(width: 300, height: 160)
    private static let resizeHandleWidth: CGFloat = 8
    private static let morphOpen: Animation = .spring(duration: 0.45, bounce: 0.15)
    // No bounce on close: an overshoot would dip below the pill's own height.
    private static let morphClose: Animation = .spring(duration: 0.35, bounce: 0)

    /// User-chosen size (0 = automatic). Persisted when a drag ends.
    @State private var savedWidth: Double = UserDefaults.standard.double(forKey: "downloads.width")
    @State private var savedHeight: Double = UserDefaults.standard.double(forKey: "downloads.height")
    @State private var dragStart: CGSize?

    public init() {}

    private var growsUpward: Bool { barPosition != .top }
    private var growsRightward: Bool { barPosition == .left }

    private var expansionAlignment: Alignment {
        if barPosition == .top { return .topTrailing }
        return growsRightward ? .bottomLeading : .bottomTrailing
    }

    private var autoHeight: CGFloat {
        let rows = min(CGFloat(max(downloads.items.count, 2)) * DownloadsTable.rowHeight,
                       Theme.downloadsListMaxHeight)
        return pillStyle.height + 1 + rows
    }

    private func clamped(_ size: CGSize) -> CGSize {
        CGSize(width: min(max(size.width, Self.minSize.width), Theme.downloadsListMaxWidth),
               height: min(max(size.height, Self.minSize.height), pillStyle.height + 1 + Theme.downloadsListMaxHeight))
    }

    private var expandedSize: CGSize {
        clamped(CGSize(width: savedWidth > 0 ? savedWidth : Self.defaultWidth,
                       height: savedHeight > 0 ? savedHeight : autoHeight))
    }

    private func header(expanded: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.down.circle")
                .accessibilityLabel("Downloads")
                .accessibilityHidden(expanded || barPosition.isHorizontal)
                .symbolEffect(.bounce.down, options: .nonRepeating, value: downloadImpact)
                .scaleEffect(dropTargeted ? 1.5 : 1)
                .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.55), value: dropTargeted)
            if expanded || barPosition.isHorizontal { Text("Downloads") }
            if expanded {
                Spacer(minLength: 0)
                Button {
                    NSWorkspace.shared.open(downloads.folderURL)
                    toggle(false)
                } label: {
                    HStack(spacing: 4) {
                        Text("Show in Finder")
                        Image(systemName: "arrow.up.forward.app.fill")
                            .accessibilityHidden(true)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color(nsColor: .controlAccentColor))
                .transition(.opacity)
            }
        }
        .font(.system(size: pillStyle.fontSize, weight: .semibold))
        .foregroundStyle(Theme.grey)
        .lineLimit(1)
        .padding(.horizontal, 10)
        .frame(minWidth: pillStyle.minWidth)
        .frame(height: pillStyle.height)
        .contentShape(Rectangle())
        .onTapGesture { toggle(!showing) }
    }

    public var body: some View {
        header(expanded: false)
            .fixedSize()
            .hidden()
            .accessibilityHidden(true)
            .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { collapsedWidth = $0 }
            .overlay(alignment: expansionAlignment) { container }
            .onChange(of: downloads.additions) { _, _ in
                if !reduceMotion { downloadImpact += 1 }
            }
            .onDisappear { stopOutsideClickMonitoring() }
    }

    private var container: some View {
        let size = expandedSize
        return VStack(spacing: 0) {
            header(expanded: showing)
            if showing {
                Divider()
                // Final size from the first frame; the container's clip reveals it.
                list.frame(width: size.width, height: size.height - pillStyle.height - 1)
            }
        }
        .frame(width: showing ? size.width : (collapsedWidth > 0 ? collapsedWidth : nil),
               height: showing ? size.height : pillStyle.height,
               alignment: .top)
        .clipShape(RoundedRectangle(cornerRadius: pillStyle.cornerRadius, style: .continuous))
        .overlay { if showing { resizeHandles } }
        .nanoPill(focused: showing || dropTargeted, hovered: hovered && !showing, intrinsic: true)
        .onDrop(of: [.fileURL], delegate: DownloadsDropDelegate(targeted: $dropTargeted))
        .onHover { hovering in
            withAnimation(reduceMotion ? nil : Theme.easeHover) { hovered = hovering }
        }
        .onChange(of: showing) { _, isShowing in
            if isShowing { startOutsideClickMonitoring() } else { stopOutsideClickMonitoring() }
        }
    }

    // MARK: Resizing

    // Resize away from the bar and the anchored edge.
    private enum Handle { case side, far, corner }

    private var resizeHandles: some View {
        ZStack {
            handle(.side)
            handle(.far)
            handle(.corner)
        }
    }

    private func handle(_ kind: Handle) -> some View {
        let farTop = growsUpward
        let corner: Alignment = farTop
            ? (growsRightward ? .topTrailing : .topLeading)
            : (growsRightward ? .bottomTrailing : .bottomLeading)
        let cornerPosition: FrameResizePosition = farTop
            ? (growsRightward ? .topTrailing : .topLeading)
            : (growsRightward ? .bottomTrailing : .bottomLeading)
        let alignment: Alignment = kind == .side ? (growsRightward ? .trailing : .leading)
            : kind == .far ? (farTop ? .top : .bottom)
            : corner
        let position: FrameResizePosition = kind == .side ? (growsRightward ? .trailing : .leading)
            : kind == .far ? (farTop ? .top : .bottom)
            : cornerPosition
        return Color.clear
            .frame(width: kind == .far ? nil : (kind == .corner ? 16 : Self.resizeHandleWidth),
                   height: kind == .side ? nil : (kind == .corner ? 16 : Self.resizeHandleWidth))
            .contentShape(Rectangle())
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
            .pointerStyle(.frameResize(position: position))
            .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { drag in
                    let start = dragStart ?? expandedSize
                    dragStart = start
                    var size = start
                    if kind != .far { size.width = start.width + (growsRightward ? drag.translation.width : -drag.translation.width) }
                    if kind != .side {
                        size.height = start.height + (farTop ? -drag.translation.height : drag.translation.height)
                    }
                    size = clamped(size)
                    savedWidth = size.width
                    savedHeight = size.height
                }
                .onEnded { _ in
                    dragStart = nil
                    UserDefaults.standard.set(savedWidth, forKey: "downloads.width")
                    UserDefaults.standard.set(savedHeight, forKey: "downloads.height")
                })
    }

    @ViewBuilder private var list: some View {
        if downloads.items.isEmpty {
            Text("No downloads")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            DownloadsTable(items: downloads.items, dismiss: { toggle(false) })
        }
    }

    private func toggle(_ open: Bool) {
        guard open != showing else { return }
        if open { downloads.refresh() }
        withAnimation(reduceMotion ? nil : (open ? Self.morphOpen : Self.morphClose)) { showing = open }
    }

    // The bar is a non-activating panel, so nothing dismisses the list when the
    // user clicks elsewhere. Watch for those clicks ourselves.
    private func startOutsideClickMonitoring() {
        stopOutsideClickMonitoring()
        let events: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        // Clicks in other apps (or on the desktop).
        monitors.global = NSEvent.addGlobalMonitorForEvents(matching: events) { _ in
            DispatchQueue.main.async { toggle(false) }
        }
        // Escape closes it too.
        monitors.local = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { toggle(false); return nil }
            return event
        }
    }

    private func stopOutsideClickMonitoring() {
        if let g = monitors.global { NSEvent.removeMonitor(g) }
        if let l = monitors.local { NSEvent.removeMonitor(l) }
        monitors.global = nil
        monitors.local = nil
    }
}

private final class ClickMonitors {
    var global: Any?
    var local: Any?
    deinit {
        if let global { NSEvent.removeMonitor(global) }
        if let local { NSEvent.removeMonitor(local) }
    }
}

// MARK: - Drop

/// Drops default to move; holding Option (the standard macOS copy modifier) copies.
private struct DownloadsDropDelegate: DropDelegate {
    @Binding var targeted: Bool

    private static var wantsCopy: Bool { NSEvent.modifierFlags.contains(.option) }

    func validateDrop(info: DropInfo) -> Bool { info.hasItemsConforming(to: [.fileURL]) }
    func dropEntered(info: DropInfo) { targeted = true }
    func dropExited(info: DropInfo) { targeted = false }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: Self.wantsCopy ? .copy : .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        targeted = false
        let copy = Self.wantsCopy
        for provider in info.itemProviders(for: [.fileURL]) {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in DownloadsState.shared.transferIn([url], copy: copy) }
            }
        }
        return true
    }
}

// MARK: - Native table

/// A single-column NSTableView, so selection is the system's: Finder-style
/// highlight that merges across consecutive rows, ⌘/⇧ multi-select, arrow keys,
/// ⌘A, double-click to open, and multi-row drag. The table is the drag source,
/// so it can offer both copy and move (the destination picks; ⌥ forces copy).
private struct DownloadsTable: NSViewRepresentable {
    static let rowHeight: CGFloat = 44

    let items: [DownloadItem]
    let dismiss: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let coordinator = context.coordinator
        let table = DownloadsTableView()
        let column = NSTableColumn(identifier: .init("download"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.autoresizingMask = [.width]
        table.style = .inset
        table.headerView = nil
        table.rowHeight = Self.rowHeight
        table.allowsMultipleSelection = true
        table.allowsEmptySelection = true
        table.backgroundColor = .clear
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.setDraggingSourceOperationMask([.copy, .move], forLocal: false)
        table.setDraggingSourceOperationMask([.copy, .move], forLocal: true)
        table.dataSource = coordinator
        table.delegate = coordinator
        table.target = coordinator
        table.doubleAction = #selector(Coordinator.openTargets)
        let menu = NSMenu()
        menu.delegate = coordinator
        table.menu = menu
        coordinator.table = table
        coordinator.dismiss = dismiss

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        coordinator.items = items
        // Load the initial rows before updateNSView skips unchanged items.
        table.reloadData()
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.dismiss = dismiss
        guard coordinator.items != items, let table = coordinator.table else { return }
        // Keep the selection across rescans by identity, not row index.
        let selected = Set(table.selectedRowIndexes.compactMap { coordinator.items.indices.contains($0) ? coordinator.items[$0].url : nil })
        coordinator.items = items
        table.reloadData()
        table.selectRowIndexes(IndexSet(items.indices.filter { selected.contains(items[$0].url) }), byExtendingSelection: false)
    }

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate {
        var items: [DownloadItem] = []
        var dismiss: () -> Void = {}
        weak var table: NSTableView?

        func numberOfRows(in tableView: NSTableView) -> Int { items.count }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            let id = NSUserInterfaceItemIdentifier("downloadCell")
            let cell = tableView.makeView(withIdentifier: id, owner: nil) as? DownloadCellView ?? {
                let c = DownloadCellView()
                c.identifier = id
                return c
            }()
            cell.configure(items[row])
            return cell
        }

        func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
            items[row].url as NSURL
        }

        func tableView(_ tableView: NSTableView, draggingSession session: NSDraggingSession,
                       endedAt screenPoint: NSPoint, operation: NSDragOperation) {
            DownloadsState.shared.refresh()
        }

        /// The row(s) an action applies to: the selection if the clicked row is
        /// part of it, otherwise just the clicked row (Finder behavior).
        private func targetURLs() -> [URL] {
            guard let table else { return [] }
            let selected = table.selectedRowIndexes
            let rows = table.clickedRow >= 0 && !selected.contains(table.clickedRow)
                ? IndexSet(integer: table.clickedRow) : selected
            return rows.compactMap { items.indices.contains($0) ? items[$0].url : nil }
        }

        @objc func openTargets() {
            let urls = targetURLs()
            guard !urls.isEmpty else { return }
            urls.forEach { NSWorkspace.shared.open($0) }
            dismiss()
        }

        func menuNeedsUpdate(_ menu: NSMenu) {
            menu.removeAllItems()
            let urls = targetURLs()
            guard !urls.isEmpty, (table?.clickedRow ?? -1) >= 0 else { return }
            menu.addItem(ClosureMenuItem("Show in Finder") { [weak self] in
                NSWorkspace.shared.activateFileViewerSelecting(urls)
                self?.dismiss()
            })
            menu.addItem(ClosureMenuItem("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(urls.map(\.path).joined(separator: "\n"), forType: .string)
            })
        }
    }
}

private final class DownloadsTableView: NSTableView {
    override var needsPanelToBecomeKey: Bool { true }

    override func mouseDown(with event: NSEvent) {
        // Give the native table keyboard focus in the nonactivating panel.
        window?.makeKey()
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }
}

private final class DownloadCellView: NSTableCellView {
    private let icon = NSImageView()
    private let name = NSTextField(labelWithString: "")
    private let detail = NSTextField(labelWithString: "")

    /// Icons by file type: asking the workspace per file path is slow and
    /// would stall opening the list.
    @MainActor private static var iconCache: [String: NSImage] = [:]

    @MainActor private static func icon(for item: DownloadItem) -> NSImage {
        let ext = item.url.pathExtension.lowercased()
        // Folders and bundles have per-item icons (apps especially).
        if item.isDirectory || ext == "app" { return NSWorkspace.shared.icon(forFile: item.url.path) }
        if let cached = iconCache[ext] { return cached }
        let type = UTType(filenameExtension: ext) ?? .data
        let image = NSWorkspace.shared.icon(for: type)
        iconCache[ext] = image
        return image
    }

    init() {
        super.init(frame: .zero)
        name.lineBreakMode = .byTruncatingMiddle
        name.usesSingleLineMode = true
        name.alignment = .left
        name.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        detail.lineBreakMode = .byTruncatingTail
        detail.usesSingleLineMode = true
        detail.alignment = .left
        detail.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        detail.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        detail.textColor = .secondaryLabelColor
        let text = NSStackView(views: [name, detail])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 1
        let row = NSStackView(views: [icon, text])
        row.distribution = .fill
        row.spacing = 10
        row.alignment = .centerY
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        imageView = icon
        textField = name
        NSLayoutConstraint.activate([
            name.widthAnchor.constraint(equalTo: text.widthAnchor),
            detail.widthAnchor.constraint(equalTo: text.widthAnchor),
            icon.widthAnchor.constraint(equalToConstant: 32),
            icon.heightAnchor.constraint(equalToConstant: 32),
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    func configure(_ item: DownloadItem) {
        icon.image = Self.icon(for: item)
        name.stringValue = item.name
        let age = item.date.formatted(.relative(presentation: .named))
        if !item.isDirectory, let size = item.size {
            detail.stringValue = "\(age) · \(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))"
        } else {
            detail.stringValue = age
        }
    }
}

private final class ClosureMenuItem: NSMenuItem {
    private let action_: () -> Void

    init(_ title: String, action: @escaping () -> Void) {
        action_ = action
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }

    @available(*, unavailable) required init(coder: NSCoder) { fatalError() }

    @objc private func fire() { action_() }
}
