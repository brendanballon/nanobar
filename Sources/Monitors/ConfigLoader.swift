import Foundation

// MARK: - ConfigLoader

@MainActor
public final class ConfigLoader: ObservableObject {
    public static let shared = ConfigLoader()

    @Published public private(set) var config = NanoConfig.defaults

    /// Set by AppDelegate. Called on the main actor after every reload.
    public var onReload: (@MainActor () -> Void)?

    private let configURL: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/nanobar/config")
    }()

    private var dirWatchSource:  DispatchSourceFileSystemObject?
    private var fileWatchSource: DispatchSourceFileSystemObject?
    private var lastRaw: String?

    private init() {}

    // MARK: - Public interface

    /// Write the commented reference config if the file is missing, then load
    /// and start watching for changes. A missing or unreadable file is not an
    /// error — the app runs on defaults.
    public func loadOrCreate() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: configURL.path) {
            let dir = configURL.deletingLastPathComponent()
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            try? NanoConfig.referenceConfig.write(to: configURL, atomically: true, encoding: .utf8)
        }
        reload()
        watch()
    }

    /// Re-read the config file. Missing file yields defaults.
    public func reload() {
        let raw = (try? String(contentsOf: configURL, encoding: .utf8)) ?? ""
        // Watchers fire for unrelated directory writes and both halves of an atomic
        // save — skip the parse + republish when the file content hasn't changed.
        guard raw != lastRaw else { return }
        lastRaw = raw
        config = NanoConfig(ConfigParser.parse(raw))
        onReload?()
    }

    // MARK: - File watching

    private func watch() {
        // Watch the directory for write events (catches atomic saves: temp-file + rename).
        let dirFd = open(configURL.deletingLastPathComponent().path, O_EVTONLY)
        if dirFd >= 0 {
            let src = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: dirFd, eventMask: .write, queue: .main)
            src.setEventHandler { [weak self] in
                guard let self else { return }
                self.reload()
            }
            src.setCancelHandler { close(dirFd) }
            src.resume()
            dirWatchSource = src
        }

        // Also watch the file directly for write events (catches in-place saves).
        // After an atomic rename the fd becomes stale, but the dir watcher still fires
        // for subsequent atomic saves, so this only needs to cover in-place writes.
        watchFile()
    }

    private func watchFile() {
        let fileFd = open(configURL.path, O_EVTONLY)
        guard fileFd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileFd, eventMask: [.write, .rename, .delete], queue: .main)
        src.setEventHandler { [weak self, weak src] in
            guard let self else { return }
            self.reload()
            // File was replaced atomically (rename/delete) — re-attach to the new inode.
            if let data = src?.data, !data.intersection([.rename, .delete]).isEmpty {
                self.fileWatchSource?.cancel()
                self.fileWatchSource = nil
                self.watchFile()
            }
        }
        src.setCancelHandler { close(fileFd) }
        src.resume()
        fileWatchSource = src
    }
}
