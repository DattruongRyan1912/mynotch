import Foundation
import SwiftUI
import Testing
@testable import MediaModule

/// The lyric view's timeline in karaoke mode ticks when a line changes, not four times a second.
@Suite struct LyricTickScheduleTests {
    let start = Date(timeIntervalSince1970: 5_000)
    let times: [Double] = [5, 12, 20, 20.5]

    func anchor(elapsed: Double = 10, rate: Double = 1) -> PlaybackAnchor {
        PlaybackAnchor(elapsedSeconds: elapsed, timestamp: start, rate: rate)
    }

    func entries(_ schedule: LyricTickSchedule, from date: Date? = nil) -> [Date] {
        Array(schedule.entries(from: date ?? start, mode: .normal))
    }

    @Test func itStartsNowAndThenTicksWhenEachLaterLineBegins() {
        let schedule = LyricTickSchedule(anchor: anchor(), isPlaying: true, lineTimes: times)
        let dates = entries(schedule)
        #expect(dates.count == 4)
        #expect(dates[0] == start)
        // 2 s, 10 s and 10.5 s on, a hair after the lyric changes so that the position is past it.
        for (date, seconds) in zip(dates.dropFirst(), [2.0, 10, 10.5]) {
            let late = date.timeIntervalSince(start) - seconds
            #expect(late > 0 && late <= LyricTickSchedule.settle + 1e-9, "\(seconds)")
        }
    }

    @Test func atEachTickTheNextLineIsTheOneBeingSung() {
        let lines = times.map { LyricLine(time: $0, text: "line \($0)") }
        let state = NowPlayingState(bundleIdentifier: "x", title: "t", durationSeconds: 100, elapsedAnchor: anchor(), isPlaying: true)
        let dates = entries(LyricTickSchedule(anchor: anchor(), isPlaying: true, lineTimes: times))
        let sung = dates.map { lines.line(at: PlaybackClock.position(state, at: $0) ?? 0)?.time }
        #expect(sung == [5, 12, 20, 20.5])
    }

    @Test func aFasterClockTicksSooner() {
        let dates = entries(LyricTickSchedule(anchor: anchor(rate: 2), isPlaying: true, lineTimes: times))
        #expect(abs(dates[1].timeIntervalSince(start) - 1) < LyricTickSchedule.settle * 2)
    }

    @Test func aTimelineStartedLaterSkipsTheLinesBeforeIt() {
        let dates = entries(LyricTickSchedule(anchor: anchor(), isPlaying: true, lineTimes: times), from: start + 5)
        #expect(dates.count == 3)
        #expect(dates[0] == start + 5)
        #expect(abs(dates[1].timeIntervalSince(start) - 10) < LyricTickSchedule.settle * 2)
    }

    @Test func aStartRightOnALineDoesNotTickForItAgain() {
        let dates = entries(LyricTickSchedule(anchor: anchor(), isPlaying: true, lineTimes: times), from: start + 2)
        #expect(dates.count == 3)
    }

    @Test func nothingFollowsTheLastLine() {
        #expect(entries(LyricTickSchedule(anchor: anchor(elapsed: 30), isPlaying: true, lineTimes: times)) == [start])
    }

    @Test func aPausedPlayerOrOneWithoutAPositionTicksOnlyOnce() {
        #expect(entries(LyricTickSchedule(anchor: anchor(), isPlaying: false, lineTimes: times)) == [start])
        #expect(entries(LyricTickSchedule(anchor: anchor(rate: 0), isPlaying: true, lineTimes: times)) == [start])
        #expect(entries(LyricTickSchedule(anchor: nil, isPlaying: true, lineTimes: times)) == [start])
    }

    @Test func withoutLinesItTicksOnlyOnce() {
        #expect(entries(LyricTickSchedule(anchor: anchor(), isPlaying: true, lineTimes: [])) == [start])
    }

    @Test func manyLinesAreTickedInOrderWithoutBuildingThemAll() {
        let many = (0..<5_000).map { Double($0) * 2 }
        let schedule = LyricTickSchedule(anchor: anchor(elapsed: 0), isPlaying: true, lineTimes: many)
        let first = Array(schedule.entries(from: start, mode: .normal).prefix(4))
        #expect(first.count == 4)
        #expect(zip(first, first.dropFirst()).allSatisfy { $0 < $1 })
    }
}
