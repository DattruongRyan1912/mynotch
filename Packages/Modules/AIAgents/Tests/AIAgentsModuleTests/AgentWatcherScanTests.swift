import Foundation
import MyNotchCore
import MyNotchTestSupport
import Synchronization
import Testing
@testable import AIAgentsModule

/// Wraps the real tailer and records every read, so a test can tell how much of a file the watcher read and how.
nonisolated final class TailerSpy: @unchecked Sendable {
    nonisolated struct Read: Equatable {
        var file: String
        var maxBytes: Int
    }

    private nonisolated final class Spied: LineTailing, @unchecked Sendable {
        let tailer: JSONLTailer
        let file: String
        let spy: TailerSpy

        init(tailer: JSONLTailer, file: String, spy: TailerSpy) {
            self.tailer = tailer
            self.file = file
            self.spy = spy
        }

        var offset: UInt64 { tailer.offset }
        var hasMoreToRead: Bool { tailer.hasMoreToRead }

        func readNewLines(maxBytes: Int) throws -> [String] {
            spy.lock.withLock { spy.recorded.append(Read(file: file, maxBytes: maxBytes)) }
            return try tailer.readNewLines(maxBytes: maxBytes)
        }
    }

    private let lock = NSLock()
    private var recorded: [Read] = []

    func reads(of file: String) -> [Read] {
        lock.withLock { recorded.filter { $0.file == file } }
    }

    func makeTailer(_ url: URL, _ startOffset: UInt64) -> any LineTailing {
        Spied(tailer: JSONLTailer(url: url, startOffset: startOffset), file: url.lastPathComponent, spy: self)
    }
}

/// What a scan costs and how the watcher stops: reads in chunks, files left alone while unchanged, transcripts
/// searched for no more than needed, and nothing delivered after a stop.
@Suite final class AgentWatcherScanTests {
    let sandbox: Sandbox
    let fileSystem = FakeAgentFileSystem()
    let store = AgentSessionStore(scheduler: ManualScheduler())
    let spy = TailerSpy()
    let session = "11111111-2222-4333-8444-555555555555"
    var watcher: AgentWatcher?

    init() throws {
        sandbox = try Sandbox()
        fileSystem.setAlive(4242)
    }

    deinit {
        watcher?.stop()
    }

    func startWatcher(heartbeat: DispatchTimeInterval = .seconds(60)) -> AgentWatcher {
        let watcher = AgentWatcher(
            store: store, claudeRoot: sandbox.claude, codexRoot: nil, fileSystem: fileSystem,
            makeTailer: { [spy] in spy.makeTailer($0, $1) }, debounce: .milliseconds(50), heartbeat: heartbeat
        )
        self.watcher = watcher
        watcher.start()
        return watcher
    }

    var claudeSession: AgentSession? {
        store.sessions[AgentSessionKey(source: .claude, sessionID: session)]
    }

    var transcriptName: String { "\(session).jsonl" }

    func waitUntil(_ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }

    func liveSession(_ lines: String? = nil) throws {
        try sandbox.writeRegistry(pid: 4242, sessionID: session)
        try sandbox.write(lines ?? Line.prompt(session) + Line.tool(session), to: sandbox.transcript(session))
    }

    /// Holds the main thread, so what a scan hands to the main queue stays queued.
    func blockMainThread(milliseconds: UInt32) {
        usleep(milliseconds * 1_000)
    }

    // MARK: Reading

    @Test func aLargeAppendIsReadInChunksOfBoundedSize() async throws {
        try liveSession()
        let watcher = startWatcher()
        await watcher.rescan()
        let before = spy.reads(of: transcriptName).count
        // About 900 KB of records the watcher has not read yet.
        try sandbox.append(String(repeating: Line.anonymousUsage(session, padding: 200), count: 3_000), to: sandbox.transcript(session))
        await watcher.rescan()
        let reads = spy.reads(of: transcriptName).dropFirst(before)
        #expect(reads.count >= 3, "read in \(reads.count) pieces")
        #expect(reads.allSatisfy { $0.maxBytes <= 256 * 1024 })
    }

    @Test func aTranscriptThatDidNotChangeIsNotReadAgain() async throws {
        try liveSession()
        let watcher = startWatcher()
        await watcher.rescan()
        let afterFirstScan = spy.reads(of: transcriptName).count
        #expect(afterFirstScan >= 1)
        await watcher.rescan()
        await watcher.rescan()
        #expect(spy.reads(of: transcriptName).count == afterFirstScan)
        try sandbox.append(Line.finish(session), to: sandbox.transcript(session))
        await watcher.rescan()
        #expect(spy.reads(of: transcriptName).count > afterFirstScan)
        #expect(claudeSession?.state == .finished)
        // And then it is left alone again.
        let afterAppend = spy.reads(of: transcriptName).count
        await watcher.rescan()
        #expect(spy.reads(of: transcriptName).count == afterAppend)
    }

    @Test func aHalfWrittenLineIsCompletedWhenTheRestArrives() async throws {
        try liveSession()
        let watcher = startWatcher()
        await watcher.rescan()
        let line = Line.finish(session)
        let cut = line.index(line.startIndex, offsetBy: line.count / 2)
        try sandbox.append(String(line[..<cut]), to: sandbox.transcript(session))
        await watcher.rescan()
        #expect(claudeSession?.state == .working(tool: "Bash", summary: "git status"))
        try sandbox.append(String(line[cut...]), to: sandbox.transcript(session))
        await watcher.rescan()
        #expect(claudeSession?.state == .finished)
    }

