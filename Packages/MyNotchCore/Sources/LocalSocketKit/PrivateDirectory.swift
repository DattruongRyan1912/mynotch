import Foundation

/// The folder an app socket lives in: the user's own and closed to everyone else.
public enum PrivateDirectory {
    public enum Failure: Error, Equatable, Sendable {
        /// What is at the path is not a real folder of the user: someone else made it first, or it is a link or a file.
        case notOwned
        /// A system call failed.
        case system(errno: Int32)
    }

    /// `/tmp/mynotch-<uid>` is in a folder every user can write to, so someone else may have made it first, or made it a link. The
    /// folder is made with `mkdir`, which fails when something is there, and then checked and changed through a descriptor opened
    /// without following a link, so nothing can be put in its place between the check and the change.
    /// - Parameter user: who must own the folder: the user who runs the app.
    public static func prepare(_ directory: URL, user: uid_t = geteuid()) throws {
        try FileManager.default.createDirectory(at: directory.deletingLastPathComponent(), withIntermediateDirectories: true)
        if mkdir(directory.path, 0o700) != 0, errno != EEXIST { throw Failure.system(errno: errno) }
        let descriptor = open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard descriptor >= 0 else { throw Failure.notOwned }
        defer { close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_uid == user else { throw Failure.notOwned }
        // `mkdir` makes it 0700 less the umask, and one that was there may be anything.
        guard fchmod(descriptor, 0o700) == 0 else { throw Failure.system(errno: errno) }
    }
}
