import Foundation

/// Where the app listens and the host connects. Both derive the path here, so they cannot drift apart.
public enum YouTubeSocket {
    public static let fileName = "youtube.sock"
    /// The app's bundle identifier: `ModuleStorage` puts its folders under it, and the host has no bundle of its own.
    static let bundleID = "io.lucasvu.mynotch"
    static let moduleID = "media"

    /// `<storage directory>/youtube.sock`, or `/tmp/mynotch-<uid>/youtube.sock` when that path would not fit a
    /// `sockaddr_un` (a long user name). The app makes the folder private to the user and refuses one that is not theirs.
    public static func path(inStorageDirectory storage: URL, uid: uid_t = getuid()) -> String {
        let path = storage.appending(path: fileName).path
        return UnixSocketAddress(path: path) == nil ? "/tmp/mynotch-\(uid)/\(fileName)" : path
    }

    /// The path the app uses with the standard storage root (`<applicationSupport>/<bundle id>/Modules/<module id>`).
    public static func defaultPath(
        applicationSupport: URL = .applicationSupportDirectory, uid: uid_t = getuid()
    ) -> String {
        path(
            inStorageDirectory: applicationSupport.appending(components: bundleID, "Modules", moduleID, directoryHint: .isDirectory),
            uid: uid
        )
    }
}

/// A `sockaddr_un` for a path, which must fit `sun_path` with its terminating zero.
public struct UnixSocketAddress {
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
