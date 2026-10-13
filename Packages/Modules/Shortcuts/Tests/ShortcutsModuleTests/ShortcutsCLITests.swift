import Foundation
import Testing
@testable import ShortcutsModule

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
        let output = try await SystemShortcutsCLI(runner: runner).run(id: "ABC")
        #expect(output == "Xin chào")
        let call = try #require(runner.calls.first)
        #expect(Array(call.prefix(4)) == ["/usr/bin/shortcuts", "run", "ABC", "-o"])
        #expect(Array(call.suffix(2)) == ["--output-type", "public.plain-text"])
        // The temporary output file is gone afterwards.
        #expect(!FileManager.default.fileExists(atPath: call[4]))
    }

    @Test func aRunWithoutOutputReturnsNil() async throws {
        #expect(try await SystemShortcutsCLI(runner: FakeProcessRunner.writing(nil)).run(id: "ABC") == nil)
        #expect(try await SystemShortcutsCLI(runner: FakeProcessRunner.writing("  \n")).run(id: "ABC") == nil)
    }

    @Test func aFailedRunThrowsTheErrorOutput() async {
        let runner = FakeProcessRunner.writing(nil, status: 1, standardError: "Error: Couldn't find shortcut\nmore")
        await #expect(throws: ShortcutsCLIError.failed("Error: Couldn't find shortcut")) {
            try await SystemShortcutsCLI(runner: runner).run(id: "ABC")
        }
    }

    @Test func aFailedRunWithoutErrorOutputSaysWhichStatus() async {
        await #expect(throws: ShortcutsCLIError.failed("Mã thoát 3")) {
            try await SystemShortcutsCLI(runner: FakeProcessRunner.writing(nil, status: 3)).run(id: "ABC")
        }
    }

    @Test func aRunThatTakesTooLongTimesOut() async {
        let cli = SystemShortcutsCLI(runner: FakeProcessRunner.hanging, timeout: .milliseconds(30))
        await #expect(throws: ShortcutsCLIError.timedOut) { try await cli.run(id: "ABC") }
        await #expect(throws: ShortcutsCLIError.timedOut) { try await cli.list() }
    }

    @Test func cancellingTheTaskStopsTheRun() async {
        let cli = SystemShortcutsCLI(runner: FakeProcessRunner.hanging)
        let task = Task { try await cli.run(id: "ABC") }
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

    @Test func cancellingTerminatesTheProcess() async {
        let started = ContinuousClock.now
        let task = Task { [runner] in try await runner.run(executable: "/bin/sleep", arguments: ["30"]) }
        try? await Task.sleep(for: .milliseconds(100))
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(ContinuousClock.now - started < .seconds(10))
    }
}
