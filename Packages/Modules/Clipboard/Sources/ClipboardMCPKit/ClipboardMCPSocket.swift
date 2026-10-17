import Foundation
import LocalSocketKit

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
        return SocketAddress(path: path) == nil ? fallbackPath(uid: uid) : path
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
