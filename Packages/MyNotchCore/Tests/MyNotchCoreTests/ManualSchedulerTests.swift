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
}
