#if DEBUG
import Foundation
import MyNotchCore
import MyNotchTestSupport
import SwiftUI
import Testing
@testable import DebugTools

@Suite struct DebugActivityTriggerTests {
    final class Clock {
        var now = ContinuousClock.now
        func advance(_ duration: Duration) { now = now.advanced(by: duration) }
    }

    final class Lines { var all: [String] = [] }

    final class Observer {
        var handler: (@MainActor (String?) -> Void)?
        var registrations = 0
        var removed = 0
        var observe: DebugActivityTrigger.Observe {
            { [self] handler in
                registrations += 1
                self.handler = handler
                return { [self] in removed += 1 }
            }
        }
        func send(_ object: String?) { handler?(object) }
    }

    let scheduler = ManualScheduler()
    let center: ActivityCenter
    let clock = Clock()
    let lines = Lines()
    let observer = Observer()
    let trigger: DebugActivityTrigger

    init() {
        center = ActivityCenter(scheduler: scheduler)
        let lines = lines
        trigger = DebugActivityTrigger(
            activities: center, observe: observer.observe, now: { [clock] in clock.now }, log: { lines.all.append($0) }
        )
    }

    /// A second later, so the next command is not dropped.
    @discardableResult
    func send(_ object: String?) -> Bool {
        clock.advance(.seconds(2))
        return trigger.receive(object)
    }

    func ids(_ entries: [ActivityCenter.Entry]) -> [String] { entries.map(\.id) }

    func settle(until condition: () -> Bool) async {
        for _ in 0..<200 where !condition() { await Task.yield() }
    }

    func realActivity(_ id: String = "now-playing", _ priority: ActivityPriority = .normal) -> LiveActivity {
        LiveActivity(id: id, priority: priority, leading: AnyView(EmptyView()), trailing: AnyView(EmptyView()))
    }

    @Test func theNotificationNameIsTheOneInTheBrief() {
        #expect(DebugActivityTrigger.notificationName.rawValue == "io.lucasvu.mynotch.debug.activities")
    }

    @Test func startObservesOnceThroughTheSeam() {
        #expect(!trigger.isObserving)
        trigger.start()
        trigger.start()
        #expect(trigger.isObserving)
        #expect(observer.registrations == 1)
    }

    @Test func addPublishesTheRequestedActivitiesUnderTheDebugModule() {
        trigger.start()
        observer.send("add 3")
        #expect(ids(center.ordered) == ["debug/debug-3", "debug/debug-2", "debug/debug-1"])
        let byID = Dictionary(uniqueKeysWithValues: center.ordered.map { ($0.activity.id, $0.activity) })
        #expect(byID["debug-1"]?.priority == .low && byID["debug-2"]?.priority == .normal && byID["debug-3"]?.priority == .high)
        #expect(byID["debug-2"]?.summary == "Thử nghiệm 2")
        #expect(byID.values.allSatisfy { $0.expiresAfter == nil && $0.minimal == nil && !$0.hasBottom })
    }

    @Test func addIsExactlyThatManyAndRepeatingItChangesNothing() {
        trigger.start()
        observer.send("add 5")
        #expect(center.ordered.count == 5)
        let before = ids(center.ordered)
        clock.advance(.seconds(2))
        observer.send("add 5")
        #expect(ids(center.ordered) == before)
        clock.advance(.seconds(2))
        observer.send("add 2")
        #expect(Set(ids(center.ordered)) == ["debug/debug-1", "debug/debug-2"])
    }

    @Test func fewerThanBeforeKeepsTheOnesThatAreStillWanted() {
        trigger.start()
        observer.send("add 4")
        clock.advance(.seconds(2))
        observer.send("add 1")
        #expect(center.ordered.count == 1)
        #expect(center.current?.activity.id == "debug-1")
    }

    @Test func highPromotesForEightSecondsAndThenTheFormerPrimaryComesBack() {
        trigger.start()
        center.set(realActivity(), from: "media")
        observer.send("high")
        #expect(center.current?.id == "debug/debug-high")
        #expect(ids(center.others) == ["media/now-playing"])
        scheduler.advance(by: .milliseconds(7900))
        #expect(center.current?.id == "debug/debug-high")
        scheduler.advance(by: .milliseconds(100))
        #expect(center.current?.id == "media/now-playing")
        #expect(center.others.isEmpty)
    }

    @Test func clearRemovesEveryDebugActivityAndNothingElse() {
        trigger.start()
        center.set(realActivity(), from: "media")
        observer.send("add 5")
        clock.advance(.seconds(2))
        observer.send("high")
        #expect(center.ordered.count == 7)
        clock.advance(.seconds(2))
        observer.send("clear")
        #expect(ids(center.ordered) == ["media/now-playing"])
    }

    @Test func clearWithNothingToClearIsHarmless() {
        trigger.start()
        observer.send("clear")
        #expect(center.ordered.isEmpty)
    }

    @Test func oneCommandPerSecond() {
        trigger.start()
        #expect(trigger.receive("add 2"))
        clock.advance(.milliseconds(500))
        #expect(!trigger.receive("clear"))
        #expect(center.ordered.count == 2)
        clock.advance(.milliseconds(500))
        #expect(trigger.receive("clear"))
        #expect(center.ordered.isEmpty)
    }

