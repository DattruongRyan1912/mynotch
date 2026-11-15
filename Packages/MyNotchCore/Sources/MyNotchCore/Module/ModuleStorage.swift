import Foundation

/// A module's own folders for data too large for `SettingsStore`, such as history or images.
/// Nothing is created until `ensureDirectories()`, so modules that never write leave nothing on disk.
nonisolated public struct ModuleStorage: Sendable {
    /// Durable data: `<applicationSupport>/Modules/<id>/`.
    public let directory: URL
    /// Data the module can rebuild; the system may purge it: `<caches>/Modules/<id>/`.
    public let cachesDirectory: URL

    public init(directory: URL, cachesDirectory: URL) {
        self.directory = directory
        self.cachesDirectory = cachesDirectory
    }

    /// Creates both folders if missing; safe to call on every start.
    public func ensureDirectories() throws {
        for url in [directory, cachesDirectory] {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }
}

/// Base folders that hold every module's storage; injected so tests can use a temporary directory.
nonisolated public struct StorageRoot: Sendable {
    public let applicationSupport: URL
    public let caches: URL

    public init(applicationSupport: URL, caches: URL) {
        self.applicationSupport = applicationSupport
        self.caches = caches
    }

    /// ~/Library/Application Support/<bundleID> and ~/Library/Caches/<bundleID>
    public static func standard(bundleID: String) -> StorageRoot {
        StorageRoot(
            applicationSupport: .applicationSupportDirectory.appending(path: bundleID, directoryHint: .isDirectory),
            caches: .cachesDirectory.appending(path: bundleID, directoryHint: .isDirectory)
        )
    }

    public func storage(for id: ModuleID) -> ModuleStorage {
        ModuleStorage(
            directory: applicationSupport.appending(components: "Modules", id.rawValue, directoryHint: .isDirectory),
            cachesDirectory: caches.appending(components: "Modules", id.rawValue, directoryHint: .isDirectory)
        )
    }
}
