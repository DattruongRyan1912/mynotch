import Foundation
import LocalSocketKit
import Synchronization
import YouTubeBridgeKit

/// Listens on a Unix stream socket for what the `mynotch-youtube-host` helper sends: frames of a 4-byte big-endian
/// length and a JSON message. Frames are read on a private queue and checked there; the main actor gets only
/// messages that passed. The socket is the user's alone (mode 0600 in a 0700 folder, and a peer of another user is
/// refused), and anything that is not a valid protocol message is ignored.
///
/// What goes the other way is a command: a `YouTubeCommand` (`send`) is written, as a frame, to the host whose page last
/// reported playback, which is the one that can act on it; a `TabCommand` is written to the connection the caller names, the
/// one the tab's reports came in on. Each message is handed on with the number of the connection it came in on (several Chromes,
/// one per profile, may be connected, and their tab ids are not one set of numbers; a number is never given to two connections),
/// and the end of a connection is told too, so that what came from it can be forgotten.
///
/// What it does goes to the log (`YouTubeBridgeLog`): connections, a count of the frames by type every 10 s, why a
/// frame was refused. Never what was in a frame.
final class YouTubeBridgeServer {
    enum StartError: Error, Equatable {
        /// The socket path does not fit a `sockaddr_un`.
        case pathTooLong
        case socket(errno: Int32)
        /// The folder belongs to someone else, as when another user made `/tmp/mynotch-<uid>` first.
        case directoryNotOwned

        /// A fixed word for the log.
        var reason: String {
            switch self {
            case .pathTooLong: "path-too-long"
            case .socket(let code): "socket-error-\(code)"
            case .directoryNotOwned: "folder-not-owned"
            }
        }
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
            /// A connection's number for the module, which no later connection ever has: a descriptor's number is reused as soon as it is
            /// closed, and a press on a tab of a Chrome that is gone must not reach the next one that gets its descriptor.
            var serials: [Int32: Int] = [:]
            var nextSerial = 1
            var listener: DispatchSourceRead?
            /// The connection that sent the latest `playback`: the host whose extension has the page that plays.
            var playbackConnection: Int32?
        }

        private let state = Mutex(State())
        let log: YouTubeBridgeLog
        /// What the connections of this session have sent, for the log.
        let tally: FrameTally

        init(log: YouTubeBridgeLog, now: @escaping @Sendable () -> TimeInterval) {
            self.log = log
            tally = FrameTally(counted: "received", lost: "rejected", now: now)
        }

        var isOpen: Bool { state.withLock { $0.isOpen } }
        var connectionCount: Int { state.withLock { $0.connections.count } }

