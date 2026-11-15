import Foundation

/// Puts the `mynotch-hook` helper where the agents' hooks run it from.
enum HookHelper {
    struct Unavailable: LocalizedError {
        var path: String

        var errorDescription: String? { "Không có mynotch-hook chạy được tại \(path)." }
    }

    /// Copies the helper out of the app bundle, which moves and is replaced on update, to a path that stays. Throws
    /// when the helper is missing or not executable, so no hook is written that would fail on every event.
    static func install(from source: URL, to destination: URL) throws {
        let fileManager = FileManager.default
        guard fileManager.isExecutableFile(atPath: source.path) else { throw Unavailable(path: source.path) }
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        // A hook that starts in between finds no file, which its guard turns into a quiet exit.
        if fileManager.fileExists(atPath: destination.path) { try fileManager.removeItem(at: destination) }
        try fileManager.copyItem(at: source, to: destination)
        guard fileManager.isExecutableFile(atPath: destination.path) else { throw Unavailable(path: destination.path) }
    }
}
