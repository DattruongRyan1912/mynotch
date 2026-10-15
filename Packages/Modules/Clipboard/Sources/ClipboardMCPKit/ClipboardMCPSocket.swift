import Foundation

/// Where the app listens and the helper connects. Both derive the path here, so they cannot drift apart.
public enum ClipboardMCPSocket {
    public static let fileName = "mcp.sock"
    /// The app's bundle identifier: `ModuleStorage` puts its folders under it, and the helper has no bundle of its own.
    static let bundleID = "io.lucasvu.mynotch"
    static let moduleID = "clipboard"

    /// `<storage directory>/mcp.sock`, or the fallback under `/tmp` when that path would not fit a `sockaddr_un` (a long
    /// user name).
    public static func path(inStorageDirectory storage: URL, uid: uid_t = getuid()) -> String {
        let path = storage.appending(path: fileName).path
        return MCPSocketAddress(path: path) == nil ? fallbackPath(uid: uid) : path
    }

    /// The path the app uses with the standard storage root (`<applicationSupport>/<bundle id>/Modules/<module id>`).
    public static func defaultPath(applicationSupport: URL = .applicationSupportDirectory, uid: uid_t = getuid()) -> String {
        path(
            inStorageDirectory: applicationSupport.appending(components: bundleID, "Modules", moduleID, directoryHint: .isDirectory),
            uid: uid
        )
    }

    /// Named apart from the AI agents' sockets, which use the same folder for the same reason.
    static func fallbackPath(uid: uid_t) -> String {
        "/tmp/mynotch-\(uid)/clipboard-mcp.sock"
    }
}

public struct MCPSocketAddress {
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

/// How the helper tells that what listens is the user's own MyNotch before it sends anything. A request can name what the
/// user is looking for, and what comes back is what they copied. In the folder under `/tmp` that the app uses for a long user
/// name anybody can create the folder first and listen in it, so the folder, the socket and the process behind the connection
/// are all checked, and anything else is not spoken to.
public enum MCPSocketTrust {
    public enum Verdict: Equatable, Sendable {
        /// The folder and the socket file are the user's and the folder is closed to everyone else.
        case trusted
        /// There is no folder or no socket file: the app is not running, or the feature is off.
        case absent
        /// Something is there that is not what the app makes.
        case untrusted
    }

    /// Looks at the folder of `socketPath` and at the file itself, without following links: a folder of `user`, a real
    /// folder, with mode 0700 so that nobody else can open it, and a socket file of `user` in it.
    public static func inspect(socketPath: String, user: uid_t = geteuid()) -> Verdict {
        let directory = (socketPath as NSString).deletingLastPathComponent
        var info = stat()
        guard lstat(directory, &info) == 0 else { return missing(errno) }
        guard info.st_mode & S_IFMT == S_IFDIR, info.st_uid == user, info.st_mode & 0o777 == 0o700 else { return .untrusted }
        guard lstat(socketPath, &info) == 0 else { return missing(errno) }
        guard info.st_mode & S_IFMT == S_IFSOCK, info.st_uid == user else { return .untrusted }
        return .trusted
    }

    /// True when the process at the other end of the connected socket `descriptor` runs as `user`.
    public static func isPeer(_ descriptor: Int32, user: uid_t = geteuid()) -> Bool {
        var peer: uid_t = 0
        var group: gid_t = 0
        return getpeereid(descriptor, &peer, &group) == 0 && peer == user
    }

    /// Nothing there is not the same as something wrong there.
    private static func missing(_ code: Int32) -> Verdict {
        code == ENOENT || code == ENOTDIR ? .absent : .untrusted
    }
}
