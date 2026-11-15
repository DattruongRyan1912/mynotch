import Observation
import SwiftUI
import Testing
@testable import MyNotchCore
import MyNotchTestSupport

/// An activity can be shown on some screens only: each screen has the activities that are shown on it, in the center's order.
@Suite struct ActivityScopeTests {
    let a = "A-0000"
    let b = "B-1111"

    func scoped(
        _ id: String, _ scope: DisplayScope, _ priority: ActivityPriority = .normal, bottomScope: BottomScope = .allScreens
    ) -> LiveActivity {
        LiveActivity(
            id: id, priority: priority, leading: AnyView(EmptyView()), trailing: AnyView(EmptyView()), bottom: AnyView(Color.white),
            bottomHeight: 26, bottomScope: bottomScope, displayScope: scope
        )
    }

    func ids(_ entries: [ActivityCenter.Entry]) -> [String] { entries.map(\.id) }

    // MARK: The scope

    @Test func aScopeSaysOnWhichScreensItIs() {
        #expect(DisplayScope.allScreens.includes(a) && DisplayScope.allScreens.includes("anything"))
        #expect(DisplayScope.only([a]).includes(a) && !DisplayScope.only([a]).includes(b))
        #expect(!DisplayScope.only([]).includes(a))
        #expect(!DisplayScope.allExcept([a]).includes(a) && DisplayScope.allExcept([a]).includes(b))
        #expect(DisplayScope.allExcept([a]).includes("plugged in later"), "a screen nobody said anything about has it")
        #expect(DisplayScope.allExcept([]).includes(a))
    }

    @Test func anActivityIsOnEveryScreenUnlessItSaysOtherwise() {
        #expect(activity("x").displayScope == .allScreens)
        #expect(LiveActivity(id: "x", leading: AnyView(EmptyView()), trailing: AnyView(EmptyView())).displayScope == .allScreens)
        #expect(scoped("x", .only([a])).displayScope == .only([a]))
    }

    // MARK: The default is all screens

    @Test func withNoScopeEveryScreenSeesWhatTheCenterHasAndNothingIsRedrawnForIt() {
        let center = ActivityCenter(scheduler: ManualScheduler())
        for (id, priority) in [("n1", ActivityPriority.normal), ("l1", .low), ("h1", .high), ("n2", .normal), ("c1", .critical), ("n3", .normal)] {
            center.set(activity(id, priority), from: "m")
        }
        for display in [a, b, "never seen", nil] {
            let screen = center.screen(display)
            #expect(screen.current == center.current, "\(display ?? "nil")")
            #expect(screen.others == center.others)
            #expect(screen.ordered == center.ordered)
            #expect(screen.hiddenCount == center.hiddenCount && center.hiddenCount == 2)
        }
        #expect(center.screen(nil) === center.screen(nil) && center.screen(a) === center.screen(a))
        #expect(center.screen(a) !== center.screen(b))

        nonisolated(unsafe) var changes = 0
        let screen = center.screen(a)
        withObservationTracking { _ = screen.current; _ = screen.others; _ = screen.hiddenCount } onChange: { changes += 1 }
        center.set(activity("n3", .normal, summary: "an update of one nobody sees"), from: "m")
        #expect(changes == 0, "as the center's own, a screen is told of what it shows")
        center.set(activity("c1", .critical, summary: "an update of the primary"), from: "m")
        #expect(changes == 1)
    }

    // MARK: A screen and not another

    @Test func anActivityOfOneScreenIsPrimaryThereAndAbsentOnTheOther() {
        let center = ActivityCenter(scheduler: ManualScheduler())
        center.set(scoped("pet", .only([a]), .low), from: "pet")
        #expect(center.screen(a).current?.id == "pet/pet")
        #expect(center.screen(b).current == nil, "nothing there: the idle notch")
        #expect(center.screen(b).ordered.isEmpty && center.screen(b).others.isEmpty && center.screen(b).hiddenCount == 0)
        #expect(center.current?.id == "pet/pet", "the center counts every activity")
    }

