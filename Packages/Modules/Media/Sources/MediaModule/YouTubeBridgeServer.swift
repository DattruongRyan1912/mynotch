import Foundation
import Synchronization
import YouTubeBridgeKit

/// Listens on a Unix stream socket for what the `mynotch-youtube-host` helper sends: frames of a 4-byte big-endian
/// length and a JSON message. Frames are read on a private queue and checked there; the main actor gets only
/// messages that passed. The socket is the user's alone (mode 0600 in a 0700 folder, and a peer of another user is
/// refused), and anything that is not a valid protocol message is ignored.
final class YouTubeBridgeServer {
    enum StartError: Error, Equatable {
        /// The socket path does not fit a `sockaddr_un`.
        case pathTooLong
        case socket(errno: Int32)
        /// The folder belongs to someone else, as when another user made `/tmp/mynotch-<uid>` first.
        case directoryNotOwned
    }

    /// Chrome starts one host per profile that runs the extension; more than a few is not Chrome.
    nonisolated static let maxConnections = 8
    private static let backlog: Int32 = 16

    /// Everything one `start` opened. The handlers that run on the private queue and the callbacks queued for the
    /// main thread share it, so closing it is what makes late ones harmless.
    private nonisolated final class Session: Sendable {
        private struct State {
            var isOpen = true
            var connections: [Int32: DispatchSourceRead] = [:]
            var listener: DispatchSourceRead?
        }

        private let state = Mutex(State())

        var isOpen: Bool { state.withLock { $0.isOpen } }
        var connectionCount: Int { state.withLock { $0.connections.count } }

        func setListener(_ source: DispatchSourceRead) { state.withLock { $0.listener = source } }

        /// Takes the source in, or cancels it when the session is over or has all the connections it allows.
        func add(_ source: DispatchSourceRead, for fd: Int32) {
            let accepted = state.withLock { state -> Bool in
                guard state.isOpen, state.connections.count < YouTubeBridgeServer.maxConnections else { return false }
                state.connections[fd] = source
                return true
            }
            // A source must be resumed before it can go away, cancelled or not.
            if !accepted { source.cancel() }
            source.resume()
        }

        func remove(_ fd: Int32) {
            state.withLock { _ = $0.connections.removeValue(forKey: fd)?.cancel() }
        }

        func close() {
            let sources = state.withLock { state -> [DispatchSourceRead] in
                state.isOpen = false
                defer {
                    state.connections = [:]
                    state.listener = nil
                }
                return Array(state.connections.values) + [state.listener].compactMap { $0 }
            }
            for source in sources { source.cancel() }
        }
    }

    /// One client's bytes, read only on the private queue.
    private nonisolated final class Reader: @unchecked Sendable {
        var decoder = AppFrameDecoder()
        var buffer = [UInt8](repeating: 0, count: 64 << 10)
    }

    let socketPath: String
    /// Runs on the main actor, in the order the frames were read.
    private let onMessage: @MainActor @Sendable (YouTubeMessage) -> Void
    private var session: Session?
    private let queue = DispatchQueue(label: "io.lucasvu.mynotch.youtube-bridge")

    init(socketPath: String, onMessage: @escaping @MainActor @Sendable (YouTubeMessage) -> Void) {
        self.socketPath = socketPath
        self.onMessage = onMessage
    }

    /// Replaces a socket file a crashed run left behind. The folder is made private to the user.
    func start() throws {
        stop()
        guard let address = UnixSocketAddress(path: socketPath) else { throw StartError.pathTooLong }
        try preparePrivateDirectory()
        unlink(socketPath)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw StartError.socket(errno: errno) }
        var target = address.value
        let bound = withUnsafePointer(to: &target) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0, chmod(socketPath, 0o600) == 0, listen(fd, Self.backlog) == 0, fcntl(fd, F_SETFL, O_NONBLOCK) == 0 else {
            let code = errno
            close(fd)
            unlink(socketPath)
            throw StartError.socket(errno: code)
        }
        let session = Session()
        let onMessage = onMessage
        let queue = queue
        // `@Sendable` keeps the handlers off the main actor, which is the default here: they run on the private queue.
        let accept: @Sendable () -> Void = { Self.accept(fd, into: session, queue: queue, onMessage: onMessage) }
        let listener = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        listener.setEventHandler(handler: accept)
        let cancelHandler: @Sendable () -> Void = { close(fd) }
        listener.setCancelHandler(handler: cancelHandler)
        session.setListener(listener)
        listener.resume()
        self.session = session
    }

    /// Closes the listener and every connection, and removes the socket file. Messages already queued for the main
    /// thread are dropped.
    func stop() {
        guard let session else { return }
        session.close()
        self.session = nil
        unlink(socketPath)
    }

    /// The clients connected right now (for tests).
    var connectionCount: Int { session?.connectionCount ?? 0 }

    isolated deinit {
        stop()
    }

    /// The folder is the user's own and closed to everyone else. One that exists is checked before anything is
    /// created or changed in it: `/tmp/mynotch-<uid>` is in a folder every user can write to, so someone else may
    /// have made it first.
    private func preparePrivateDirectory() throws {
        let directory = URL(filePath: socketPath).deletingLastPathComponent()
        var info = stat()
        if stat(directory.path, &info) == 0, info.st_uid != geteuid() { throw StartError.directoryNotOwned }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // `attributes` of `createDirectory` apply only to a directory it creates.
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    }

    // MARK: private queue

    /// Takes in every connection waiting.
    private nonisolated static func accept(
        _ listener: Int32, into session: Session, queue: DispatchQueue, onMessage: @escaping @MainActor @Sendable (YouTubeMessage) -> Void
    ) {
        while true {
            let fd = Foundation.accept(listener, nil, nil)
            guard fd >= 0 else { return }
            var uid: uid_t = 0
            var gid: gid_t = 0
            // The socket's mode already keeps others out; this also refuses a peer that got a descriptor some other way.
            guard fcntl(fd, F_SETFL, O_NONBLOCK) == 0, getpeereid(fd, &uid, &gid) == 0, uid == geteuid() else {
                close(fd)
                continue
            }
            var noSigPipe: Int32 = 1
            _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
            let reader = Reader()
            let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
            let handler: @Sendable () -> Void = {
                if !drain(fd, reader: reader, onMessage: onMessage, session: session) { session.remove(fd) }
            }
            source.setEventHandler(handler: handler)
            let cancelHandler: @Sendable () -> Void = { close(fd) }
            source.setCancelHandler(handler: cancelHandler)
            session.add(source, for: fd)
        }
    }

    /// Reads what a client has sent and hands on its messages; false when the connection is over, because the client
    /// closed it or broke the framing.
    private nonisolated static func drain(
        _ fd: Int32, reader: Reader, onMessage: @escaping @MainActor @Sendable (YouTubeMessage) -> Void, session: Session
    ) -> Bool {
        while true {
            let count = recv(fd, &reader.buffer, reader.buffer.count, 0)
            if count == 0 { return false }
            if count < 0 { return errno == EAGAIN || errno == EINTR }
            reader.decoder.append(Data(reader.buffer[0..<count]))
            frames: while true {
                switch reader.decoder.next() {
                case .needMore:
                    break frames
                case .tooLarge:
                    return false
                case .frame(let frame):
                    guard let message = YouTubeMessage.decode(frame) else { continue }
                    DispatchQueue.main.async { MainActor.assumeIsolated { if session.isOpen { onMessage(message) } } }
                }
            }
        }
    }
}
