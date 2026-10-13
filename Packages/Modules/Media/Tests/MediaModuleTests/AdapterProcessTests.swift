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

    /// Each fake adapter appends one line here per launch.
    var launches: Int { ((try? String(contentsOfFile: path("launches"), encoding: .utf8)) ?? "").split(separator: "\n").count }

    func makeAdapter(_ body: String, killDelay: TimeInterval = 1) throws -> AdapterProcess {
        let script = directory.appending(path: "adapter.sh")
        try ("echo launch >> '\(path("launches"))'\n" + body).write(to: script, atomically: true, encoding: .utf8)
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

    /// Lets the process and its callbacks run until `condition` holds, for at most two seconds.
    func eventually(_ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(2)
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

    /// The process ID the fake adapter wrote to `pid` before `exec`-ing into a long `sleep`.
    func launchedPID() async -> pid_t? {
        var pid: pid_t?
        _ = await eventually {
            pid = (try? String(contentsOfFile: path("pid"), encoding: .utf8)).flatMap { pid_t($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            return pid != nil
        }
        return pid
    }

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
        #expect(try String(contentsOfFile: path("arguments"), encoding: .utf8) == "stream --micros --debounce=100\n")
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
        try await Task.sleep(for: .milliseconds(100))
        #expect(launches == 3)
        #expect(adapter.launchCount == 3)
        #expect(scheduler.pendingCount == 0)
        #expect(recorder.failures.count == 1)
        #expect(recorder.logs.contains("adapter broke"))
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
        let adapter = try makeAdapter("echo $$ > '\(path("pid"))'\nexec sleep 30", killDelay: 30)
        start(adapter)
        let pid = try #require(await launchedPID())

        adapter.stop()
        #expect(!adapter.isStreamRunning)
        #expect(await eventually { processIsGone(pid) })
        try await Task.sleep(for: .milliseconds(100))
        scheduler.advance(by: .seconds(120))
        #expect(scheduler.pendingCount == 0)
        #expect(adapter.launchCount == 1)
        #expect(launches == 1)
        #expect(recorder.failures.isEmpty)
    }

    @Test func startingAgainIgnoresTheReplacedProcess() async throws {
        let adapter = try makeAdapter("exec sleep 30")
        start(adapter)
        defer { adapter.stop() }
        #expect(await eventually { launches == 1 })

        start(adapter)
        #expect(await eventually { launches == 2 })
        // Long enough for the replaced process to exit and its exit callback to run.
        try await Task.sleep(for: .milliseconds(200))
        #expect(adapter.isStreamRunning)
        scheduler.advance(by: .seconds(1))
        #expect(adapter.launchCount == 2)
    }

    @Test func stopKillsAnAdapterThatIgnoresSIGTERM() async throws {
        let adapter = try makeAdapter("trap '' TERM\necho $$ > '\(path("pid"))'\nexec sleep 30", killDelay: 0.2)
        start(adapter)
        let pid = try #require(await launchedPID())

        adapter.stop()
        #expect(await eventually { processIsGone(pid) })
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
    }

    @Test func sendAndSeekRunOneShotProcessesAndLogFailures() async throws {
        let adapter = try makeAdapter(#"echo "$@" >> '\#(path("commands"))'"# + "\nexit 3")
        adapter.send(.nextTrack)
        #expect(await eventually { launches == 1 && recorder.logs.count == 1 })
        adapter.seek(toSeconds: 1.5)
        #expect(await eventually { launches == 2 && recorder.logs.count == 2 })

        #expect(try String(contentsOfFile: path("commands"), encoding: .utf8) == "send 4\nseek 1500000\n")
        #expect(recorder.logs.allSatisfy { $0.contains("status 3") })
        #expect(adapter.launchCount == 0)
    }
}