    @Test func theOtherScreenFallsBackToTheNextActivity() {
        let center = ActivityCenter(scheduler: ManualScheduler())
        center.set(scoped("pet", .only([a]), .high), from: "pet")
        center.set(activity("music", .normal), from: "media")
        center.set(activity("count", .low), from: "todo")
        #expect(center.screen(a).current?.id == "pet/pet")
        #expect(ids(center.screen(a).others) == ["media/music", "todo/count"])
        #expect(center.screen(b).current?.id == "media/music", "the pet is not there: the next one is the primary")
        #expect(ids(center.screen(b).others) == ["todo/count"], "and not a bubble either")
        #expect(ids(center.screen(b).ordered) == ["media/music", "todo/count"], "nor a row of the list")
        #expect(ids(center.screen(a).ordered) == ["pet/pet", "media/music", "todo/count"])
    }

    @Test func theBubblesAndTheCountOfWhatIsLeftOutAreOfWhatTheScreenShows() {
        let center = ActivityCenter(scheduler: ManualScheduler(), maxOthers: 2)
        center.set(scoped("pet", .only([a]), .critical), from: "pet")
        for index in 1...4 { center.set(activity("a\(index)"), from: "m") }
        #expect(ids(center.screen(a).others) == ["m/a1", "m/a2"] && center.screen(a).hiddenCount == 2)
        #expect(ids(center.screen(b).others) == ["m/a2", "m/a3"] && center.screen(b).current?.id == "m/a1")
        #expect(center.screen(b).hiddenCount == 1, "four activities: the primary, two bubbles and one left out")
        #expect(center.hiddenCount == 2)
    }

    @Test func aScreenAllButOneIsOnEveryOtherAndOneAskedForLaterHasWhatItShould() {
        let center = ActivityCenter(scheduler: ManualScheduler())
        center.set(scoped("pet", .allExcept([a]), .low), from: "pet")
        #expect(center.screen(a).current == nil)
        #expect(center.screen(b).current?.id == "pet/pet")
        #expect(center.screen("plugged in later").current?.id == "pet/pet")
    }

    @Test func aScreenAskedForAfterTheActivitiesAreLiveIsRightAtOnce() {
        let center = ActivityCenter(scheduler: ManualScheduler())
        center.set(scoped("one", .only([a]), .high), from: "m")
        center.set(scoped("two", .only([b]), .normal), from: "m")
        center.set(activity("all", .low), from: "m")
        #expect(ids(center.screen(b).ordered) == ["m/two", "m/all"])
        #expect(ids(center.screen(a).ordered) == ["m/one", "m/all"])
    }

    // MARK: They follow the center

    @Test func aScreenFollowsEveryChangeOfTheEntries() {
        let center = ActivityCenter(scheduler: ManualScheduler())
        let screenA = center.screen(a)
        let screenB = center.screen(b)
        center.set(scoped("pet", .only([a]), .low), from: "pet")
        #expect(screenA.current?.id == "pet/pet" && screenB.current == nil)
        center.set(activity("music"), from: "media")
        #expect(screenA.current?.id == "media/music" && ids(screenA.others) == ["pet/pet"])
        #expect(screenB.current?.id == "media/music" && screenB.others.isEmpty)
        center.clear(id: "music", from: "media")
        #expect(screenA.current?.id == "pet/pet" && screenB.current == nil)
        center.clear(id: "pet", from: "pet")
        #expect(screenA.current == nil && screenB.current == nil && center.current == nil)
    }

    @Test func settingAnActivityAgainWithAnotherScopeMovesItAmongTheScreens() {
        let center = ActivityCenter(scheduler: ManualScheduler())
        center.set(scoped("pet", .only([a]), .low), from: "pet")
        #expect(center.screen(a).current != nil && center.screen(b).current == nil)
        center.set(scoped("pet", .only([b]), .low), from: "pet")
        #expect(center.screen(a).current == nil && center.screen(b).current != nil)
        center.set(scoped("pet", .allScreens, .low), from: "pet")
        #expect(center.screen(a).current != nil && center.screen(b).current != nil)
    }

