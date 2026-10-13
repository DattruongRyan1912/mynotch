import Foundation
import Testing
@testable import TimerModule

@Suite struct TimerModelTests {
    let t0 = Date(timeIntervalSinceReferenceDate: 1_000)

    @Test func countdownRunsAndFinishesAtItsEndDate() {
        var model = TimerModel.idle
        model.startCountdown(minutes: 5, now: t0)
        #expect(model.remaining(now: t0.addingTimeInterval(100)) == 200)
        let finished1 = model.refresh(now: t0.addingTimeInterval(299))
        #expect(!finished1)
        let finished2 = model.refresh(now: t0.addingTimeInterval(300))
        #expect(finished2)
        #expect(model == .finished)
        let finished3 = model.refresh(now: t0.addingTimeInterval(400))
        #expect(!finished3)
    }

    @Test func pauseKeepsTheRemainingTimeAndResumeMovesTheEndDate() {
        var model = TimerModel.idle
        model.startCountdown(minutes: 10, now: t0)
        model.pause(now: t0.addingTimeInterval(120))
        #expect(model == .countdownPaused(remaining: 480))
        let finished4 = model.refresh(now: t0.addingTimeInterval(10_000))
        #expect(!finished4)
        model.resume(now: t0.addingTimeInterval(1_000))
        #expect(model == .countdown(endDate: t0.addingTimeInterval(1_480)))
    }

    @Test func clockJumpAcrossSleepFinishesTheCountdown() {
        var model = TimerModel.idle
        model.startCountdown(minutes: 5, now: t0)
        let finished5 = model.refresh(now: t0.addingTimeInterval(3_600))
        #expect(finished5)
        #expect(model.remaining(now: t0.addingTimeInterval(3_600)) == 0)
    }

    @Test func addMinuteExtendsRunningPausedAndFinishedCountdowns() {
        var running = TimerModel.idle
        running.startCountdown(minutes: 1, now: t0)
        running.addMinute(now: t0.addingTimeInterval(10))
        #expect(running == .countdown(endDate: t0.addingTimeInterval(120)))

        var paused = TimerModel.countdownPaused(remaining: 30)
        paused.addMinute(now: t0)
        #expect(paused == .countdownPaused(remaining: 90))

        var finished = TimerModel.finished
        finished.addMinute(now: t0)
        #expect(finished == .countdown(endDate: t0.addingTimeInterval(60)))

        var idle = TimerModel.idle
        idle.addMinute(now: t0)
        #expect(idle == .idle)
    }

    @Test func cancelReturnsToIdleFromAnyState() {
        for start in [TimerModel.countdown(endDate: t0), .countdownPaused(remaining: 5), .finished, .stopwatch(accumulated: 1, startedAt: t0)] {
            var model = start
            model.cancel()
            #expect(model == .idle)
        }
    }

    @Test func stopwatchAccumulatesAcrossPauseAndResume() {
        var model = TimerModel.idle
        model.startStopwatch(now: t0)
        #expect(model.elapsed(now: t0.addingTimeInterval(30)) == 30)
        model.pause(now: t0.addingTimeInterval(30))
        #expect(model == .stopwatchPaused(accumulated: 30))
        #expect(model.elapsed(now: t0.addingTimeInterval(500)) == 30)
        model.resume(now: t0.addingTimeInterval(100))
        #expect(model.elapsed(now: t0.addingTimeInterval(110)) == 40)
        let finished6 = model.refresh(now: t0.addingTimeInterval(100_000))
        #expect(!finished6)
    }

    @Test func pausingAStopwatchWhoseClockMovedBackKeepsWhatItHad() {
        var model = TimerModel.stopwatch(accumulated: 10, startedAt: t0)
        model.pause(now: t0.addingTimeInterval(-5))
        #expect(model == .stopwatchPaused(accumulated: 10))
    }

    @Test func startingWhileBusyReplacesTheTimer() {
        var model = TimerModel.idle
        model.startStopwatch(now: t0)
        model.startCountdown(minutes: 1, now: t0)
        #expect(model == .countdown(endDate: t0.addingTimeInterval(60)))
    }

    @Test func survivesEncodingRoundTrip() throws {
        for model in [TimerModel.idle, .countdown(endDate: t0), .countdownPaused(remaining: 9), .finished,
                      .stopwatch(accumulated: 3, startedAt: t0), .stopwatchPaused(accumulated: 4)] {
            let decoded = try JSONDecoder().decode(TimerModel.self, from: JSONEncoder().encode(model))
            #expect(decoded == model)
        }
    }

    @Test func clockFormatting() {
        #expect(TimerFormat.clock(0) == "0:00")
        #expect(TimerFormat.clock(59.4) == "0:59")
        #expect(TimerFormat.clock(600) == "10:00")
        #expect(TimerFormat.clock(3_725) == "1:02:05")
    }
}
