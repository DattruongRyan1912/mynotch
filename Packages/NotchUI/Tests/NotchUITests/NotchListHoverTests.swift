import MyNotchCore
import MyNotchTestSupport
import SwiftUI
import Testing
@testable import NotchUI

/// Hovering a bubble opens the list of all live activities under the collapsed notch; leaving closes it like the notch.
@Suite struct NotchListHoverTests {
    let scheduler = ManualScheduler()

    /// A notch with an activity and `bubbles` bubbles beside it.
    func makeModel(bubbles: Int = 2, tabs: [ModuleID] = ["media", "battery"]) -> NotchViewModel {
        let model = NotchViewModel(scheduler: scheduler, availableTabs: { tabs }, delays: { (.milliseconds(150), .milliseconds(300)) })
        model.hasActivity = true
        model.bubbleCount = bubbles
        return model
    }

    // MARK: Opening

    @Test func hoveringABubbleOpensTheListAfterTheOpenDelay() {
        let model = makeModel()
        model.bubblesEntered()
        scheduler.advance(by: .milliseconds(149))
        #expect(!model.isListOpen)
        scheduler.advance(by: .milliseconds(1))
        #expect(model.isListOpen)
    }

    @Test func theListLeavesTheNotchsOwnStateAlone() {
        let model = makeModel()
        model.bubblesEntered()
        scheduler.advance(by: .milliseconds(150))
        #expect(model.isListOpen)
        // The collapsed notch stays what it was: only what hangs under it changes.
        #expect(model.state == .closed)
        #expect(model.displayState == .compact)
        #expect(!model.state.isExpanded)
        model.pointerExited()
        scheduler.advance(by: .milliseconds(300))
        #expect(!model.isListOpen)
        #expect(model.state == .closed && model.displayState == .compact)
    }

    @Test func withoutBubblesThereIsNothingToOpen() {
        let model = makeModel(bubbles: 0)
        model.bubblesEntered()
        scheduler.advance(by: .seconds(1))
        #expect(!model.isListOpen)
        model.showList()
        #expect(!model.isListOpen)
    }

    @Test func leavingABubbleBeforeTheDelayCancelsTheList() {
        let model = makeModel()
        model.bubblesEntered()
        scheduler.advance(by: .milliseconds(100))
        model.pointerExited()
        scheduler.advance(by: .seconds(1))
        #expect(!model.isListOpen)
    }

    @Test func movingFromABubbleToTheNotchOpensTheNotchAndNotTheList() {
        let model = makeModel()
        model.bubblesEntered()
        scheduler.advance(by: .milliseconds(100))
        model.pointerEntered()
        scheduler.advance(by: .milliseconds(50))
        #expect(!model.isListOpen)
        #expect(model.state == .closed)
        scheduler.advance(by: .milliseconds(100))
        #expect(model.state == .open("media"))
        #expect(!model.isListOpen)
    }

    @Test func movingFromTheNotchToABubbleCancelsTheNotchOpenAndOpensTheListInstead() {
        let model = makeModel()
        model.pointerEntered()
        scheduler.advance(by: .milliseconds(100))
        model.bubblesEntered()
        scheduler.advance(by: .milliseconds(149))
        #expect(model.state == .closed)
        #expect(!model.isListOpen)
        scheduler.advance(by: .milliseconds(1))
        #expect(model.state == .closed)
        #expect(model.isListOpen)
    }

    @Test func hoveringTheNotchStillOpensItLikeBefore() {
        let model = makeModel()
        model.pointerEntered()
        scheduler.advance(by: .milliseconds(150))
        #expect(model.state == .open("media"))
        #expect(!model.isOpenedOnPurpose)
        #expect(!model.isListOpen)
    }

    // MARK: Closing

    @Test func movingTheListAwayClosesItAfterTheCloseDelayUnlessTheTipComesBack() {
        let model = makeModel()
        model.bubblesEntered()
        scheduler.advance(by: .milliseconds(150))
        model.pointerExited()
        scheduler.advance(by: .milliseconds(299))
        #expect(model.isListOpen)
        model.bubblesEntered()
        scheduler.advance(by: .seconds(1))
        #expect(model.isListOpen)
        model.pointerExited()
        scheduler.advance(by: .milliseconds(300))
        #expect(!model.isListOpen)
    }

    @Test func movingFromABubbleOntoTheListKeepsItOpen() {
        let model = makeModel()
        model.bubblesEntered()
        scheduler.advance(by: .milliseconds(150))
        model.listEntered()
        scheduler.advance(by: .seconds(1))
        #expect(model.isListOpen)
        #expect(model.hover == .list)
        model.pointerMoved(to: .bubbles)
        scheduler.advance(by: .seconds(1))
        #expect(model.isListOpen)
        model.pointerMoved(to: .outside)
        scheduler.advance(by: .milliseconds(300))
        #expect(!model.isListOpen)
    }

    @Test func crossingThePillOnTheWayToTheListDoesNotOpenTheNotchOrCloseTheList() {
        let model = makeModel()
        model.bubblesEntered()
        scheduler.advance(by: .milliseconds(150))
        // Bubble -> pill (a few ms) -> list.
        model.pointerMoved(to: .notch)
        scheduler.advance(by: .milliseconds(20))
        model.pointerMoved(to: .list)
        scheduler.advance(by: .seconds(2))
        #expect(model.isListOpen)
        #expect(model.state == .closed)
    }

    @Test func lingeringOnThePillWithTheListOpenOpensTheNotchAndTheListGivesWay() {
        let model = makeModel()
        model.bubblesEntered()
        scheduler.advance(by: .milliseconds(150))
        model.pointerMoved(to: .notch)
        scheduler.advance(by: .milliseconds(149))
        #expect(model.isListOpen)
        scheduler.advance(by: .milliseconds(1))
        #expect(model.state == .open("media"))
        #expect(!model.isListOpen)
    }

