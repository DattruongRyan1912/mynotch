import Foundation
import MyNotchCore
import MyNotchTestSupport
import Testing
@testable import AIAgentsModule

/// A temporary `~/.claude` and `~/.codex` filled with hand-written fixture lines. Nothing here touches the
/// real home directory.
final class Sandbox {
    let directory = FileManager.default.temporaryDirectory.appending(path: "AIAgentsWatcherTests-\(UUID().uuidString)")
    var claude: URL { directory.appending(path: "claude") }
    var codex: URL { directory.appending(path: "codex") }

    init() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    func createDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func write(_ text: String, to url: URL) throws {
        try createDirectory(url.deletingLastPathComponent())
        try Data(text.utf8).write(to: url)
    }

    func append(_ text: String, to url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(text.utf8))
    }

    func age(_ url: URL, byDays days: Double) throws {
        let old = Date().addingTimeInterval(-days * 86_400)
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: url.path)
    }

    // MARK: Claude

    func registryFile(pid: pid_t) -> URL {
        claude.appending(path: "sessions/\(pid).json")
    }

    func writeRegistry(pid: pid_t, sessionID: String, status: String = "busy") throws {
        let json = #"{"pid":\#(pid),"sessionId":"\#(sessionID)","cwd":"/Users/example/Projects/demo","status":"\#(status)","name":"placeholder","kind":"interactive"}"#
        try write(json, to: registryFile(pid: pid))
    }

    func transcript(_ sessionID: String) -> URL {
        claude.appending(path: "projects/-Users-example-Projects-demo/\(sessionID).jsonl")
    }

    // MARK: Codex

    func rollout(_ sessionID: String, daysAgo: Int = 0) -> URL {
        let day = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: day)
        let folder = String(format: "sessions/%04d/%02d/%02d", parts.year!, parts.month!, parts.day!)
        return codex.appending(path: "\(folder)/rollout-2026-10-14T08-00-00-\(sessionID).jsonl")
    }
}

func iso(_ date: Date = Date()) -> String {
    date.formatted(Date.ISO8601FormatStyle())
}

/// Hand-written transcript lines for the tests that need files; no real conversation text.
enum Line {
    static func prompt(_ id: String, branch: String = "main") -> String {
        #"{"type":"user","isSidechain":false,"sessionId":"\#(id)","cwd":"/Users/example/Projects/demo","gitBranch":"\#(branch)","message":{"role":"user","content":"placeholder prompt"},"timestamp":"\#(iso())"}"# + "\n"
    }

    static func tool(_ id: String, name: String = "Bash", command: String = "git status", message: String = "msg_1", output: Int = 10) -> String {
        #"{"type":"assistant","isSidechain":false,"sessionId":"\#(id)","message":{"id":"\#(message)","model":"claude-opus-4-1","role":"assistant","content":[{"type":"tool_use","id":"toolu_1","name":"\#(name)","input":{"command":"\#(command)"}}],"stop_reason":"tool_use","usage":{"input_tokens":1,"output_tokens":\#(output)}},"timestamp":"\#(iso())"}"# + "\n"
    }

    static func finish(_ id: String) -> String {
        #"{"type":"assistant","isSidechain":false,"sessionId":"\#(id)","message":{"id":"msg_9","model":"claude-opus-4-1","role":"assistant","content":[{"type":"text","text":"placeholder answer"}],"stop_reason":"end_turn","usage":{"input_tokens":1,"output_tokens":1}},"timestamp":"\#(iso())"}"# + "\n"
    }

    /// Reports one output token without naming a message, so every copy would count again.
    static func anonymousUsage(_ id: String, padding: Int = 0) -> String {
        #"{"type":"assistant","isSidechain":false,"sessionId":"\#(id)","message":{"model":"claude-opus-4-1","role":"assistant","content":[{"type":"text","text":"\#(String(repeating: "x", count: padding))"}],"usage":{"output_tokens":1}},"timestamp":"\#(iso())"}"# + "\n"
    }

    static func codexMeta(cwd: String = "/Users/example/Projects/tool", padding: Int = 0) -> String {
        #"{"timestamp":"\#(iso())","type":"session_meta","payload":{"id":"x","cwd":"\#(cwd)","instructions":"\#(String(repeating: "i", count: padding))","git":{"branch":"feature/x"}}}"# + "\n"
    }

