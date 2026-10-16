import Foundation
import Synchronization

/// A folder under /tmp (short, so a socket path fits) that is removed with the test.
final class SocketFolder {
    let path = "/tmp/mn-\(UUID().uuidString.prefix(8))"
    var socketPath: String { path + "/mcp.sock" }
    private var listener: Int32 = -1

    init(mode: mode_t = 0o700) throws {
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true, attributes: [.posixPermissions: Int(mode)])
        chmod(path, mode)
    }

    /// A listening socket file in it.
    func bindSocket(named name: String = "mcp.sock") throws {
        listener = socket(AF_UNIX, SOCK_STREAM, 0)
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: Array((path + "/" + name).utf8) + [0]) }
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(listener, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0, listen(listener, 1) == 0 else { throw CocoaError(.fileWriteUnknown) }
    }

    /// Closes the socket and leaves its file, as a crashed app does.
    func stopListening() {
        if listener >= 0 { close(listener) }
        listener = -1
    }

    deinit {
        if listener >= 0 { close(listener) }
        try? FileManager.default.removeItem(atPath: path)
    }
}

/// A listening stream socket that stands in for the app: it accepts connections, reads each request line and answers as
/// scripted. It runs on threads of its own, so the code under test can block on it like the real helper does; they stop, and
/// close what they own, when the object is released.
final class FakeMCPApp: Sendable {
    enum Behavior: Sendable {
        /// Writes these bytes at once, then closes.
        case reply(String)
        /// Writes the first piece, waits, writes the second, then closes.
        case replyInPieces(String, String)
        /// Reads the request and says nothing, holding the connection open until the test ends.
        case silent
        /// Reads the request and closes.
        case hangUp
        /// Never reads the request and holds the connection open.
        case ignore
    }

    private final class Shared: Sendable {
        let requests = Mutex<[Data]>([])
        let connections = Mutex(0)
        let stopped = Mutex(false)
        var isStopped: Bool { stopped.withLock { $0 } }
    }

    let directory: String
    var socketPath: String { directory + "/mcp.sock" }
    private let shared = Shared()

    init(behavior: Behavior, folderMode: Int = 0o700) throws {
        // A helper that leaves before the fake answers must not end the test process.
        signal(SIGPIPE, SIG_IGN)
        directory = "/tmp/mn-\(UUID().uuidString.prefix(8))"
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: folderMode])
        chmod(directory, mode_t(folderMode))
        let listener = socket(AF_UNIX, SOCK_STREAM, 0)
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: Array((directory + "/mcp.sock").utf8) + [0]) }
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(listener, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0, listen(listener, 8) == 0 else {
            close(listener)
            throw CocoaError(.fileWriteUnknown)
        }
        let shared = shared
        Thread.detachNewThread {
            while !shared.isStopped {
                var poller = pollfd(fd: listener, events: Int16(POLLIN), revents: 0)
                guard poll(&poller, 1, 50) > 0 else { continue }
                let client = accept(listener, nil, nil)
                guard client >= 0 else { continue }
                var enable: Int32 = 1
                setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &enable, socklen_t(MemoryLayout<Int32>.size))
                shared.connections.withLock { $0 += 1 }
                Self.serve(client, behavior, shared)
            }
            close(listener)
        }
    }

    deinit {
        shared.stopped.withLock { $0 = true }
        try? FileManager.default.removeItem(atPath: directory)
    }

    /// The request lines read so far, without their newline.
    var requests: [Data] { shared.requests.withLock { $0 } }
    var connectionCount: Int { shared.connections.withLock { $0 } }

    private static func serve(_ client: Int32, _ behavior: Behavior, _ shared: Shared) {
        if case .ignore = behavior {
            holdOpen(client, shared)
            return
        }
        if let line = readLine(client, shared) { shared.requests.withLock { $0.append(line) } }
        switch behavior {
        case let .reply(text):
            put(client, text)
            close(client)
        case let .replyInPieces(first, second):
            put(client, first)
            usleep(150_000)
            put(client, second)
            close(client)
        case .silent:
            holdOpen(client, shared)
        case .hangUp, .ignore:
            close(client)
        }
    }

    private static func holdOpen(_ client: Int32, _ shared: Shared) {
        Thread.detachNewThread {
            while !shared.isStopped { usleep(20_000) }
            close(client)
        }
    }

    private static func readLine(_ client: Int32, _ shared: Shared) -> Data? {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1_024)
        let deadline = Date().addingTimeInterval(120)
        while Date() < deadline, !shared.isStopped {
            var poller = pollfd(fd: client, events: Int16(POLLIN), revents: 0)
            guard poll(&poller, 1, 50) > 0 else { continue }
            let count = read(client, &buffer, buffer.count)
            guard count > 0 else { return data.isEmpty ? nil : data }
            data.append(contentsOf: buffer[0..<count])
            if let newline = data.firstIndex(of: 0x0A) { return data[data.startIndex..<newline] }
        }
        return nil
    }

    private static func put(_ client: Int32, _ text: String) {
        let bytes = Array(text.utf8)
        _ = write(client, bytes, bytes.count)
    }
}
