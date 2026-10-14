import Observation
import SwiftUI
import Testing
@testable import MyNotchCore
import MyNotchTestSupport

/// The activities besides the primary one: their order, the cap and how they follow the primary.
@Suite struct ActivityOthersTests {
    func ids(_ entries: [ActivityCenter.Entry]) -> [String] { entries.map(\.id) }

    @Test func nothingLiveMeansNoPrimaryAndNoOthers() {
        let center = ActivityCenter(scheduler: ManualScheduler())
        #expect(center.current == nil && center.others.isEmpty && center.ordered.isEmpty)
    }

    @Test func aSingleActivityIsPrimaryWithNoOthers() {
        let center = ActivityCenter(scheduler: ManualScheduler())
        center.set(activity("a"), from: "m")
        #expect(center.current?.id == "m/a")
        #expect(center.others.isEmpty)
        #expect(ids(center.ordered) == ["m/a"])
    }

    @Test func othersFollowPriorityThenWhoWasLiveFirst() {
        let center = ActivityCenter(scheduler: ManualScheduler())
        center.set(activity("n1"), from: "m")
        center.set(activity("l1", .low), from: "m")
        center.set(activity("h1", .high), from: "m")
        center.set(activity("n2"), from: "m")
        center.set(activity("c1", .critical), from: "m")
        #expect(center.current?.id == "m/c1")
        #expect(ids(center.others) == ["m/h1", "m/n1", "m/n2"])
        #expect(ids(center.ordered) == ["m/c1", "m/h1", "m/n1", "m/n2", "m/l1"])
    }

    @Test func aNewcomerAtTheSamePriorityJoinsBehindTheOthers() {
        let center = ActivityCenter(scheduler: ManualScheduler())
        center.set(activity("a"), from: "m")
        center.set(activity("b"), from: "m")
        center.set(activity("c"), from: "m")
        #expect(center.current?.id == "m/a")
        #expect(ids(center.others) == ["m/b", "m/c"])
    }

    @Test func aSamePriorityUpdateNeverReorders() {
        let center = ActivityCenter(scheduler: ManualScheduler())
        center.set(activity("a"), from: "m")
        center.set(activity("b"), from: "m")
        center.set(activity("c"), from: "m")
        for _ in 0..<3 {
            center.set(activity("c"), from: "m")
            center.set(activity("b"), from: "m")
            center.set(activity("a"), from: "m")
        }
        #expect(center.current?.id == "m/a")
        #expect(ids(center.others) == ["m/b", "m/c"])
    }

    @Test func aHighPriorityActivityTakesPrimaryAndTheFormerPrimaryBecomesTheFirstBubble() {
        let center = ActivityCenter(scheduler: ManualScheduler())
        center.set(activity("music"), from: "media")
        center.set(activity("timer"), from: "timer")
        #expect(center.current?.id == "media/music")
        #expect(ids(center.others) == ["timer/timer"])
        center.set(activity("alert", .high), from: "ai")
        #expect(center.current?.id == "ai/alert")
        #expect(ids(center.others) == ["media/music", "timer/timer"])
        center.clear(id: "alert", from: "ai")
        #expect(center.current?.id == "media/music")
        #expect(ids(center.others) == ["timer/timer"])
    }

    @Test func demotingThePrimaryGivesWayToTheOneLiveFirstAtTheNewPriority() {
        let center = ActivityCenter(scheduler: ManualScheduler())
        center.set(activity("music"), from: "media")
        center.set(activity("agent"), from: "ai")
        center.set(activity("agent", .low), from: "ai")
        #expect(center.current?.id == "media/music")
        center.set(activity("agent", .normal), from: "ai")
        #expect(center.current?.id == "media/music")
        center.set(activity("agent", .high), from: "ai")
        #expect(center.current?.id == "ai/agent")
        #expect(ids(center.others) == ["media/music"])
        center.set(activity("agent", .low), from: "ai")
        #expect(center.current?.id == "media/music")
        #expect(ids(center.others) == ["ai/agent"])
    }

