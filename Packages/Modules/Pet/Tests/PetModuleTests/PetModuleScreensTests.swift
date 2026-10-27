import AppKit
import MyNotchCore
import MyNotchTestSupport
import NotchUI
import SwiftUI
import Testing
@testable import PetModule

/// The module with a choice for each screen: the pets reach the stages as soon as the choice is made, and with no pet on any screen that is
/// connected there is nothing to put on the notch.
@Suite(.serialized) @MainActor struct PetModuleScreensTests {
    func display(_ id: DisplayID, notch: Bool = false) -> ConnectedDisplay {
        ConnectedDisplay(id: id, name: "Display \(id)", hasNotch: notch)
    }

    @Test func theChoiceForAScreenReachesItsStageAtOnceAndNoOtherScreens() async throws {
        let harness = PetHarness()
        await harness.start()
        let stages = try #require(harness.madeStages)
        let notches = [try harness.notch(Screens.hardware, on: Screens.macID), try harness.notch(Screens.pill, on: Screens.externalID)]
        #expect(stages.all.count == 2)
        let mac = try #require(stages.stage(for: Screens.macID))

        harness.setting("screens", PetScreens().setting([], for: Screens.externalID))
        await harness.settle(until: { stages.stage(for: Screens.externalID) == nil })
        #expect(stages.stage(for: Screens.externalID) == nil && stages.stage(for: Screens.macID) === mac && mac.isTicking)
        #expect(stages.screens.kinds(for: Screens.externalID).isEmpty)
        let pill = try #require(notches.last?.container.lane)
        #expect(!pill.isShowingCat && pill.stage == nil)

        harness.setting("screens", PetScreens())
        await harness.settle(until: { stages.stage(for: Screens.externalID) != nil })
        #expect(try #require(stages.stage(for: Screens.externalID)).attachedHosts.count == 1 && pill.isShowingCat)
        withExtendedLifetime(notches) {}
    }

    @Test func withNoPetOnAnyScreenThatIsConnectedNothingIsPutOnTheNotchAndItComesBackWithOne() async throws {
        let harness = PetHarness()
        harness.connected.displays = [display("A", notch: true), display("B")]
        await harness.start()
        harness.advance(2)
        #expect(harness.cat != nil, "a cat on both, which is what a screen has")

        harness.setting("screens", PetScreens().setting([], for: "A"))
        await harness.settle()
        #expect(harness.cat != nil, "one of the two still has a pet")

        harness.setting("screens", PetScreens().setting([], for: "A").setting([], for: "B"))
        await harness.settle(until: { harness.cat == nil })
        #expect(harness.cat == nil && !harness.module.isShowing, "none left: the notch is not made wider for nothing")
        harness.advance(60)
        #expect(harness.cat == nil)

        harness.setting("screens", PetScreens().setting([], for: "A").setting([.cat], for: "B"))
        await harness.settle(until: { !harness.pendingShowIsEmpty })
        harness.advance(2)
        #expect(harness.cat != nil, "after the pause, as ever")
    }

    @Test func aScreenSetToNoneHasNoSuchActivityAndAScreenWithAPetKeepsIt() async throws {
        let harness = PetHarness()
        harness.connected.displays = [display("A", notch: true), display("B")]
        await harness.start()
        harness.advance(2)
        #expect(harness.cat?.activity.displayScope == .allScreens, "no choice: a cat on every screen")
        #expect(harness.activities.screen("A").current?.id == "pet/cat" && harness.activities.screen("B").current?.id == "pet/cat")

        harness.setting("screens", PetScreens().setting([], for: "A"))
        await harness.settle(until: { harness.activities.screen("A").current == nil })
        #expect(harness.cat?.activity.displayScope == .allExcept(["A"]))
        #expect(harness.activities.screen("A").current == nil, "the notch of A behaves as if the pet did not exist")
        #expect(harness.activities.screen("A").others.isEmpty && harness.activities.screen("A").ordered.isEmpty)
        #expect(harness.activities.screen("B").current?.id == "pet/cat", "B has its pet")
        #expect(harness.activities.screen("plugged in later").current?.id == "pet/cat", "and a screen nobody chose for has a cat")

        harness.setting("screens", PetScreens())
        await harness.settle(until: { harness.activities.screen("A").current != nil })
        #expect(harness.activities.screen("A").current?.id == "pet/cat" && harness.cat?.activity.displayScope == .allScreens)
    }