    static let codexContext = #"{"timestamp":"\#(iso())","type":"turn_context","payload":{"model":"gpt-5-codex"}}"# + "\n"
    static func codexTurn() -> String {
        #"{"timestamp":"\#(iso())","type":"event_msg","payload":{"type":"task_started","turn_id":"t1"}}"# + "\n"
    }

    static func codexTokens(input: Int, output: Int) -> String {
        #"{"timestamp":"\#(iso())","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":\#(input),"cached_input_tokens":0,"output_tokens":\#(output),"reasoning_output_tokens":0}}}}"# + "\n"
    }
}

/// The watcher's clock moved by hand: nothing it schedules runs until the test says so. Timers run on the
/// watcher's own queue, as the real ones do, and `settle` waits for that queue, so a test that has fired a file
/// event and settled knows the watcher has seen it.
nonisolated final class ManualAgentWatcherScheduler: AgentWatcherScheduler, @unchecked Sendable {
    private nonisolated final class Beat: AgentWatchHandle {
        let stopped: @Sendable () -> Void
        init(stopped: @escaping @Sendable () -> Void) { self.stopped = stopped }
        func cancel() { stopped() }
    }

    let queue = DispatchQueue(label: "io.lucasvu.mynotch.aiagents.watcher.tests")
    private let lock = NSLock()
    private var debounces: [(delay: DispatchTimeInterval, action: @Sendable () -> Void)] = []
    private var beats: [UUID: (interval: DispatchTimeInterval, action: @Sendable () -> Void)] = [:]

    /// The delays of the one-shot timers still waiting.
    var pendingDebounces: [DispatchTimeInterval] { lock.withLock { debounces.map(\.delay) } }
    /// The intervals of the repeating timers still running.
    var heartbeats: [DispatchTimeInterval] { lock.withLock { beats.values.map(\.interval) } }

    func after(_ delay: DispatchTimeInterval, _ action: @escaping @Sendable () -> Void) {
        lock.withLock { debounces.append((delay, action)) }
    }

    func every(_ interval: DispatchTimeInterval, _ action: @escaping @Sendable () -> Void) -> any AgentWatchHandle {
        let id = UUID()
        lock.withLock { beats[id] = (interval, action) }
        return Beat { [weak self] in self?.lock.withLock { self?.beats[id] = nil } }
    }

    /// Returns once the watcher's queue has run everything handed to it so far.
    func settle() {
        queue.sync {}
    }

    /// Runs the one-shot timers that are waiting, as if their time had come, and returns how many there were.
    @discardableResult
    func fireDebounce() -> Int {
        settle()
        let due = lock.withLock {
            let due = debounces
            debounces = []
            return due
        }
        queue.sync { due.forEach { $0.action() } }
        return due.count
    }

    /// Runs one tick of every repeating timer and returns how many there were.
    @discardableResult
    func fireHeartbeat() -> Int {
        settle()
        let due = lock.withLock { beats.values.map(\.action) }
        queue.sync { due.forEach { $0() } }
        return due.count
    }
}

/// Returns once the main queue has run what was queued before this call, such as the batch a scan handed over.
func drainMainQueue() async {
    await withCheckedContinuation { continuation in
        DispatchQueue.main.async { continuation.resume() }
    }
}

/// The real file system, remembering the paths its events carried.
nonisolated final class RecordingFileSystem: AgentFileSystem, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [String] = []
    var paths: [String] { lock.withLock { recorded } }

    func watch(_ roots: [URL], onChange: @escaping @Sendable ([String]) -> Void) -> any AgentWatchHandle {
        LocalAgentFileSystem().watch(roots) { [self] paths in
            lock.withLock { recorded += paths }
            onChange(paths)
        }
    }

    func isAlive(_ session: ClaudeSessionInfo) -> Bool {
        LocalAgentFileSystem().isAlive(session)
    }
}

@Suite final class AgentWatcherTests {
    let sandbox: Sandbox
    let fileSystem = FakeAgentFileSystem()
    let scheduler = ManualAgentWatcherScheduler()
    let store: AgentSessionStore
    let session = "11111111-2222-4333-8444-555555555555"
    let codexID = "0199aaaa-bbbb-7ccc-8ddd-eeeeeeeeeeee"
    var watcher: AgentWatcher?

