import Foundation
import Testing
@testable import MediaModule

@Suite struct PlaybackClockTests {
    let start = Date(timeIntervalSince1970: 1_000)

    func state(playing: Bool = true, rate: Double = 1, elapsed: Double = 10, duration: Double? = 100) -> NowPlayingState {
        NowPlayingState(
            bundleIdentifier: "com.example.Player", title: "Song", durationSeconds: duration,
            elapsedAnchor: PlaybackAnchor(elapsedSeconds: elapsed, timestamp: start, rate: rate), isPlaying: playing
        )
    }

    @Test func playingAdvancesFromTheAnchor() {
        #expect(PlaybackClock.position(state(), at: start) == 10)
        #expect(PlaybackClock.position(state(), at: start + 5) == 15)
    }

    @Test func pausedStaysAtElapsed() {
        #expect(PlaybackClock.position(state(playing: false), at: start + 5) == 10)
        #expect(PlaybackClock.position(state(playing: false, rate: 0), at: start + 5) == 10)
    }

    @Test func rateScalesTheAdvance() {
        #expect(PlaybackClock.position(state(rate: 2), at: start + 5) == 20)
    }

    @Test func clampsToTheTrack() {
        #expect(PlaybackClock.position(state(), at: start + 500) == 100)
        #expect(PlaybackClock.position(state(), at: start - 60) == 0)
        #expect(PlaybackClock.position(state(playing: false, elapsed: 130), at: start) == 100)
    }

    @Test func unknownDurationOnlyClampsAtZero() {
        #expect(PlaybackClock.position(state(duration: nil), at: start + 1_000) == 1_010)
        #expect(PlaybackClock.position(state(duration: nil), at: start - 60) == 0)
    }

    @Test func noAnchorMeansNoPosition() {
        #expect(PlaybackClock.position(NowPlayingState(bundleIdentifier: "com.example.Player", title: "Song", isPlaying: true), at: start) == nil)
        #expect(PlaybackClock.position(.empty, at: start) == nil)
    }
}
