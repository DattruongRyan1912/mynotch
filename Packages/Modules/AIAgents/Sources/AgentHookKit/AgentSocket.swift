import Foundation

/// Where the app listens and the helper sends. Both derive the path here, so they cannot drift apart.
public enum AgentSocket {
    public static let fileName = "agent.sock"
    /// The stream socket a permission request goes over and its answer comes back on. Shorter than `fileName`, so it
    /// fits wherever that does.
    public static let permissionFileName = "perm.sock"
    /// The app's bundle identifier: `ModuleStorage` puts its folders under it, and the helper has no bundle of its own.
    static let bundleID = "io.lucasvu.mynotch"
    static let moduleID = "aiagents"

    /// `<storage directory>/agent.sock`, or `/tmp/mynotch-<uid>/agent.sock` when that path would not fit a
    /// `sockaddr_un` (a long user name).
    public static func path(inStorageDirectory storage: URL, uid: uid_t = getuid()) -> String {
        let path = storage.appending(path: fileName).path
        return SocketAddress(path: path) == nil ? "/tmp/mynotch-\(uid)/\(fileName)" : path
    }

    /// The permission socket in the folder of the datagram socket: the helper knows only the latter's path.
    public static func permissionPath(besides socketPath: String) -> String {
        URL(filePath: socketPath).deletingLastPathComponent().appending(path: permissionFileName).path
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
