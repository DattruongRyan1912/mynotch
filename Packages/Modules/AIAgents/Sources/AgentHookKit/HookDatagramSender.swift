import Foundation
import LocalSocketKit

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