    init() throws {
        sandbox = try Sandbox()
        store = AgentSessionStore(scheduler: ManualScheduler())
        fileSystem.setAlive(4242)
    }

    deinit {
        watcher?.stop()
    }

    /// Starts a watcher whose timers only run when the test fires them, unless it is given the real scheduler.
    func startWatcher(
        claude: Bool = true, codex: Bool = true, fileSystem: (any AgentFileSystem)? = nil,
        scheduler: (any AgentWatcherScheduler)? = nil,
        debounce: DispatchTimeInterval = .milliseconds(100), heartbeat: DispatchTimeInterval = .seconds(60)
    ) -> AgentWatcher {
        let watcher = AgentWatcher(
            store: store, claudeRoot: claude ? sandbox.claude : nil, codexRoot: codex ? sandbox.codex : nil,
            fileSystem: fileSystem ?? self.fileSystem, debounce: debounce, heartbeat: heartbeat,
            scheduler: scheduler ?? self.scheduler
        )
        self.watcher = watcher
        watcher.start()
        return watcher
    }

    func claudeSession(_ id: String? = nil) -> AgentSession? {
        store.sessions[AgentSessionKey(source: .claude, sessionID: id ?? session)]
    }

    func codexSession() -> AgentSession? {
        store.sessions[AgentSessionKey(source: .codex, sessionID: codexID)]
    }

