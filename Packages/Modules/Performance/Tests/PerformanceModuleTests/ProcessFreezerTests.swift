import Foundation
import Testing
@testable import PerformanceModule

private nonisolated final class SignalRecorder: @unchecked Sendable {
    private let lock = NSLock()
    var signals: [(pid: pid_t, sig: Int32)] = []

    func send(pid: pid_t, sig: Int32) -> Int32 {
        lock.withLock {
            signals.append((pid: pid, sig: sig))
            return 0
        }
    }

    func signalCount(for pid: pid_t, sig: Int32) -> Int {
        lock.withLock {
            signals.filter { $0.pid == pid && $0.sig == sig }.count
        }
    }
}

@Suite struct ProcessFreezerTests {
    @Test func isProtectedReturnsTrueForRootSelfAndFrontmostPIDs() {
        let freezer = ProcessFreezer(
            killSignal: { _, _ in 0 },
            frontmostPID: { 999 },
            ownPID: { 555 }
        )

        #expect(freezer.isProtected(pid: 0))
        #expect(freezer.isProtected(pid: 1))
        #expect(freezer.isProtected(pid: 555))
        #expect(freezer.isProtected(pid: 999))
        #expect(!freezer.isProtected(pid: 1234))
    }

    @Test func freezeRefusesProtectedPIDs() {
        let recorder = SignalRecorder()
        let freezer = ProcessFreezer(
            killSignal: { pid, sig in recorder.send(pid: pid, sig: sig) },
            frontmostPID: { 999 },
            ownPID: { 555 }
        )

        #expect(!freezer.freeze(pid: 0))
        #expect(!freezer.freeze(pid: 1))
        #expect(!freezer.freeze(pid: 555))
        #expect(!freezer.freeze(pid: 999))
        #expect(recorder.signals.isEmpty)
    }

    @Test func freezeSendsSIGSTOPAndRecordsFrozenState() {
        let recorder = SignalRecorder()
        let freezer = ProcessFreezer(
            killSignal: { pid, sig in recorder.send(pid: pid, sig: sig) },
            frontmostPID: { 999 },
            ownPID: { 555 }
        )

        let targetPID: Int32 = 4321
        #expect(freezer.freeze(pid: targetPID))
        #expect(freezer.isFrozen(pid: targetPID))
        #expect(recorder.signalCount(for: targetPID, sig: SIGSTOP) == 1)
        #expect(freezer.remainingTimeout(for: targetPID) != nil)
    }

    @Test func resumeSendsSIGCONTAndClearsFrozenState() {
        let recorder = SignalRecorder()
        let freezer = ProcessFreezer(
            killSignal: { pid, sig in recorder.send(pid: pid, sig: sig) },
            frontmostPID: { 999 },
            ownPID: { 555 }
        )

        let targetPID: Int32 = 4321
        #expect(freezer.freeze(pid: targetPID))
        #expect(freezer.isFrozen(pid: targetPID))

        #expect(freezer.resume(pid: targetPID))
        #expect(!freezer.isFrozen(pid: targetPID))
        #expect(recorder.signalCount(for: targetPID, sig: SIGCONT) == 1)
    }

    @Test func resumeAllResumesAllFrozenProcesses() {
        let recorder = SignalRecorder()
        let freezer = ProcessFreezer(
            killSignal: { pid, sig in recorder.send(pid: pid, sig: sig) },
            frontmostPID: { 999 },
            ownPID: { 555 }
        )

        #expect(freezer.freeze(pid: 1001))
        #expect(freezer.freeze(pid: 1002))

        freezer.resumeAll()

        #expect(!freezer.isFrozen(pid: 1001))
        #expect(!freezer.isFrozen(pid: 1002))
        #expect(recorder.signalCount(for: 1001, sig: SIGCONT) == 1)
        #expect(recorder.signalCount(for: 1002, sig: SIGCONT) == 1)
    }

    @Test func autoResumeRestoresProcessAfterTimeout() async throws {
        let recorder = SignalRecorder()
        let freezer = ProcessFreezer(
            killSignal: { pid, sig in recorder.send(pid: pid, sig: sig) },
            frontmostPID: { 999 },
            ownPID: { 555 }
        )

        let targetPID: Int32 = 8888
        // Set short timeout of 0.05 seconds (50ms) for test
        #expect(freezer.freeze(pid: targetPID, timeoutSeconds: 0.05))
        #expect(freezer.isFrozen(pid: targetPID))

        // Wait with jitter-resilient polling up to 1 second
        var waited = 0
        while freezer.isFrozen(pid: targetPID) && waited < 1000 {
            try await Task.sleep(for: .milliseconds(15))
            waited += 15
        }

        #expect(!freezer.isFrozen(pid: targetPID))
        #expect(recorder.signalCount(for: targetPID, sig: SIGCONT) == 1)
    }

    @Test func frozenCountAndHasFrozenProcessesTrackStateAccurately() {
        let recorder = SignalRecorder()
        let freezer = ProcessFreezer(
            killSignal: { pid, sig in recorder.send(pid: pid, sig: sig) },
            frontmostPID: { 999 },
            ownPID: { 555 }
        )

        #expect(!freezer.hasFrozenProcesses)
        #expect(freezer.frozenCount == 0)
        #expect(freezer.frozenPIDs.isEmpty)

        #expect(freezer.freeze(pid: 2001))
        #expect(freezer.hasFrozenProcesses)
        #expect(freezer.frozenCount == 1)
        #expect(freezer.frozenPIDs == [2001])

        #expect(freezer.freeze(pid: 2002))
        #expect(freezer.frozenCount == 2)
        #expect(freezer.frozenPIDs == [2001, 2002])

        #expect(freezer.resume(pid: 2001))
        #expect(freezer.frozenCount == 1)
        #expect(freezer.frozenPIDs == [2002])

        freezer.resumeAll()
        #expect(!freezer.hasFrozenProcesses)
        #expect(freezer.frozenCount == 0)
        #expect(freezer.frozenPIDs.isEmpty)
    }
}
