import Darwin
import Foundation
import Testing
@testable import PortsModule

/// A child process this test starts itself and is the only thing these tests ever signal. It is killed and reaped when the value
/// goes out of scope, whatever the test did.
@MainActor final class ChildProcess {
    let process = Process()
    let pid: Int32
    private let input = Pipe()
    private let output = Pipe()

    /// Starts `/bin/sh -c script`; when `awaitingReady`, returns once the script printed a line, so a trap set first is in place.
    init(script: String, awaitingReady: Bool) throws {
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        pid = process.processIdentifier
        if awaitingReady {
            // Blocks until the child writes, or exits and closes the pipe.
            guard !output.fileHandleForReading.availableData.isEmpty else { throw ChildError.neverReady }
        }
    }

    enum ChildError: Error { case neverReady }

    deinit {
        let process = process
        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        process.waitUntilExit()
    }
}

/// The real `kill` and libproc, on a child the test started. Nothing else is ever signalled.
@Suite struct RealProcessControlTests {
    let control = LibprocProcessControl()

    func waitUntilGone(_ pid: Int32, seconds: Double = 20) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if control.identity(of: pid) == nil { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return false
    }

    @Test func aChildIsIdentifiedAndSIGTERMEndsIt() async throws {
        let child = try ChildProcess(script: "exec /bin/sleep 300", awaitingReady: false)
        // `exec` replaces the shell: wait for the image to be sleep before looking at the path.
        var identity = control.identity(of: child.pid)
        for _ in 0..<1500 where identity?.path != "/bin/sleep" {
            try await Task.sleep(for: .milliseconds(10))
            identity = control.identity(of: child.pid)
        }
        let seen = try #require(identity)
        #expect(seen.uid == getuid())
        #expect(seen.realUID == getuid())
        #expect(seen.path == "/bin/sleep")
        #expect(seen.startTime > 0)
        #expect(control.identity(of: child.pid) == seen, "the identity is the same each time it is read")
        #expect(StopPolicy.current.refusal(for: seen) == .system, "/bin/sleep is a system program")

        #expect(control.send(.terminate, to: child.pid) == .sent)
        #expect(await waitUntilGone(child.pid), "SIGTERM ended the child")
    }

    @Test func aChildThatIgnoresSIGTERMStaysUntilSIGKILL() async throws {
        let child = try ChildProcess(script: "trap '' TERM; echo ready; read line", awaitingReady: true)
        let before = try #require(control.identity(of: child.pid))

        #expect(control.send(.terminate, to: child.pid) == .sent)
        try await Task.sleep(for: .milliseconds(300))
        #expect(control.identity(of: child.pid) == before, "still the same process, still alive")

        #expect(control.send(.kill, to: child.pid) == .sent)
        #expect(await waitUntilGone(child.pid), "SIGKILL cannot be ignored")
    }

    @Test func anExitedChildIsGoneEvenBeforeItIsReaped() async throws {
        let child = try ChildProcess(script: "exit 0", awaitingReady: false)
        #expect(await waitUntilGone(child.pid))
    }
}
