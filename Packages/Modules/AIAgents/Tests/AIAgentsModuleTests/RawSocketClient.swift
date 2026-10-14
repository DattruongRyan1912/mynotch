import Foundation

/// A client that connects to a stream socket by hand and writes `bytes`, so a test decides when it leaves. The caller
/// closes the descriptor.
func connectRaw(to path: String, send bytes: [UInt8]) throws -> Int32 {
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: Array(path.utf8) + [0]) }
    let connected = withUnsafePointer(to: &address) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
    }
    guard connected == 0 else {
        close(fd)
        throw CocoaError(.fileReadUnknown)
    }
    var enable: Int32 = 1
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &enable, socklen_t(MemoryLayout<Int32>.size))
    _ = write(fd, bytes, bytes.count)
    return fd
}
