import Foundation
import Testing
@testable import MediaModule

@Suite struct KaraokeClockTests {
    let start = Date(timeIntervalSince1970: 2_000)

    func state(playing: Bool = true, rate: Double = 1, elapsed: Double = 10, duration: Double? = 100) -> NowPlayingState {
        NowPlayingState(
            bundleIdentifier: "com.example.Player", title: "Song", durationSeconds: duration,
            elapsedAnchor: PlaybackAnchor(elapsedSeconds: elapsed, timestamp: start, rate: rate), isPlaying: playing
        )
    }

    @Test func itReadsTheSamePositionAsThePlaybackClock() {
        for state in [state(), state(playing: false), state(rate: 2), state(elapsed: 99, duration: 100), state(duration: nil)] {
            let clock = KaraokeClock(state)
            for seconds in [-5.0, 0, 3, 40, 500] {
                #expect(clock.position(at: start + seconds) == PlaybackClock.position(state, at: start + seconds))
            }
        }
    }

    @Test func noAnchorMeansNoPositionAndNoRate() {
        let clock = KaraokeClock(NowPlayingState(bundleIdentifier: "com.example.Player", title: "Song", isPlaying: true))
        #expect(clock.position(at: start) == nil)
        #expect(clock.rate == 0)
    }

    @Test func theRateIsTheAnchorsWhilePlayingAndZeroWhilePaused() {
        #expect(KaraokeClock(state(rate: 1.5)).rate == 1.5)
        #expect(KaraokeClock(state(playing: false, rate: 1.5)).rate == 0)
        #expect(KaraokeClock(state(rate: 0)).rate == 0)
    }

    @Test func onlyWhatTheSweepDependsOnMakesTwoClocksDiffer() {
        var other = state()
        other.title = "Another"
        other.album = "Album"
        #expect(KaraokeClock(state()) == KaraokeClock(other))
        #expect(KaraokeClock(state()) != KaraokeClock(state(elapsed: 11)))
        #expect(KaraokeClock(state()) != KaraokeClock(state(playing: false)))
        #expect(KaraokeClock(state()) != KaraokeClock(state(rate: 2)))
    }
}
