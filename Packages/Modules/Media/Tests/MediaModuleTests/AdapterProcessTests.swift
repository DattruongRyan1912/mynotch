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
    /// What the fake adapters wait on (`gate.wait`) until the test lets them through.
    let gate: ProcessGate
    /// Commands the test has let through so far, in order (see `letCommandsRun`).
    var finishedCommands: [String] = []

    init() throws {
        directory = FileManager.default.temporaryDirectory.appending(path: "AdapterProcessTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        gate = try ProcessGate(in: directory)
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
    /// wrong, so it is very generous: starting a shell can take many seconds on a machine that is very busy.
    func eventually(_ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(120)
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

    /// A fake adapter that runs until the test opens the gate, then exits with `status`.
    func releasable(exitStatus status: Int32) throws -> AdapterProcess {
        try makeAdapter("\(gate.wait)\nexit \(status)")
    }

    func release(_ adapter: AdapterProcess, launches count: Int) async -> Bool {
        gate.open()
        return await exited(adapter, launches: count)
    }

    func processIsGone(_ pid: pid_t) -> Bool { kill(pid, 0) != 0 && errno == ESRCH }

    @Test func deliversCompleteLinesInOrderOnTheMainActor() async throws {
        let adapter = try makeAdapter(#"""
            printf '{"n":1}\n{"n":'
            \#(gate.wait)
            printf '2}\n{"n":3}\n'
            exec sleep 30
            """#)
        start(adapter)
        defer { adapter.stop() }

        // The first line and the start of the second are one write, so the reader holds the start when the line arrives.
        #expect(await eventually { recorder.lines == [#"{"n":1}"#] })
        gate.open()
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

        #expect(await eventually { recorder.logs.contains("adapter broke") })

        scheduler.advance(by: .seconds(120))
        #expect(launches == 3)
        #expect(adapter.launchCount == 3)
        #expect(scheduler.pendingCount == 0)
        #expect(recorder.failures.count == 1)
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
        // The background subshell keeps stdout open and writes after the adapter has exited, once the test opens the gate.
        let adapter = try makeAdapter("(\(gate.wait); echo late; echo written >> '\(path("written"))') &\nexit 1")
        start(adapter)
        defer { adapter.stop() }

        // The first two launches are still the current one when their late line comes.
        #expect(await eventually { launches == 1 })
        gate.open()
        #expect(await eventually { recorder.lines == ["late"] && !adapter.isStreamRunning })
        scheduler.advance(by: .seconds(1))
        #expect(await eventually { launches == 2 })
        gate.open()
        #expect(await eventually { recorder.lines.count == 2 && !adapter.isStreamRunning })
        scheduler.advance(by: .seconds(2))
        // The third failed start ends it, and only then is the last late line written.
        #expect(await eventually { recorder.failures.count == 1 })
        #expect(await eventually { launches == 3 })
        gate.open()
        #expect(await eventually { contents("written").split(separator: "\n").count == 3 })
        await drainMainQueue()
        #expect(recorder.lines == ["late", "late"])
        #expect(adapter.launchCount == 3)
    }

    @Test func aLineThatComesAfterGivingUpIsDropped() {
        let adapter = AdapterProcess(
            executable: directory.appending(path: "missing-perl"), baseArguments: [],
            scheduler: scheduler, log: { [recorder] in recorder.logs.append($0) }
        )
        start(adapter)
        defer { adapter.stop() }
        adapter.deliver(["early"], from: 1)
        #expect(recorder.lines == ["early"], "launch 1 is the current one")

        scheduler.advance(by: .seconds(1))
        scheduler.advance(by: .seconds(2))
        #expect(recorder.failures.count == 1)
        adapter.deliver(["late"], from: 3)
        #expect(recorder.lines == ["early"])
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
        await drainMainQueue()
        scheduler.advance(by: .seconds(120))
        #expect(scheduler.pendingCount == 0)
        #expect(adapter.launchCount == 1)
        #expect(launches == 1)
        #expect(recorder.failures.isEmpty)
    }

    @Test func theExitOfAStoppedStreamIsIgnored() async throws {
        let adapter = try makeAdapter("exec sleep 30", killDelay: .seconds(30))
        start(adapter)
        #expect(await eventually { launches == 1 })
        let id = adapter.launchCount

        adapter.stop()
        // What the terminated process reports, whenever it does: no restart, no failure, no log.
        adapter.streamExited(id, succeeded: false, reason: "signal 15")
        #expect(scheduler.pendingCount == 0)
        scheduler.advance(by: .seconds(120))
        #expect(adapter.launchCount == 1)
        #expect(recorder.failures.isEmpty)
        #expect(recorder.logs.isEmpty)
    }

    @Test func stopKillsAnAdapterThatIgnoresSIGTERM() async throws {
        let adapter = try makeAdapter("trap '' TERM\nexec sleep 30", killDelay: .milliseconds(200))
        start(adapter)
        #expect(await eventually { launches == 1 })
        let pid = try #require(pids.first)

        adapter.stop()
        #expect(await eventually { processIsGone(pid) })
    }

    /// The first launch prints a line when it gets SIGTERM, so its output arrives after the second launch started. The
    /// second waits for the gate, then prints its own line.
    func replaceableAdapter() throws -> AdapterProcess {
        try makeAdapter("""
            if [ ! -f '\(path("armed"))' ]; then
                trap 'echo replaced; kill $!; exit 0' TERM
                touch '\(path("armed"))'
                sleep 30 &
                wait $!
            fi
            \(gate.wait)
            echo fresh
            exec sleep 30
            """, killDelay: .seconds(30))
    }

    /// The first launch has set up its SIGTERM handler; one that came earlier would end it without its line.
    var isArmed: Bool { FileManager.default.fileExists(atPath: path("armed")) }

    @Test func startingAgainTerminatesThePreviousProcess() async throws {
        let adapter = try replaceableAdapter()
        start(adapter)
        defer { adapter.stop() }
        #expect(await eventually { isArmed })
        let first = try #require(pids.first)

        start(adapter)
        #expect(await eventually { launches == 2 && processIsGone(first) })
        // The exit of the first launch comes whenever it comes; it is not the current stream's.
        adapter.streamExited(1, succeeded: true, reason: "status 0")
        #expect(adapter.isStreamRunning)
        #expect(scheduler.pendingCount == 2, "the second launch's own timers, nothing more")
        await drainMainQueue()
        #expect(adapter.isStreamRunning)
        scheduler.advance(by: .seconds(1))
        #expect(adapter.launchCount == 2)
    }

    @Test func linesFromAReplacedLaunchAreDropped() async throws {
        let adapter = try replaceableAdapter()
        start(adapter)
        defer { adapter.stop() }
        #expect(await eventually { isArmed })
        let first = try #require(pids.first)

        start(adapter)
        #expect(await eventually { processIsGone(first) })
        // The first launch said "replaced" before it ended; the second launch says its own line only now.
        gate.open()
        #expect(await eventually { recorder.lines.contains("fresh") })
        await drainMainQueue()
        #expect(recorder.lines == ["fresh"])
    }

    @Test func onlyTheCurrentLaunchsLinesAreDelivered() async throws {
        let adapter = try replaceableAdapter()
        start(adapter)
        defer { adapter.stop() }
        #expect(await eventually { isArmed })
        start(adapter)
        #expect(adapter.launchCount == 2)

        adapter.deliver(["from the first"], from: 1)
        #expect(recorder.lines.isEmpty)
        adapter.deliver(["from the second"], from: 2)
        #expect(recorder.lines == ["from the second"])
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

    @Test func buildsTheShuffleRepeatAndLikeCommandLines() {
        let adapter = AdapterProcess(executable: URL(filePath: "/usr/bin/perl"), baseArguments: ["adapter.pl", "Framework"], scheduler: scheduler)
        let base = ["adapter.pl", "Framework"]
        // The ids of the README's `shuffle MODE` and `repeat MODE` tables.
        #expect(adapter.shuffleArguments(.off) == base + ["shuffle", "1"])
        #expect(adapter.shuffleArguments(.albums) == base + ["shuffle", "2"])
        #expect(adapter.shuffleArguments(.tracks) == base + ["shuffle", "3"])
        #expect(adapter.repeatArguments(.off) == base + ["repeat", "1"])
        #expect(adapter.repeatArguments(.track) == base + ["repeat", "2"])
        #expect(adapter.repeatArguments(.playlist) == base + ["repeat", "3"])
        // MRCommand 0x6A, which the vendored adapter's `send` does not accept yet.
        #expect(adapter.arguments(for: .likeTrack) == base + ["send", "106"])
        #expect(!adapter.canLike)
    }

    @Test func shuffleRepeatAndSendRunOneAtATimeInOrder() async throws {
        let adapter = try heldCommands()
        adapter.setShuffle(.tracks)
        adapter.setRepeat(.playlist)
        adapter.send(.nextTrack)
        adapter.setRepeat(.off)

        #expect(adapter.pendingCommandCount == 3, "the first is running; a repeat is not a seek, so none of them replaces another")
        await letCommandsRun("shuffle 3", "repeat 3", "send 4", "repeat 1")
        #expect(adapter.pendingCommandCount == 0)
        #expect(recorder.logs.isEmpty)
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

    /// Each command logs its start, waits for the gate and logs its end, so overlapping runs would show in the log.
    func heldCommands() throws -> AdapterProcess {
        try makeAdapter("""
            echo "start $*" >> '\(path("commands"))'
            \(gate.wait)
            echo "end $*" >> '\(path("commands"))'
            """)
    }

    func commandLog(_ commands: [String]) -> String {
        commands.map { "start \($0)\nend \($0)\n" }.joined()
    }

    /// Waits until the commands log starts with `expected`. False when the log is something that `final`, the log the test
    /// is heading for, does not start with (a wrong order or an overlap), or when it never gets there.
    func commandsLogReaches(_ expected: String, heading final: String) async -> Bool {
        _ = await eventually {
            let text = contents("commands")
            return text.hasPrefix(expected) || !final.hasPrefix(text)
        }
        let text = contents("commands")
        return text.hasPrefix(expected) && final.hasPrefix(text)
    }

    /// Lets `commands` through one at a time, each only once it is the one running, and checks the log at every step:
    /// while one is held nothing else may have started, and when it is let through it ends before the next begins.
    func letCommandsRun(_ commands: String..., sourceLocation: SourceLocation = #_sourceLocation) async {
        let final = commandLog(finishedCommands + commands)
        for command in commands {
            let running = commandLog(finishedCommands) + "start \(command)\n"
            #expect(await commandsLogReaches(running, heading: final), "\(command) did not start", sourceLocation: sourceLocation)
            #expect(contents("commands") == running, "\(command) did not run alone", sourceLocation: sourceLocation)
            gate.open()
            finishedCommands.append(command)
            #expect(await commandsLogReaches(commandLog(finishedCommands), heading: final), "\(command) did not end", sourceLocation: sourceLocation)
        }
        #expect(launches == finishedCommands.count, sourceLocation: sourceLocation)
    }

    @Test func commandsRunOneAtATimeInOrder() async throws {
        let adapter = try heldCommands()
        adapter.send(.play)
        adapter.send(.nextTrack)
        adapter.send(.pause)

        #expect(adapter.pendingCommandCount == 2, "only the first is running")
        await letCommandsRun("send 0", "send 4", "send 1")
        #expect(adapter.pendingCommandCount == 0)
        #expect(recorder.logs.isEmpty)
    }

    @Test func aBurstOfSeeksKeepsOnlyTheLatestPendingSeek() async throws {
        let adapter = try heldCommands()
        adapter.seek(toSeconds: 1)
        adapter.seek(toSeconds: 2)
        adapter.send(.pause)
        adapter.seek(toSeconds: 3)
        adapter.seek(toSeconds: 4)

        // The first seek is already running; 2 and 3 are superseded, and 4 still follows the pause it came after.
        #expect(adapter.pendingCommandCount == 2)
        await letCommandsRun("seek 1000000", "send 1", "seek 4000000")
        #expect(adapter.pendingCommandCount == 0)
    }

    @Test func stopDropsQueuedCommands() async throws {
        let adapter = try heldCommands()
        adapter.send(.play)
        adapter.send(.nextTrack)
        adapter.seek(toSeconds: 2)
        #expect(adapter.pendingCommandCount == 2)
        adapter.stop()
        #expect(adapter.pendingCommandCount == 0, "nothing that waited behind the running command is left")

        // The running command finishes.
        await letCommandsRun("send 0")

        // The next command is the one sent after the stop, not one of the dropped.
        adapter.send(.pause)
        await letCommandsRun("send 1")
    }
}
