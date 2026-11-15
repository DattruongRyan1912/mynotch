import AppKit
import Foundation
import SwiftUI
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
        // A tick on a whole second can compute a hair below it; that is still the new second.
        #expect(PlaybackProgress.format(10.9999999) == "0:11")
    }

    @Test func remainingStepsTogetherWithElapsed() {
        // With a fractional length the remaining time still changes when the elapsed second does.
        #expect(PlaybackProgress(elapsed: 75.0, duration: 213.4).remainingText == "-2:18")
        #expect(PlaybackProgress(elapsed: 75.9, duration: 213.4).remainingText == "-2:18")
        #expect(PlaybackProgress(elapsed: 76.0, duration: 213.4).remainingText == "-2:17")
        #expect(PlaybackProgress(elapsed: 250, duration: 213.4).remainingText == "-0:00")
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
        for bar in 0..<NowPlayingBars.barCount {
            let levels = (0..<120).map { NowPlayingBars.level(bar: bar, at: start + Double($0) / 30) }
            #expect(levels.allSatisfy { (0...1).contains($0) })
            #expect(Set(levels).count > 60)
        }
        #expect(NowPlayingBars.level(bar: 0, at: start) != NowPlayingBars.level(bar: 1, at: start))
    }
}

@Suite struct PlaybackTickScheduleTests {
    let start = Date(timeIntervalSince1970: 1_000)

    func entries(_ schedule: PlaybackTickSchedule, from date: Date, count: Int = 4) -> [TimeInterval] {
        Array(schedule.entries(from: date, mode: .normal).prefix(count)).map { $0.timeIntervalSince(start) }
    }

    func expectClose(_ actual: [TimeInterval], _ expected: [TimeInterval]) {
        #expect(actual.count == expected.count)
        #expect(zip(actual, expected).allSatisfy { abs($0 - $1) < 1e-6 }, "\(actual) != \(expected)")
    }

    @Test func ticksWhenThePositionReachesWholeSeconds() {
        let anchor = PlaybackAnchor(elapsedSeconds: 10.4, timestamp: start, rate: 1)
        let schedule = PlaybackTickSchedule(anchor: anchor, isPlaying: true)
        expectClose(entries(schedule, from: start), [0, 0.6, 1.6, 2.6])
        // Starting later keeps the same phase instead of counting seconds from the start date.
        expectClose(entries(schedule, from: start + 5.3), [5.3, 5.6, 6.6, 7.6])
        // Exactly on a whole second the next tick is a full second away.
        expectClose(entries(schedule, from: start + 0.6, count: 2), [0.6, 1.6])
    }

    @Test func fasterPlaybackTicksMoreOften() {
        let schedule = PlaybackTickSchedule(anchor: PlaybackAnchor(elapsedSeconds: 3, timestamp: start, rate: 2), isPlaying: true)
        expectClose(entries(schedule, from: start + 0.1), [0.1, 0.5, 1, 1.5])
    }

    @Test func pausedOrUnknownPositionTicksOnce() {
        let paused = PlaybackTickSchedule(anchor: PlaybackAnchor(elapsedSeconds: 3, timestamp: start, rate: 0), isPlaying: false)
        #expect(entries(paused, from: start + 2) == [2])
        #expect(entries(PlaybackTickSchedule(anchor: nil, isPlaying: true), from: start) == [0])
    }
}

@Suite struct PlayerAppCacheTests {
    @Test func looksEachBundleUpOnce() {
        var requested: [String] = []
        let icon = NSImage(size: NSSize(width: 1, height: 1))
        let cache = PlayerAppCache { bundleID in
            requested.append(bundleID)
            return bundleID == "com.example.Player" ? PlayerApp(name: "Player", icon: icon) : nil
        }
        #expect(cache.app(for: "com.example.Player")?.name == "Player")
        #expect(cache.app(for: "com.example.Player")?.name == "Player")
        #expect(cache.app(for: "com.example.Missing") == nil)
        #expect(cache.app(for: "com.example.Missing") == nil)
        #expect(requested == ["com.example.Player", "com.example.Missing"])
    }
}
