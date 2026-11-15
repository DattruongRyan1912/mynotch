import AgentHookKit
import Foundation
import LocalSocketKit

/// Listens on a Unix datagram socket for what the `mynotch-hook` helper sends. A datagram is one whole message,
/// so there is no framing and a slow or absent reader never blocks the helper.
final class AgentEventServer {
    enum StartError: Error, Equatable {
        /// The socket path does not fit a `sockaddr_un`.
        case pathTooLong
        case socket(errno: Int32)
        /// The folder belongs to someone else, as when another user made `/tmp/mynotch-<uid>` first.
        case directoryNotOwned
    }

    let directory: URL
    var socketPath: String { directory.appending(path: "agent.sock").path }
    /// Runs on the main actor, in the order the datagrams were read.
    private let onPayload: @MainActor @Sendable (HookPayload) -> Void
    /// The datagrams are queued for the main thread from the private queue, so `stop` cannot recall them; it
    /// changes this instead, and a queued one that finds another value is dropped.
    private let generation = ServerGeneration()
    private var source: DispatchSourceRead?

    init(directory: URL, onPayload: @escaping @MainActor @Sendable (HookPayload) -> Void) {
        self.directory = directory
        self.onPayload = onPayload
    }

    /// Replaces a socket file a crashed run left behind. The directory is made private to the user.
    func start() throws {
        stop()
        guard let address = SocketAddress(path: socketPath) else { throw StartError.pathTooLong }
        try StartError.preparePrivateDirectory(directory)
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
        // The helpers send in bursts, so give the queue room to hold them; the default is a few KB. Best effort.
        var bufferSize: Int32 = 256 * 1024
        _ = setsockopt(fd, SOL_SOCKET, SO_RCVBUF, &bufferSize, socklen_t(MemoryLayout<Int32>.size))
        let ticket = generation.current
        let generation = generation
        let onPayload: @MainActor @Sendable (HookPayload) -> Void = { [onPayload] payload in
            if generation.current == ticket { onPayload(payload) }
        }
        // `@Sendable` keeps the handlers off the main actor, which is the default here: they run on the private queue.
        let handler: @Sendable () -> Void = { Self.drain(fd, into: onPayload) }
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: DispatchQueue(label: "io.lucasvu.mynotch.agent-events"))
        source.setEventHandler(handler: handler)
        let cancelHandler: @Sendable () -> Void = { close(fd) }
        source.setCancelHandler(handler: cancelHandler)
        source.resume()
        self.source = source
    }

    /// The size of the open socket's receive buffer, nil while not listening. Asking for a larger one is best
    /// effort, so this is how a test can tell it was granted.
    var receiveBufferSize: Int? {
        guard let source else { return nil }
        var size: Int32 = 0
        var length = socklen_t(MemoryLayout<Int32>.size)
        guard getsockopt(Int32(source.handle), SOL_SOCKET, SO_RCVBUF, &size, &length) == 0 else { return nil }
        return Int(size)
    }

    /// Closes the socket and removes its file.
    func stop() {
        generation.advance()
        guard let source else { return }
        source.cancel()
        self.source = nil
        unlink(socketPath)
    }

    isolated deinit {
        stop()
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
