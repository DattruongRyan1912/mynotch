import Foundation
import Testing
@testable import MediaModule

@Suite struct LyricStripHoldTests {
    typealias Inputs = LyricStripHold.Inputs

    let start = Date(timeIntervalSinceReferenceDate: 1_000)

    let live = Inputs(enabled: true, playing: true, hasLyrics: true, lyricsPending: false)
    /// The lyrics are gone and the new ones are on their way, whether or not the new track already plays.
    let loading = Inputs(enabled: true, playing: true, hasLyrics: false, lyricsPending: true)
    let loadingPaused = Inputs(enabled: true, playing: false, hasLyrics: false, lyricsPending: true)
    /// Playback stopped for a moment while the lyrics stay.
    let stalled = Inputs(enabled: true, playing: false, hasLyrics: true, lyricsPending: false)
    /// The lookup ended and there are no synced lyrics.
    let none = Inputs(enabled: true, playing: true, hasLyrics: false, lyricsPending: false)

    func hold(after steps: [(Inputs, TimeInterval)] = []) -> LyricStripHold {
        var hold = LyricStripHold()
        for (inputs, seconds) in steps { hold.update(inputs, at: start + seconds) }
        return hold
    }

    @Test func theThresholdsAreThreeSecondsForANewTrackAndOneForAStall() {
        #expect(LyricStripHold.trackChangeHold == 3)
        #expect(LyricStripHold.stallHold == 1)
    }

    @Test func theStripShowsWhilePlayingWithLyricsAndNeedsNoTimer() {
        let hold = hold(after: [(live, 0)])
        #expect(hold.isShown)
        #expect(hold.nextDeadline == nil)
    }

    @Test func nothingIsShownBeforeTheStripHasBeenUp() {
        for inputs in [loading, loadingPaused, stalled, none] {
            let hold = hold(after: [(inputs, 0)])
            #expect(!hold.isShown)
            #expect(hold.nextDeadline == nil)
        }
    }

    @Test func aTrackChangeKeepsTheStripForThreeSecondsAfterTheLyricsWentAway() {
        var hold = hold(after: [(live, 0), (loading, 5)])
        #expect(hold.isShown)
        #expect(hold.nextDeadline == start + 8)

        hold.update(loadingPaused, at: start + 5.5)
        hold.update(loading, at: start + 7.9)
        #expect(hold.isShown)
        #expect(hold.nextDeadline == start + 8, "later updates do not push the end of the hold back")

        hold.tick(at: start + 7.99)
        #expect(hold.isShown)
        hold.tick(at: start + 8)
        #expect(!hold.isShown)
        #expect(hold.nextDeadline == nil)
    }

    @Test func lyricsArrivingInTimeKeepTheStripWithoutEverDroppingIt() {
        var hold = hold(after: [(live, 0), (loading, 5)])
        var seen = [hold.isShown]
        hold.update(live, at: start + 6.2)
        seen.append(hold.isShown)
        #expect(seen == [true, true])
        #expect(hold.nextDeadline == nil, "the timer is no longer needed")
        hold.tick(at: start + 20)
        #expect(hold.isShown)
    }

    @Test func aLookupThatEndsWithoutSyncedLyricsDropsTheStripAtOnce() {
        var hold = hold(after: [(live, 0), (loading, 5)])
        hold.update(none, at: start + 5.4)
        #expect(!hold.isShown)
        #expect(hold.nextDeadline == nil)
    }

    @Test func aTrackWithNothingToWaitForDropsTheStripAtOnce() {
        let hold = hold(after: [(live, 0), (none, 5)])
        #expect(!hold.isShown)
    }

    @Test func aStallKeepsTheStripForOneSecond() {
        var hold = hold(after: [(live, 0), (stalled, 5)])
        #expect(hold.isShown)
        #expect(hold.nextDeadline == start + 6)
        hold.update(stalled, at: start + 5.9)
        #expect(hold.isShown)
        hold.tick(at: start + 6)
        #expect(!hold.isShown)
    }

    @Test func aStallThatEndsInTimeNeverShowsAGap() {
        var hold = hold(after: [(live, 0), (stalled, 5)])
        hold.update(live, at: start + 5.8)
        #expect(hold.isShown)
        #expect(hold.nextDeadline == nil)
        // The next stall measures from itself, not from the first one.
        hold.update(stalled, at: start + 30)
        #expect(hold.isShown)
        #expect(hold.nextDeadline == start + 31)
    }

    @Test func aTrackChangeDuringAStallEndsThreeSecondsAfterTheStallBegan() {
        var hold = hold(after: [(live, 0), (stalled, 5)])
        hold.update(loading, at: start + 5.5)
        #expect(hold.isShown)
        #expect(hold.nextDeadline == start + 8)
    }

    @Test func aHoldThatRanOutDoesNotComeBackWithoutLiveLyrics() {
        var hold = hold(after: [(live, 0), (loading, 5)])
        hold.tick(at: start + 8)
        hold.update(loading, at: start + 8.1)
        hold.update(stalled, at: start + 8.2)
        #expect(!hold.isShown)
        hold.update(live, at: start + 9)
        #expect(hold.isShown, "it grows again when the lyrics finally arrive")
    }

    @Test func aStalledUpdateAfterTheDeadlineAlsoEndsTheHold() {
        var hold = hold(after: [(live, 0), (stalled, 5)])
        hold.update(stalled, at: start + 6.5)
        #expect(!hold.isShown)
    }

    @Test func switchingTheSettingOffEndsEverythingAtOnce() {
        var hold = hold(after: [(live, 0), (loading, 5)])
        hold.update(Inputs(enabled: false, playing: true, hasLyrics: true, lyricsPending: false), at: start + 5.2)
        #expect(!hold.isShown)
        #expect(hold.nextDeadline == nil)
        hold.update(live, at: start + 5.3)
        #expect(hold.isShown)
    }

    @Test func aTickWithNothingHeldChangesNothing() {
        var hold = hold(after: [(live, 0)])
        hold.tick(at: start + 100)
        #expect(hold.isShown)
        var idle = LyricStripHold()
        idle.tick(at: start)
        #expect(!idle.isShown)
    }
}
