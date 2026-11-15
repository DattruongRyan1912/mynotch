import Foundation

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
