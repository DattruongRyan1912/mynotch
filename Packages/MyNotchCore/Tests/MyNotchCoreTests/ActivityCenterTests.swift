import Observation
import Testing
@testable import MyNotchCore
import MyNotchTestSupport

@Suite struct ActivityCenterTests {
    @Test func highestPriorityWinsThenTheOneLiveFirst() {
        let center = ActivityCenter(scheduler: ManualScheduler())
        center.set(activity("a", .normal), from: "one")
        center.set(activity("b", .high), from: "two")
        #expect(center.current?.id == "two/b")
        center.set(activity("c", .high), from: "one")
        #expect(center.current?.id == "two/b")
        center.clear(id: "b", from: "two")
        #expect(center.current?.id == "one/c")
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
        #expect(scheduler.pendingCount == 1)
        scheduler.advance(by: .seconds(3))
        #expect(center.current?.id == "m/x")
        scheduler.advance(by: .seconds(1))
        #expect(center.current == nil)
    }

    @Test func updatingWithoutExpiryStopsExpiring() {
        let scheduler = ManualScheduler()
        let center = ActivityCenter(scheduler: scheduler)
        center.set(activity("x", expiresAfter: .seconds(4)), from: "m")
        center.set(activity("x"), from: "m")
        #expect(scheduler.pendingCount == 0)
        scheduler.advance(by: .seconds(60))
        #expect(center.current?.id == "m/x")
    }

    @Test func raiseKeepsAPendingExpiry() {
        let scheduler = ManualScheduler()
        let center = ActivityCenter(scheduler: scheduler)
        center.set(activity("y"), from: "m")
        center.set(activity("x", expiresAfter: .seconds(4)), from: "m")
        center.set(activity("z", expiresAfter: .seconds(10)), from: "m")
        #expect(center.current?.id == "m/z")
        center.raise(id: "x", from: "m")
        #expect(center.current?.id == "m/x")
        scheduler.advance(by: .seconds(4))
        #expect(center.entries.map(\.id) == ["m/y", "m/z"])
        #expect(center.current?.id == "m/z")
    }

    @Test func staleExpiryDoesNotRemoveAnUpdatedActivity() {
        let scheduler = UncancellableScheduler()
        let center = ActivityCenter(scheduler: scheduler)
        center.set(activity("x", expiresAfter: .seconds(4)), from: "m")
        scheduler.base.advance(by: .seconds(3))
        center.set(activity("x", expiresAfter: .seconds(4)), from: "m")
        scheduler.base.advance(by: .seconds(1))
        #expect(center.current?.id == "m/x")
        scheduler.base.advance(by: .seconds(3))
        #expect(center.current == nil)
    }

    @Test func updatingKeepsPositionAmongSamePriority() {
        let center = ActivityCenter(scheduler: ManualScheduler())
        center.set(activity("a"), from: "m")
        center.set(activity("b"), from: "m")
        center.set(activity("b"), from: "m")
        #expect(center.current?.id == "m/a")
        center.set(activity("a"), from: "m")
        center.set(activity("b"), from: "m")
        #expect(center.current?.id == "m/a")
        #expect(center.entries.map(\.id) == ["m/a", "m/b"])
    }

    @Test func updatingTheCurrentActivityNotifiesButKeepsItsPosition() {
        let center = ActivityCenter(scheduler: ManualScheduler())
        center.set(activity("a"), from: "m")
        center.set(activity("b"), from: "m")
        let before = center.current
        nonisolated(unsafe) var changes = 0
        withObservationTracking { _ = center.current } onChange: { changes += 1 }
        // expiresAfter stands in for new content: AnyView leading/trailing can't be compared.
        center.set(activity("a", expiresAfter: .seconds(10)), from: "m")
        #expect(changes == 1)
        #expect(center.current?.id == "m/a")
        #expect(center.current?.sequence == before?.sequence)
        #expect(center.current?.revision != before?.revision)
        #expect(center.current?.activity.expiresAfter == .seconds(10))
        #expect(center.entries.map(\.id) == ["m/a", "m/b"])
    }

    @Test func priorityStillDominatesUpdates() {
        let center = ActivityCenter(scheduler: ManualScheduler())
        center.set(activity("a"), from: "m")
        center.set(activity("b"), from: "m")
        center.set(activity("b", .high), from: "m")
        #expect(center.current?.id == "m/b")
        center.set(activity("b"), from: "m")
        #expect(center.current?.id == "m/a")
    }

    @Test func raiseWinsTiesAtItsPriority() {
        let center = ActivityCenter(scheduler: ManualScheduler())
        center.set(activity("a"), from: "m")
        center.set(activity("b"), from: "m")
        #expect(center.current?.id == "m/a")
        center.raise(id: "b", from: "m")
        #expect(center.current?.id == "m/b")
        center.raise(id: "missing", from: "m")
        center.raise(id: "a", from: "other")
        #expect(center.current?.id == "m/b")
        #expect(center.entries.map(\.id) == ["m/a", "m/b"])
        center.set(activity("c", .high), from: "m")
        center.raise(id: "a", from: "m")
        #expect(center.current?.id == "m/c")
    }

    @Test func clearingANonCurrentEntryDoesNotNotify() {
        let center = ActivityCenter(scheduler: ManualScheduler())
        center.set(activity("a"), from: "m")
        center.set(activity("b", .high), from: "m")
        nonisolated(unsafe) var changes = 0
        withObservationTracking { _ = center.current } onChange: { changes += 1 }
        center.clear(id: "a", from: "m")
        #expect(changes == 0)
        #expect(center.current?.id == "m/b")
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

    @Test func publisherRaiseIsInertAfterInvalidate() {
        let center = ActivityCenter(scheduler: ManualScheduler())
        let publisher = ActivityPublisher(center: center, module: "m")
        publisher.set(activity("a"))
        publisher.set(activity("b"))
        publisher.raise(id: "b")
        #expect(center.current?.id == "m/b")
        publisher.invalidate()
        center.set(activity("a"), from: "m")
        center.set(activity("b"), from: "m")
        publisher.raise(id: "b")
        #expect(center.current?.id == "m/a")
    }
}
