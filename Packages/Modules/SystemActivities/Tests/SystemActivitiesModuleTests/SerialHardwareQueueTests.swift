import Dispatch
import Foundation
import Testing
@testable import SystemActivitiesModule

/// The real queue, with no hardware: only what the HUD relies on, that the work stays off the main thread and in order.
@Suite struct SerialHardwareQueueTests {
    @Test func workRunsOffTheMainThreadInOrderAndTheAnswersComeBackOnIt() async {
        let queue = SerialHardwareQueue()
        var answers: [(order: Int, ranOnMain: Bool, answeredOnMain: Bool)] = []
        await withCheckedContinuation { done in
            for order in 0..<20 {
                queue.run({ (order, Thread.isMainThread) }, then: { result in
                    answers.append((result.0, result.1, Thread.isMainThread))
                    if answers.count == 20 { done.resume() }
                })
            }
        }
        #expect(answers.map(\.order) == Array(0..<20))
        #expect(answers.allSatisfy { !$0.ranOnMain && $0.answeredOnMain })
    }

    @Test func workThatBlocksDoesNotHoldUpTheCaller() async {
        let queue = SerialHardwareQueue()
        let gate = DispatchSemaphore(value: 0)
        var answered = false
        queue.run({ gate.wait() }, then: { answered = true })
        // Back at once, with the work still waiting, like hardware that stalls.
        #expect(!answered)
        await withCheckedContinuation { done in
            queue.run({ gate.signal() }, then: { done.resume() })
            // The first piece blocks the queue, so the second cannot signal: release it from here.
            gate.signal()
        }
        #expect(answered)
    }
}