    @Test func theChoiceOfAScreenMovesTheActivityWithoutTakingItOffTheNotchAndKeepsItWhenThePlaceChanges() async throws {
        let harness = PetHarness()
        harness.connected.displays = [display("A", notch: true), display("B")]
        await harness.start()
        harness.advance(2)
        harness.setting("screens", PetScreens().setting([], for: "A"))
        await harness.settle(until: { harness.activities.screen("A").current == nil })
        #expect(harness.module.isShowing && harness.pendingShowIsEmpty, "put again at once, not taken off for a pause")

        harness.setting("playPlace", PlayPlace.strip)
        await harness.settle(until: { harness.cat?.activity.hasBottom == true })
        #expect(harness.cat?.activity.displayScope == .allExcept(["A"]), "the new place keeps the screens")
        #expect(harness.activities.screen("A").current == nil && harness.activities.screen("B").current?.id == "pet/cat")

        harness.setting("screens", PetScreens().setting([], for: "A").setting([], for: "B"))
        await harness.settle(until: { harness.cat == nil })
        #expect(harness.cat == nil, "none anywhere: not published at all, as before")
    }

    @Test func otherActivitiesShowOnAScreenWithNoPetAsOnAnyOther() async throws {
        let harness = PetHarness()
        harness.connected.displays = [display("A", notch: true), display("B")]
        harness.setting("screens", PetScreens().setting([], for: "A"))
        await harness.start()
        harness.advance(2)
        #expect(harness.activities.screen("A").current == nil && harness.activities.screen("B").current?.id == "pet/cat")
        harness.put("song")
        await harness.settle(until: { harness.cat == nil })
        for display in ["A", "B"] {
            #expect(harness.activities.screen(display).current?.id == "media/song", "\(display)")
        }
        harness.activities.clear(id: "song", from: PetHarness.someone)
        await harness.settle(until: { !harness.pendingShowIsEmpty })
        harness.advance(2)
        #expect(harness.activities.screen("A").current == nil && harness.activities.screen("B").current?.id == "pet/cat")
    }

    @Test func aScreenPluggedInIsOneThatMayHaveAPetAndOneTakenOutMayBeTheLastThatDid() async throws {
        let harness = PetHarness()
        harness.connected.displays = [display("A", notch: true)]
        await harness.start()
        harness.setting("screens", PetScreens().setting([], for: "A"))
        await harness.settle()
        harness.advance(5)
        #expect(harness.cat == nil, "the only screen has none")

        // A display nobody has chosen for is plugged in: it has a cat, and so there is something to show.
        harness.connected.displays = [display("A", notch: true), display("NEW")]
        harness.screenNotifications.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        await harness.settle(until: { !harness.pendingShowIsEmpty })
        harness.advance(2)
        #expect(harness.cat != nil)

        // It is unplugged again, and the one left has none.
        harness.connected.displays = [display("A", notch: true)]
        harness.screenNotifications.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        await harness.settle(until: { harness.cat == nil })
        #expect(harness.cat == nil)
    }

    @Test func theModuleStopsListeningToTheScreensWhenItStops() async throws {
        let harness = PetHarness()
        harness.connected.displays = [display("A")]
        await harness.start()
        harness.advance(2)
        await harness.registry.setEnabled(false, for: "pet")
        harness.connected.displays = [display("A"), display("B")]
        harness.screenNotifications.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        await harness.settle()
        harness.advance(10)
        #expect(harness.cat == nil && harness.scheduler.pendingCount == 0)
    }

    @Test func aChoiceMadeBeforeTheModuleStartsIsThereWhenItDoes() async throws {
        let harness = PetHarness()
        harness.setting("screens", PetScreens().setting([], for: Screens.externalID))
        await harness.start()
        let stages = try #require(harness.madeStages)
        #expect(stages.screens.kinds(for: Screens.externalID).isEmpty)
        let notch = try harness.notch(Screens.pill, on: Screens.externalID)
        #expect(stages.all.isEmpty && stages.stage(for: Screens.externalID) == nil)
        withExtendedLifetime(notch) {}
    }
}
