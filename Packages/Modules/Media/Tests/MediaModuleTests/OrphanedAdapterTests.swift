import Darwin
import Foundation
import MyNotchTestSupport
import Testing
@testable import MediaModule

/// A process table that lists what the test says and "terminates" by writing it down: no test ever signals a real process.
final class FakeProcessTable: ProcessTable {
    var entries: [ProcessEntry] = []
    private(set) var queries: [pid_t] = []
    private(set) var terminated: [pid_t] = []
    /// Runs for each query, so a test can look at what else has happened by then.
    var onQuery: () -> Void = {}

    /// Ignores `parent` on purpose: the reaper must not rely on the table having filtered.
    func processes(withParent parent: pid_t) -> [ProcessEntry] {
        queries.append(parent)
        onQuery()
        return entries
    }

    func terminate(_ pid: pid_t) { terminated.append(pid) }
}

@Suite struct OrphanedAdapterReaperTests {
    let script = "/Applications/MyNotch.app/Contents/Resources/mediaremote-adapter.pl"
    let framework = "/Applications/MyNotch.app/Contents/Frameworks/MediaRemoteAdapter.framework"
    let table = FakeProcessTable()

    var adapterArguments: [String] { [script, framework] }

    var reaper: OrphanedAdapterReaper {
        OrphanedAdapterReaper(table: table, adapterArguments: adapterArguments)
    }

    func entry(
        _ pid: pid_t, parent: pid_t = 1, user: uid_t = getuid(), arguments: [String]? = nil
    ) -> ProcessEntry {
        ProcessEntry(
            pid: pid, parentPID: parent, userID: user,
            arguments: arguments ?? ["/usr/bin/perl", script, framework, "stream", "--micros", "--debounce=100"]
        )
    }

    // MARK: what is stopped

    @Test func anAdapterStreamOfThisBundleWhoseParentIsLaunchdIsStopped() {
        table.entries = [entry(4_001)]
        #expect(reaper.reap() == [4_001])
        #expect(table.terminated == [4_001])
    }

    @Test func everyOrphanIsStoppedAndOnlyOrphans() {
        table.entries = [entry(4_001), entry(4_002, parent: 777), entry(4_003)]
        #expect(reaper.reap() == [4_001, 4_003])
        #expect(table.terminated == [4_001, 4_003])
    }

    @Test func onlyLaunchdsChildrenAreAskedFor() {
        _ = reaper.reap()
        #expect(table.queries == [1])
    }

    @Test func aStreamThatStillHasItsAppIsLeftAlone() {
        // The live stream of this very app, or of another running copy of it.
        table.entries = [entry(4_001, parent: getpid()), entry(4_002, parent: 31_337), entry(4_003, parent: 0)]
        #expect(reaper.reap().isEmpty)
        #expect(table.terminated.isEmpty)
    }

    @Test func anotherBundlesAdapterIsLeftAlone() {
        let other = "/Users/someone/Other.app/Contents/Resources/mediaremote-adapter.pl"
        table.entries = [
            entry(4_001, arguments: ["/usr/bin/perl", other, framework, "stream", "--micros"]),
            entry(4_002, arguments: ["/usr/bin/perl", script, "/elsewhere/MediaRemoteAdapter.framework", "stream"]),
            entry(4_003, arguments: ["/usr/bin/perl", script + "x", framework, "stream"]),
        ]
        #expect(reaper.reap().isEmpty)
        #expect(table.terminated.isEmpty)
    }

    @Test func onlyTheStreamIsStoppedNotAShortCommand() {
        table.entries = [
            entry(4_001, arguments: ["/usr/bin/perl", script, framework, "send", "2"]),
            entry(4_002, arguments: ["/usr/bin/perl", script, framework, "seek", "1000000"]),
            entry(4_003, arguments: ["/usr/bin/perl", script, framework]),
        ]
        #expect(reaper.reap().isEmpty)
    }

    @Test func theScriptHasToBeWhereTheAdapterPutsIt() {
        // The same words in other places of a command line are not an adapter.
        table.entries = [
            entry(4_001, arguments: ["stream", framework, script, "/usr/bin/vim"]),
            entry(4_002, arguments: [script, framework, "stream"]),
            entry(4_003, arguments: ["/usr/bin/perl", "-e", "1", script, framework, "stream"]),
            entry(4_004, arguments: []),
        ]
        #expect(reaper.reap().isEmpty)
    }

    @Test func aProcessOfAnotherUserIsLeftAlone() {
        table.entries = [entry(4_001, user: getuid() &+ 1)]
        #expect(reaper.reap().isEmpty)
        #expect(table.terminated.isEmpty)
    }

    @Test func neitherLaunchdNorThisProcessIsEverStopped() {
        table.entries = [entry(1), entry(getpid()), entry(0)]
        #expect(reaper.reap().isEmpty)
        #expect(table.terminated.isEmpty)
    }

    @Test func withNothingRunningNothingHappens() {
        #expect(reaper.reap().isEmpty)
        #expect(table.terminated.isEmpty)
    }
}

/// `AdapterProcess` runs the reaper before it launches its own stream. The fake adapters are `/bin/sh` scripts.
@Suite final class AdapterProcessOrphanTests {
    let directory: URL
    let scheduler = ManualScheduler()
    let table = FakeProcessTable()

    /// What the adapter logged. The adapter's log closure holds this, not the suite: a shell that starts after the test has
    /// ended and its folder is gone says so on stderr, and that line reaches the closure on the main actor whenever it comes.
    final class LogBox {
        var lines: [String] = []
    }

    let logBox = LogBox()
    var logs: [String] { logBox.lines }

