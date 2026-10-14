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
        /// What listens is not the user's own app, or its folder is open to others: nothing was sent and nothing it says
        /// is believed. The helper then says nothing at all, since the status datagram would go to the same folder.
        case untrusted
        case answered(PermissionAnswer)
    }

    /// - Parameter trustedUser: the user whose app is spoken to: the one who owns the folder and the socket, and runs the
    ///   process on the other end. The helper's own user.
    public static func ask(_ payload: HookPayload, socketPath: String, timeout: TimeInterval, trustedUser: uid_t = geteuid()) -> Outcome {
        ask(payload, socketPath: socketPath, timeout: timeout, trustedUser: trustedUser, peerUser: trustedUser)
    }

    /// With the user of the process on the other end apart from the owner of the files, which a test cannot otherwise tell.
    static func ask(_ payload: HookPayload, socketPath: String, timeout: TimeInterval, trustedUser: uid_t, peerUser: uid_t) -> Outcome {
        guard let line = PermissionWire.requestLine(payload), let address = SocketAddress(path: socketPath) else { return .unreachable }
        switch SocketTrust.inspect(socketPath: socketPath, user: trustedUser) {
        case .absent: return .unreachable
        case .untrusted: return .untrusted
        case .trusted: break
        }
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
        // Before a byte is written: the folder was right, but it is the process on the connection that answers.
        guard SocketTrust.isPeer(fd, user: peerUser) else { return .untrusted }
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
