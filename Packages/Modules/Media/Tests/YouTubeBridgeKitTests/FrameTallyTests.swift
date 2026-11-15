import Foundation
import Testing
@testable import YouTubeBridgeKit

@Suite struct FrameTallyTests {
    let clock = TestClock()

    func makeTally() -> FrameTally {
        FrameTally(counted: "forwarded", lost: "dropped", interval: 10, now: { [clock] in clock.now })
    }

    @Test func aSummaryNamesEachKindAndReasonWithItsCountSorted() {
        let tally = makeTally()
        for kind in ["playback", "playback", "captions", "playback", "diag"] { tally.count(kind) }
        tally.lose("app-away")
        tally.lose("app-away")
        tally.lose("invalid-clear")
        clock.advance(by: 10)
        #expect(tally.line() == "forwarded[captions=1 diag=1 playback=3] dropped[app-away=2 invalid-clear=1]")
    }

    @Test func aGroupWithNothingInItIsLeftOut() {
        let tally = makeTally()
        tally.count("clear")
        #expect(tally.line(force: true) == "forwarded[clear=1]")
        tally.lose("too-large")
        #expect(tally.line(force: true) == "dropped[too-large=1]")
    }

    @Test func aSummaryComesOnlyOnceEveryTenSecondsAndOnlyWithSomethingToSay() {
        let tally = makeTally()
        #expect(tally.line() == nil)
        tally.count("playback")
        #expect(tally.line() == nil, "not yet ten seconds")
        clock.advance(by: 9.9)
        #expect(tally.line() == nil)
        clock.advance(by: 0.1)
        #expect(tally.line() == "forwarded[playback=1]")
        // Counting starts over, and so does the wait.
        tally.count("playback")
        clock.advance(by: 9)
        #expect(tally.line() == nil)
        clock.advance(by: 1)
        #expect(tally.line() == "forwarded[playback=1]")
        clock.advance(by: 30)
        #expect(tally.line() == nil, "nothing new")
    }

    @Test func aForcedSummaryComesAtOnceOnceAndEmptiesTheCounts() {
        let tally = makeTally()
        tally.count("captions")
        #expect(tally.line(force: true) == "forwarded[captions=1]")
        #expect(tally.line(force: true) == nil)
    }

    @Test func aNoticeIsAnnouncedOncePerKeyEveryTenSeconds() {
        let tally = makeTally()
        #expect(tally.announces("invalid-clear"))
        #expect(!tally.announces("invalid-clear"))
        #expect(tally.announces("malformed"))
        clock.advance(by: 9.9)
        #expect(!tally.announces("invalid-clear"))
        clock.advance(by: 0.1)
        #expect(tally.announces("invalid-clear"))
    }
}
