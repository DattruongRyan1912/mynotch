import Foundation
import Testing
@testable import TodoModule

/// Time here is a `ManualClock`: a change is fed, the test waits until the coalescer has taken it (its wait is
/// registered on the clock), then moves time by hand. Nothing depends on how long a real sleep takes.
@Suite struct ChangeCoalescerTests {
    let quiet = Duration.milliseconds(300)
    let clock = ManualClock()

    /// Counts the signals on `output` as they arrive.
    private func count(_ output: AsyncStream<Void>) -> (signals: Counter, consumer: Task<Void, Never>) {
        let signals = Counter()
        return (signals, Task { for await _ in output { signals.increment() } })
    }

    /// Feeds a change and waits until the coalescer has taken it, so the next step of time is deterministic.
    private func change(_ input: AsyncStream<Void>.Continuation, takenCalls: Int) async {
        input.yield()
        await settle { clock.sleepCalls == takenCalls }
    }

    @Test func aBurstBecomesOneSignal() async {
        let (source, input) = AsyncStream<Void>.makeStream()
        let (signals, consumer) = count(ChangeCoalescer.coalescing(source, quietPeriod: quiet, clock: clock))
        for call in 1...5 { await change(input, takenCalls: call) }
        input.finish()

        clock.advance(by: quiet)
        await consumer.value

        #expect(signals.value == 1)
    }

    @Test func noSignalWithoutChanges() async {
        let (source, input) = AsyncStream<Void>.makeStream()
        let (signals, consumer) = count(ChangeCoalescer.coalescing(source, quietPeriod: quiet, clock: clock))
        input.finish()
        await consumer.value

        #expect(signals.value == 0)
    }

    @Test func theSignalWaitsForQuietAfterTheLastChange() async {
        let (source, input) = AsyncStream<Void>.makeStream()
        let (signals, consumer) = count(ChangeCoalescer.coalescing(source, quietPeriod: quiet, clock: clock))
        defer { consumer.cancel() }

        await change(input, takenCalls: 1)
        clock.advance(by: quiet / 2)
        await change(input, takenCalls: 2)

        // The first change's quiet period is over, but the second one started a new one.
        clock.advance(by: quiet - .milliseconds(1))
        await letAnythingPending()
        #expect(signals.value == 0)

        clock.advance(by: .milliseconds(1))
        await settle { signals.value == 1 }
        #expect(signals.value == 1)
    }

    @Test func aContinuousStreamStillSignalsOnceTheMaxWaitPasses() async {
        let (source, input) = AsyncStream<Void>.makeStream()
        let maxWait = Duration.milliseconds(800)
        let (signals, consumer) = count(ChangeCoalescer.coalescing(source, quietPeriod: quiet, maxWait: maxWait, clock: clock))
        defer { consumer.cancel() }

        // A change every 100 ms is never quiet for 300 ms, so only the max wait can end the burst.
        for call in 1...7 {
            await change(input, takenCalls: call)
            if call < 7 { clock.advance(by: .milliseconds(100)) }
        }
        clock.advance(by: .milliseconds(199))
        await letAnythingPending()
        #expect(signals.value == 0)

        clock.advance(by: .milliseconds(1))
        await settle { signals.value == 1 }
        #expect(signals.value == 1)
    }

    @Test func aNewBurstAfterASignalWaitsForQuietAgain() async {
        let (source, input) = AsyncStream<Void>.makeStream()
        let (signals, consumer) = count(ChangeCoalescer.coalescing(source, quietPeriod: quiet, maxWait: quiet * 3, clock: clock))
        defer { consumer.cancel() }

        await change(input, takenCalls: 1)
        clock.advance(by: quiet)
        await settle { signals.value == 1 }

        await change(input, takenCalls: 2)
        clock.advance(by: quiet - .milliseconds(1))
        await letAnythingPending()
        #expect(signals.value == 1)

        clock.advance(by: .milliseconds(1))
        await settle { signals.value == 2 }
        #expect(signals.value == 2)
    }

    @Test(.timeLimit(.minutes(1)))
    func stoppingTheConsumerReleasesTheSource() async {
        let (source, input) = AsyncStream<Void>.makeStream()
        let (released, markReleased) = AsyncStream<Void>.makeStream()
        input.onTermination = { _ in markReleased.yield() }
        let consumer = Task { for await _ in ChangeCoalescer.coalescing(source, quietPeriod: quiet) {} }

        consumer.cancel()
        await consumer.value

        var iterator = released.makeAsyncIterator()
        #expect(await iterator.next() != nil)
    }
}