    @Test func somethingThatIsNoCommandDoesNothing() {
        trigger.start()
        for object in ["add 99", nil, "rm -rf /"] {
            #expect(!send(object))
        }
        #expect(center.ordered.isEmpty)
        #expect(send("add 1"))
        #expect(center.ordered.count == 1)
    }

    @Test func anObjectThatIsNoCommandIsThrottledLikeAnyOther() {
        trigger.start()
        #expect(!trigger.receive("nonsense"))
        clock.advance(.milliseconds(200))
        // Dropped for the rate, before anyone reads what it says; and the dropped one does not push the next back.
        #expect(!trigger.receive("add 2"))
        #expect(center.ordered.isEmpty)
        #expect(lines.all.filter { $0 == "command ignored: not a command" }.count == 1)
        #expect(lines.all.filter { $0 == "command ignored: one per second" }.count == 1)
        clock.advance(.milliseconds(800))
        #expect(trigger.receive("add 2"))
        #expect(center.ordered.count == 2)
    }

    @Test func thePublisherNeverTouchesAnotherModulesActivities() {
        trigger.start()
        center.set(realActivity("a"), from: "one")
        center.set(realActivity("a"), from: "two")
        observer.send("add 5")
        clock.advance(.seconds(2))
        observer.send("clear")
        #expect(ids(center.ordered) == ["one/a", "two/a"])
    }

    @Test func commandsAreLoggedButNeverTheirRawText() {
        trigger.start()
        trigger.receive("add 2")
        clock.advance(.milliseconds(100))
        trigger.receive("super-secret-clear")
        clock.advance(.seconds(2))
        trigger.receive("super-secret-text")
        #expect(lines.all.contains("command add 2"))
        #expect(lines.all.contains("command ignored: not a command"))
        #expect(lines.all.contains("command ignored: one per second"))
        #expect(!lines.all.contains { $0.contains("super-secret") })
    }

    @Test func everyChangeOfPrimaryAndBubblesIsLoggedAsIdsAndCounts() async {
        trigger.start()
        await settle { lines.all.contains("primary=- others=[] total=0") }
        #expect(lines.all.contains("primary=- others=[] total=0"))
        observer.send("add 2")
        await settle { lines.all.contains("primary=debug/debug-2 others=[debug/debug-1] total=2") }
        #expect(lines.all.contains("primary=debug/debug-2 others=[debug/debug-1] total=2"))
        center.set(realActivity(), from: "media")
        await settle { lines.all.contains("primary=debug/debug-2 others=[media/now-playing,debug/debug-1] total=3") }
        #expect(lines.all.contains("primary=debug/debug-2 others=[media/now-playing,debug/debug-1] total=3"))
        clock.advance(.seconds(2))
        observer.send("clear")
        await settle { lines.all.contains("primary=media/now-playing others=[] total=1") }
        #expect(lines.all.contains("primary=media/now-playing others=[] total=1"))
    }

    @Test func aChangeThatLeavesIdsAndCountsAloneIsNotLoggedAgain() async {
        trigger.start()
        center.set(realActivity(), from: "media")
        await settle { lines.all.contains("primary=media/now-playing others=[] total=1") }
        let count = lines.all.count
        // A content update of the primary: new revision, same ids.
        center.set(LiveActivity(id: "now-playing", expiresAfter: .seconds(60), leading: AnyView(EmptyView()), trailing: AnyView(EmptyView())), from: "media")
        for _ in 0..<50 { await Task.yield() }
        #expect(lines.all.count == count)
    }

    @Test func stopTakesTheObserverOff() {
        trigger.start()
        #expect(trigger.isObserving && observer.removed == 0)
        trigger.stop()
        #expect(!trigger.isObserving && observer.removed == 1)
    }

    @Test func stopCanBeCalledTwiceOrBeforeStart() {
        trigger.stop()
        #expect(observer.removed == 0)
        trigger.start()
        trigger.stop()
        trigger.stop()
        #expect(observer.removed == 1)
    }

    @Test func aStoppedTriggerCanStartAgain() {
        trigger.start()
        trigger.stop()
        trigger.start()
        #expect(trigger.isObserving && observer.registrations == 2)
        observer.send("add 1")
        #expect(center.ordered.count == 1)
    }

    @Test func stopEndsTheChangeLog() async {
        trigger.start()
        await settle { lines.all.contains("primary=- others=[] total=0") }
        trigger.stop()
        let count = lines.all.count
        center.set(realActivity(), from: "media")
        for _ in 0..<100 { await Task.yield() }
        #expect(lines.all.count == count)
        #expect(!lines.all.contains { $0.hasPrefix("primary=media/") })
    }

    @Test func whatWasPublishedStaysAfterStop() {
        trigger.start()
        observer.send("add 2")
        trigger.stop()
        #expect(center.ordered.count == 2)
    }

    @Test func describeIsIdsAndCountsOnly() {
        center.set(realActivity("a", .high), from: "one")
        center.set(realActivity("b"), from: "two")
        #expect(DebugActivityTrigger.describe(center) == "primary=one/a others=[two/b] total=2")
        #expect(DebugActivityTrigger.describe(ActivityCenter(scheduler: scheduler)) == "primary=- others=[] total=0")
    }
}
#endif
