import Foundation

/// How the helper tells that what listens is the user's own MyNotch before it sends anything. A request names the tool
/// and the command, and what comes back can let the agent run it. In the folder under `/tmp` that the app uses for a
/// long user name anybody can create the folder first and listen in it, so the folder, the socket and the process behind
/// the connection are all checked, and anything else is not spoken to.
public enum SocketTrust {
    public enum Verdict: Equatable, Sendable {
        /// The folder and the socket file are the user's and the folder is closed to everyone else.
        case trusted
        /// There is no folder or no socket file: the app is not running.
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
