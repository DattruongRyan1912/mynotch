import Foundation
import MyNotchCore
import MyNotchTestSupport
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
    let scheduler = ManualAgentWatcherScheduler()
    let store = frozenStore()
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

    /// Starts a watcher whose timers only run when the test fires them.
    func startWatcher() -> AgentWatcher {
        let watcher = AgentWatcher(
            store: store, claudeRoot: sandbox.claude, codexRoot: nil, fileSystem: fileSystem,
            makeTailer: { [spy] in spy.makeTailer($0, $1) }, scheduler: scheduler
        )
        self.watcher = watcher
        watcher.start()
        return watcher
    }

    var claudeSession: AgentSession? {
        store.sessions[AgentSessionKey(source: .claude, sessionID: session)]
    }

    var transcriptName: String { "\(session).jsonl" }

    func liveSession(_ lines: String? = nil) throws {
        try sandbox.writeRegistry(pid: 4242, sessionID: session)
        try sandbox.write(lines ?? Line.prompt(session) + Line.tool(session), to: sandbox.transcript(session))
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
        // Waiting for the scan's queue holds this test on the main thread, so the batch the scan handed over is
        // still waiting for the main queue when the watcher stops.
        scheduler.settle()
        watcher.stop()
        await drainMainQueue()
        #expect(store.sessions.isEmpty)
    }

    @Test func aBatchQueuedBeforeAQuickStopAndStartIsNotDeliveredWithTheNewOne() async throws {
        // Without a message id every record counts, so a batch delivered twice would show as 2.
        try liveSession(Line.prompt(session) + Line.anonymousUsage(session))
        let watcher = startWatcher()
        scheduler.settle()
        watcher.stop()
        watcher.start()
        await watcher.rescan()
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
        // The start and the stop are on the watcher's queue ahead of this rescan, so it returns after both.
        await watcher.rescan()
        #expect(store.sessions.isEmpty)
        #expect(!fileSystem.isWatching)
        #expect(scheduler.heartbeats.isEmpty)
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
        let watcher = try await sessionWaitingForItsTranscript()
        fileSystem.fire(projects("22222222-2222-4333-8444-555555555555.jsonl"))
        fileSystem.fire(sandbox.registryFile(pid: 4242).path)
        #expect(scheduler.fireDebounce() == 1)
        await drainMainQueue()
        #expect(claudeSession == nil)
        // The transcript was there to be found: a rescan that looks for it again does find it.
        await watcher.rescan()
        #expect(claudeSession != nil)
    }

    @Test func anEventForTheTranscriptItselfSearchesAgain() async throws {
        _ = try await sessionWaitingForItsTranscript()
        fileSystem.fire(projects(transcriptName))
        #expect(scheduler.fireDebounce() == 1)
        await drainMainQueue()
        #expect(claudeSession != nil)
    }

    @Test func anEventForAFolderSearchesAgain() async throws {
        _ = try await sessionWaitingForItsTranscript()
        fileSystem.fire(sandbox.claude.appending(path: "projects/-Users-example-Projects-demo").path)
        #expect(scheduler.fireDebounce() == 1)
        await drainMainQueue()
        #expect(claudeSession != nil)
    }

    @Test func anEventWithoutPathsSearchesAgain() async throws {
        _ = try await sessionWaitingForItsTranscript()
        fileSystem.fire()
        #expect(scheduler.fireDebounce() == 1)
        await drainMainQueue()
        #expect(claudeSession != nil)
    }

    @Test func theHeartbeatSearchesAgain() async throws {
        try sandbox.writeRegistry(pid: 4242, sessionID: session)
        let watcher = startWatcher()
        await watcher.rescan()
        try sandbox.write(Line.prompt(session), to: sandbox.transcript(session))
        #expect(scheduler.fireHeartbeat() == 1)
        await drainMainQueue()
        #expect(claudeSession != nil)
    }
}
