import Foundation

/// The host's side of the stream socket: connect, send whole frames, notice that the app has gone.
enum UnixStreamSocket {
    /// How long a send may wait for a slow app before the connection is given up.
    static let sendTimeoutSeconds = 5

    /// A connected socket, or nil when nothing listens, the path does not fit, or the one that listens belongs to
    /// someone other than `expectedOwner`: a folder in `/tmp` can be made by anyone, and captions are not sent to another
    /// user's socket. The owner is asked of the connection itself, so a socket file swapped in after the path was
    /// looked at makes no difference; nothing is sent before that.
    static func connect(to path: String, expectedOwner: uid_t) -> Int32? {
        guard var address = UnixSocketAddress(path: path)?.value else { return nil }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        var yes: Int32 = 1
        var timeout = timeval(tv_sec: sendTimeoutSeconds, tv_usec: 0)
        // Without SO_NOSIGPIPE a send to a closed socket would kill the host instead of failing.
        guard setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &yes, socklen_t(MemoryLayout<Int32>.size)) == 0,
              setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size)) == 0,
              // Non-blocking while connecting, so an app whose queue of waiting connections is full cannot hold the host.
              fcntl(fd, F_SETFL, O_NONBLOCK) == 0
        else {
            close(fd)
            return nil
        }
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Foundation.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        var owner: uid_t = 0
        var group: gid_t = 0
        guard connected == 0, getpeereid(fd, &owner, &group) == 0, owner == expectedOwner, fcntl(fd, F_SETFL, 0) == 0 else {
            close(fd)
            return nil
        }
        return fd
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

    /// The app never sends anything, so a socket that can be read has either closed or been written to by a stranger;
    /// only the first matters.
    static func peerHasClosed(_ fd: Int32) -> Bool {
        var poller = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
        guard poll(&poller, 1, 0) > 0 else { return false }
        if poller.revents & Int16(POLLHUP | POLLERR | POLLNVAL) != 0 { return true }
        var byte: UInt8 = 0
        let count = recv(fd, &byte, 1, MSG_PEEK | MSG_DONTWAIT)
        return count == 0 || (count < 0 && errno != EAGAIN && errno != EINTR)
    }
}
