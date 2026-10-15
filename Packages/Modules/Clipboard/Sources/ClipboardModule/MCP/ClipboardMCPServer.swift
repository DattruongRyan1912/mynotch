import ClipboardMCPKit
import Foundation
import Synchronization

/// A counter shared with the closures that run on a server's private queues. Work those queues hand to the main thread cannot
/// be recalled when the server stops; `stop` advances this instead, and the work that finds another value is dropped.
nonisolated final class ServerGeneration: Sendable {
    private let value = Mutex(0)
    var current: Int { value.withLock { $0 } }
    func advance() { value.withLock { $0 += 1 } }
}

/// The folder the socket lives in: the user's own and closed to everyone else.
enum PrivateDirectory {
    /// One that exists is checked before anything is made or changed in it: `/tmp/mynotch-<uid>` is in a folder every user can
    /// write to, so someone else may have made it first, or made it a link.
    static func prepare(_ directory: URL, user: uid_t) throws {
        var info = stat()
        if lstat(directory.path, &info) == 0, info.st_mode & S_IFMT != S_IFDIR || info.st_uid != user {
            throw ClipboardMCPServer.StartError.directoryNotOwned
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // `attributes` of `createDirectory` apply only to a directory it creates.
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    }
}

/// Listens on a Unix stream socket for the `mynotch-clipboard-mcp` helper. Each connection carries one request line and gets
/// one answer line; the answer is worked out on the main actor, where the history is, and the connection is closed.
///
/// The socket is `0600` in a folder that only the user can open, and a peer that is not the user is dropped.
final class ClipboardMCPServer {
    /// Gets the request line, without its newline, on the main actor.
    typealias Handler = @MainActor @Sendable (Data) -> ClipboardMCPWireReply

    enum StartError: Error, Equatable {
        case pathTooLong
        case directoryNotOwned
        case socket(errno: Int32)
    }

    /// What the private queues work with. It holds no reference to the server, so the server can go while a connection ends.
    private nonisolated final class Acceptor: Sendable {
        private struct Counts {
            var connections = 0
            var requestsRead = 0
        }

        private let listener: Int32
        private let workQueue = DispatchQueue(label: "io.lucasvu.mynotch.clipboard-mcp.work", attributes: .concurrent)
        private let requestTimeout: TimeInterval
        private let maxConnections: Int
        private let servedUser: uid_t
        /// Passes the request to the main actor, and tells `complete` the answer, or nil when it is not to be answered.
        private let deliver: @Sendable (Data, @escaping @Sendable (ClipboardMCPWireReply?) -> Void) -> Void
        private let counts = Mutex(Counts())

        init(
            listener: Int32, requestTimeout: TimeInterval, maxConnections: Int, servedUser: uid_t,
            deliver: @escaping @Sendable (Data, @escaping @Sendable (ClipboardMCPWireReply?) -> Void) -> Void
        ) {
            self.listener = listener
            self.requestTimeout = requestTimeout
            self.maxConnections = maxConnections
            self.servedUser = servedUser
            self.deliver = deliver
        }

        var connectionCount: Int { counts.withLock { $0.connections } }
        var requestsRead: Int { counts.withLock { $0.requestsRead } }

        /// Takes every connection waiting. The listener is not blocking, so this ends when there is none.
        func acceptPending() {
            while true {
                let client = accept(listener, nil, nil)
                guard client >= 0 else { return }
                var enable: Int32 = 1
                guard MCPSocketTrust.isPeer(client, user: servedUser), fcntl(client, F_SETFL, O_NONBLOCK) == 0,
                      setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &enable, socklen_t(MemoryLayout<Int32>.size)) == 0,
                      reserveConnection()
                else {
                    close(client)
                    continue
                }
                workQueue.async { [self] in serve(client) }
            }
        }

        private func reserveConnection() -> Bool {
            counts.withLock { counts in
                guard counts.connections < maxConnections else { return false }
                counts.connections += 1
                return true
            }
        }

        private func finish(_ client: Int32) {
            close(client)
            counts.withLock { $0.connections -= 1 }
        }

