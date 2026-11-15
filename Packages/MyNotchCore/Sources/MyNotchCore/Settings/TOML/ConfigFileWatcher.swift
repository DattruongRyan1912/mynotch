import Foundation

/// File system monitor observing `config.toml` and its parent directory.
/// Gracefully handles both direct overwrites and atomic replace/rename saves from Neovim, Zed, and VS Code.
nonisolated final class ConfigFileWatcher: @unchecked Sendable {
    private let fileURL: URL
    private let directoryURL: URL
    private let queue: DispatchQueue
    private let onChange: @Sendable () -> Void

    private let lock = NSLock()
    private var isCancelled = false
    private var fileSource: DispatchSourceFileSystemObject?
    private var dirSource: DispatchSourceFileSystemObject?
    private var watchedInode: UInt64 = 0

    public init(fileURL: URL, onChange: @escaping @Sendable () -> Void) {
        self.fileURL = fileURL
        self.directoryURL = fileURL.deletingLastPathComponent()
        self.queue = DispatchQueue(label: "io.lucasvu.mynotch.config-watcher", qos: .utility)
        self.onChange = onChange

        startWatching()
    }

    deinit {
        cancel()
    }

    public func cancel() {
        lock.lock()
        defer { lock.unlock() }
        guard !isCancelled else { return }
        isCancelled = true

        fileSource?.cancel()
        fileSource = nil

        dirSource?.cancel()
        dirSource = nil
    }

    private func startWatching() {
        lock.lock()
        defer { lock.unlock() }
        guard !isCancelled else { return }

        // 1. Watch directory for file creation, rename, replacement
        let dirPath = directoryURL.path
        let dirFD = open(dirPath, O_EVTONLY)
        if dirFD >= 0 {
            let dSource = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: dirFD,
                eventMask: [.write, .rename, .delete, .extend],
                queue: queue
            )
            dSource.setEventHandler { [weak self] in
                self?.handleDirectoryEvent()
            }
            dSource.setCancelHandler {
                close(dirFD)
            }
            dSource.resume()
            self.dirSource = dSource
        }

        // 2. Watch file directly if it exists
        attachFileSourceLocked()
    }

    private func attachFileSourceLocked() {
        fileSource?.cancel()
        fileSource = nil
        watchedInode = 0

        let filePath = fileURL.path
        let fileFD = open(filePath, O_EVTONLY)
        guard fileFD >= 0 else { return }

        var statBuf = stat()
        if fstat(fileFD, &statBuf) == 0 {
            watchedInode = UInt64(statBuf.st_ino)
        }

        let fSource = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileFD,
            eventMask: [.write, .extend, .attrib, .rename, .delete, .revoke],
            queue: queue
        )
        fSource.setEventHandler { [weak self] in
            self?.handleFileEvent()
        }
        fSource.setCancelHandler {
            close(fileFD)
        }
        fSource.resume()
        self.fileSource = fSource
    }

    private func handleFileEvent() {
        lock.lock()
        let source = fileSource
        lock.unlock()

        guard let source = source else { return }
        let flags = source.data

        if flags.contains(.delete) || flags.contains(.rename) || flags.contains(.revoke) {
            // Inode was unlinked or replaced (atomic save). Re-attach file source.
            lock.lock()
            attachFileSourceLocked()
            lock.unlock()
            onChange()
        } else if flags.contains(.write) || flags.contains(.extend) || flags.contains(.attrib) {
            onChange()
        }
    }

    private func handleDirectoryEvent() {
        lock.lock()
        var statBuf = stat()
        let exists = stat(fileURL.path, &statBuf) == 0
        let currentInode = exists ? UInt64(statBuf.st_ino) : 0
        let needsReattach = (currentInode != 0 && currentInode != watchedInode) || (fileSource == nil && exists)

        if needsReattach {
            attachFileSourceLocked()
            lock.unlock()
            onChange()
        } else {
            lock.unlock()
        }
    }
}