    @Test func aClickOutsideClosesTheList() {
        let model = makeModel()
        model.bubblesEntered()
        scheduler.advance(by: .milliseconds(150))
        model.clickedOutside()
        #expect(!model.isListOpen)
    }

    @Test func theListGoesWhenTheBubblesOrTheActivityGo() {
        let model = makeModel()
        model.bubblesEntered()
        scheduler.advance(by: .milliseconds(150))
        model.bubbleCount = 0
        #expect(!model.isListOpen)

        let gone = makeModel()
        gone.bubblesEntered()
        scheduler.advance(by: .milliseconds(150))
        gone.hasActivity = false
        gone.bubbleCount = 0
        #expect(!gone.isListOpen)
    }

    @Test func fewerBubblesKeepTheListWhileSomeRemain() {
        let model = makeModel(bubbles: 2)
        model.bubblesEntered()
        scheduler.advance(by: .milliseconds(150))
        model.bubbleCount = 1
        #expect(model.isListOpen)
    }

    @Test func openingTheNotchByAnyMeansClosesTheList() {
        for open in [
            { (model: NotchViewModel) in model.click() },
            { $0.toggle() },
            { $0.open(tab: "battery") },
            { $0.dragEntered(tab: "media") },
            { $0.showToast(AnyView(EmptyView()), duration: .seconds(2)) },
            { $0.close() },
        ] as [(NotchViewModel) -> Void] {
            let model = makeModel()
            model.bubblesEntered()
            scheduler.advance(by: .milliseconds(150))
            #expect(model.isListOpen)
            open(model)
            #expect(!model.isListOpen)
        }
    }

    @Test func aToastEndingNeverBringsTheListBack() {
        let model = makeModel()
        model.bubblesEntered()
        scheduler.advance(by: .milliseconds(150))
        model.showToast(AnyView(EmptyView()), duration: .seconds(2))
        model.pointerExited()
        scheduler.advance(by: .seconds(5))
        #expect(!model.isListOpen)
        #expect(model.state == .closed)
    }

    // MARK: Activating

    @Test func aModulesTabOpensOnPurposeAndClosesTheList() {
        let model = makeModel()
        model.bubblesEntered()
        scheduler.advance(by: .milliseconds(150))
        #expect(model.hasTab(of: "battery"))
        #expect(model.openTab(of: "battery"))
        #expect(model.state == .open("battery"))
        #expect(model.isOpenedOnPurpose)
        #expect(!model.isListOpen)
        #expect(model.lastTab == "battery")
    }

    @Test func aModuleWithoutATabOrNotRegisteredOpensNothing() {
        let model = makeModel()
        model.bubblesEntered()
        scheduler.advance(by: .milliseconds(150))
        // Neither a module that runs without a tab (system notices) nor an id nobody registered (the debug publisher).
        #expect(!model.hasTab(of: "systemactivities"))
        #expect(!model.hasTab(of: "debug"))
        #expect(!model.openTab(of: "debug"))
        #expect(model.state == .closed)
        #expect(model.isListOpen)
        #expect(model.lastTab == nil)
    }

    @Test func aModuleWhoseTabWentAwayOpensNothing() {
        var tabs: [ModuleID] = ["media", "battery"]
        let model = NotchViewModel(scheduler: scheduler, availableTabs: { tabs }, delays: { (.milliseconds(150), .milliseconds(300)) })
        model.hasActivity = true
        model.bubbleCount = 1
        tabs = ["media"]
        #expect(!model.openTab(of: "battery"))
        #expect(model.state == .closed)
    }

    @Test func anActivationWithoutHoverOpensTheListAtOnce() {
        // VoiceOver and the keyboard have no hover: activating a bubble whose module has no tab shows the list straight away.
        let model = makeModel()
        model.showList()
        #expect(model.isListOpen)
    }

    @Test func anActivationInAnExpandedNotchDoesNotOpenAList() {
        let model = makeModel()
        model.click()
        model.showList()
        #expect(!model.isListOpen)
    }

    @Test func theListOpensOnceWhateverTheHoverDoes() {
        let model = makeModel()
        model.bubblesEntered()
        model.bubblesEntered()
        model.pointerMoved(to: .bubbles)
        scheduler.advance(by: .milliseconds(150))
        #expect(model.isListOpen)
        #expect(scheduler.pendingCount == 0)
    }

    // MARK: Zones

    @Test func theModelRemembersWhichZoneThePointerIsOver() {
        let model = makeModel()
        #expect(model.hover == .outside)
        model.pointerMoved(to: .notch)
        #expect(model.hover == .notch && model.isPointerInside)
        model.pointerMoved(to: .bubbles)
        #expect(model.hover == .bubbles && model.isPointerInside)
        model.pointerMoved(to: .outside)
        #expect(model.hover == .outside && !model.isPointerInside)
        model.dragEntered(tab: "media")
        #expect(model.hover == .notch && model.isPointerInside)
    }

    #if DEBUG
    @Test func theLogSaysWhenTheListOpensAndClosesWithCountsOnly() {
        let model = makeModel()
        let lines = captureNotchLog {
            model.bubblesEntered()
            scheduler.advance(by: .milliseconds(150))
            model.pointerExited()
            scheduler.advance(by: .milliseconds(300))
        }
        #expect(lines.contains { $0.contains("list open") })
        #expect(lines.contains { $0.contains("list closed") })
        #expect(lines.contains { $0.contains("bubbles") })
    }
    #endif
}