    @Test func workingAtLowPriorityNeverHidesMusicWhicheverStartedFirst() {
        let center = ActivityCenter(scheduler: ManualScheduler())
        center.set(activity("agent", .low), from: "ai")
        center.set(activity("music"), from: "media")
        #expect(center.current?.id == "media/music")
        #expect(ids(center.others) == ["ai/agent"])
    }

    @Test func expiryRemovesABubble() {
        let scheduler = ManualScheduler()
        let center = ActivityCenter(scheduler: scheduler)
        center.set(activity("music"), from: "media")
        center.set(activity("copied", expiresAfter: .seconds(2)), from: "clipboard")
        center.set(activity("timer"), from: "timer")
        #expect(ids(center.others) == ["clipboard/copied", "timer/timer"])
        scheduler.advance(by: .seconds(2))
        #expect(ids(center.others) == ["timer/timer"])
        #expect(center.current?.id == "media/music")
    }

    @Test func theExpiryOfThePrimaryPromotesTheFirstBubble() {
        let scheduler = ManualScheduler()
        let center = ActivityCenter(scheduler: scheduler)
        center.set(activity("alert", .high, expiresAfter: .seconds(8)), from: "ai")
        center.set(activity("music"), from: "media")
        center.set(activity("timer"), from: "timer")
        scheduler.advance(by: .seconds(8))
        #expect(center.current?.id == "media/music")
        #expect(ids(center.others) == ["timer/timer"])
    }

    @Test func clearAllOfAModuleRemovesItsBubbles() {
        let center = ActivityCenter(scheduler: ManualScheduler())
        center.set(activity("music"), from: "media")
        center.set(activity("a"), from: "debug")
        center.set(activity("b"), from: "debug")
        center.clearAll(from: "debug")
        #expect(center.others.isEmpty)
        #expect(center.current?.id == "media/music")
    }

    @Test func othersAreCappedAtThreeByDefault() {
        let center = ActivityCenter(scheduler: ManualScheduler())
        for index in 1...6 { center.set(activity("a\(index)"), from: "m") }
        #expect(center.current?.id == "m/a1")
        #expect(ids(center.others) == ["m/a2", "m/a3", "m/a4"])
        #expect(center.ordered.count == 6)
    }

    @Test func theCapIsConfigurable() {
        let center = ActivityCenter(scheduler: ManualScheduler(), maxOthers: 1)
        for index in 1...4 { center.set(activity("a\(index)"), from: "m") }
        #expect(ids(center.others) == ["m/a2"])
        let none = ActivityCenter(scheduler: ManualScheduler(), maxOthers: 0)
        none.set(activity("a"), from: "m")
        none.set(activity("b"), from: "m")
        #expect(none.current?.id == "m/a" && none.others.isEmpty)
        let negative = ActivityCenter(scheduler: ManualScheduler(), maxOthers: -2)
        negative.set(activity("a"), from: "m")
        negative.set(activity("b"), from: "m")
        #expect(negative.others.isEmpty)
    }

    @Test func anActivityBeyondTheCapComesInWhenABubbleGoes() {
        let center = ActivityCenter(scheduler: ManualScheduler())
        for index in 1...5 { center.set(activity("a\(index)"), from: "m") }
        center.clear(id: "a3", from: "m")
        #expect(ids(center.others) == ["m/a2", "m/a4", "m/a5"])
        center.clear(id: "a1", from: "m")
        #expect(center.current?.id == "m/a2")
        #expect(ids(center.others) == ["m/a4", "m/a5"])
    }

    @Test func raiseTakesPrimaryAtItsPriorityAndTheOldPrimaryBecomesABubble() {
        let center = ActivityCenter(scheduler: ManualScheduler())
        center.set(activity("a"), from: "m")
        center.set(activity("b"), from: "m")
        center.set(activity("c"), from: "m")
        center.raise(id: "c", from: "m")
        #expect(center.current?.id == "m/c")
        #expect(ids(center.others) == ["m/a", "m/b"])
        center.raise(id: "b", from: "m")
        #expect(center.current?.id == "m/b")
        #expect(ids(center.others) == ["m/c", "m/a"])
    }

