import Foundation
import Testing
@testable import PetModule

/// A watch fed a load a second at a time by a clock the test holds.
struct Feed {
    var watch = BusyWatch()
    var now: TimeInterval = 0
    /// The seconds at which a burst was on, as the stage would have asked at each of them.
    private(set) var bursting: [TimeInterval] = []

    /// `seconds` of the load, a sample a second.
    mutating func run(_ load: Double, seconds: Int) {
        for _ in 0..<seconds {
            now += 1
            watch.record(load, at: now)
            if watch.isBursting(at: now) { bursting.append(now) }
        }
    }

    /// The bursts as (start, end): runs of consecutive seconds.
    var bursts: [(start: TimeInterval, end: TimeInterval)] {
        var result: [(TimeInterval, TimeInterval)] = []
        for second in bursting {
            if let last = result.last, second - last.1 <= 1 { result[result.count - 1].1 = second } else { result.append((second, second)) }
        }
        return result
    }
}

@Suite struct BusyWatchTests {
    @Test func theRulesAreTheOnesThatWereAskedFor() {
        #expect((10 * 60...15 * 60).contains(BusyWatch.window), "the usual load is that of the last ten to fifteen minutes")
        #expect(BusyWatch.margin >= 0.25 && BusyWatch.floor >= 0.7, "clearly over it, and over seventy in a hundred")
        #expect(BusyWatch.hold >= 10, "and held for ten seconds at the least")
        #expect(BusyWatch.cooldown >= 5 * 60, "a burst no more often than every five minutes")
        #expect((15...20).contains(BusyWatch.longestBurst), "and of fifteen to twenty seconds at the most")
    }

    @Test func theUsualLoadIsUnknownUntilThereAreSamplesEnoughAndThenItIsTheMedian() {
        var feed = Feed()
        feed.run(0.3, seconds: BusyWatch.minimumSamples - 1)
        #expect(feed.watch.usual == nil)
        feed.run(0.3, seconds: 1)
        #expect(feed.watch.usual == 0.3)
        // A median is not moved by a spike of some seconds, as a mean would be.
        feed.run(1.0, seconds: 20)
        #expect(feed.watch.usual == 0.3)
        feed.run(0.1, seconds: 300)
        #expect(feed.watch.usual == 0.1)
    }

    @Test func samplesAgeOutOfTheWindow() {
        var feed = Feed()
        feed.run(0.9, seconds: 200)
        #expect(feed.watch.usual == 0.9)
        // The cat is away for longer than the window, and then back to a quiet Mac: the old samples are gone, not diluted.
        feed.now += BusyWatch.window + 60
        feed.watch.resume()
        feed.run(0.1, seconds: BusyWatch.minimumSamples)
        #expect(feed.watch.usual == 0.1)
    }

    @Test func aMacThatIsAlwaysBusyIsNeverInABurst() {
        var feed = Feed()
        feed.run(0.9, seconds: 30 * 60)
        #expect(feed.bursting.isEmpty, "busy is the normal state")
        var full = Feed()
        full.run(1.0, seconds: 30 * 60)
        #expect(full.bursting.isEmpty)
    }

    @Test func aSpikeOverTheUsualLoadIsABurstOnlyAfterItHasHeldForTheHoldAndItLastsNoLongerThanItsCap() throws {
        var feed = Feed()
        feed.run(0.05, seconds: 120)
        let before = feed.now
        feed.run(0.9, seconds: 60)
        let burst = try #require(feed.bursts.first)
        #expect(feed.bursts.count == 1)
        // The first second of the spike is the one after `before`, and it has held for the hold when the sample the hold later comes.
        #expect(burst.start == before + 1 + BusyWatch.hold, "after the spike has held for \(BusyWatch.hold) seconds, no sooner: \(burst.start - before)")
        #expect(burst.end - burst.start < BusyWatch.longestBurst, "and for no longer than its cap")
        #expect(burst.end - burst.start >= BusyWatch.longestBurst - 2, "though the load stays high, which is a burst until its cap")
    }

    @Test func aSpikeThatDoesNotHoldIsNoBurst() {
        var feed = Feed()
        feed.run(0.05, seconds: 120)
        feed.run(0.9, seconds: Int(BusyWatch.hold) - 1)
        feed.run(0.05, seconds: 60)
        #expect(feed.bursting.isEmpty)
        // Nor are two that, together, are as long, with a quiet second between them.
        feed.run(0.9, seconds: 6)
        feed.run(0.05, seconds: 1)
        feed.run(0.9, seconds: 6)
        feed.run(0.05, seconds: 60)
        #expect(feed.bursting.isEmpty)
    }

