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

    /// A unique path `/tmp/mn-<8 hex digits>` for the folder of a Unix socket. A `sockaddr_un` path holds 103 bytes, and the
    /// path of `reserve` (the per-user temporary folder, the label and a UUID) leaves no room for a file name in it. Nothing is
    /// created, and the folder is deleted with its contents at process exit like the others, so a test that forgets, or
    /// fails before its own clean-up, leaves nothing behind. `mn-` followed by 8 characters is the name to sweep for after a
    /// run that was killed.
    public func reserveShort() -> URL {
        let url = URL(filePath: "/tmp/mn-\(UUID().uuidString.prefix(8))", directoryHint: .isDirectory)
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
