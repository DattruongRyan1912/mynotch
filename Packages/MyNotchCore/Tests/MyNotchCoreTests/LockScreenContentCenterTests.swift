import SwiftUI
import Testing
@testable import MyNotchCore
import MyNotchTestSupport

@Suite struct LockScreenContentCenterTests {
    func view(_ text: String) -> AnyView { AnyView(Text(text)) }

    @Test func nothingRegisteredMeansNothingToShow() {
        let center = LockScreenContentCenter()
        #expect(center.current == nil)
        #expect(center.entries.isEmpty)
    }

    @Test func highestPriorityWinsThenMostRecentlyAdded() {
        let center = LockScreenContentCenter()
        center.set(view("a"), priority: .normal, from: "one")
        center.set(view("b"), priority: .high, from: "two")
        #expect(center.current?.module == "two")
        center.set(view("c"), priority: .high, from: "three")
        #expect(center.current?.module == "three")
        center.clear(from: "three")
        #expect(center.current?.module == "two")
        center.clear(from: "two")
        #expect(center.current?.module == "one")
    }

    @Test func settingAgainReplacesInPlaceWithoutReorderingTies() {
        let center = LockScreenContentCenter()
        center.set(view("a"), priority: .normal, from: "one")
        center.set(view("b"), priority: .normal, from: "two")
        center.set(view("a2"), priority: .normal, from: "one")
        #expect(center.entries.map(\.module) == ["one", "two"])
        #expect(center.current?.module == "two")
        center.set(view("a3"), priority: .critical, from: "one")
        #expect(center.entries.count == 2)
        #expect(center.current?.module == "one")
    }

    @Test func currentCanSkipContributorsTheCallerDoesNotWant() {
        let center = LockScreenContentCenter()
        center.set(view("timer"), priority: .high, from: "timer")
        center.set(view("media"), priority: .normal, from: "media")
        #expect(center.current(allowing: { $0 != "timer" })?.module == "media")
        #expect(center.current(allowing: { _ in false }) == nil)
    }

    @Test func changesNotifyObserversOfCurrent() {
        let center = LockScreenContentCenter()
        nonisolated(unsafe) var changes = 0
        withObservationTracking { _ = center.current } onChange: { changes += 1 }
        center.set(view("a"), priority: .normal, from: "one")
        #expect(changes == 1)
    }

    @Test func clearingAModuleThatHasNothingIsHarmless() {
        let center = LockScreenContentCenter()
        center.clear(from: "ghost")
        #expect(center.entries.isEmpty)
    }

    @Test func publisherIsScopedToItsModuleAndInertAfterInvalidate() {
        let center = LockScreenContentCenter()
        let media = LockScreenPublisher(center: center, module: "media")
        let timer = LockScreenPublisher(center: center, module: "timer")
        media.set(view("m"))
        timer.set(view("t"), priority: .high)
        #expect(center.entries.map(\.module) == ["media", "timer"])
        #expect(media.current(allowing: { _ in true })?.module == "timer")

        media.invalidate()
        #expect(center.entries.map(\.module) == ["timer"])
        media.set(view("late"))
        #expect(center.entries.map(\.module) == ["timer"])
        media.clear()
        timer.clear()
        #expect(center.current == nil)
    }

    @Test func stoppingTheModuleRemovesItsContent() async {
        let module = FakeModule("m")
        module.lockScreenOnStart = AnyView(Text("m"))
        let harness = RegistryHarness([module])
        await harness.registry.bootstrap()
        #expect(harness.lockScreen.current?.module == "m")

        await harness.registry.setEnabled(false, for: "m")
        #expect(harness.lockScreen.current == nil)
        module.context?.lockScreen.set(AnyView(Text("late")))
        #expect(harness.lockScreen.current == nil)
    }

    @Test func anEntryIsReadOnlyUnlessItsModuleSaysItHasControls() {
        let center = LockScreenContentCenter()
        center.set(view("timer"), priority: .normal, from: "timer")
        center.set(view("media"), priority: .normal, isInteractive: true, from: "media")
        #expect(center.entries.first { $0.module == "timer" }?.isInteractive == false)
        #expect(center.entries.first { $0.module == "media" }?.isInteractive == true)
    }

    @Test func replacingAnEntryReplacesItsFlagToo() {
        let center = LockScreenContentCenter()
        center.set(view("a"), priority: .normal, isInteractive: true, from: "one")
        center.set(view("b"), priority: .normal, from: "one")
        #expect(center.current?.isInteractive == false)
    }

    @Test func changingTheFlagNotifiesWhoeverReadsCurrent() {
        let center = LockScreenContentCenter()
        center.set(view("a"), priority: .normal, from: "one")
        nonisolated(unsafe) var changes = 0
        withObservationTracking { _ = center.current?.isInteractive } onChange: { changes += 1 }
        center.set(view("a"), priority: .normal, isInteractive: true, from: "one")
        #expect(changes == 1)
    }

    @Test func thePublisherPassesTheFlagOn() {
        let center = LockScreenContentCenter()
        let publisher = LockScreenPublisher(center: center, module: "media")
        publisher.set(view("m"), isInteractive: true)
        #expect(publisher.current(allowing: { _ in true })?.isInteractive == true)
        publisher.set(view("m"))
        #expect(publisher.current(allowing: { _ in true })?.isInteractive == false)
    }

    @Test func theLockScreenLetsControlsBeShownUnlessTheUserTurnedThemOff() {
        #expect(EnvironmentValues().lockScreenControlsEnabled)
        var environment = EnvironmentValues()
        environment.lockScreenControlsEnabled = false
        #expect(!environment.lockScreenControlsEnabled)
    }
}
