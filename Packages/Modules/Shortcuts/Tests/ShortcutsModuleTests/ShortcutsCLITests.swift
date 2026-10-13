import Foundation
import MyNotchTestSupport
import Synchronization
import Testing
@testable import ShortcutsModule

private let shortcutID = "11111111-2222-3333-4444-555555555555"

@Suite struct ShortcutsCLITests {
    @Test func listsWithIdentifiers() async throws {
        let runner = FakeProcessRunner { _, _ in
            ProcessOutput(status: 0, standardOutput: "Hello (11111111-2222-3333-4444-555555555555)\n", standardError: "")
        }
        let list = try await SystemShortcutsCLI(runner: runner).list()
        #expect(list == [ShortcutInfo(id: "11111111-2222-3333-4444-555555555555", name: "Hello")])
        #expect(runner.calls == [["/usr/bin/shortcuts", "list", "--show-identifiers"]])
    }

    @Test func aFailedListThrowsTheErrorOutput() async {
        let runner = FakeProcessRunner { _, _ in ProcessOutput(status: 1, standardOutput: "", standardError: "boom\n") }
        await #expect(throws: ShortcutsCLIError.failed("boom")) { try await SystemShortcutsCLI(runner: runner).list() }
    }

    @Test func runsByIdentifierAndReadsTheTextOutput() async throws {
        let runner = FakeProcessRunner.writing("Xin chào\n")
        let output = try await SystemShortcutsCLI(runner: runner).run(id: shortcutID)
        #expect(output == "Xin chào")
        let call = try #require(runner.calls.first)
        #expect(Array(call.prefix(4)) == ["/usr/bin/shortcuts", "run", shortcutID, "-o"])
        #expect(Array(call.suffix(2)) == ["--output-type", "public.plain-text"])
        // The temporary output file is gone afterwards.
        #expect(!FileManager.default.fileExists(atPath: call[4]))
    }

    @Test func aRunWithoutOutputReturnsNil() async throws {
        #expect(try await SystemShortcutsCLI(runner: FakeProcessRunner.writing(nil)).run(id: shortcutID) == nil)
        #expect(try await SystemShortcutsCLI(runner: FakeProcessRunner.writing("  \n")).run(id: shortcutID) == nil)
    }

    @Test func aFailedRunThrowsTheErrorOutput() async {
        let runner = FakeProcessRunner.writing(nil, status: 1, standardError: "Error: Couldn't find shortcut\nmore")
        await #expect(throws: ShortcutsCLIError.failed("Error: Couldn't find shortcut")) {
            try await SystemShortcutsCLI(runner: runner).run(id: shortcutID)
        }
    }

    @Test func aFailedRunWithoutErrorOutputSaysWhichStatus() async {
        await #expect(throws: ShortcutsCLIError.failed("Mã thoát 3")) {
            try await SystemShortcutsCLI(runner: FakeProcessRunner.writing(nil, status: 3)).run(id: shortcutID)
        }
    }

    @Test func anIdentifierThatIsNotAUUIDNeverReachesTheCommandLine() async {
        for id in ["-h", "--help", "ABC", "", "\(shortcutID) -o /tmp/x"] {
            let runner = FakeProcessRunner.writing("x")
            await #expect(throws: ShortcutsCLIError.failed("Mã shortcut không hợp lệ")) {
                try await SystemShortcutsCLI(runner: runner).run(id: id)
            }
            #expect(runner.calls.isEmpty)
        }
    }

    @Test func textBeyondTheLimitIsCutWhenReadFromTheOutputFile() async throws {
        let long = try await SystemShortcutsCLI(runner: FakeProcessRunner.writing(String(repeating: "a", count: 200_000))).run(id: shortcutID)
        #expect(long?.utf8.count == SystemProcessRunner.maxOutputBytes)
        // The cut can land inside a multi-byte character; the text must still come back.
        let euros = try await SystemShortcutsCLI(runner: FakeProcessRunner.writing(String(repeating: "€", count: 40_000))).run(id: shortcutID)
        let text = try #require(euros)
        #expect(text.hasPrefix("€€€"))
        #expect(text.count <= SystemProcessRunner.maxOutputBytes / 3 + 1)
    }

    @Test func aRunThatTakesTooLongTimesOut() async {
        let cli = SystemShortcutsCLI(runner: FakeProcessRunner.hanging, timeout: .milliseconds(30))
        await #expect(throws: ShortcutsCLIError.timedOut) { try await cli.run(id: shortcutID) }
        await #expect(throws: ShortcutsCLIError.timedOut) { try await cli.list() }
    }

    @Test func cancellingTheTaskStopsTheRun() async {
        let cli = SystemShortcutsCLI(runner: FakeProcessRunner.hanging)
        let task = Task { try await cli.run(id: shortcutID) }
        try? await Task.sleep(for: .milliseconds(20))
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}

/// The real runner, on harmless system tools: never the `shortcuts` binary.
@Suite struct SystemProcessRunnerTests {
    let runner = SystemProcessRunner()

