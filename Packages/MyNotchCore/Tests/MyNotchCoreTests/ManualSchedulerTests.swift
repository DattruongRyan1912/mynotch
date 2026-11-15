import Testing
@testable import MyNotchCore
import MyNotchTestSupport

@Suite struct ManualSchedulerTests {
    @Test func runsDueActionsInOrderAndSkipsCancelled() {
        let scheduler = ManualScheduler()
        var log: [String] = []
        scheduler.schedule(after: .milliseconds(200)) { log.append("b") }
        scheduler.schedule(after: .milliseconds(100)) { log.append("a") }
        let cancelled = scheduler.schedule(after: .milliseconds(150)) { log.append("x") }
        cancelled.cancel()
        scheduler.advance(by: .milliseconds(150))
        #expect(log == ["a"])
        scheduler.advance(by: .milliseconds(50))
        #expect(log == ["a", "b"])
        #expect(scheduler.pendingCount == 0)
    }

    @Test func runsSeveralDueActionsInTimeOrder() {
        let scheduler = ManualScheduler()
        var log: [String] = []
        scheduler.schedule(after: .milliseconds(200)) { log.append("late") }
        scheduler.schedule(after: .milliseconds(100)) { log.append("early") }
        scheduler.advance(by: .milliseconds(300))
        #expect(log == ["early", "late"])
    }

    @Test func tiesRunInSchedulingOrder() {
        let scheduler = ManualScheduler()
        var log: [String] = []
        scheduler.schedule(after: .milliseconds(100)) { log.append("first") }
        scheduler.schedule(after: .milliseconds(100)) { log.append("second") }
        scheduler.advance(by: .milliseconds(100))
        #expect(log == ["first", "second"])
    }

    @Test func actionsScheduledDuringAdvanceRunWhenDueAndSeeTheirFireTime() {
        let scheduler = ManualScheduler()
        var log: [String] = []
        scheduler.schedule(after: .milliseconds(100)) {
            log.append("outer@\(scheduler.now)")
            scheduler.schedule(after: .milliseconds(50)) { log.append("inner@\(scheduler.now)") }
        }
        scheduler.schedule(after: .milliseconds(-10)) { log.append("negative@\(scheduler.now)") }
        scheduler.advance(by: .milliseconds(200))
        #expect(log == ["negative@0.0 seconds", "outer@0.1 seconds", "inner@0.15 seconds"])
        #expect(scheduler.now == .milliseconds(200))
    }
}
