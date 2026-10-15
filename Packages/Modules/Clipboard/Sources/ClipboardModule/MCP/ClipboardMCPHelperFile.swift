import Foundation

/// Puts the `mynotch-clipboard-mcp` helper where the agents' configuration points to: the app bundle moves and is replaced on
/// update, so the agents get a copy in the module's own folder, which stays.
nonisolated enum ClipboardMCPHelperFile {
    static let name = "mynotch-clipboard-mcp"

    nonisolated struct Unavailable: LocalizedError {
        var path: String

        var errorDescription: String? { "Không có \(ClipboardMCPHelperFile.name) chạy được tại \(path)." }
    }

    /// `<module storage>/bin/mynotch-clipboard-mcp`
    static func destination(in storage: URL) -> URL {
        storage.appending(path: "bin/\(name)")
    }

    /// The copy the running app carries, in `Contents/MacOS` beside the app's own executable.
    static func installFromBundle(to destination: URL) throws {
        try install(from: Bundle.main.bundleURL.appending(path: "Contents/MacOS/\(name)"), to: destination)
    }

    /// Throws when the helper is missing or not executable, before anything of the old copy is touched, so a copy that works
    /// is never replaced by nothing.
    static func install(from source: URL, to destination: URL) throws {
        let fileManager = FileManager.default
        guard fileManager.isExecutableFile(atPath: source.path) else { throw Unavailable(path: source.path) }
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        // An agent that starts the helper in between finds no file, which it reports as a server that did not start.
        if fileManager.fileExists(atPath: destination.path) { try fileManager.removeItem(at: destination) }
        try fileManager.copyItem(at: source, to: destination)
        guard fileManager.isExecutableFile(atPath: destination.path) else { throw Unavailable(path: destination.path) }
    }
}