        private func serve(_ client: Int32) {
            let read = MCPSocketIO.readLine(from: client, maxLength: ClipboardMCPWire.maxRequestLength, until: MCPDeadline(after: requestTimeout))
            guard case .line(let line) = read else {
                finish(client)
                return
            }
            counts.withLock { $0.requestsRead += 1 }
            deliver(line) { [self] reply in
                workQueue.async { [self] in
                    if let reply, let bytes = ClipboardMCPWire.replyLine(reply) {
                        _ = MCPSocketIO.writeAll(bytes, to: client, until: MCPDeadline(after: 5))
                    }
                    finish(client)
                }
            }
        }
    }

    let socketPath: String
    /// How many helpers are connected and not yet answered or gone.
    var connectionCount: Int { acceptor?.connectionCount ?? 0 }
    /// How many request lines were read, for tests.
    var requestsRead: Int { acceptor?.requestsRead ?? 0 }
    var isListening: Bool { source != nil }

    private let requestTimeout: TimeInterval
    private let maxConnections: Int
    private let trustedUser: uid_t
    private let servedUser: uid_t
    private let handler: Handler
    /// The requests are queued for the main thread from a private queue, so `stop` cannot recall them; it changes this instead,
    /// and a queued one that finds another value is dropped.
    private let generation = ServerGeneration()
    private var source: DispatchSourceRead?
    private var acceptor: Acceptor?

    /// - Parameters:
    ///   - requestTimeout: how long a new connection has to send its request line before it is dropped.
    ///   - maxConnections: how many helpers may be served at once; one over it is dropped.
    ///   - trustedUser: who must own the folder: the user who runs the app.
    ///   - servedUser: whose processes may connect; the same user unless a test says otherwise.
    init(
        socketPath: String, requestTimeout: TimeInterval = 5, maxConnections: Int = 8, trustedUser: uid_t = geteuid(),
        servedUser: uid_t? = nil, handler: @escaping Handler
    ) {
        self.socketPath = socketPath
        self.requestTimeout = requestTimeout
        self.maxConnections = maxConnections
        self.trustedUser = trustedUser
        self.servedUser = servedUser ?? trustedUser
        self.handler = handler
    }

    /// Only the user who runs the app may ask: a request from another user's process is dropped.
    nonisolated static func serves(peerUser: uid_t, trustedUser: uid_t = geteuid()) -> Bool {
        peerUser == trustedUser
    }

    /// Replaces a socket file a crashed run left behind. The folder is made private to the user.
    func start() throws {
        stop()
        guard let address = MCPSocketAddress(path: socketPath) else { throw StartError.pathTooLong }
        try PrivateDirectory.prepare(URL(filePath: socketPath).deletingLastPathComponent(), user: trustedUser)
        unlink(socketPath)
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw StartError.socket(errno: errno) }
        var target = address.value
        let bound = withUnsafePointer(to: &target) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        // The folder already keeps everyone else out; the mode is the second lock.
        guard bound == 0, chmod(socketPath, 0o600) == 0, listen(descriptor, 16) == 0, fcntl(descriptor, F_SETFL, O_NONBLOCK) == 0 else {
            let code = errno
            close(descriptor)
            unlink(socketPath)
            throw StartError.socket(errno: code)
        }
        let ticket = generation.current
        let generation = generation
        let handler = handler
        let acceptor = Acceptor(listener: descriptor, requestTimeout: requestTimeout, maxConnections: maxConnections, servedUser: servedUser) { line, complete in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    complete(generation.current == ticket ? handler(line) : nil)
                }
            }
        }
        let source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: DispatchQueue(label: "io.lucasvu.mynotch.clipboard-mcp.accept"))
        let eventHandler: @Sendable () -> Void = { acceptor.acceptPending() }
        source.setEventHandler(handler: eventHandler)
        let cancelHandler: @Sendable () -> Void = { close(descriptor) }
        source.setCancelHandler(handler: cancelHandler)
        source.resume()
        self.source = source
        self.acceptor = acceptor
    }

    /// Closes the socket and removes the file. A request already read and waiting for the main thread is not answered.
    func stop() {
        generation.advance()
        acceptor = nil
        guard let source else { return }
        source.cancel()
        self.source = nil
        unlink(socketPath)
    }

    isolated deinit {
        stop()
    }
}
