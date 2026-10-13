import Foundation
import MyNotchTestSupport
import Testing
@testable import SystemActivitiesModule

/// Only temporary folders: nothing here reads the real Downloads folder, so no permission prompt can appear.
@Suite final class DownloadsWatcherTests {
    let scheduler = ManualScheduler()
    var directories: [URL] = []

    isolated deinit {
        for directory in directories {
            _ = try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)
            try? FileManager.default.removeItem(at: directory)
        }
    }

    func tempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("MyNotchTests.\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        directories.append(url)
        return url
    }

    func watcher(on directory: URL) -> DownloadsWatcher {
        DownloadsWatcher(directory: directory, scheduler: scheduler)
    }

    @Test func startsOnAReadableFolderAndStopsCleanly() throws {
        let watcher = watcher(on: try tempDirectory())
        #expect(watcher.start { _ in })
        watcher.stop()
    }

    /// Reading the folder is what makes macOS ask for access to Downloads; a denial then fails the start.
    @Test func startFailsWhenTheFolderIsMissing() throws {
        let missing = try tempDirectory().appendingPathComponent("nope")
        let watcher = watcher(on: missing)
        #expect(!watcher.start { _ in })
        watcher.stop()
    }

    @Test func startFailsWhenTheFolderCannotBeRead() throws {
        let directory = try tempDirectory()
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: directory.path)
        let watcher = watcher(on: directory)
        #expect(!watcher.start { _ in })
        watcher.stop()
    }

    @Test func aLateEventAfterStopSchedulesNothing() throws {
        let directory = try tempDirectory()
        let file = directory.appendingPathComponent("a.zip")
        try Data([1]).write(to: file)
        let origin = Array("0083;00000000;Safari;".utf8)
        #expect(setxattr(file.path, "com.apple.quarantine", origin, origin.count, 0, 0) == 0)

        let watcher = watcher(on: directory)
        #expect(watcher.start { _ in })
        watcher.stop()
        watcher.receive([(path: file.path, flags: 0)])
        #expect(scheduler.pendingCount == 0)
    }
}
