import Foundation
import os

/// Temporary folders for tests. Each is named `MyNotchTests-<label>-<uuid>`, the prefix `scripts/verify.sh` sweeps
/// after a run that crashed, and is deleted with its contents when the test process exits. A test cannot do that
/// itself when a shared helper hands the folder to many tests, or when a module writes to it after the test ended.
public nonisolated final class ScratchFolders: Sendable {
    /// What the test helpers use; removed at process exit.
    public static let shared: ScratchFolders = {
        let folders = ScratchFolders()
        atexit { ScratchFolders.shared.removeAll() }
        return folders
    }()

    private let reserved = OSAllocatedUnfairLock(initialState: [URL]())

    public init() {}

    /// A unique path under the temporary directory. Nothing is created: the caller creates the folder, or leaves
    /// that to the code under test.
    public func reserve(_ label: String = "") -> URL {
        let name = label.isEmpty ? "MyNotchTests-\(UUID().uuidString)" : "MyNotchTests-\(label)-\(UUID().uuidString)"
        let url = FileManager.default.temporaryDirectory.appending(path: name, directoryHint: .isDirectory)
        reserved.withLock { $0.append(url) }
        return url
    }

    /// Deletes every folder reserved so far and forgets them.
    public func removeAll() {
        let urls = reserved.withLock { urls in
            defer { urls = [] }
            return urls
        }
        for url in urls { try? FileManager.default.removeItem(at: url) }
    }
}
