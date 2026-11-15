import Foundation
import os

/// A `MyNotchTests.` suite that empties itself when released and whose plist is deleted after the process ends.
/// The plist cannot be deleted straight away: cfprefsd writes the emptied domain back several seconds after the
/// removal and recreates a file deleted earlier. A test process rarely lives that long, so the files go to a
/// detached `sh` that outlives it.
public final class IsolatedUserDefaults: UserDefaults {
    /// Nothing outside this prefix is ever emptied or deleted.
    private nonisolated static let prefix = "MyNotchTests."
    /// Longer than cfprefsd takes to write the removal back, with room to spare when the machine is busy.
    private nonisolated static let sweepDelaySeconds = 20
    private nonisolated static let plists = OSAllocatedUnfairLock(initialState: Set<String>())

    public nonisolated let suite: String

    /// Fails for a name without the `MyNotchTests.` prefix, or with a `/` that could point the plist outside the
    /// preferences folder, so this class can never touch real preferences.
    public nonisolated override init?(suiteName suite: String?) {
        guard let suite, suite.hasPrefix(Self.prefix), !suite.contains("/") else { return nil }
        self.suite = suite
        super.init(suiteName: suite)
        Self.track(plist: URL.libraryDirectory.appending(path: "Preferences/\(suite).plist").path)
    }

    deinit {
        removePersistentDomain(forName: suite)
    }

    private nonisolated static func track(plist: String) {
        let first = plists.withLock { plists in
            plists.insert(plist)
            return plists.count == 1
        }
        if first { atexit { IsolatedUserDefaults.sweepAfterExit() } }
    }

    private nonisolated static func sweepAfterExit() {
        let paths = plists.withLock { $0 }.sorted()
        let sweeper = Process()
        sweeper.executableURL = URL(filePath: "/bin/sh")
        sweeper.arguments = ["-c", "sleep \(sweepDelaySeconds); rm -f -- \"$@\"", "sh"] + paths
        sweeper.standardInput = FileHandle.nullDevice
        sweeper.standardOutput = FileHandle.nullDevice
        sweeper.standardError = FileHandle.nullDevice
        try? sweeper.run()
    }
}

/// A fresh, empty UserDefaults suite per call, removed when released.
public func makeIsolatedDefaults() -> UserDefaults {
    IsolatedUserDefaults(suiteName: "MyNotchTests.\(UUID().uuidString)")!
}