        /// Whether every connection refuses to raise SIGPIPE when the host has gone (for tests).
        var allAreGuardedAgainstSIGPIPE: Bool {
            state.withLock { state in
                state.connections.keys.allSatisfy { fd in
                    var value: Int32 = 0
                    var size = socklen_t(MemoryLayout<Int32>.size)
                    return getsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &value, &size) == 0 && value == 1
                }
            }
        }

        func setListener(_ source: DispatchSourceRead) { state.withLock { $0.listener = source } }

        enum Admission {
            case accepted(open: Int, serial: Int)
            case refusedLimit
            case sessionOver
        }

        /// Takes the source in, or cancels it when the session is over or has all the connections it allows.
        @discardableResult
        func add(_ source: DispatchSourceRead, for fd: Int32) -> Admission {
            let admission = state.withLock { state -> Admission in
                guard state.isOpen else { return .sessionOver }
                guard state.connections.count < YouTubeBridgeServer.maxConnections else { return .refusedLimit }
                state.connections[fd] = source
                let serial = state.nextSerial
                state.nextSerial += 1
                state.serials[fd] = serial
                return .accepted(open: state.connections.count, serial: serial)
            }
            // A source must be resumed before it can go away, cancelled or not.
            if case .accepted = admission {} else { source.cancel() }
            source.resume()
            return admission
        }

        /// The summary of the frames since the last one, when it is due or `force`d.
        func writeSummary(force: Bool = false) {
            if let line = tally.line(force: force) { log("app frames \(line)") }
        }

        /// The number of the connection on `fd`, for the module.
        func serial(of fd: Int32) -> Int? { state.withLock { $0.serials[fd] } }

        func remove(_ fd: Int32) {
            state.withLock { state in
                state.serials[fd] = nil
                _ = state.connections.removeValue(forKey: fd)?.cancel()
                if state.playbackConnection == fd { state.playbackConnection = nil }
            }
        }

        /// A playback arrived on `fd`.
        func playbackArrived(on fd: Int32) {
            state.withLock { state in
                if state.connections[fd] != nil { state.playbackConnection = fd }
            }
        }

        /// Writes `frame` to the connection that sent the latest playback; false when there is none or the write did not
        /// take all of it, in which case the connection is given up, since a partly written frame leaves the host out of step.
        /// The sockets do not block, and a frame is a few dozen bytes, so this never waits for the host.
        func sendToPlaybackConnection(_ frame: Data) -> Bool {
            state.withLock { state in
                guard state.isOpen, let fd = state.playbackConnection else { return false }
                return Self.write(frame, to: fd, in: state)
            }
        }

        /// Writes `frame` to the connection that has this number, like `sendToPlaybackConnection`; false when it is not a connection
        /// of this session (any more).
        func send(_ frame: Data, toConnection serial: Int) -> Bool {
            state.withLock { state in
                guard state.isOpen, let fd = state.serials.first(where: { $0.value == serial })?.key else { return false }
                return Self.write(frame, to: fd, in: state)
            }
        }

        /// Writes `frame` to every open connection; true when at least one connection took it.
        func sendToAll(_ frame: Data) -> Bool {
            state.withLock { state in
                guard state.isOpen, !state.connections.isEmpty else { return false }
                var anySent = false
                for fd in state.connections.keys {
                    if Self.write(frame, to: fd, in: state) {
                        anySent = true
                    }
                }
                return anySent
            }
        }

        /// Under the lock, so the descriptor is still open: it is closed only after its source is cancelled and removed.
        private static func write(_ frame: Data, to fd: Int32, in state: State) -> Bool {
            guard state.connections[fd] != nil else { return false }
            let written = frame.withUnsafeBytes { Foundation.send(fd, $0.baseAddress, $0.count, 0) }
            if written == frame.count { return true }
            // The host sees the end and the read source takes the connection out.
            shutdown(fd, SHUT_RDWR)
            return false
        }

        func close() {
            let sources = state.withLock { state -> [DispatchSourceRead] in
                state.isOpen = false
                defer {
                    state.connections = [:]
                    state.serials = [:]
                    state.listener = nil
                    state.playbackConnection = nil
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

    /// A message and the connection it came in on (the descriptor's number, which is told to `Disconnected` when it ends).
    typealias Received = @MainActor @Sendable (YouTubeMessage, _ connection: Int) -> Void
    /// A connection has ended: what came from it is no longer there.
    typealias Disconnected = @MainActor @Sendable (_ connection: Int) -> Void

    let socketPath: String
    /// Runs on the main actor, in the order the frames were read.
    private let onMessage: Received
    private let onDisconnect: Disconnected
    private let log: YouTubeBridgeLog
    /// A monotonic clock in seconds, for the pace of the log.
    private let now: @Sendable () -> TimeInterval
    private var session: Session?
    private let queue = DispatchQueue(label: "io.lucasvu.mynotch.youtube-bridge")

    init(
        socketPath: String,
        log: YouTubeBridgeLog = .system,
        now: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        onMessage: @escaping Received,
        onDisconnect: @escaping Disconnected = { _ in }
    ) {
        self.socketPath = socketPath
        self.log = log
        self.now = now
        self.onMessage = onMessage
        self.onDisconnect = onDisconnect
    }

    /// For a caller that does not tell connections apart.
    convenience init(
        socketPath: String,
        log: YouTubeBridgeLog = .system,
        now: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        onMessage: @escaping @MainActor @Sendable (YouTubeMessage) -> Void
    ) {
        self.init(socketPath: socketPath, log: log, now: now, onMessage: { message, _ in onMessage(message) })
    }

    /// Replaces a socket file a crashed run left behind. The folder is made private to the user.
    func start() throws {
        stop()
        do {
            try open()
            log("app listening")
        } catch {
            log("app listen failed: \((error as? StartError)?.reason ?? "folder-error")")
            throw error
        }
    }

    private func open() throws {
        guard let address = SocketAddress(path: socketPath) else { throw StartError.pathTooLong }
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
        let session = Session(log: log, now: now)
        let onMessage = onMessage
        let onDisconnect = onDisconnect
        let queue = queue
        // `@Sendable` keeps the handlers off the main actor, which is the default here: they run on the private queue.
        let accept: @Sendable () -> Void = { Self.accept(fd, into: session, queue: queue, onMessage: onMessage, onDisconnect: onDisconnect) }
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
        session.writeSummary(force: true)
        log("app stopped")
    }

    /// Asks the host whose page last reported playback to do `command`. False when no host has, or the host cannot be written
    /// to; nothing is retried or sent to another host.
    func send(_ command: YouTubeCommand) -> Bool {
        session?.sendToPlaybackConnection(command.frame) ?? false
    }

    /// Asks the host on `connection` (the one the tab's reports came in on) to do `command` to its tab. False when that
    /// connection is gone or cannot be written to; nothing is retried or sent to another host.
    func send(_ command: TabCommand, toConnection connection: Int) -> Bool {
        session?.send(command.frame, toConnection: connection) ?? false
    }

    /// Asks every connected host to do `command` to its tabs (e.g. broadcast volume to all tabs). False when no host is connected.
    @discardableResult
    func sendToAll(_ command: TabCommand) -> Bool {
        session?.sendToAll(command.frame) ?? false
    }

    /// Asks the host on `connection` to have the tab draw `subtitle` over its film. False when that connection is gone or cannot be
    /// written to.
    func send(_ subtitle: TabSubtitle, toConnection connection: Int) -> Bool {
        guard let frame = subtitle.frame else { return false }
        return session?.send(frame, toConnection: connection) ?? false
    }

    /// The clients connected right now (for tests).
    var connectionCount: Int { session?.connectionCount ?? 0 }

    /// Whether every connection refuses to raise SIGPIPE: the app writes commands to the host, and a write to a host that
    /// has gone would otherwise end the app (for tests).
    var connectionsAreGuardedAgainstSIGPIPE: Bool { session?.allAreGuardedAgainstSIGPIPE ?? true }

    isolated deinit {
        stop()
    }

    /// The folder is the user's own and closed to everyone else. Anything else that goes wrong is passed on as it is, and the log
    /// says `folder-error`.
    private func preparePrivateDirectory() throws {
        do {
            try PrivateDirectory.prepare(URL(filePath: socketPath).deletingLastPathComponent())
        } catch PrivateDirectory.Failure.notOwned {
            throw StartError.directoryNotOwned
        }
    }

    // MARK: private queue

    /// Takes in every connection waiting.
    private nonisolated static func accept(
        _ listener: Int32, into session: Session, queue: DispatchQueue, onMessage: @escaping Received, onDisconnect: @escaping Disconnected
    ) {
        while true {
            let fd = Foundation.accept(listener, nil, nil)
            guard fd >= 0 else { return }
            // The socket's mode already keeps others out; this also refuses a peer that got a descriptor some other way.
            guard fcntl(fd, F_SETFL, O_NONBLOCK) == 0, SocketTrust.isPeer(fd) else {
                close(fd)
                session.log("app connection refused: peer user")
                continue
            }
            // The app writes commands to the host: a write to a host that has gone must fail, not end the app with SIGPIPE.
            var guarded: Int32 = 1
            guard setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &guarded, socklen_t(MemoryLayout<Int32>.size)) == 0 else {
                close(fd)
                session.log("app connection refused: socket option")
                continue
            }
            let reader = Reader()
            let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
            let handler: @Sendable () -> Void = {
                if let reason = drain(fd, reader: reader, onMessage: onMessage, session: session) {
                    let serial = session.serial(of: fd)
                    session.remove(fd)
                    session.writeSummary(force: true)
                    session.log("app connection closed: \(reason)")
                    // After what the connection sent.
                    if let serial {
                        DispatchQueue.main.async { MainActor.assumeIsolated { if session.isOpen { onDisconnect(serial) } } }
                    }
                }
            }
            source.setEventHandler(handler: handler)
            let cancelHandler: @Sendable () -> Void = { close(fd) }
            source.setCancelHandler(handler: cancelHandler)
            switch session.add(source, for: fd) {
            case .accepted(let open, _): session.log("app connection accepted open=\(open)")
            case .refusedLimit: session.log("app connection refused: limit")
            case .sessionOver: break
            }
        }
    }

    /// Reads what a client has sent and hands on its messages. The reason, when the connection is over: the client
    /// closed it, or broke the framing. nil while it goes on.
    private nonisolated static func drain(
        _ fd: Int32, reader: Reader, onMessage: @escaping Received, session: Session
    ) -> String? {
        while true {
            let count = recv(fd, &reader.buffer, reader.buffer.count, 0)
            if count == 0 { return "peer closed" }
            if count < 0 { return errno == EAGAIN || errno == EINTR ? nil : "read error" }
            reader.decoder.append(Data(reader.buffer[0..<count]))
            frames: while true {
                switch reader.decoder.next() {
                case .needMore:
                    break frames
                case .tooLarge:
                    return "frame too large"
                case .frame(let frame):
                    receive(frame, from: fd, onMessage: onMessage, session: session)
                }
            }
        }
    }

    /// Checks one frame: a valid message goes to the main actor, any other is counted with the reason (announced once
    /// per reason every 10 s), and the log gets a summary when one is due.
    private nonisolated static func receive(
        _ frame: Data, from fd: Int32, onMessage: @escaping Received, session: Session
    ) {
        switch YouTubeMessage.check(frame) {
        case .success(let message):
            session.tally.count(message.typeName)
            // Before the message is handed on, so that whoever acts on it can already answer on this connection.
            if case .playback = message { session.playbackArrived(on: fd) }
            let serial = session.serial(of: fd) ?? 0
            DispatchQueue.main.async { MainActor.assumeIsolated { if session.isOpen { onMessage(message, serial) } } }
        case .failure(let rejection):
            session.tally.lose(rejection.rawValue)
            if session.tally.announces(rejection.rawValue) { session.log("app rejected frame: \(rejection.rawValue)") }
        }
        session.writeSummary()
    }
}