    /// Polls for the one test on real file system events, whose arrival has no moment to wait for. The limit only
    /// stops a broken run from hanging: it is far above any delivery time, and no test asserts on how long it took.
    func eventually(_ condition: () -> Bool) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(30)
        while clock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return condition()
    }

    func liveClaudeSession() throws {
        try sandbox.writeRegistry(pid: 4242, sessionID: session)
        try sandbox.write(Line.prompt(session) + Line.tool(session), to: sandbox.transcript(session))
    }

    // MARK: Claude

    @Test func aLiveSessionsTranscriptShowsInTheStore() async throws {
        try liveClaudeSession()
        let watcher = startWatcher()
        await watcher.rescan()
        let found = claudeSession()
        #expect(found?.state == .working(tool: "Bash", summary: "git status"))
        #expect(found?.project == "demo")
        #expect(found?.branch == "main")
        #expect(found?.usage.output == 10)
    }

    @Test func appendedLinesUpdateTheSessionWithoutRereadingOldOnes() async throws {
        try liveClaudeSession()
        let watcher = startWatcher()
        await watcher.rescan()
        try sandbox.append(Line.finish(session), to: sandbox.transcript(session))
        await watcher.rescan()
        #expect(claudeSession()?.state == .finished)
        // The tool record's usage was counted once although the file was scanned twice.
        #expect(claudeSession()?.usage.output == 11)
    }

    @Test func aFileEventRescansAfterTheDebounce() async throws {
        try liveClaudeSession()
        let watcher = startWatcher()
        await watcher.rescan()
        #expect(claudeSession() != nil)
        try sandbox.append(Line.finish(session), to: sandbox.transcript(session))
        fileSystem.fire()
        scheduler.settle()
        await drainMainQueue()
        // The event only asks for a rescan, which waits for the debounce.
        #expect(claudeSession()?.state == .working(tool: "Bash", summary: "git status"))
        #expect(scheduler.fireDebounce() == 1)
        await drainMainQueue()
        #expect(claudeSession()?.state == .finished)
    }

    @Test func aBurstOfFileEventsDoesNotStarveTheRescan() async throws {
        try liveClaudeSession()
        let watcher = startWatcher()
        await watcher.rescan()
        try sandbox.append(Line.finish(session), to: sandbox.transcript(session))
        // Events keep coming before the debounce is up: they share the rescan the first one asked for, and none
        // of them pushes it back.
        for _ in 0..<50 { fileSystem.fire() }
        scheduler.settle()
        #expect(scheduler.pendingDebounces == [.milliseconds(100)])
        #expect(scheduler.fireDebounce() == 1)
        await drainMainQueue()
        #expect(claudeSession()?.state == .finished)
        // Once it has run, the next event asks for another.
        try sandbox.append(Line.anonymousUsage(session), to: sandbox.transcript(session))
        let before = claudeSession()?.usage.output ?? 0
        fileSystem.fire()
        #expect(scheduler.fireDebounce() == 1)
        await drainMainQueue()
        #expect(claudeSession()?.usage.output == before + 1)
    }

    @Test func aTranscriptIsReadFromItsLastKilobytesOnly() async throws {
        let filler = String(repeating: Line.anonymousUsage(session, padding: 150), count: 1_000)
        try sandbox.writeRegistry(pid: 4242, sessionID: session)
        try sandbox.write(filler + Line.prompt(session) + Line.tool(session), to: sandbox.transcript(session))
        let watcher = startWatcher()
        await watcher.rescan()
        let output = claudeSession()?.usage.output ?? 0
        // 64 KB of 300-byte lines is about 220 of the thousand; the tool record adds 10.
        #expect(output > 100 && output < 400, "read \(output)")
        #expect(claudeSession()?.state == .working(tool: "Bash", summary: "git status"))
    }

    @Test func aLargeAppendIsReadInPiecesWithoutLosingALine() async throws {
        try liveClaudeSession()
        let watcher = startWatcher()
        await watcher.rescan()
        let before = claudeSession()?.usage.output ?? 0
        try sandbox.append(String(repeating: Line.anonymousUsage(session, padding: 200), count: 3_000), to: sandbox.transcript(session))
        await watcher.rescan()
        #expect(claudeSession()?.usage.output == before + 3_000)
    }

    @Test func eventsTakeTheSessionOfTheFileTheyAreIn() async throws {
        try sandbox.writeRegistry(pid: 4242, sessionID: session)
        let foreign = Line.prompt("99999999-0000-4000-8000-000000000000")
        try sandbox.write(foreign + Line.tool(session), to: sandbox.transcript(session))
        let watcher = startWatcher()
        await watcher.rescan()
        #expect(store.sessions.keys.map(\.sessionID) == [session])
    }

    @Test func sessionsOfDeadProcessesAreNotWatched() async throws {
        try liveClaudeSession()
        fileSystem.setAlive()
        let watcher = startWatcher()
        await watcher.rescan()
        #expect(store.sessions.isEmpty)
        fileSystem.setAlive(4242)
        await watcher.rescan()
        #expect(claudeSession() != nil)
    }

    @Test func aSessionEndsWhenItsRegistryFileIsRemoved() async throws {
        try liveClaudeSession()
        let watcher = startWatcher()
        await watcher.rescan()
        #expect(claudeSession() != nil)
        try FileManager.default.removeItem(at: sandbox.registryFile(pid: 4242))
        await watcher.rescan()
        #expect(claudeSession() == nil)
    }

    @Test func aProcessThatDiesWithoutTouchingFilesIsNoticedByTheHeartbeat() async throws {
        try liveClaudeSession()
        let watcher = startWatcher()
        await watcher.rescan()
        #expect(claudeSession() != nil)
        fileSystem.setAlive()
        await drainMainQueue()
        // No file changed, so nothing notices until the heartbeat ticks.
        #expect(claudeSession() != nil)
        #expect(scheduler.fireHeartbeat() == 1)
        await drainMainQueue()
        #expect(claudeSession() == nil)
    }

    @Test func aRegistryFileCaughtHalfWrittenDoesNotEndTheSession() async throws {
        try liveClaudeSession()
        let watcher = startWatcher()
        await watcher.rescan()
        let file = sandbox.registryFile(pid: 4242)
        try sandbox.write(#"{"pid":4242,"sessionI"#, to: file)
        try sandbox.append(Line.finish(session), to: sandbox.transcript(session))
        await watcher.rescan()
        #expect(claudeSession()?.state == .finished)
        try FileManager.default.removeItem(at: file)
        await watcher.rescan()
        #expect(claudeSession() == nil)
    }

    @Test func theRegistryStatusReachesTheStore() async throws {
        try sandbox.writeRegistry(pid: 4242, sessionID: session, status: "idle")
        try sandbox.write(Line.prompt(session), to: sandbox.transcript(session))
        let watcher = startWatcher()
        await watcher.rescan()
        // Idle in the registry and silent for 90 s means an interrupted turn.
        store.tick(now: Date().addingTimeInterval(91))
        #expect(claudeSession()?.state == .idle)
    }

    @Test func aTranscriptNotTouchedForADayIsIgnored() async throws {
        try liveClaudeSession()
        try sandbox.age(sandbox.transcript(session), byDays: 2)
        let watcher = startWatcher()
        await watcher.rescan()
        #expect(store.sessions.isEmpty)
    }

    @Test func aSessionWithoutATranscriptYetAppearsWhenItIsCreated() async throws {
        try sandbox.writeRegistry(pid: 4242, sessionID: session)
        let watcher = startWatcher()
        await watcher.rescan()
        #expect(store.sessions.isEmpty)
        try sandbox.write(Line.prompt(session), to: sandbox.transcript(session))
        await watcher.rescan()
        #expect(claudeSession()?.state == .working(tool: nil, summary: nil))
    }

    @Test func aRegistryEntryCannotPointOutsideTheProjects() async throws {
        try sandbox.writeRegistry(pid: 4242, sessionID: "../../../outside")
        try sandbox.write(Line.prompt("outside"), to: sandbox.directory.appending(path: "outside.jsonl"))
        let watcher = startWatcher()
        await watcher.rescan()
        #expect(store.sessions.isEmpty)
    }

    // MARK: Codex

    @Test func aNewRolloutFileIsPickedUpAndReadFromItsFirstLine() async throws {
        try sandbox.createDirectory(sandbox.codex)
        let watcher = startWatcher()
        await watcher.rescan()
        #expect(store.sessions.isEmpty)
        let file = sandbox.rollout(codexID)
        try sandbox.write(Line.codexMeta() + Line.codexContext + Line.codexTurn() + Line.codexTokens(input: 1_000, output: 50), to: file)
        fileSystem.fire()
        #expect(scheduler.fireDebounce() == 1)
        await drainMainQueue()
        let found = codexSession()
        #expect(found?.state == .working(tool: nil, summary: nil))
        #expect(found?.project == "tool")
        #expect(found?.branch == "feature/x")
        #expect(found?.usage == UsageTotals(input: 1_000, output: 50))
        #expect(store.todayUsage[.codex]?.tokens == UsageTotals(input: 1_000, output: 50))
    }

    @Test func aRolloutJoinedMidwayKeepsItsProjectButCountsOnlyNewUsageToday() async throws {
        let file = sandbox.rollout(codexID)
        let history = String(repeating: Line.codexTurn(), count: 1_000)
        try sandbox.write(Line.codexMeta(padding: 20_000) + history + Line.codexContext + Line.codexTokens(input: 50_000, output: 500), to: file)
        let watcher = startWatcher()
        await watcher.rescan()
        #expect(codexSession()?.project == "tool")
        #expect(codexSession()?.branch == "feature/x")
        #expect(codexSession()?.usage == UsageTotals(input: 50_000, output: 500))
        #expect(store.todayUsage[.codex] == nil)
        try sandbox.append(Line.codexTokens(input: 52_000, output: 560), to: file)
        await watcher.rescan()
        #expect(codexSession()?.usage == UsageTotals(input: 52_000, output: 560))
        #expect(store.todayUsage[.codex]?.tokens == UsageTotals(input: 2_000, output: 60))
    }

    @Test func rolloutsNotTouchedForADayAreIgnored() async throws {
        let file = sandbox.rollout(codexID, daysAgo: 2)
        try sandbox.write(Line.codexMeta() + Line.codexTurn(), to: file)
        try sandbox.age(file, byDays: 2)
        let watcher = startWatcher()
        await watcher.rescan()
        #expect(store.sessions.isEmpty)
    }

    @Test func aRolloutFromYesterdayThatIsStillBeingWrittenIsFollowed() async throws {
        let file = sandbox.rollout(codexID, daysAgo: 1)
        try sandbox.write(Line.codexMeta() + Line.codexTurn(), to: file)
        let watcher = startWatcher()
        await watcher.rescan()
        #expect(codexSession()?.state == .working(tool: nil, summary: nil))
    }

    @Test func filesThatAreNotRolloutsAreSkipped() async throws {
        let folder = sandbox.rollout(codexID).deletingLastPathComponent()
        try sandbox.write(Line.codexTurn(), to: folder.appending(path: "notes.jsonl"))
        try sandbox.write(Line.codexTurn(), to: folder.appending(path: "rollout-without-an-id.jsonl"))
        let watcher = startWatcher()
        await watcher.rescan()
        #expect(store.sessions.isEmpty)
    }

    // MARK: Lifecycle

    @Test func missingRootsAreSimplyOff() async throws {
        let watcher = startWatcher()
        await watcher.rescan()
        fileSystem.fire()
        await watcher.rescan()
        #expect(store.sessions.isEmpty)
        #expect(fileSystem.watchedRoots.isEmpty)
        watcher.stop()
    }

    @Test func onlyExistingRootsAreWatched() async throws {
        try sandbox.createDirectory(sandbox.claude)
        let watcher = startWatcher()
        await watcher.rescan()
        #expect(fileSystem.watchedRoots.map(\.lastPathComponent) == ["claude"])
    }

    @Test func theDebounceAndTheHeartbeatUseTheDelaysTheWatcherWasGiven() async throws {
        try liveClaudeSession()
        let watcher = startWatcher(debounce: .milliseconds(70), heartbeat: .seconds(3))
        await watcher.rescan()
        fileSystem.fire()
        scheduler.settle()
        #expect(scheduler.heartbeats == [.seconds(3)])
        #expect(scheduler.pendingDebounces == [.milliseconds(70)])
    }

    @Test func aSourceCanBeLeftOut() async throws {
        try liveClaudeSession()
        try sandbox.write(Line.codexMeta() + Line.codexTurn(), to: sandbox.rollout(codexID))
        let watcher = startWatcher(claude: false)
        await watcher.rescan()
        #expect(claudeSession() == nil)
        #expect(codexSession() != nil)
    }

    @Test func stoppingEndsTheWatching() async throws {
        try liveClaudeSession()
        let watcher = startWatcher()
        await watcher.rescan()
        #expect(fileSystem.isWatching)
        #expect(scheduler.heartbeats.count == 1)
        // An event the watcher has already seen leaves a rescan waiting for the debounce.
        try sandbox.append(Line.finish(session), to: sandbox.transcript(session))
        fileSystem.fire()
        scheduler.settle()
        #expect(scheduler.pendingDebounces.count == 1)
        watcher.stop()
        // The watch is cancelled on the watcher's own queue, so `stop` does not wait for it; a rescan queued
        // after it does.
        await watcher.rescan()
        #expect(!fileSystem.isWatching)
        #expect(scheduler.heartbeats.isEmpty)
        // The rescan that was waiting finds the watcher stopped, and later events have nobody to reach.
        fileSystem.fire()
        scheduler.fireDebounce()
        scheduler.fireHeartbeat()
        await drainMainQueue()
        #expect(claudeSession()?.state == .working(tool: "Bash", summary: "git status"))
    }

    @Test func aStoppedWatcherCanStartAgainAndReadsFromTheEndOfTheFileAgain() async throws {
        try liveClaudeSession()
        let watcher = startWatcher()
        await watcher.rescan()
        watcher.stop()
        store.removeSessions(of: .claude)
        watcher.start()
        await watcher.rescan()
        #expect(claudeSession()?.state == .working(tool: "Bash", summary: "git status"))
        #expect(claudeSession()?.usage.output == 10)
    }

    // MARK: Real file system events

    /// The only test on real FSEvents: it proves that what they report reaches the store, and that the events
    /// carry the paths the watcher filters by. Everything else drives the events and the timers by hand.
    @Test func realFileSystemEventsReachTheStore() async throws {
        try sandbox.createDirectory(sandbox.claude.appending(path: "sessions"))
        try sandbox.createDirectory(sandbox.claude.appending(path: "projects"))
        let recording = RecordingFileSystem()
        // The heartbeat is a minute away, so only the events can bring the files in.
        let watcher = startWatcher(fileSystem: recording, scheduler: QueueAgentWatcherScheduler())
        // Once this returns the watcher is running, so the files below can only reach it as events.
        await watcher.rescan()
        // The registry names this very process, which is alive.
        try sandbox.writeRegistry(pid: getpid(), sessionID: session)
        try sandbox.write(Line.prompt(session) + Line.tool(session), to: sandbox.transcript(session))
        #expect(await eventually { claudeSession()?.state == .working(tool: "Bash", summary: "git status") })
        try sandbox.append(Line.finish(session), to: sandbox.transcript(session))
        #expect(await eventually { claudeSession()?.state == .finished })
        #expect(recording.paths.contains { $0.hasSuffix("/\(session).jsonl") })
    }
}
