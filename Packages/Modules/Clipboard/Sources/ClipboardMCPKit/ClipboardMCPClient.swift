import Foundation
import LocalSocketKit

/// The helper's side of the socket: sends one request and waits, never past `timeout`, for the app's answer. Whatever goes
/// wrong is an outcome, not an error, because the helper must keep answering its agent.
public enum ClipboardMCPClient {
    /// The app answers from memory, so this is only long when its main thread is busy.
    public static let defaultTimeout: TimeInterval = 10

    public enum Outcome: Equatable, Sendable {
        case reply(ClipboardMCPWireReply)
        /// Nobody listens: the app is not running, or the feature is off, which closes the socket.
        case unreachable
        /// What listens is not the user's own app, or its folder is open to others: nothing was sent and nothing it says is
        /// believed.
        case untrusted
        /// The app took the request but no answer came in time, or what came was not one.
        case noAnswer
    }

    /// - Parameter trustedUser: the user whose app is spoken to: the one who owns the folder and the socket, and runs the
    ///   process on the other end. The helper's own user.
    public static func send(
        _ request: ClipboardMCPRequest, socketPath: String, timeout: TimeInterval = defaultTimeout, trustedUser: uid_t = geteuid()
    ) -> Outcome {
        send(request, socketPath: socketPath, timeout: timeout, trustedUser: trustedUser, peerUser: trustedUser)
    }

    /// With the user of the process on the other end apart from the owner of the files, which a test cannot otherwise tell.
    static func send(_ request: ClipboardMCPRequest, socketPath: String, timeout: TimeInterval, trustedUser: uid_t, peerUser: uid_t) -> Outcome {
        guard let line = ClipboardMCPWire.requestLine(request), let address = SocketAddress(path: socketPath) else { return .unreachable }
        switch SocketTrust.inspect(socketPath: socketPath, user: trustedUser) {
        case .absent: return .unreachable
        case .untrusted: return .untrusted
        case .trusted: break
        }
        let deadline = MCPDeadline(after: timeout)
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return .unreachable }
        defer { close(descriptor) }
        // Non-blocking, so a listener whose queue is full cannot hold the helper; a failed write to a peer that is gone is an
        // error and not a SIGPIPE that would end the helper.
        var enable: Int32 = 1
        guard fcntl(descriptor, F_SETFL, O_NONBLOCK) == 0,
              setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &enable, socklen_t(MemoryLayout<Int32>.size)) == 0
        else { return .unreachable }
        var target = address.value
        let connected = withUnsafePointer(to: &target) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard connected == 0 else { return .unreachable }
        // Before a byte is written: the folder was right, but it is the process on the connection that answers.
        guard SocketTrust.isPeer(descriptor, user: peerUser) else { return .untrusted }
        guard MCPSocketIO.writeAll(line, to: descriptor, until: deadline) else { return .noAnswer }
        switch MCPSocketIO.readLine(from: descriptor, maxLength: ClipboardMCPWire.maxReplyLength, until: deadline) {
        case .line(let data), .endOfStream(let data):
            return ClipboardMCPWire.decodeReply(data).map(Outcome.reply) ?? .noAnswer
        case .timedOut, .tooLong, .failed:
            return .noAnswer
        }
    }
}
