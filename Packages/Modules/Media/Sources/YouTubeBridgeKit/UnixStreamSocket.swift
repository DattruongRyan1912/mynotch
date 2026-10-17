import Foundation
import LocalSocketKit

/// The host's side of the stream socket: connect, send whole frames. The thread that reads the connection notices that the app has gone.
enum UnixStreamSocket {
    /// How long a send may wait for a slow app before the connection is given up.
    static let sendTimeoutSeconds = 5

    /// Why no connection was made; the words go to the log.
    enum ConnectFailure: Error, Equatable {
        case pathTooLong
        /// The folder, or what is at the socket's place, is not what the app makes: a link, a folder that others can open,
        /// a file that is not a socket, something that is not the user's. Nothing was connected to.
        case untrusted
        /// The process that listens runs as someone other than the expected user.
        case otherUser
        /// No socket file: the app is not running, or not listening.
        case noSocket
        case refused
        /// The app's queue of waiting connections is full.
        case busy
        case failed(errno: Int32)

        var reason: String {
            switch self {
            case .pathTooLong: "path-too-long"
            case .untrusted: "untrusted"
            case .otherUser: "other-user"
            case .noSocket: "no-socket"
            case .refused: "refused"
            case .busy: "busy"
            case .failed(let code): "error-\(code)"
            }
        }
    }

    /// A connected socket, or nil when there is none; see `open`.
    static func connect(to path: String, expectedOwner: uid_t) -> Int32? {
        try? open(to: path, expectedOwner: expectedOwner).get()
    }

    /// A connected socket, or why there is none: nothing listens, the path does not fit, or what is there is not the
    /// user's own app. A folder in `/tmp` can be made by anyone, and captions are not sent to another user's socket, so
    /// the folder and the socket file are looked at first, without following links (`SocketTrust.inspect`: a real folder
    /// of `expectedOwner` that nobody else can open, and a socket file of `expectedOwner` in it); a folder or file that is
    /// not there is a `noSocket`, as a connect would say, and anything else there is `untrusted`, and nothing is connected to.
    /// After the connection the owner is asked of the connection itself, so a socket file swapped in after the path was
    /// looked at makes no difference; nothing is sent before that.
    static func open(to path: String, expectedOwner: uid_t) -> Result<Int32, ConnectFailure> {
        open(to: path, fileOwner: expectedOwner, peerUser: expectedOwner)
    }

    /// With the user of the process on the other end apart from the owner of the files, which a test cannot otherwise tell.
    static func open(to path: String, fileOwner: uid_t, peerUser: uid_t) -> Result<Int32, ConnectFailure> {
        guard var address = SocketAddress(path: path)?.value else { return .failure(.pathTooLong) }
        switch SocketTrust.inspect(socketPath: path, user: fileOwner) {
        case .absent: return .failure(.noSocket)
        case .untrusted: return .failure(.untrusted)
        case .trusted: break
        }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return .failure(.failed(errno: errno)) }
        var yes: Int32 = 1
        var timeout = timeval(tv_sec: sendTimeoutSeconds, tv_usec: 0)
        // Without SO_NOSIGPIPE a send to a closed socket would kill the host instead of failing.
        guard setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &yes, socklen_t(MemoryLayout<Int32>.size)) == 0,
              setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size)) == 0,
              // Non-blocking while connecting, so an app whose queue of waiting connections is full cannot hold the host.
              fcntl(fd, F_SETFL, O_NONBLOCK) == 0
        else {
            let code = errno
            close(fd)
            return .failure(.failed(errno: code))
        }
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Foundation.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard connected == 0 else {
            let code = errno
            close(fd)
            switch code {
            case ENOENT: return .failure(.noSocket)
            case ECONNREFUSED: return .failure(.refused)
            case EAGAIN: return .failure(.busy)
            default: return .failure(.failed(errno: code))
            }
        }
        guard SocketTrust.isPeer(fd, user: peerUser) else {
            close(fd)
            return .failure(.otherUser)
        }
        guard fcntl(fd, F_SETFL, 0) == 0 else {
            let code = errno
            close(fd)
            return .failure(.failed(errno: code))
        }
        return .success(fd)
    }

    /// Sends all of `data`; false when the app closed the socket or took longer than the send timeout.
    static func writeAll(_ data: Data, to fd: Int32) -> Bool {
        data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let written = send(fd, bytes.baseAddress! + offset, bytes.count - offset, 0)
                if written > 0 {
                    offset += written
                } else if written < 0, errno == EINTR {
                    continue
                } else {
                    return false
                }
            }
            return true
        }
    }
}