    init() throws {
        directory = FileManager.default.temporaryDirectory.appending(path: "AdapterOrphanTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: directory) }

    var scriptPath: String { directory.appending(path: "adapter.sh").path }
    var launchesPath: String { directory.appending(path: "launches").path }
    var launches: Int { ((try? String(contentsOfFile: launchesPath, encoding: .utf8)) ?? "").split(separator: "\n").count }

    /// A fake adapter that notes each launch and then runs until it is stopped.
    func makeAdapter(table: FakeProcessTable? = nil, body: String = "sleep 30") throws -> AdapterProcess {
        try "echo $$ >> '\(launchesPath)'\n\(body)".write(toFile: scriptPath, atomically: true, encoding: .utf8)
        return AdapterProcess(
            executable: URL(filePath: "/bin/sh"), baseArguments: [scriptPath], scheduler: scheduler, killDelay: .milliseconds(100),
            processTable: table, log: { [logBox] in logBox.lines.append($0) }
        )
    }

    func start(_ adapter: AdapterProcess) {
        adapter.start(onLine: { _ in }, onFailure: { _ in })
    }

    func eventually(_ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(30)
        while !condition() {
            guard ContinuousClock.now < deadline else { return false }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return true
    }

    @Test func startStopsTheOrphansBeforeItLaunchesItsOwnStream() async throws {
        table.entries = [
            ProcessEntry(pid: 5_001, parentPID: 1, userID: getuid(), arguments: ["/bin/sh", scriptPath, "stream", "--micros", "--debounce=100"]),
        ]
        var launchesWhenAsked: [Int] = []
        table.onQuery = { [unowned self] in launchesWhenAsked.append(launches) }
        let adapter = try makeAdapter(table: table)
        defer { adapter.stop() }
        start(adapter)
        #expect(table.terminated == [5_001])
        #expect(launchesWhenAsked == [0], "the orphans go first")
        #expect(await eventually { launches == 1 })
        #expect(logs.contains { $0.contains("1") && $0.contains("left running") })
    }

    @Test func aStreamOfAnotherScriptIsNotTouchedAndNothingIsLoggedForIt() async throws {
        table.entries = [
            ProcessEntry(pid: 5_001, parentPID: 1, userID: getuid(), arguments: ["/bin/sh", "/elsewhere/adapter.sh", "stream"]),
        ]
        let adapter = try makeAdapter(table: table)
        defer { adapter.stop() }
        start(adapter)
        #expect(table.terminated.isEmpty)
        #expect(await eventually { launches == 1 })
        #expect(!logs.contains { $0.contains("left running") })
    }

    @Test func everyStartLooksButARestartAfterACrashDoesNot() async throws {
        let adapter = try makeAdapter(table: table, body: "exit 0")
        defer { adapter.stop() }
        start(adapter)
        #expect(await eventually { launches == 1 && !adapter.isStreamRunning })
        // The backoff timer relaunches the stream: its predecessor was ours, so there is nothing to look for.
        scheduler.advance(by: .seconds(1))
        #expect(await eventually { launches == 2 })
        #expect(table.queries == [1])

        adapter.stop()
        start(adapter)
        #expect(table.queries == [1, 1])
    }

    @Test func withoutATableNothingIsLookedFor() async throws {
        let adapter = try makeAdapter()
        defer { adapter.stop() }
        start(adapter)
        #expect(await eventually { launches == 1 })
        #expect(table.queries.isEmpty)
    }
}

@Suite struct SystemProcessTableTests {
    /// Reads only: this table is never asked to terminate anything.
    @Test func itSeesThisProcessWithItsParentUserAndCommandLine() throws {
        let entries = SystemProcessTable().processes(withParent: getppid())
        let entry = try #require(entries.first { $0.pid == getpid() })
        #expect(entry.parentPID == getppid())
        #expect(entry.userID == getuid())
        #expect(entry.arguments == CommandLine.arguments)
        #expect(entries.allSatisfy { $0.parentPID == getppid() })
    }

    @Test func itSeesNothingForAParentThatHasNoChildren() {
        // The highest process ID the kernel hands out is below this.
        #expect(SystemProcessTable().processes(withParent: 99_999_999).isEmpty)
    }

    @Test func theCommandLineIsReadFromTheKernelsArgumentBlock() {
        func block(argc: Int32, path: String, arguments: [String], environment: [String]) -> [UInt8] {
            var bytes = withUnsafeBytes(of: argc) { Array($0) }
            bytes += Array(path.utf8) + [0, 0, 0]
            for text in arguments + environment { bytes += Array(text.utf8) + [0] }
            return bytes
        }
        let bytes = block(argc: 3, path: "/usr/bin/perl", arguments: ["perl", "a b.pl", "stream"], environment: ["HOME=/x", "PATH=/y"])
        #expect(SystemProcessTable.parseArguments(bytes) == ["perl", "a b.pl", "stream"])
        #expect(SystemProcessTable.parseArguments(block(argc: 0, path: "/bin/x", arguments: [], environment: ["A=1"])) == [])
        // An empty argument is an argument.
        #expect(SystemProcessTable.parseArguments(block(argc: 2, path: "/bin/x", arguments: ["x", ""], environment: [])) == ["x", ""])
    }

    @Test func anArgumentBlockThatIsCutOrMadeUpIsNotTrusted() {
        #expect(SystemProcessTable.parseArguments([]) == nil)
        #expect(SystemProcessTable.parseArguments([3, 0, 0]) == nil)
        // Promises three arguments, holds one.
        #expect(SystemProcessTable.parseArguments([3, 0, 0, 0] + Array("/x".utf8) + [0, 0] + Array("x".utf8) + [0]) == nil)
        #expect(SystemProcessTable.parseArguments([255, 255, 255, 255, 0]) == nil)
        #expect(SystemProcessTable.parseArguments([1, 0, 0, 0] + Array("/x".utf8)) == nil)
    }
}
