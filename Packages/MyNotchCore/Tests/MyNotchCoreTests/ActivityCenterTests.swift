import Testing
@testable import MyNotchCore
import MyNotchTestSupport

@Suite struct ActivityCenterTests {
    @Test func highestPriorityWinsThenMostRecent() {
        let center = ActivityCenter(scheduler: ManualScheduler())
        center.set(activity("a", .normal), from: "one")
        center.set(activity("b", .high), from: "two")
        #expect(center.current?.id == "two/b")
        center.set(activity("c", .high), from: "one")
        #expect(center.current?.id == "one/c")
        center.clear(id: "c", from: "one")
        #expect(center.current?.id == "two/b")
    }

    @Test func expiresAfterLifetime() {
        let scheduler = ManualScheduler()
        let center = ActivityCenter(scheduler: scheduler)
        center.set(activity("charging", expiresAfter: .seconds(4)), from: "battery")
        scheduler.advance(by: .seconds(3))
        #expect(center.current?.id == "battery/charging")
        scheduler.advance(by: .seconds(1))
        #expect(center.current == nil)
    }

    @Test func replacingAnActivityRestartsItsLifetime() {
        let scheduler = ManualScheduler()
        let center = ActivityCenter(scheduler: scheduler)
        center.set(activity("x", expiresAfter: .seconds(4)), from: "m")
        scheduler.advance(by: .seconds(3))
        center.set(activity("x", expiresAfter: .seconds(4)), from: "m")
        scheduler.advance(by: .seconds(3))
        #expect(center.current?.id == "m/x")
        scheduler.advance(by: .seconds(1))
        #expect(center.current == nil)
    }

    @Test func clearAllRemovesOnlyThatModule() {
        let scheduler = ManualScheduler()
        let center = ActivityCenter(scheduler: scheduler)
        center.set(activity("a", expiresAfter: .seconds(4)), from: "one")
        center.set(activity("b", expiresAfter: .seconds(4)), from: "two")
        center.clearAll(from: "two")
        #expect(center.entries.map(\.id) == ["one/a"])
        #expect(center.current?.id == "one/a")
        #expect(scheduler.pendingCount == 1)
        scheduler.advance(by: .seconds(4))
        #expect(center.current == nil)
    }

    @Test func sameActivityIDInDifferentModulesIsIndependent() {
        let scheduler = ManualScheduler()
        let center = ActivityCenter(scheduler: scheduler)
        center.set(activity("x", expiresAfter: .seconds(4)), from: "one")
        center.set(activity("x"), from: "two")
        scheduler.advance(by: .seconds(4))
        #expect(center.entries.map(\.id) == ["two/x"])
    }

    @Test func invalidatedPublisherIsInert() {
        let center = ActivityCenter(scheduler: ManualScheduler())
        let publisher = ActivityPublisher(center: center, module: "m")
        publisher.set(activity("live"))
        publisher.invalidate()
        #expect(center.current == nil)
        publisher.set(activity("late"))
        #expect(center.current == nil)
    }
}