    @Test func clearingAModulesActivitiesClearsThemOnEveryScreen() {
        let center = ActivityCenter(scheduler: ManualScheduler())
        center.set(scoped("pet", .only([a]), .low), from: "pet")
        center.set(scoped("pet2", .only([b]), .low), from: "pet")
        center.clearAll(from: "pet")
        #expect(center.screen(a).current == nil && center.screen(b).current == nil)
    }

    @Test func anExpiringActivityOfOneScreenLeavesItWhenItExpires() {
        let scheduler = ManualScheduler()
        let center = ActivityCenter(scheduler: scheduler)
        center.set(activity("music"), from: "media")
        center.set(
            LiveActivity(
                id: "volume", priority: .high, expiresAfter: .seconds(2), leading: AnyView(EmptyView()), trailing: AnyView(EmptyView()),
                displayScope: .only([a])
            ),
            from: "audio"
        )
        #expect(center.screen(a).current?.id == "audio/volume" && center.screen(b).current?.id == "media/music")
        scheduler.advance(by: .seconds(3))
        #expect(center.screen(a).current?.id == "media/music" && center.screen(b).current?.id == "media/music")
    }

    @Test func raisingAnActivityRaisesItOnTheScreensItIsOn() {
        let center = ActivityCenter(scheduler: ManualScheduler())
        center.set(activity("first"), from: "m")
        center.set(scoped("second", .only([a])), from: "m")
        #expect(center.screen(a).current?.id == "m/first")
        center.raise(id: "second", from: "m")
        #expect(center.screen(a).current?.id == "m/second")
        #expect(center.screen(b).current?.id == "m/first")
    }

    // MARK: Observation

    @Test func aScreenIsToldOnlyOfWhatHappensOnIt() {
        let center = ActivityCenter(scheduler: ManualScheduler())
        center.set(activity("music", .normal), from: "media")
        let screenB = center.screen(b)
        nonisolated(unsafe) var changes = 0
        withObservationTracking {
            _ = screenB.current; _ = screenB.others; _ = screenB.ordered; _ = screenB.hiddenCount
        } onChange: { changes += 1 }
        center.set(scoped("pet", .only([a]), .low), from: "pet")
        #expect(changes == 0, "an activity of the other screen is not news here")
        center.set(scoped("pet", .only([a]), .low, bottomScope: .hardwareNotchOnly), from: "pet")
        #expect(changes == 0)
        center.set(scoped("pet", .allScreens, .low), from: "pet")
        #expect(changes == 1, "it is on this screen now")
    }

    @Test func theScreenHandsOverWhatTheCenterOrdersByAndNothingElse() {
        // A screen that is asked for is not what makes the center's own readers redraw.
        let center = ActivityCenter(scheduler: ManualScheduler())
        center.set(activity("music"), from: "media")
        nonisolated(unsafe) var changes = 0
        withObservationTracking { _ = center.current } onChange: { changes += 1 }
        _ = center.screen(a)
        _ = center.screen(b)
        #expect(changes == 0)
    }

    // MARK: The strip scope is kept

    @Test func theStripScopeIsKeptAndIsNotTheDisplayScope() {
        let strip = scoped("pet", .only([a]), bottomScope: .hardwareNotchOnly)
        #expect(strip.bottomScope == .hardwareNotchOnly && strip.displayScope == .only([a]))
        #expect(strip.hasBottom && strip.bottomHeight == 26)
        #expect(strip.bottomHeight(onHardwareNotch: true) == 26 && strip.bottomHeight(onHardwareNotch: false) == 0)
        let everywhere = scoped("pet", .allScreens, bottomScope: .allScreens)
        #expect(everywhere.bottomHeight(onHardwareNotch: false) == 26)
        // An activity that is on a screen has its strip scope there as it always had it.
        let center = ActivityCenter(scheduler: ManualScheduler())
        center.set(strip, from: "pet")
        #expect(center.screen(a).current?.activity.bottomHeight(onHardwareNotch: false) == 0)
        #expect(center.screen(a).current?.activity.bottomHeight(onHardwareNotch: true) == 26)
        #expect(center.screen(b).current == nil)
    }
}
