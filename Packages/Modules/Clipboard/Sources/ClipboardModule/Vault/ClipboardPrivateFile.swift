import Foundation

/// Files that only the user may read, from the first byte: created with mode 0600 and never replaced, so no moment leaves one open.
nonisolated enum ClipboardPrivateFile {
    /// Creates `url` (which must not exist) with mode 0600 and writes `data`; with `flush` the bytes are on disk before this returns.
    static func write(_ data: Data, to url: URL, flush: Bool = false) throws {
        let descriptor = open(url.path(percentEncoded: false), O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw ClipboardVaultError.cannotWrite(String(cString: strerror(errno))) }
        do {
            try data.withUnsafeBytes { buffer in
                var offset = 0
                while offset < buffer.count {
                    let written = Darwin.write(descriptor, buffer.baseAddress! + offset, buffer.count - offset)
                    if written < 0 {
                        if errno == EINTR { continue }
                        throw ClipboardVaultError.cannotWrite(String(cString: strerror(errno)))
                    }
                    offset += written
                }
            }
            if flush, fsync(descriptor) != 0 { throw ClipboardVaultError.cannotWrite(String(cString: strerror(errno))) }
            close(descriptor)
        } catch {
            close(descriptor)
            unlink(url.path(percentEncoded: false))
            throw error
        }
    }

    /// A folder closed to everyone but the user, made if it is missing and closed if it was open.
    static func makeFolder(_ url: URL) throws {
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path(percentEncoded: false))
        } catch {
            throw ClipboardVaultError.cannotWrite(error.localizedDescription)
        }
    }
}

/// The files a drag of an open board's picture needs: a drop target wants a file, so one is made when it asks for it (not before),
/// in a folder of its own that only the user can open, and removed when the drag has ended, when the board closes, when the module
/// stops and at the next start. Nothing else of an open board is ever a file.
nonisolated final class ClipboardDragFiles: @unchecked Sendable {
    let directory: URL
    private let lock = NSLock()

    init(directory: URL) {
        self.directory = directory
    }

    /// A new file called `name` in a new folder, so two drags never collide and the target sees a readable name.
    func makeFile(data: Data, name: String) throws -> URL {
        lock.lock()
        defer { lock.unlock() }
        try ClipboardPrivateFile.makeFolder(directory)
        let folder = directory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try ClipboardPrivateFile.makeFolder(folder)
        let file = folder.appending(path: name, directoryHint: .notDirectory)
        try ClipboardPrivateFile.write(data, to: file)
        return file
    }

    /// Removes everything in the folder.
    func removeAll() {
        lock.lock()
        defer { lock.unlock() }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false))) ?? []
        for name in names { try? FileManager.default.removeItem(at: directory.appending(path: name)) }
    }
}
