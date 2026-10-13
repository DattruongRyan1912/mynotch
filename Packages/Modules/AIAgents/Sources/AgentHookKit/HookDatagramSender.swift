import Foundation

/// Sends one datagram to the app's socket. Whatever goes wrong (the app is not running, the buffer is full)
/// is ignored: a hook must never fail, block or print.
public enum HookDatagramSender {
    public static func send(_ data: Data, to socketPath: String) {
        guard let address = SocketAddress(path: socketPath) else { return }
        let fd = socket(AF_UNIX, SOCK_DGRAM, 0)
        guard fd >= 0 else { return }
        defer { close(fd) }
        guard fcntl(fd, F_SETFL, O_NONBLOCK) == 0 else { return }
        var target = address.value
        data.withUnsafeBytes { bytes in
            withUnsafePointer(to: &target) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    _ = sendto(fd, bytes.baseAddress, bytes.count, 0, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }
        }
    }
}

/// A `sockaddr_un` for a path, which must fit `sun_path` with its terminating zero.
public struct SocketAddress {
    /// The longest path in bytes that fits.
    public static let maxPathLength = MemoryLayout.size(ofValue: sockaddr_un().sun_path) - 1

    public var value = sockaddr_un()

    public init?(path: String) {
        let bytes = Array(path.utf8)
        guard bytes.count <= Self.maxPathLength else { return nil }
        value.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &value.sun_path) { $0.copyBytes(from: bytes + [0]) }
    }
}
