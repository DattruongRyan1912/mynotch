import Foundation
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
}
