import Darwin
import Foundation
import MyNotchTestSupport
import Testing
@testable import MediaModule

/// Runs fake adapters as `/bin/sh` scripts; `$@` holds the adapter command, e.g. `stream --micros --debounce=100`.
@Suite final class AdapterProcessTests {
    final class Recorder {
        var lines: [String] = []
        var linesOnMainThread: [Bool] = []
        var failures: [String] = []
        var logs: [String] = []
    }

    let directory: URL
    let scheduler = ManualScheduler()
    let recorder = Recorder()

    init() throws {
        directory = FileManager.default.temporaryDirectory.appending(path: "AdapterProcessTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: directory) }

    func path(_ name: String) -> String { directory.appending(path: name).path }

    func contents(_ name: String) -> String { (try? String(contentsOfFile: path(name), encoding: .utf8)) ?? "" }

    /// Each fake adapter appends its process ID here when it launches (`exec` keeps the ID).
    var pids: [pid_t] { contents("launches").split(separator: "\n").compactMap { pid_t($0) } }
    var launches: Int { pids.count }

    func makeAdapter(_ body: String, killDelay: Duration = .seconds(1)) throws -> AdapterProcess {
        let script = directory.appending(path: "adapter.sh")
        try ("echo $$ >> '\(path("launches"))'\n" + body).write(to: script, atomically: true, encoding: .utf8)
        let recorder = recorder
        return AdapterProcess(
            executable: URL(filePath: "/bin/sh"), baseArguments: [script.path],
            scheduler: scheduler, killDelay: killDelay, log: { recorder.logs.append($0) }
        )
    }

    func start(_ adapter: AdapterProcess) {
        let recorder = recorder
        adapter.start(
            onLine: { line in
                recorder.lines.append(line)
                recorder.linesOnMainThread.append(Thread.isMainThread)
            },
            onFailure: { recorder.failures.append($0) }
        )
    }

    /// Lets the process and its callbacks run until `condition` holds. The limit only matters when something is
    /// wrong, so it is generous: starting a shell can take seconds on a machine that is very busy.
    func eventually(_ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(30)
        while !condition() {
            guard ContinuousClock.now < deadline else { return false }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return true
    }

    /// Waits until the current launch has run and its exit has been handled.
    func exited(_ adapter: AdapterProcess, launches count: Int) async -> Bool {
        await eventually { launches == count && !adapter.isStreamRunning }
    }

    /// A fake adapter that runs until the test creates `release`, then exits with `status`.
    func releasable(exitStatus status: Int32) throws -> AdapterProcess {
        try makeAdapter("while [ ! -f '\(path("release"))' ]; do sleep 0.02; done\nexit \(status)")
    }

    func release(_ adapter: AdapterProcess, launches count: Int) async -> Bool {
        FileManager.default.createFile(atPath: path("release"), contents: nil)
        defer { try? FileManager.default.removeItem(atPath: path("release")) }
        return await exited(adapter, launches: count)
    }

    func processIsGone(_ pid: pid_t) -> Bool { kill(pid, 0) != 0 && errno == ESRCH }

    /// Lets late output and exit callbacks of finished processes reach the main actor.
    func settle() async throws { try await Task.sleep(for: .milliseconds(200)) }


    @Test func deliversCompleteLinesInOrderOnTheMainActor() async throws {
        let adapter = try makeAdapter(#"""
            printf '{"n":1}\n{"n":'
            sleep 0.1
            printf '2}\n{"n":3}\n'
            exec sleep 30
            """#)
        start(adapter)
        defer { adapter.stop() }

        #expect(await eventually { recorder.lines.count == 3 })
        #expect(recorder.lines == [#"{"n":1}"#, #"{"n":2}"#, #"{"n":3}"#])
        #expect(recorder.linesOnMainThread == [true, true, true])
        #expect(recorder.failures.isEmpty)
        #expect(adapter.isStreamRunning)
    }

    @Test func flushesAnUnterminatedLastLineAtTheEnd() async throws {
        let adapter = try makeAdapter("printf 'first\\nlast'")
        start(adapter)
        defer { adapter.stop() }

        #expect(await eventually { recorder.lines == ["first", "last"] })
    }

    @Test func forwardsStandardErrorToTheLog() async throws {
        let adapter = try makeAdapter("echo 'first problem' >&2\necho 'second problem' >&2\nexec sleep 30")
        start(adapter)
        defer { adapter.stop() }

        #expect(await eventually { recorder.logs.contains("second problem") })
        let first = try #require(recorder.logs.firstIndex(of: "first problem"))
        let second = try #require(recorder.logs.firstIndex(of: "second problem"))
        #expect(first < second)
        #expect(recorder.lines.isEmpty)
        #expect(adapter.isStreamRunning)
    }

    @Test func passesTheStreamArgumentsAfterTheScript() async throws {
        let adapter = try makeAdapter(#"echo "$@" > '\#(path("arguments"))'"#)
        start(adapter)
        defer { adapter.stop() }

        #expect(await exited(adapter, launches: 1))
        #expect(contents("arguments") == "stream --micros --debounce=100\n")
    }

    @Test func removesVariablesThatChangePerlOrTheAdapter() {
        let environment = [
            "HOME": "/Users/me", "PATH": "/usr/bin:/bin", "LANG": "vi_VN.UTF-8",
            "PERL5OPT": "-MEvil", "PERL5LIB": "/tmp/lib", "PERLLIB": "/tmp/lib", "PERL5DB": "BEGIN {}",
            "ADAPTER_TEST_MODE": "1",
            "MEDIAREMOTEADAPTER_OPTION_no-artwork": "", "MEDIAREMOTEADAPTER_PARAM_adapter_send_0_command": "3",
            "MEDIAREMOTEADAPTER_TEST_CLIENT_PATH": "/tmp/client", "PERL_UNICODE": "S", "mediaremoteadapter_x": "kept",
        ]
        #expect(AdapterProcess.adapterEnvironment(from: environment) == [
            "HOME": "/Users/me", "PATH": "/usr/bin:/bin", "LANG": "vi_VN.UTF-8", "PERL_UNICODE": "S", "mediaremoteadapter_x": "kept",
        ])
    }


    @Test func restartsAfterAnUnexpectedExitWithGrowingBackoff() async throws {
        let adapter = try makeAdapter("exit 0")
        start(adapter)
        defer { adapter.stop() }

        #expect(await exited(adapter, launches: 1))
        scheduler.advance(by: .milliseconds(999))
        #expect(adapter.launchCount == 1)
        scheduler.advance(by: .milliseconds(1))
        #expect(adapter.launchCount == 2)
        #expect(await exited(adapter, launches: 2))

        scheduler.advance(by: .milliseconds(1_999))
        #expect(adapter.launchCount == 2)
        scheduler.advance(by: .milliseconds(1))
        #expect(await exited(adapter, launches: 3))
        #expect(recorder.failures.isEmpty)

        adapter.stop()
        #expect(scheduler.pendingCount == 0)
        scheduler.advance(by: .seconds(60))
        #expect(adapter.launchCount == 3)
    }

    @Test func backoffDoublesUpToThirtySeconds() {
        let delays = (0..<8).map(AdapterProcess.restartDelay(attempt:))
        #expect(delays == [1, 2, 4, 8, 16, 30, 30, 30].map { .seconds($0) })
    }

    @Test func givesUpAfterThreeFailedStartsInARow() async throws {
        let adapter = try makeAdapter("echo 'adapter broke' >&2\nexit 1")
        start(adapter)
        defer { adapter.stop() }

        #expect(await exited(adapter, launches: 1))
        scheduler.advance(by: .seconds(1))
        #expect(await exited(adapter, launches: 2))
        #expect(recorder.failures.isEmpty)
        scheduler.advance(by: .seconds(2))
        #expect(await eventually { recorder.failures.count == 1 })
        #expect(await exited(adapter, launches: 3))

        scheduler.advance(by: .seconds(120))
        try await settle()
        #expect(launches == 3)
        #expect(adapter.launchCount == 3)
        #expect(scheduler.pendingCount == 0)
        #expect(recorder.failures.count == 1)
        #expect(recorder.logs.contains("adapter broke"))
    }

    @Test func signalKilledStartsCountAsFailedStarts() async throws {
        let adapter = try makeAdapter("kill -KILL $$")
        start(adapter)
        defer { adapter.stop() }

        #expect(await exited(adapter, launches: 1))
        scheduler.advance(by: .seconds(1))
        #expect(await exited(adapter, launches: 2))
        scheduler.advance(by: .seconds(2))
        #expect(await eventually { recorder.failures.count == 1 })
        #expect(recorder.failures.first?.contains("signal 9") == true)
        #expect(scheduler.pendingCount == 0)
    }

    @Test func deliversNothingAfterGivingUp() async throws {
        // The background subshell keeps stdout open and writes after the adapter has exited.
        let adapter = try makeAdapter("(sleep 0.1; echo late) &\nexit 1")
        start(adapter)
        defer { adapter.stop() }

        #expect(await eventually { recorder.lines.count == 1 && !adapter.isStreamRunning })
        scheduler.advance(by: .seconds(1))
        #expect(await eventually { recorder.lines.count == 2 && !adapter.isStreamRunning })
        scheduler.advance(by: .seconds(2))
        #expect(await eventually { recorder.failures.count == 1 })
        #expect(await eventually { launches == 3 })
        try await settle()
        #expect(recorder.lines == ["late", "late"])
    }

    @Test func missingExecutableGivesUpAfterThreeAttempts() {
        let adapter = AdapterProcess(
            executable: directory.appending(path: "missing-perl"), baseArguments: [],
            scheduler: scheduler, log: { [recorder] in recorder.logs.append($0) }
        )
        start(adapter)
        defer { adapter.stop() }

        scheduler.advance(by: .seconds(1))
        scheduler.advance(by: .seconds(2))
        #expect(adapter.launchCount == 3)
        #expect(recorder.failures.count == 1)
        scheduler.advance(by: .seconds(120))
        #expect(adapter.launchCount == 3)
        #expect(!recorder.logs.isEmpty)
    }

    @Test func onlyFailuresRightAfterLaunchCountAndUptimeResetsTheBackoff() async throws {
        let adapter = try releasable(exitStatus: 1)
        start(adapter)
        defer { adapter.stop() }

        #expect(await eventually { launches == 1 })
        #expect(await release(adapter, launches: 1))
        scheduler.advance(by: .seconds(1))
        #expect(await eventually { launches == 2 })
        #expect(await release(adapter, launches: 2))
        scheduler.advance(by: .seconds(2))
        #expect(await eventually { launches == 3 })

        // Up for a minute: this failure is not a failed start, and the backoff starts over at 1 s.
        scheduler.advance(by: .seconds(60))
        #expect(await release(adapter, launches: 3))
        #expect(recorder.failures.isEmpty)
        scheduler.advance(by: .seconds(1))
        #expect(adapter.launchCount == 4)
    }


    @Test func stopTerminatesTheStreamAndNeverRestarts() async throws {
        // The kill fallback is far away, so only SIGTERM can end the process within the wait.
        let adapter = try makeAdapter("exec sleep 30", killDelay: .seconds(30))
        start(adapter)
        #expect(await eventually { launches == 1 })
        let pid = try #require(pids.first)

        adapter.stop()
        #expect(!adapter.isStreamRunning)
        #expect(await eventually { processIsGone(pid) })
        try await settle()
        scheduler.advance(by: .seconds(120))
        #expect(scheduler.pendingCount == 0)
        #expect(adapter.launchCount == 1)
        #expect(launches == 1)
        #expect(recorder.failures.isEmpty)
    }

    @Test func stopKillsAnAdapterThatIgnoresSIGTERM() async throws {
        let adapter = try makeAdapter("trap '' TERM\nexec sleep 30", killDelay: .milliseconds(200))
        start(adapter)
        #expect(await eventually { launches == 1 })
        let pid = try #require(pids.first)

        adapter.stop()
        #expect(await eventually { processIsGone(pid) })
    }

    /// The first launch prints a line when it gets SIGTERM, so its output arrives after the second launch started.
    func replaceableAdapter() throws -> AdapterProcess {
        try makeAdapter("""
            if [ ! -f '\(path("replaced"))' ]; then
                touch '\(path("replaced"))'
                trap 'echo replaced; exit 0' TERM
                while :; do sleep 0.02; done
            fi
            exec sleep 30
            """, killDelay: .seconds(30))
    }

    @Test func startingAgainTerminatesThePreviousProcess() async throws {
        let adapter = try replaceableAdapter()
        start(adapter)
        defer { adapter.stop() }
        #expect(await eventually { launches == 1 })
        let first = try #require(pids.first)

        start(adapter)
        #expect(await eventually { launches == 2 && processIsGone(first) })
        try await settle()
        #expect(adapter.isStreamRunning)
        scheduler.advance(by: .seconds(1))
        #expect(adapter.launchCount == 2)
    }

    @Test func linesFromAReplacedLaunchAreDropped() async throws {
        let adapter = try replaceableAdapter()
        start(adapter)
        defer { adapter.stop() }
        #expect(await eventually { launches == 1 })
        let first = try #require(pids.first)

        start(adapter)
        #expect(await eventually { processIsGone(first) })
        try await settle()
        #expect(recorder.lines.isEmpty)
    }


    @Test func buildsAdapterCommandLines() {
        let adapter = AdapterProcess(
            script: URL(filePath: "/App/Resources/mediaremote-adapter.pl"),
            framework: URL(filePath: "/App/Frameworks/MediaRemoteAdapter.framework"),
            scheduler: scheduler
        )
        let base = ["/App/Resources/mediaremote-adapter.pl", "/App/Frameworks/MediaRemoteAdapter.framework"]
        #expect(adapter.executable == URL(filePath: "/usr/bin/perl"))
        #expect(adapter.streamArguments == base + ["stream", "--micros", "--debounce=100"])
        #expect(adapter.arguments(for: .play) == base + ["send", "0"])
        #expect(adapter.arguments(for: .pause) == base + ["send", "1"])
        #expect(adapter.arguments(for: .togglePlayPause) == base + ["send", "2"])
        #expect(adapter.arguments(for: .nextTrack) == base + ["send", "4"])
        #expect(adapter.arguments(for: .previousTrack) == base + ["send", "5"])
        #expect(adapter.seekArguments(toSeconds: 12.5) == base + ["seek", "12500000"])
        #expect(adapter.seekArguments(toSeconds: 0.0000014) == base + ["seek", "1"])
        #expect(adapter.seekArguments(toSeconds: -3) == base + ["seek", "0"])
        #expect(adapter.seekArguments(toSeconds: .nan) == nil)
        #expect(adapter.seekArguments(toSeconds: .infinity) == nil)
        #expect(adapter.seekArguments(toSeconds: -.infinity) == nil)
    }

    @Test func seekPositionsBeyondTheMicrosecondRangeAreIgnored() {
        let adapter = AdapterProcess(executable: URL(filePath: "/usr/bin/perl"), baseArguments: [], scheduler: scheduler)
        #expect(adapter.seekArguments(toSeconds: 9_000_000_000_000) == ["seek", "9000000000000000000"])
        #expect(adapter.seekArguments(toSeconds: Double(Int64.max) / 1_000_000) == nil)
        #expect(adapter.seekArguments(toSeconds: 1e300) == nil)
        #expect(adapter.seekArguments(toSeconds: .greatestFiniteMagnitude) == nil)
    }

    @Test func sendAndSeekRunOneShotProcessesAndLogFailures() async throws {
        let adapter = try makeAdapter(#"echo "$@" >> '\#(path("commands"))'"# + "\nexit 3")
        adapter.send(.nextTrack)
        #expect(await eventually { launches == 1 && recorder.logs.count == 1 })
        adapter.seek(toSeconds: 1.5)
        #expect(await eventually { launches == 2 && recorder.logs.count == 2 })

        #expect(contents("commands") == "send 4\nseek 1500000\n")
        #expect(recorder.logs.allSatisfy { $0.contains("status 3") })
        #expect(adapter.launchCount == 0)
    }

    /// Each command logs its start and end and takes a while, so overlapping runs would interleave.
    func slowCommands() throws -> AdapterProcess {
        try makeAdapter("""
            echo "start $*" >> '\(path("commands"))'
            sleep 0.15
            echo "end $*" >> '\(path("commands"))'
            """)
    }

    func commandLog(_ commands: String...) -> String {
        commands.map { "start \($0)\nend \($0)\n" }.joined()
    }

    @Test func commandsRunOneAtATimeInOrder() async throws {
        let adapter = try slowCommands()
        adapter.send(.play)
        adapter.send(.nextTrack)
        adapter.send(.pause)

        let expected = commandLog("send 0", "send 4", "send 1")
        #expect(await eventually { contents("commands") == expected })
        try await settle()
        #expect(contents("commands") == expected)
        #expect(recorder.logs.isEmpty)
    }

    @Test func aBurstOfSeeksKeepsOnlyTheLatestPendingSeek() async throws {
        let adapter = try slowCommands()
        adapter.seek(toSeconds: 1)
        adapter.seek(toSeconds: 2)
        adapter.send(.pause)
        adapter.seek(toSeconds: 3)
        adapter.seek(toSeconds: 4)

        // The first seek is already running; 2 and 3 are superseded, and 4 still follows the pause it came after.
        let expected = commandLog("seek 1000000", "send 1", "seek 4000000")
        #expect(await eventually { contents("commands") == expected })
        try await settle()
        #expect(contents("commands") == expected)
        #expect(launches == 3)
    }

    @Test func stopDropsQueuedCommands() async throws {
        let adapter = try slowCommands()
        adapter.send(.play)
        adapter.send(.nextTrack)
        adapter.seek(toSeconds: 2)
        adapter.stop()

        // The running command finishes; nothing that waited behind it runs.
        #expect(await eventually { contents("commands") == commandLog("send 0") })
        try await settle()
        #expect(contents("commands") == commandLog("send 0"))

        adapter.send(.pause)
        #expect(await eventually { contents("commands") == commandLog("send 0", "send 1") })
    }
}
