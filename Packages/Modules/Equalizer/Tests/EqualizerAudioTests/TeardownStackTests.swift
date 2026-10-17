import Foundation
import Synchronization
import Testing
@testable import EqualizerAudio

/// What the undo closures did, in order.
private nonisolated final class Log: Sendable {
    private let entries = Mutex<[String]>([])
    var all: [String] { entries.withLock { $0 } }
    func add(_ entry: String) { entries.withLock { $0.append(entry) } }
}

@Suite struct TeardownStackTests {
    private struct StepFailed: Error {}

    @Test func unwindsInReverseOrder() {
        let log = Log()
        let stack = TeardownStack()
        stack.push { log.add("destroy tap") }
        stack.push { log.add("destroy aggregate") }
        stack.push { log.add("destroy IO proc") }
        stack.push { log.add("stop") }
        stack.unwind()
        #expect(log.all == ["stop", "destroy IO proc", "destroy aggregate", "destroy tap"])
    }

    @Test func runsEachStepOnce() {
        let log = Log()
        let stack = TeardownStack()
        stack.push { log.add("a") }
        stack.unwind()
        stack.unwind()
        #expect(log.all == ["a"])
    }

    @Test func aSetupThatFailsPartwayUndoesOnlyWhatWasDone() {
        let log = Log()
        let stack = TeardownStack()
        func setUp() throws {
            stack.push { log.add("destroy tap") }
            try { throw StepFailed() }()  // the aggregate device could not be made
            stack.push { log.add("destroy aggregate") }
        }
        do {
            try setUp()
        } catch {
            stack.unwind()
        }
        #expect(log.all == ["destroy tap"])
    }

    @Test func canBeUsedAgainAfterUnwinding() {
        let log = Log()
        let stack = TeardownStack()
        stack.push { log.add("first") }
        stack.unwind()
        stack.push { log.add("second") }
        stack.unwind()
        #expect(log.all == ["first", "second"])
    }
}
