import Foundation

/// The helper's side of the permission socket: sends one request and waits, never past `timeout`, for the app's
/// answer. Whatever goes wrong is an outcome, not an error, because a hook must never fail or hang.
public enum PermissionClient {
    /// How long the helper waits for the user. The hook's own timeout in the agent's settings is longer, so the helper
    /// always gives up first and quietly.
    public static let defaultTimeout: TimeInterval = 60
    /// The longest reply read: the three real ones are about 20 bytes.
    static let maxReplyLength = 256

    public enum Outcome: Equatable, Sendable {
        /// Nobody listens: the app is not running or does not have the socket open. The agent's status goes to the
        /// datagram socket instead, as it did before there was a permission socket.
        case unreachable
        /// The app took the request but no answer came in time, or what came was not one.
        case noAnswer
        case answered(PermissionAnswer)
    }

    public static func ask(_ payload: HookPayload, socketPath: String, timeout: TimeInterval) -> Outcome {
        guard let line = PermissionWire.requestLine(payload), let address = SocketAddress(path: socketPath) else { return .unreachable }
        let deadline = DispatchTime.now().uptimeNanoseconds + UInt64(max(timeout, 0) * 1e9)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return .unreachable }
        defer { close(fd) }
        // Non-blocking, so a listener whose queue is full cannot hold the helper; a failed write to a peer that is
        // gone is an error and not a SIGPIPE that would end the helper with a non-zero status.
        var enable: Int32 = 1
        guard fcntl(fd, F_SETFL, O_NONBLOCK) == 0,
              setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &enable, socklen_t(MemoryLayout<Int32>.size)) == 0
        else { return .unreachable }
        var target = address.value
        let connected = withUnsafePointer(to: &target) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard connected == 0 else { return .unreachable }
        guard writeAll(line, to: fd, until: deadline) else { return .noAnswer }
        return readAnswer(from: fd, until: deadline)
    }

    /// Milliseconds left until `deadline`, 0 when it has passed.
    private static func milliseconds(until deadline: UInt64) -> Int32 {
        let now = DispatchTime.now().uptimeNanoseconds
        guard deadline > now else { return 0 }
        return Int32(min((deadline - now + 999_999) / 1_000_000, UInt64(Int32.max)))
    }

    /// True when the poll says `events` can proceed before the deadline.
    private static func wait(for events: Int32, on fd: Int32, until deadline: UInt64) -> Bool {
        while true {
            let remaining = milliseconds(until: deadline)
            guard remaining > 0 else { return false }
            var poller = pollfd(fd: fd, events: Int16(events), revents: 0)
            let ready = poll(&poller, 1, remaining)
            if ready > 0 { return true }
            if ready == 0 || errno != EINTR { return false }
        }
    }

    private static func writeAll(_ data: Data, to fd: Int32, until deadline: UInt64) -> Bool {
        var offset = 0
        while offset < data.count {
            let written = data.withUnsafeBytes { write(fd, $0.baseAddress! + offset, data.count - offset) }
            if written > 0 {
                offset += written
            } else if written < 0, errno == EAGAIN || errno == EINTR {
                guard wait(for: Int32(POLLOUT), on: fd, until: deadline) else { return false }
            } else {
                return false
            }
        }
        return true
    }

    private static func readAnswer(from fd: Int32, until deadline: UInt64) -> Outcome {
        var reply = Data()
        var buffer = [UInt8](repeating: 0, count: 128)
        while true {
            guard wait(for: Int32(POLLIN), on: fd, until: deadline) else { return .noAnswer }
            let count = read(fd, &buffer, buffer.count)
            if count < 0 {
                if errno == EAGAIN || errno == EINTR { continue }
                return .noAnswer
            }
            // The app closed: what it wrote, if it wrote a whole answer, is the reply.
            if count == 0 { return PermissionWire.decodeReply(reply).map(Outcome.answered) ?? .noAnswer }
            reply.append(contentsOf: buffer[0..<count])
            if reply.count > maxReplyLength { return .noAnswer }
            if let end = reply.firstIndex(of: UInt8(ascii: "\n")) {
                return PermissionWire.decodeReply(reply[reply.startIndex..<end]).map(Outcome.answered) ?? .noAnswer
            }
        }
    }
}
