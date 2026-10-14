import AgentHookKit
import Foundation
import Synchronization

/// Listens on a Unix stream socket for the permission requests the `mynotch-hook` helper sends and waits on. The
/// datagram socket of `AgentEventServer` is one-way; here each request keeps its connection open, and the answer
/// goes back over it, so a decision can only reach the helper that asked.
///
/// The socket is `0600` in the private folder, and a peer that is not the same user is dropped.
final class PermissionServer {
    typealias Handler = @MainActor @Sendable (HookPayload, PermissionConnection) -> Void

    /// What the private queue works with: the accepted connections and the way to hand a request to the main actor.
    private nonisolated final class Acceptor: Sendable {
        private let listener: Int32
        private let queue: DispatchQueue
        private let requestTimeout: TimeInterval
        private let maxConnections: Int
        private let deliver: @Sendable (HookPayload, PermissionConnection) -> Void
        private struct Registry {
            var connections: [ObjectIdentifier: PermissionConnection] = [:]
            /// Set by `shutDown`: a connection accepted after it is closed at once.
            var isShutDown = false
        }

        private let registry = Mutex(Registry())

        init(
            listener: Int32, queue: DispatchQueue, requestTimeout: TimeInterval, maxConnections: Int,
            deliver: @escaping @Sendable (HookPayload, PermissionConnection) -> Void
        ) {
            self.listener = listener
            self.queue = queue
            self.requestTimeout = requestTimeout
            self.maxConnections = maxConnections
            self.deliver = deliver
        }

        var count: Int { registry.withLock { $0.connections.count } }

        /// Takes every connection waiting. The listener is not blocking, so this ends when there is none.
        func acceptPending() {
            while true {
                let client = accept(listener, nil, nil)
                guard client >= 0 else { return }
                var user: uid_t = 0
                var group: gid_t = 0
                var enable: Int32 = 1
                guard getpeereid(client, &user, &group) == 0, PermissionServer.serves(peerUser: user), count < maxConnections,
                      fcntl(client, F_SETFL, O_NONBLOCK) == 0,
                      setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &enable, socklen_t(MemoryLayout<Int32>.size)) == 0
                else {
                    close(client)
                    continue
                }
                let connection = PermissionConnection(fd: client, queue: queue) { [weak self] ended in self?.forget(ended) }
                let isOpen = registry.withLock { registry in
                    if !registry.isShutDown { registry.connections[ObjectIdentifier(connection)] = connection }
                    return !registry.isShutDown
                }
                guard isOpen else {
                    close(client)
                    continue
                }
                let deliver = deliver
                connection.begin(timeout: requestTimeout) { payload in deliver(payload, connection) }
            }
        }

        func forget(_ connection: PermissionConnection) {
            registry.withLock { _ = $0.connections.removeValue(forKey: ObjectIdentifier(connection)) }
        }

        /// Closes what is still open, without a word to the helpers: they let the agent ask as usual.
        func shutDown() {
            let open = registry.withLock { registry in
                registry.isShutDown = true
                defer { registry.connections = [:] }
                return Array(registry.connections.values)
            }
            for connection in open { connection.shutDown() }
        }
    }

    let directory: URL
    var socketPath: String { directory.appending(path: AgentSocket.permissionFileName).path }
    /// How many helpers are connected and not yet answered or gone.
    var connectionCount: Int { acceptor?.count ?? 0 }

    private let requestTimeout: TimeInterval
    private let maxConnections: Int
    /// Runs on the main actor, in the order the requests were read.
    private let onRequest: Handler
    /// The requests are queued for the main thread from the private queue, so `stop` cannot recall them; it changes
    /// this instead, and a queued one that finds another value is dropped.
    private let generation = ServerGeneration()
    private var source: DispatchSourceRead?
    private var acceptor: Acceptor?

    /// - Parameters:
    ///   - requestTimeout: how long a new connection has to send its request line before it is dropped.
    ///   - maxConnections: how many helpers may wait at once; a helper over it is refused and the agent asks as usual.
    init(directory: URL, requestTimeout: TimeInterval = 10, maxConnections: Int = 32, onRequest: @escaping Handler) {
        self.directory = directory
        self.requestTimeout = requestTimeout
        self.maxConnections = maxConnections
        self.onRequest = onRequest
    }

    /// Only the user who runs the app may ask: a request from another user's process is dropped.
    nonisolated static func serves(peerUser: uid_t) -> Bool {
        peerUser == geteuid()
    }

    /// Replaces a socket file a crashed run left behind. The directory is made private to the user.
    func start() throws {
        stop()
        guard let address = SocketAddress(path: socketPath) else { throw AgentEventServer.StartError.pathTooLong }
        try PrivateDirectory.prepare(directory)
        unlink(socketPath)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw AgentEventServer.StartError.socket(errno: errno) }
        var target = address.value
        let bound = withUnsafePointer(to: &target) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        // The folder already keeps everyone else out; the mode is the second lock.
        guard bound == 0, chmod(socketPath, 0o600) == 0, listen(fd, 16) == 0, fcntl(fd, F_SETFL, O_NONBLOCK) == 0 else {
            let code = errno
            close(fd)
            unlink(socketPath)
            throw AgentEventServer.StartError.socket(errno: code)
        }
        let ticket = generation.current
        let generation = generation
        let onRequest = onRequest
        let queue = DispatchQueue(label: "io.lucasvu.mynotch.agent-permissions")
        let acceptor = Acceptor(listener: fd, queue: queue, requestTimeout: requestTimeout, maxConnections: maxConnections) { payload, connection in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    if generation.current == ticket { onRequest(payload, connection) }
                }
            }
        }
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        let handler: @Sendable () -> Void = { acceptor.acceptPending() }
        source.setEventHandler(handler: handler)
        let cancelHandler: @Sendable () -> Void = { close(fd) }
        source.setCancelHandler(handler: cancelHandler)
        source.resume()
        self.source = source
        self.acceptor = acceptor
    }

    /// Closes the socket and the connections that wait, and removes the file.
    func stop() {
        generation.advance()
        acceptor?.shutDown()
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
