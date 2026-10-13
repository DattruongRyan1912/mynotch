import Foundation
import Testing
@testable import MediaModule

@Suite struct PlaybackProgressTests {
    let start = Date(timeIntervalSince1970: 1_000)

    func state(elapsed: Double = 30, at timestamp: Date? = nil, duration: Double? = 200, playing: Bool = true) -> NowPlayingState {
        NowPlayingState(
            bundleIdentifier: "com.example.Player", title: "Song", durationSeconds: duration,
            elapsedAnchor: PlaybackAnchor(elapsedSeconds: elapsed, timestamp: timestamp ?? start, rate: playing ? 1 : 0),
            isPlaying: playing
        )
    }

    @Test func formatsClockTimes() {
        #expect(PlaybackProgress.format(0) == "0:00")
        #expect(PlaybackProgress.format(59.9) == "0:59")
        #expect(PlaybackProgress.format(65) == "1:05")
        #expect(PlaybackProgress.format(3723) == "1:02:03")
        #expect(PlaybackProgress.format(-4) == "0:00")
        #expect(PlaybackProgress.format(.infinity) == "--:--")
    }

    @Test func texts() {
        let progress = PlaybackProgress(elapsed: 30, duration: 200)
        #expect(progress.elapsedText == "0:30")
        #expect(progress.remainingText == "-2:50")
        #expect(PlaybackProgress(elapsed: 30, duration: nil).remainingText == "")
        #expect(PlaybackProgress(elapsed: nil, duration: 200).elapsedText == "--:--")
    }

    @Test func fractionAndSeekTargetStayInTheTrack() {
        #expect(PlaybackProgress(elapsed: 50, duration: 200).fraction == 0.25)
        #expect(PlaybackProgress(elapsed: 500, duration: 200).fraction == 1)
        #expect(PlaybackProgress(elapsed: 50, duration: nil).fraction == 0)
        #expect(PlaybackProgress(elapsed: nil, duration: 200).fraction == 0)

        let progress = PlaybackProgress(elapsed: 50, duration: 200)
        #expect(progress.seconds(atFraction: 0.5) == 100)
        #expect(progress.seconds(atFraction: -1) == 0)
        #expect(progress.seconds(atFraction: 2) == 200)
        #expect(PlaybackProgress(elapsed: 50, duration: nil).seconds(atFraction: 0.5) == nil)
    }

    @Test func followsTheClockByDefault() {
        let progress = PlaybackProgress(state: state(), at: start + 10)
        #expect(progress == PlaybackProgress(elapsed: 40, duration: 200))
    }

    @Test func showsTheDragPosition() {
        let progress = PlaybackProgress(state: state(), at: start + 10, dragFraction: 0.75)
        #expect(progress == PlaybackProgress(elapsed: 150, duration: 200))
    }

    @Test func showsASentSeekUntilThePlayerReportsTheNewPosition() {
        let before = state()
        let seek = PendingSeek(seconds: 120, anchor: before.elapsedAnchor, date: start + 10)
        #expect(PlaybackProgress(state: before, at: start + 10.5, pendingSeek: seek).elapsed == 120)

        let reported = state(elapsed: 120.2, at: start + 10.3)
        #expect(PlaybackProgress(state: reported, at: start + 10.5, pendingSeek: seek).elapsed.map { abs($0 - 120.4) < 0.001 } == true)

        // The player never answered: fall back to the clock rather than freezing the bar.
        #expect(PlaybackProgress(state: before, at: start + 12, pendingSeek: seek).elapsed == 42)
    }
}

@Suite struct NowPlayingBarsTests {
    @Test func fakeLevelsStayInRangeAndMove() {
        let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
        var samples: [[Double]] = []
        for frame in 0..<120 {
            let levels = NowPlayingBars.levels(at: start + Double(frame) / 30)
            #expect(levels.count == NowPlayingBars.barCount)
            #expect(levels.allSatisfy { (0...1).contains($0) })
            samples.append(levels)
        }
        #expect(Set(samples.map { $0[0] }).count > 60)
    }
}