    @Test func aSessionWhoseRegistryFileWasRemovedIsNoLongerRead() async throws {
        try liveSession()
        let watcher = startWatcher()
        await watcher.rescan()
        try FileManager.default.removeItem(at: sandbox.registryFile(pid: 4242))
        await watcher.rescan()
        #expect(claudeSession == nil)
        let reads = spy.reads(of: transcriptName).count
        try sandbox.append(Line.anonymousUsage(session), to: sandbox.transcript(session))
        await watcher.rescan()
        await watcher.rescan()
        #expect(spy.reads(of: transcriptName).count == reads)
        #expect(claudeSession == nil)
    }

    // MARK: Stopping

    @Test func aBatchTheScanQueuedBeforeAStopIsDropped() async throws {
        try liveSession()
        let watcher = startWatcher()
        // The scan finishes while the main thread is busy, so its batch is still waiting for the main queue.
        blockMainThread(milliseconds: 400)
        watcher.stop()
        try await Task.sleep(for: .milliseconds(100))
        #expect(store.sessions.isEmpty)
    }

    @Test func aBatchQueuedBeforeAQuickStopAndStartIsNotDeliveredWithTheNewOne() async throws {
        // Without a message id every record counts, so a batch delivered twice would show as 2.
        try liveSession(Line.prompt(session) + Line.anonymousUsage(session))
        let watcher = startWatcher()
        blockMainThread(milliseconds: 400)
        watcher.stop()
        watcher.start()
        await watcher.rescan()
        try await Task.sleep(for: .milliseconds(100))
        #expect(claudeSession?.usage.output == 1)
    }

    @Test func stoppingTwiceOrBeforeStartingIsHarmless() async throws {
        let watcher = startWatcher()
        watcher.stop()
        watcher.stop()
        try liveSession()
        watcher.start()
        await watcher.rescan()
        #expect(claudeSession != nil)
    }

    @Test func startImmediatelyFollowedByStopLeavesTheWatcherStopped() async throws {
        try liveSession()
        let watcher = startWatcher()
        watcher.stop()
        await watcher.rescan()
        try await Task.sleep(for: .milliseconds(100))
        #expect(store.sessions.isEmpty)
        #expect(await waitUntil { !fileSystem.isWatching })
    }

    // MARK: Finding transcripts

    /// A live session whose transcript does not exist yet, searched for once.
    func sessionWaitingForItsTranscript() async throws -> AgentWatcher {
        try sandbox.writeRegistry(pid: 4242, sessionID: session)
        try sandbox.createDirectory(sandbox.claude.appending(path: "projects/-Users-example-Projects-demo"))
        let watcher = startWatcher()
        await watcher.rescan()
        try sandbox.write(Line.prompt(session), to: sandbox.transcript(session))
        return watcher
    }

    func projects(_ name: String) -> String {
        sandbox.claude.appending(path: "projects/-Users-example-Projects-demo/\(name)").path
    }

    @Test func aMissingTranscriptIsNotSearchedForAgainByEventsThatCannotHaveCreatedIt() async throws {
        _ = try await sessionWaitingForItsTranscript()
        fileSystem.fire(projects("22222222-2222-4333-8444-555555555555.jsonl"))
        fileSystem.fire(sandbox.registryFile(pid: 4242).path)
        try await Task.sleep(for: .milliseconds(300))
        #expect(claudeSession == nil)
    }

    @Test func anEventForTheTranscriptItselfSearchesAgain() async throws {
        _ = try await sessionWaitingForItsTranscript()
        fileSystem.fire(projects(transcriptName))
        #expect(await waitUntil { claudeSession != nil })
    }

    @Test func anEventForAFolderSearchesAgain() async throws {
        _ = try await sessionWaitingForItsTranscript()
        fileSystem.fire(sandbox.claude.appending(path: "projects/-Users-example-Projects-demo").path)
        #expect(await waitUntil { claudeSession != nil })
    }

    @Test func anEventWithoutPathsSearchesAgain() async throws {
        _ = try await sessionWaitingForItsTranscript()
        fileSystem.fire()
        #expect(await waitUntil { claudeSession != nil })
    }

    @Test func theHeartbeatSearchesAgain() async throws {
        try sandbox.writeRegistry(pid: 4242, sessionID: session)
        let watcher = startWatcher(heartbeat: .milliseconds(100))
        await watcher.rescan()
        try sandbox.write(Line.prompt(session), to: sandbox.transcript(session))
        #expect(await waitUntil { claudeSession != nil })
    }
}

/// The real file system events carry the paths that changed.
@Suite struct LocalAgentFileSystemTests {
    @Test func eventsCarryTheChangedPaths() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "LocalAgentFileSystemTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let seen = Mutex<[String]>([])
        let handle = LocalAgentFileSystem().watch([directory]) { paths in seen.withLock { $0 += paths } }
        defer { handle.cancel() }
        // Let the stream start before the file is written.
        try await Task.sleep(for: .milliseconds(300))
        try Data("x".utf8).write(to: directory.appending(path: "transcript.jsonl"))
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline, !seen.withLock({ $0.contains { $0.hasSuffix("/transcript.jsonl") } }) {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(seen.withLock { $0.contains { $0.hasSuffix("/transcript.jsonl") } })
    }
}
