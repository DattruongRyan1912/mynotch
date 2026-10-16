import Foundation
import Testing
@testable import ClipboardModule

/// The line decodes wait in: a few at once, the rest in order, and a request that is cancelled while it waits leaves it.
@Suite struct ClipboardDecodeGateTests {
    func eventually(_ condition: () -> Bool) async -> Bool {
        // By the clock, not by the count: the cooperative pool is shared with the heavy tests of this package, which can keep a decode
        // from starting for many seconds.
        let deadline = ContinuousClock.now + .seconds(240)
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return condition()
    }

    @Test func theLimitIsAtLeastOne() {
        #expect(ClipboardDecodeGate(limit: 0).limit == 1)
        #expect(ClipboardDecodeGate(limit: -3).limit == 1)
        #expect(ClipboardDecodeGate(limit: 4).limit == 4)
    }

    @Test func theSlotsUpToTheLimitAreGivenAtOnceAndTheRestWait() async {
        let gate = ClipboardDecodeGate(limit: 3)
        var tasks: [Task<Bool, Never>] = []
        for _ in 0..<5 { tasks.append(Task { await gate.acquire() }) }

        #expect(await eventually { gate.running == 3 && gate.queued == 2 })
        #expect(gate.peak == 3)

        // A slot given back goes to the one that has waited longest; the number running stays at the limit.
        gate.release()
        #expect(await eventually { gate.queued == 1 })
        #expect(gate.running == 3)
        gate.release()
        #expect(await eventually { gate.queued == 0 })
        #expect(gate.running == 3)
        #expect(gate.peak == 3)

        for _ in 0..<3 { gate.release() }
        #expect(gate.running == 0)
        for task in tasks { #expect(await task.value) }
    }

    @Test func requestsAreServedInTheOrderTheyAsked() async {
        let gate = ClipboardDecodeGate(limit: 1)
        #expect(await gate.acquire())
        let served = Order()
        var tasks: [Task<Void, Never>] = []
        for index in 0..<4 {
            tasks.append(Task {
                if await gate.acquire() {
                    served.append(index)
                    gate.release()
                }
            })
            // One at a time into the queue, so the order they asked in is known.
            #expect(await eventually { gate.queued == index + 1 })
        }

        gate.release()
        for task in tasks { await task.value }

        #expect(served.values == [0, 1, 2, 3])
        #expect(gate.running == 0)
    }

    final class Order: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: [Int] = []
        var values: [Int] { lock.withLock { stored } }
        func append(_ value: Int) { lock.withLock { stored.append(value) } }
    }

    @Test func aRequestCancelledWhileItWaitsLeavesTheLineAndNeverRuns() async {
        let gate = ClipboardDecodeGate(limit: 1)
        #expect(await gate.acquire())
        let waiting = Task { await gate.acquire() }
        #expect(await eventually { gate.queued == 1 })

        waiting.cancel()

        #expect(await waiting.value == false)
        #expect(gate.queued == 0)
        // The slot was never theirs: giving back the one that is held frees it.
        gate.release()
        #expect(gate.running == 0)
    }

    @Test func aRequestThatWasCancelledBeforeItAskedIsRefusedWithoutTakingASlot() async {
        let gate = ClipboardDecodeGate(limit: 2)
        let task = Task {
            while !Task.isCancelled { await Task.yield() }
            return await gate.acquire()
        }
        task.cancel()

        #expect(await task.value == false)
        #expect(gate.running == 0)
        #expect(gate.queued == 0)
    }

    @Test func manyCancelledRequestsLeaveNothingBehindAndNewOnesStillRun() async {
        let gate = ClipboardDecodeGate(limit: 2)
        #expect(await gate.acquire())
        #expect(await gate.acquire())
        var waiting: [Task<Bool, Never>] = []
        for _ in 0..<50 { waiting.append(Task { await gate.acquire() }) }
        #expect(await eventually { gate.queued == 50 })

        for task in waiting { task.cancel() }
        for task in waiting { #expect(await task.value == false) }
        #expect(gate.queued == 0)
        #expect(gate.running == 2)

        gate.release()
        gate.release()
        #expect(gate.running == 0)
        // No slot was lost to the cancelled ones: the next two are given at once.
        #expect(await gate.acquire())
        #expect(await gate.acquire())
        #expect(gate.peak == 2)
        gate.release()
        gate.release()
    }

    @Test func cancellingTheOneThatWasJustGivenTheSlotDoesNotLoseIt() async {
        let gate = ClipboardDecodeGate(limit: 1)
        #expect(await gate.acquire())
        let waiting = Task { await gate.acquire() }
        #expect(await eventually { gate.queued == 1 })

        // The slot is handed over, and the cancel comes after: the answer was already yes, and the slot must still be given back.
        gate.release()
        let granted = await waiting.value
        waiting.cancel()
        #expect(granted)
        #expect(gate.running == 1)
        gate.release()
        #expect(gate.running == 0)
    }

    @Test func stressedByManyRequestsAndCancelsTheSlotsAreAlwaysGivenBack() async {
        let gate = ClipboardDecodeGate(limit: 4)
        var tasks: [Task<Void, Never>] = []
        for index in 0..<400 {
            tasks.append(Task {
                guard await gate.acquire() else { return }
                // A decode takes a moment, in which others come and go.
                await Task.yield()
                gate.release()
            })
            if index % 3 == 0 { tasks[index].cancel() }
        }
        for task in tasks { await task.value }

        #expect(gate.running == 0)
        #expect(gate.queued == 0)
        #expect(gate.peak <= 4)
    }
}