    @Test func capturesOutputAndStatus() async throws {
        let ok = try await runner.run(executable: "/bin/echo", arguments: ["a b", "(c)"])
        #expect(ok == ProcessOutput(status: 0, standardOutput: "a b (c)\n", standardError: ""))
        let failed = try await runner.run(executable: "/usr/bin/false", arguments: [])
        #expect(failed.status == 1)
    }

    @Test func aMissingExecutableFailsToLaunch() async {
        await #expect(throws: ShortcutsCLIError.self) { try await runner.run(executable: "/nonexistent/tool", arguments: []) }
    }

    @Test func keepsOnlyTheFirstOutputBytesButStillDrainsTheRest() async throws {
        let out = try await runner.run(executable: "/usr/bin/head", arguments: ["-c", "1000000", "/dev/zero"])
        #expect(out.status == 0)
        #expect(out.standardOutput.utf8.count == SystemProcessRunner.maxOutputBytes)
        let err = try await runner.run(executable: "/bin/sh", arguments: ["-c", "/usr/bin/head -c 1000000 /dev/zero >&2"])
        #expect(err.status == 0)
        #expect(err.standardError.utf8.count == SystemProcessRunner.maxOutputBytes)
    }

    @Test func cancellingTerminatesTheProcess() async {
        let started = ContinuousClock.now
        let task = Task { [runner] in try await runner.run(executable: "/bin/sleep", arguments: ["30"]) }
        try? await Task.sleep(for: .milliseconds(100))
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(ContinuousClock.now - started < .seconds(10))
    }

    /// `exec` keeps the ignored signal and leaves no child behind that could hold the pipe open after the kill.
    @Test func aChildThatIgnoresTermIsKilledAfterTheGracePeriod() async {
        let runner = SystemProcessRunner(killGrace: .milliseconds(200))
        let started = ContinuousClock.now
        let task = Task { try await runner.run(executable: "/bin/sh", arguments: ["-c", "trap '' TERM; exec /bin/sleep 20"]) }
        try? await Task.sleep(for: .milliseconds(300))
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(ContinuousClock.now - started < .seconds(10))
    }

    @Test func aVeryLargeOutputIsDrainedWithoutBlockingTheChild() async throws {
        let out = try await runner.run(executable: "/usr/bin/head", arguments: ["-c", "5000000", "/dev/zero"])
        #expect(out.status == 0)
        #expect(out.standardOutput.utf8.count == SystemProcessRunner.maxOutputBytes)
    }

    @Test func theChildHasNoInputFromTheApp() async throws {
        // Device 3,2 is /dev/null; anything the app itself reads from would show another one.
        let out = try await runner.run(executable: "/usr/bin/stat", arguments: ["-L", "-f", "%Hr,%Lr", "/dev/stdin"])
        #expect(out.standardOutput == "3,2\n")
    }

    @Test(.timeLimit(.minutes(1)))
    func aCancelWhileTheChildStartsStillEndsIt() async {
        for _ in 0..<20 {
            let task = Task { [runner] in try await runner.run(executable: "/bin/sleep", arguments: ["30"]) }
            // Cancels at a different moment each time, down to before the task has begun.
            await Task.yield()
            task.cancel()
            await #expect(throws: CancellationError.self) { try await task.value }
        }
    }

    /// The shell and its `sleep` both ignore TERM, and the `sleep` holds the output pipes open, so only a kill of the
    /// whole process group ends the run. The task and the sleep are always ended, so a regression fails instead of hanging.
    @Test(.timeLimit(.minutes(1)))
    func aChildThatIgnoresTermIsKilledWithItsChildrenAfterTheGracePeriod() async throws {
        let folder = ScratchFolders.shared.reserve("shortcuts-runner")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let pidFile = folder.appending(path: "sleep.pid")
        let outcome = Mutex<String?>(nil)
        let task = Task { [pidFile] in
            do {
                _ = try await SystemProcessRunner().run(
                    executable: "/bin/sh", arguments: ["-c", "trap '' TERM; /bin/sleep 30 & echo $! > \"$0\"; wait", pidFile.path(percentEncoded: false)]
                )
                outcome.withLock { $0 = "finished" }
            } catch is CancellationError {
                outcome.withLock { $0 = "cancelled" }
            } catch {
                outcome.withLock { $0 = "failed: \(error)" }
            }
        }
        func sleepPID() -> pid_t? {
            (try? String(contentsOf: pidFile, encoding: .utf8)).flatMap { pid_t($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        }
        defer { task.cancel() }
        await settle { sleepPID() != nil }
        let pid = try #require(sleepPID())
        defer { kill(pid, SIGKILL) }

        let started = ContinuousClock.now
        task.cancel()
        await settle(timeout: .seconds(8)) { outcome.withLock { $0 } != nil }
        let elapsed = ContinuousClock.now - started
        #expect(outcome.withLock { $0 } == "cancelled")
        // Not before the grace period (TERM was ignored), and about two seconds after it.
        #expect(elapsed > .seconds(1.5))
        #expect(elapsed < .seconds(4))
        await settle(timeout: .seconds(2)) { kill(pid, 0) != 0 }
        #expect(kill(pid, 0) != 0, "the sleep is still running")
    }
}