    @Test func sameIDInTwoModulesAreTwoActivities() {
        let center = ActivityCenter(scheduler: ManualScheduler())
        center.set(activity("x"), from: "one")
        center.set(activity("x"), from: "two")
        #expect(center.current?.id == "one/x")
        #expect(ids(center.others) == ["two/x"])
    }

    @Test func aStoppedModulesFacadeLeavesNoBubbleAndAddsNone() {
        let center = ActivityCenter(scheduler: ManualScheduler())
        let publisher = ActivityPublisher(center: center, module: "m")
        center.set(activity("music"), from: "media")
        publisher.set(activity("a"))
        publisher.set(activity("b"))
        #expect(ids(center.others) == ["m/a", "m/b"])
        publisher.invalidate()
        #expect(center.others.isEmpty)
        publisher.set(activity("late"))
        publisher.raise(id: "music")
        #expect(center.others.isEmpty)
        #expect(center.current?.id == "media/music")
    }

    @Test func changingTheOthersNotifiesAndLeavingThemAloneDoesNot() {
        let center = ActivityCenter(scheduler: ManualScheduler())
        for index in 1...5 { center.set(activity("a\(index)"), from: "m") }
        nonisolated(unsafe) var changes = 0
        func watch() { withObservationTracking { _ = center.others } onChange: { changes += 1 } }
        watch()
        // Beyond the cap: a5 is not a bubble, so nothing a bubble shows changes.
        center.clear(id: "a5", from: "m")
        center.set(activity("a6"), from: "m")
        #expect(changes == 0)
        center.clear(id: "a3", from: "m")
        #expect(changes == 1)
        watch()
        // Content of a bubble changed: its view has to be redrawn.
        center.set(activity("a2", expiresAfter: .seconds(60)), from: "m")
        #expect(changes == 2)
        watch()
        // Content of the primary changed: the bubbles stay as they are.
        center.set(activity("a1", expiresAfter: .seconds(60)), from: "m")
        #expect(changes == 2)
    }

    @Test func promotingTheFirstBubbleNotifiesBothCurrentAndOthers() {
        let center = ActivityCenter(scheduler: ManualScheduler())
        center.set(activity("a"), from: "m")
        center.set(activity("b"), from: "m")
        nonisolated(unsafe) var currentChanges = 0
        nonisolated(unsafe) var othersChanges = 0
        withObservationTracking { _ = center.current } onChange: { currentChanges += 1 }
        withObservationTracking { _ = center.others } onChange: { othersChanges += 1 }
        center.clear(id: "a", from: "m")
        #expect(currentChanges == 1 && othersChanges == 1)
        #expect(center.current?.id == "m/b" && center.others.isEmpty)
    }
}

@Suite struct LiveActivityDescriptionTests {
    @Test func theMinimalViewAndSummaryDefaultToNil() {
        let plain = activity("x")
        #expect(plain.minimal == nil)
        #expect(plain.summary == nil)
    }

    @Test func aMinimalViewAndSummaryAreKept() {
        let described = LiveActivity(
            id: "x", leading: AnyView(EmptyView()), trailing: AnyView(EmptyView()),
            minimal: AnyView(Image(systemName: "star")), summary: "Đang phát"
        )
        #expect(described.minimal != nil)
        #expect(described.summary == "Đang phát")
    }

    @Test func aBlankSummaryCountsAsNone() {
        for blank in ["", " ", " \n\t "] {
            let described = LiveActivity(id: "x", leading: AnyView(EmptyView()), trailing: AnyView(EmptyView()), summary: blank)
            #expect(described.summary == nil)
        }
    }

    @Test func aStripAndABubbleDescriptionCanBeCombined() {
        let both = LiveActivity(
            id: "x", leading: AnyView(EmptyView()), trailing: AnyView(EmptyView()),
            bottom: AnyView(Text("under")), bottomHeight: 36, minimal: AnyView(EmptyView()), summary: "s"
        )
        #expect(both.hasBottom && both.minimal != nil && both.summary == "s")
    }
}
