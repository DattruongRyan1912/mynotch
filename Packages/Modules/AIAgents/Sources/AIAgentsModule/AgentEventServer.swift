import AgentHookKit
import Foundation

/// Listens on a Unix datagram socket for what the `mynotch-hook` helper sends. A datagram is one whole message,
/// so there is no framing and a slow or absent reader never blocks the helper.
final class AgentEventServer {
    enum StartError: Error, Equatable {
        /// The socket path does not fit a `sockaddr_un`.
        case pathTooLong
        case socket(errno: Int32)
    }

    let directory: URL
    var socketPath: String { directory.appending(path: "agent.sock").path }
    /// Runs on the main actor, in the order the datagrams were read.
    private let onPayload: @MainActor @Sendable (HookPayload) -> Void
    private var source: DispatchSourceRead?

    init(directory: URL, onPayload: @escaping @MainActor @Sendable (HookPayload) -> Void) {
        self.directory = directory
        self.onPayload = onPayload
    }

    /// Replaces a socket file a crashed run left behind. The directory is private to the user.
    func start() throws {
        stop()
        guard let address = SocketAddress(path: socketPath) else { throw StartError.pathTooLong }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        unlink(socketPath)
        let fd = socket(AF_UNIX, SOCK_DGRAM, 0)
        guard fd >= 0 else { throw StartError.socket(errno: errno) }
        var target = address.value
        let bound = withUnsafePointer(to: &target) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0, fcntl(fd, F_SETFL, O_NONBLOCK) == 0 else {
            let code = errno
            close(fd)
            throw StartError.socket(errno: code)
        }
        let onPayload = onPayload
        // `@Sendable` keeps the handlers off the main actor, which is the default here: they run on the private queue.
        let handler: @Sendable () -> Void = { Self.drain(fd, into: onPayload) }
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: DispatchQueue(label: "io.lucasvu.mynotch.agent-events"))
        source.setEventHandler(handler: handler)
        let cancelHandler: @Sendable () -> Void = { close(fd) }
        source.setCancelHandler(handler: cancelHandler)
        source.resume()
        self.source = source
    }

    /// Closes the socket and removes its file.
    func stop() {
        guard let source else { return }
        source.cancel()
        self.source = nil
        unlink(socketPath)
    }

    deinit {
        source?.cancel()
    }

    /// Reads every datagram waiting; anything that does not decode is dropped.
    private nonisolated static func drain(_ fd: Int32, into onPayload: @escaping @MainActor @Sendable (HookPayload) -> Void) {
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while true {
            let count = recv(fd, &buffer, buffer.count, 0)
            guard count > 0 else { return }
            guard let payload = try? HookPayload.decode(Data(buffer[0..<count])) else { continue }
            DispatchQueue.main.async { MainActor.assumeIsolated { onPayload(payload) } }
        }
    }
}
