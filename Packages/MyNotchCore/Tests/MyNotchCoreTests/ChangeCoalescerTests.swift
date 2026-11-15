import Foundation
import Synchronization
import Testing
import MyNotchTestSupport
@testable import MyNotchCore

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

    @Test func changesAfterTheQuietPeriodSignalAgain() async {
        let (source, input) = AsyncStream<Void>.makeStream()
        var iterator = ChangeCoalescer.coalescing(source, quietPeriod: quiet, clock: clock).makeAsyncIterator()

        await change(input, takenCalls: 1)
        clock.advance(by: quiet)
        #expect(await iterator.next() != nil)
        input.yield()
        await change(input, takenCalls: 3)
        clock.advance(by: quiet)
        #expect(await iterator.next() != nil)
        input.finish()
        #expect(await iterator.next() == nil)
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

    @Test func aContinuousStreamStillSignalsOnceTheMaxWaitPasses() async {
        let (source, input) = AsyncStream<Void>.makeStream()
        let maxWait = Duration.milliseconds(800)
        let (signals, consumer) = count(ChangeCoalescer.coalescing(source, quietPeriod: quiet, maxWait: maxWait, clock: clock))
        defer { consumer.cancel() }

        // A change every 100 ms is never quiet for 300 ms, so only the max wait can end the burst. The last
        // change comes at 600 ms: its quiet period would end at 900 ms, after the max wait.
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

        // A new burst gets a new window: it waits for quiet again instead of signaling at once.
        await change(input, takenCalls: 2)
        clock.advance(by: quiet - .milliseconds(1))
        await letAnythingPending()
        #expect(signals.value == 1)

        clock.advance(by: .milliseconds(1))
        await settle { signals.value == 2 }
        #expect(signals.value == 2)
    }

    @Test(.timeLimit(.minutes(1)))
    func aStreamNobodyIteratesReleasesItsSourceWhenDropped() async {
        let (source, input) = AsyncStream<Void>.makeStream()
        let (released, markReleased) = AsyncStream<Void>.makeStream()
        input.onTermination = { _ in markReleased.yield() }

        var output: AsyncStream<Void>? = ChangeCoalescer.coalescing(source, quietPeriod: quiet)
        #expect(output != nil)
        output = nil

        var iterator = released.makeAsyncIterator()
        #expect(await iterator.next() != nil)
    }
}

/// Lets the tasks the coalescer started run: they hop a few times between executors.
private func settle(timeout: Duration = .seconds(5), until condition: () -> Bool) async {
    let deadline = ContinuousClock.now + timeout
    while !condition(), ContinuousClock.now < deadline {
        try? await Task.sleep(for: .milliseconds(2))
    }
}

/// A short wait for the "nothing happens" checks, so a late task would have shown up.
private func letAnythingPending() async {
    try? await Task.sleep(for: .milliseconds(60))
}

private nonisolated final class Counter: Sendable {
    private let count = Mutex(0)

    var value: Int { count.withLock { $0 } }
    func increment() { count.withLock { $0 += 1 } }
}
