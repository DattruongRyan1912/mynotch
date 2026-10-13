import Foundation
import MyNotchTestSupport
import Testing
import os
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

    @Test func startsOnAReadableFolderAndStopsCleanly() async throws {
        let watcher = watcher(on: try tempDirectory())
        #expect(await watcher.start { _ in })
        #expect(watcher.isWatching)
        watcher.stop()
        #expect(!watcher.isWatching)
    }

    /// Reading the folder is what makes macOS ask for access to Downloads; a denial then fails the start.
    @Test func startFailsWhenTheFolderIsMissing() async throws {
        let missing = try tempDirectory().appendingPathComponent("nope")
        let watcher = watcher(on: missing)
        #expect(!(await watcher.start { _ in }))
        #expect(!watcher.isWatching)
        watcher.stop()
    }

    @Test func startFailsWhenTheFolderCannotBeRead() async throws {
        let directory = try tempDirectory()
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: directory.path)
        let watcher = watcher(on: directory)
        #expect(!(await watcher.start { _ in }))
        #expect(!watcher.isWatching)
        watcher.stop()
    }

    /// The first read of Downloads blocks until the user answers macOS's prompt, so it must not run on the main thread.
    @Test func theFolderIsProbedOffTheMainThread() async throws {
        let probedOnMain = OSAllocatedUnfairLock<Bool?>(initialState: nil)
        let watcher = DownloadsWatcher(directory: try tempDirectory(), scheduler: scheduler, probe: { _ in
            probedOnMain.withLock { $0 = Thread.isMainThread }
            return true
        })
        #expect(await watcher.start { _ in })
        #expect(probedOnMain.withLock { $0 } == false)
        watcher.stop()
    }

    @Test func theMainActorStaysFreeWhileTheProbeIsBlocked() async throws {
        let prompt = DispatchSemaphore(value: 0)
        // A probe that ran on the main thread would wait out the timeout and fail the start below.
        let watcher = DownloadsWatcher(directory: try tempDirectory(), scheduler: scheduler, probe: { _ in
            prompt.wait(timeout: .now() + 5) == .success
        })
        let start = Task { await watcher.start { _ in } }
        await Task.yield()
        #expect(!watcher.isWatching)
        prompt.signal()
        #expect(await start.value)
        #expect(watcher.isWatching)
        watcher.stop()
    }

    @Test func aStartCancelledBeforeItBeginsNeitherProbesNorWatches() async throws {
        let probes = OSAllocatedUnfairLock(initialState: 0)
        let watcher = DownloadsWatcher(directory: try tempDirectory(), scheduler: scheduler, probe: { _ in
            probes.withLock { $0 += 1 }
            return true
        })
        let start = Task { await watcher.start { _ in } }
        start.cancel()
        #expect(!(await start.value))
        #expect(probes.withLock { $0 } == 0)
        #expect(!watcher.isWatching)
    }

    @Test func aStartCancelledWhileProbingDoesNotWatch() async throws {
        let prompt = DispatchSemaphore(value: 0)
        let watcher = DownloadsWatcher(directory: try tempDirectory(), scheduler: scheduler, probe: { _ in
            prompt.wait(timeout: .now() + 5) == .success
        })
        let start = Task { await watcher.start { _ in } }
        await Task.yield()
        start.cancel()
        prompt.signal()
        #expect(!(await start.value))
        #expect(!watcher.isWatching)
    }

    @Test func aLateEventAfterStopSchedulesNothing() async throws {
        let directory = try tempDirectory()
        let file = directory.appendingPathComponent("a.zip")
        try Data([1]).write(to: file)
        let origin = Array("0083;00000000;Safari;".utf8)
        #expect(setxattr(file.path, "com.apple.quarantine", origin, origin.count, 0, 0) == 0)

        let watcher = watcher(on: directory)
        #expect(await watcher.start { _ in })
        watcher.stop()
        watcher.receive([(path: file.path, flags: 0)])
        #expect(scheduler.pendingCount == 0)
    }
}
