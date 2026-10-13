import Foundation
import Synchronization
import Testing
@testable import CalendarModule

@Suite struct ChangeCoalescerTests {
    /// Long enough that a burst fed in one go never straddles it, even on a loaded machine.
    let quiet = Duration.milliseconds(300)

    @Test func aBurstBecomesOneSignal() async {
        let (source, input) = AsyncStream<Void>.makeStream()
        let output = ChangeCoalescer.coalescing(source, quietPeriod: quiet)
        for _ in 0..<5 { input.yield() }
        input.finish()

        var signals = 0
        for await _ in output { signals += 1 }

        #expect(signals == 1)
    }

    @Test func noSignalWithoutChanges() async {
        let (source, input) = AsyncStream<Void>.makeStream()
        let output = ChangeCoalescer.coalescing(source, quietPeriod: quiet)
        input.finish()

        var signals = 0
        for await _ in output { signals += 1 }

        #expect(signals == 0)
    }

    @Test func theSignalWaitsForQuietAfterTheLastChange() async throws {
        let (source, input) = AsyncStream<Void>.makeStream()
        var iterator = ChangeCoalescer.coalescing(source, quietPeriod: quiet).makeAsyncIterator()

        input.yield()
        try await Task.sleep(for: quiet / 2)
        let lastChange = ContinuousClock.now
        input.yield()
        await iterator.next()
        let waited = lastChange.duration(to: .now)

        #expect(waited >= quiet)
    }

    @Test func changesAfterTheQuietPeriodSignalAgain() async {
        let (source, input) = AsyncStream<Void>.makeStream()
        var iterator = ChangeCoalescer.coalescing(source, quietPeriod: quiet).makeAsyncIterator()

        input.yield()
        #expect(await iterator.next() != nil)
        input.yield()
        input.yield()
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

    @Test(.timeLimit(.minutes(1)))
    func aContinuousStreamStillSignalsOnceTheMaxWaitPasses() async {
        let (source, input) = AsyncStream<Void>.makeStream()
        let output = ChangeCoalescer.coalescing(source, quietPeriod: quiet, maxWait: quiet * 3)
        let start = ContinuousClock.now
        // A change every 100 ms is never quiet for 300 ms, so only the max wait can end the burst.
        let feeder = Task {
            while !Task.isCancelled {
                input.yield()
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
        defer { feeder.cancel() }

        var iterator = output.makeAsyncIterator()
        #expect(await iterator.next() != nil)
        let waited = start.duration(to: .now)

        #expect(waited >= quiet * 3 - .milliseconds(50))
        #expect(waited < .seconds(3))
    }

    @Test func aNewBurstAfterASignalWaitsForQuietAgain() async {
        let (source, input) = AsyncStream<Void>.makeStream()
        var iterator = ChangeCoalescer.coalescing(source, quietPeriod: quiet, maxWait: quiet * 3).makeAsyncIterator()

        input.yield()
        #expect(await iterator.next() != nil)
        // A new burst gets a new window: it waits for quiet again instead of signaling at once.
        let start = ContinuousClock.now
        input.yield()
        #expect(await iterator.next() != nil)
        #expect(start.duration(to: .now) >= quiet - .milliseconds(50))
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
