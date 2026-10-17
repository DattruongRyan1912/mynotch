import Foundation
import LocalSocketKit
import MyNotchTestSupport
import Synchronization
@testable import YouTubeBridgeKit

/// Stands in for the app: listens on a stream socket in a short `/tmp/mn-<id>` folder and collects the frames each
/// client sends. Plain threads and blocking calls, so the host's own behaviour is all that is under test. With
/// `closesClientsAtOnce` it is an app that accepts every connection and hangs up, as one that is quitting does.
final class FrameServer: Sendable {
    private struct State {
        var frames: [Data] = []
        var connections = 0
        var hangUps = 0
        var clients: [Int32] = []
        var listener: Int32 = -1
    }

    let directory: URL
    var path: String { directory.appending(path: YouTubeSocket.fileName).path }
    private let closesClientsAtOnce: Bool
    private let state = Mutex(State())

    /// A folder with a path short enough for a socket (`directory` to reuse one), private to the user as the app makes it
    /// (the host does not connect to any other); the socket file is made by `start`.
    init(directory: URL? = nil, closesClientsAtOnce: Bool = false) {
        self.closesClientsAtOnce = closesClientsAtOnce
        self.directory = directory ?? ScratchFolders.shared.reserveShort()
        try? FileManager.default.createDirectory(
            at: self.directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]
        )
        // A reused folder is not made again, so its mode is set here too.
        chmod(self.directory.path, 0o700)
    }

    var frames: [Data] { state.withLock { $0.frames } }
    var connectionCount: Int { state.withLock { $0.connections } }
    /// Connections that were accepted and closed again at once.
    var hangUpCount: Int { state.withLock { $0.hangUps } }

    /// Sends bytes to every client, as the app does with a command.
    func send(_ bytes: Data) {
        state.withLock { state in
            for client in state.clients { _ = UnixStreamSocket.writeAll(bytes, to: client) }
        }
    }

    /// Sends one frame (4-byte big-endian length, then the JSON) to every client.
    func sendFrame(_ json: Data) {
        send(AppFrame.encode(json)!)
    }

    func start() throws {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard var address = SocketAddress(path: path)?.value else { close(fd); throw POSIXError(.ENAMETOOLONG) }
        unlink(path)
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0, listen(fd, 8) == 0, fcntl(fd, F_SETFL, O_NONBLOCK) == 0 else { close(fd); throw POSIXError(.EADDRINUSE) }
        state.withLock { $0.listener = fd }
        Thread.detachNewThread { [self] in accept(on: fd) }
    }

    /// Closes the listener and every client, like the app quitting.
    func stop() {
        // Under the lock, and only for descriptors still listed: one that its thread has closed may be another test's by now.
        state.withLock { state in
            for client in state.clients { shutdown(client, SHUT_RDWR) }
            state.clients = []
            if state.listener >= 0 { close(state.listener) }
            state.listener = -1
        }
        unlink(path)
    }

    func remove() {
        stop()
        try? FileManager.default.removeItem(at: directory)
    }

    private func accept(on listener: Int32) {
        while true {
            // Checked and accepted under the lock, so `stop` cannot close the descriptor in between.
            let client = state.withLock { state -> Int32? in
                guard state.listener == listener else { return nil }
                let client = Foundation.accept(listener, nil, nil)
                guard client >= 0 else { return client }
                state.connections += 1
                if closesClientsAtOnce {
                    // The peer's end is closed by the time `hangUpCount` shows it.
                    close(client)
                    state.hangUps += 1
                    return -2
                }
                // A socket accepted from a non-blocking listener is non-blocking too on macOS.
                _ = fcntl(client, F_SETFL, 0)
                state.clients.append(client)
                return client
            }
            guard let client else { return }
            if client < 0 {
                if client == -1 { usleep(5_000) }
                continue
            }
            Thread.detachNewThread { [self] in read(from: client) }
        }
    }

    private func read(from client: Int32) {
        var decoder = AppFrameDecoder()
        var buffer = [UInt8](repeating: 0, count: 65_536)
        while true {
            let count = recv(client, &buffer, buffer.count, 0)
            guard count > 0 else { break }
            decoder.append(Data(buffer[0..<count]))
            while case .frame(let frame) = decoder.next() { state.withLock { $0.frames.append(frame) } }
        }
        // Unlisted before it is closed, so `stop` never touches a descriptor that is no longer this client's.
        state.withLock { $0.clients.removeAll { $0 == client } }
        close(client)
    }
}

/// Polls until `condition` holds, for at most `seconds`; the result says whether it did. The limit only matters when
/// something is wrong, so it is very generous: a busy machine can hold a thread back for many seconds.
@discardableResult
func waitUntil(seconds: Double = 60, _ condition: () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + .seconds(seconds)
    while !condition() {
        if ContinuousClock.now > deadline { return false }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return true
}

/// A clock the test moves by hand, in seconds.
final class TestClock: Sendable {
    private let seconds = Mutex(1_000.0)

    var now: TimeInterval { seconds.withLock { $0 } }

    func advance(by interval: TimeInterval) { seconds.withLock { $0 += interval } }
}
