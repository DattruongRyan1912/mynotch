import Foundation
import Synchronization

/// A counter shared with the closures that run on a server's private queue. Work that queue hands to the main thread
/// cannot be recalled when the server stops; `stop` advances this instead, and the work that finds another value is
/// dropped.
nonisolated final class ServerGeneration: Sendable {
    private let value = Mutex(0)
    var current: Int { value.withLock { $0 } }
    func advance() { value.withLock { $0 += 1 } }
}

/// The folder the app's sockets live in: the user's own and closed to everyone else.
enum PrivateDirectory {
    /// One that exists is checked before anything is created or changed in it: `/tmp/mynotch-<uid>` is in a folder
    /// every user can write to, so someone else may have made it first.
    static func prepare(_ directory: URL) throws {
        var info = stat()
        if stat(directory.path, &info) == 0, info.st_uid != geteuid() { throw AgentEventServer.StartError.directoryNotOwned }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // `attributes` of `createDirectory` apply only to a directory it creates.
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    }
}