    @Test func aLoadThatIsOverTheUsualByTheMarginButUnderTheFloorIsNoSpike() {
        var feed = Feed()
        feed.run(0.05, seconds: 120)
        feed.run(BusyWatch.floor - 0.01, seconds: 120)
        #expect(feed.bursting.isEmpty, "a Mac that goes from idle to two thirds busy is not in trouble")
    }

    @Test func aLoadThatIsOverTheFloorButNotOverTheUsualByTheMarginIsNoSpike() {
        var feed = Feed()
        feed.run(0.6, seconds: 120)
        feed.run(0.6 + BusyWatch.margin - 0.02, seconds: 120)
        #expect(feed.bursting.isEmpty, "\(feed.watch.usual ?? -1)")
        var over = Feed()
        over.run(0.6, seconds: 120)
        over.run(0.6 + BusyWatch.margin + 0.02, seconds: 30)
        #expect(!over.bursting.isEmpty)
    }

    @Test func aBurstIsOverBeforeItsTimeWhenTheLoadEasesOffAndOtherwiseAtItsCap() throws {
        var feed = Feed()
        feed.run(0.05, seconds: 120)
        feed.run(0.9, seconds: Int(BusyWatch.hold) + 4)
        #expect(feed.watch.isBursting(at: feed.now))
        feed.run(0.1, seconds: 1)
        #expect(!feed.watch.isBursting(at: feed.now), "back to normal: over")
        feed.run(0.9, seconds: 10)
        #expect(feed.bursts.count == 1, "and does not begin again within the cooldown")
    }

    @Test func noBurstBeginsWithinTheCooldownOfTheLastOneAndAnotherDoesAfterIt() throws {
        var feed = Feed()
        feed.run(0.05, seconds: 120)
        // Spikes every minute for twenty minutes, each held for twenty seconds, over a Mac that is quiet in between.
        for _ in 0..<20 {
            feed.run(0.9, seconds: 20)
            feed.run(0.05, seconds: 40)
        }
        let starts = feed.bursts.map(\.start)
        #expect(starts.count >= 3 && starts.count <= 5, "\(starts)")
        for (before, after) in zip(starts, starts.dropFirst()) {
            #expect(after - before >= BusyWatch.cooldown, "a burst at \(after) after one at \(before)")
        }
        for burst in feed.bursts { #expect(burst.end - burst.start < BusyWatch.longestBurst) }
    }

    @Test func aMacThatTurnsBusyAndStaysSoGetsABurstNowAndThenUntilItsUsualHasCaughtUp() throws {
        var feed = Feed()
        feed.run(0.05, seconds: 15 * 60)
        feed.run(0.9, seconds: 40 * 60)
        let bursts = feed.bursts
        #expect(!bursts.isEmpty)
        #expect(bursts.count <= 3, "\(bursts)")
        for (before, after) in zip(bursts, bursts.dropFirst()) { #expect(after.start - before.start >= BusyWatch.cooldown) }
        for burst in bursts { #expect(burst.end - burst.start < BusyWatch.longestBurst) }
        #expect(try #require(feed.watch.usual) == 0.9, "and then busy is what is normal")
        let last = try #require(bursts.last)
        #expect(last.end < 15 * 60 + 20 * 60, "none after the usual has caught up: \(last)")
    }

    @Test func aGapInTheSamplesIsTimeTheCatWasNotThereAndASpikeDoesNotHoldThroughIt() {
        var feed = Feed()
        feed.run(0.05, seconds: 120)
        feed.run(0.9, seconds: 6)
        feed.now += 120
        feed.run(0.9, seconds: 6)
        #expect(feed.bursting.isEmpty)
    }

    @Test func comingBackClearsWhatWasHoldingAndABurstThatWasOnButNotTheCooldown() throws {
        var feed = Feed()
        feed.run(0.05, seconds: 120)
        feed.run(0.9, seconds: 14)
        #expect(feed.watch.isBursting(at: feed.now))
        feed.watch.resume()
        #expect(!feed.watch.isBursting(at: feed.now), "a burst does not go on while the cat is not there")
        feed.run(0.9, seconds: 60)
        #expect(feed.bursts.count == 1, "and the cat's going away and coming back does not make another one within the cooldown")
        feed.watch.resume()
        feed.run(0.05, seconds: 120)
        feed.watch.resume()
        feed.run(0.9, seconds: 30)
        #expect(feed.bursts.count == 1, "however often it comes back")
        // Once the cooldown is over it does.
        feed.run(0.05, seconds: Int(BusyWatch.cooldown))
        feed.run(0.9, seconds: 30)
        #expect(feed.bursts.count == 2)
    }

    @Test func theLoadsAreHeldToZeroAndOne() {
        var feed = Feed()
        feed.run(-3, seconds: 100)
        #expect(feed.watch.usual == 0)
        feed.run(7, seconds: 400)
        #expect(feed.watch.usual == 1)
    }
}
