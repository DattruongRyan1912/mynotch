import Foundation

/// A folder under `/tmp` for a Unix socket, short enough that a socket path fits (see `ScratchFolders.reserveShort`). It is
/// removed with the test, and at process exit whatever the test did, so one that fails or forgets leaves nothing behind.
public nonisolated final class SocketFolder {
    public let path: String
    public let socketName: String
    public var socketPath: String { path + "/" + socketName }
    private var listener: Int32 = -1

    /// A short path of its own with nothing at it: for a test that makes what is there itself, or needs nothing.
    public static func reservedPath() -> String { ScratchFolders.shared.reserveShort().path }

    /// - Parameters:
    ///   - socketName: the file name `socketPath` and `bindSocket()` use.
    ///   - mode: the folder's mode; the folder the app makes is 0700.
    public init(socketName: String = "app.sock", mode: mode_t = 0o700) throws {
        path = Self.reservedPath()
        self.socketName = socketName
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true, attributes: [.posixPermissions: Int(mode)])
        chmod(path, mode)
    }

    /// A listening stream socket file in it, at `socketPath` or at `name`.
    public func bindSocket(named name: String? = nil) throws {
        listener = socket(AF_UNIX, SOCK_STREAM, 0)
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: Array((path + "/" + (name ?? socketName)).utf8) + [0]) }
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(listener, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0, listen(listener, 1) == 0 else { throw CocoaError(.fileWriteUnknown) }
    }

    /// Closes the socket and leaves its file, as a crashed app does.
    public func stopListening() {
        if listener >= 0 { close(listener) }
        listener = -1
    }

    deinit {
        if listener >= 0 { close(listener) }
        // A test that made the folder read-only for a moment must not leave one nobody can delete.
        chmod(path, 0o700)
        try? FileManager.default.removeItem(atPath: path)
    }
}
