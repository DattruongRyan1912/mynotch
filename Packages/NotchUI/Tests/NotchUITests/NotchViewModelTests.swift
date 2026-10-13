import MyNotchCore
import MyNotchTestSupport
import SwiftUI
import Testing
@testable import NotchUI

@Suite struct NotchViewModelTests {
    let scheduler = ManualScheduler()

    func makeModel(tabs: [ModuleID] = ["battery", "clipboard"]) -> NotchViewModel {
        NotchViewModel(scheduler: scheduler, availableTabs: { tabs }, delays: { (.milliseconds(150), .milliseconds(300)) })
    }

    @Test func hoverOpensAfterDelay() {
        let model = makeModel()
        model.pointerEntered()
        scheduler.advance(by: .milliseconds(149))
        #expect(model.state == .closed)
        scheduler.advance(by: .milliseconds(1))
        #expect(model.state == .open("battery"))
    }

    @Test func leavingBeforeDelayCancelsOpen() {
        let model = makeModel()
        model.pointerEntered()
        scheduler.advance(by: .milliseconds(100))
        model.pointerExited()
        scheduler.advance(by: .seconds(1))
        #expect(model.state == .closed)
    }

    @Test func leavingClosesAfterDelayUnlessReentered() {
        let model = makeModel()
        model.click()
        model.pointerExited()
        scheduler.advance(by: .milliseconds(200))
        model.pointerEntered()
        scheduler.advance(by: .seconds(1))
        #expect(model.state.isExpanded)
        model.pointerExited()
        scheduler.advance(by: .milliseconds(300))
        #expect(model.state == .closed)
    }

    @Test func pinnedAndDraggingKeepItOpen() {
        let model = makeModel()
        model.click()
        model.isPinned = true
        model.pointerExited()
        scheduler.advance(by: .seconds(1))
        #expect(model.state.isExpanded)
        model.isPinned = false
        model.setDragging(true)
        scheduler.advance(by: .seconds(1))
        #expect(model.state.isExpanded)
        model.setDragging(false)
        scheduler.advance(by: .milliseconds(300))
        #expect(model.state == .closed)
    }

    @Test func remembersLastTab() {
        let model = makeModel()
        model.open(tab: "clipboard")
        model.close()
        model.click()
        #expect(model.state == .open("clipboard"))
    }

    @Test func unknownTabFallsBackToFirst() {
        let model = makeModel()
        model.open(tab: "missing")
        #expect(model.state == .open("battery"))
    }

    @Test func toggleOpensAndCloses() {
        let model = makeModel()
        model.toggle()
        #expect(model.state.isExpanded)
        model.toggle()
        #expect(model.state == .closed)
    }

    @Test func activityTurnsClosedIntoCompact() {
        let model = makeModel()
        model.hasActivity = true
        #expect(model.displayState == .compact)
        model.click()
        #expect(model.displayState == .open("battery"))
        model.close()
        #expect(model.displayState == .compact)
    }

    @Test func toastClosesAfterDurationUnlessPointerInside() {
        let model = makeModel()
        model.showToast(AnyView(EmptyView()), duration: .seconds(2))
        #expect(model.state == .toast)
        scheduler.advance(by: .seconds(2))
        #expect(model.state == .closed)

        model.showToast(AnyView(EmptyView()), duration: .seconds(2))
        model.pointerEntered()
        scheduler.advance(by: .seconds(2))
        #expect(model.state == .toast)
        model.pointerExited()
        scheduler.advance(by: .milliseconds(300))
        #expect(model.state == .closed)
    }

    @Test func clickingAToastOpensTheTabs() {
        let model = makeModel()
        model.showToast(AnyView(EmptyView()), duration: .seconds(5))
        model.click()
        #expect(model.state == .open("battery"))
    }

    @Test func passingOverAToastDoesNotCutItShort() {
        let model = makeModel()
        model.showToast(AnyView(EmptyView()), duration: .seconds(5))
        model.pointerEntered()
        model.pointerExited()
        scheduler.advance(by: .seconds(1))
        #expect(model.state == .toast)
        scheduler.advance(by: .seconds(4))
        #expect(model.state == .closed)
    }

    @Test func toastSurvivesPendingHoverOpenAndStaysWhileInsideOrPinned() {
        let model = makeModel()
        model.pointerEntered()
        model.showToast(AnyView(EmptyView()), duration: .seconds(2))
        scheduler.advance(by: .seconds(3))
        #expect(model.state == .toast)

        let pinned = makeModel()
        pinned.showToast(AnyView(EmptyView()), duration: .seconds(2))
        pinned.isPinned = true
        scheduler.advance(by: .seconds(3))
        #expect(pinned.state == .toast)
    }

    @Test func toastStaysWhileDraggingPastItsDuration() {
        let model = makeModel()
        model.showToast(AnyView(EmptyView()), duration: .seconds(2))
        model.setDragging(true)
        scheduler.advance(by: .seconds(3))
        #expect(model.state == .toast)
        model.setDragging(false)
        scheduler.advance(by: .milliseconds(300))
        #expect(model.state == .closed)
    }

    @Test func repeatedPinAndDragSettersHaveNoSideEffects() {
        let model = makeModel()
        model.toggle()
        model.setDragging(false)
        model.isPinned = false
        scheduler.advance(by: .seconds(1))
        #expect(model.state.isExpanded)
    }

    @Test func tabResolutionPrefersRequestedThenLastThenFirst() {
        var tabs: [ModuleID] = ["battery", "clipboard"]
        let model = NotchViewModel(scheduler: scheduler, availableTabs: { tabs }, delays: { (.milliseconds(150), .milliseconds(300)) })
        model.open(tab: "clipboard")
        model.open(tab: "missing")
        #expect(model.state == .open("clipboard"))
        tabs = []
        model.open(tab: nil)
        #expect(model.state == .open(nil))
    }

    @Test func clickingOutsideClosesAnOpenNotchOrAToast() {
        let model = makeModel()
        model.click()
        model.clickedOutside()
        #expect(model.state == .closed)

        model.showToast(AnyView(EmptyView()), duration: .seconds(5))
        model.clickedOutside()
        #expect(model.state == .closed)
        #expect(model.toastContent == nil)
    }

    @Test func clickingOutsideKeepsAPinnedOrDraggingNotchOpen() {
        let pinned = makeModel()
        pinned.click()
        pinned.isPinned = true
        pinned.clickedOutside()
        #expect(pinned.state == .open("battery"))

        let dragging = makeModel()
        dragging.click()
        dragging.setDragging(true)
        dragging.clickedOutside()
        #expect(dragging.state == .open("battery"))
    }

    @Test func clickingOutsideIgnoresAClosedNotch() {
        let model = makeModel()
        model.hasActivity = true
        model.pointerEntered()
        model.clickedOutside()
        #expect(model.displayState == .compact)
        scheduler.advance(by: .milliseconds(150))
        #expect(model.state == .open("battery"))
    }

    @Test func toastOverAnOpenTabReturnsToItThenClosesWhenPointerIsOutside() {
        let model = makeModel()
        model.open(tab: "clipboard")
        model.showToast(AnyView(EmptyView()), duration: .seconds(2))
        #expect(model.state == .toast)
        scheduler.advance(by: .seconds(2))
        #expect(model.state == .open("clipboard"))
        #expect(model.toastContent == nil)
        scheduler.advance(by: .milliseconds(299))
        #expect(model.state == .open("clipboard"))
        scheduler.advance(by: .milliseconds(1))
        #expect(model.state == .closed)
    }

    @Test func toastOverAnOpenTabReturnsToItAndStaysWhilePointerIsInside() {
        let model = makeModel()
        model.pointerEntered()
        scheduler.advance(by: .milliseconds(150))
        model.showToast(AnyView(EmptyView()), duration: .seconds(2))
        scheduler.advance(by: .seconds(5))
        #expect(model.state == .open("battery"))
        #expect(model.toastContent == nil)
    }

    @Test func toastOverAClosedNotchStillClosesAfterItsDuration() {
        let model = makeModel()
        model.open(tab: "clipboard")
        model.close()
        model.showToast(AnyView(EmptyView()), duration: .seconds(2))
        scheduler.advance(by: .seconds(2))
        #expect(model.state == .closed)
        #expect(model.toastContent == nil)
    }

    @Test func secondToastOverATabStillReturnsToTheTab() {
        let model = makeModel()
        model.open(tab: "clipboard")
        model.showToast(AnyView(EmptyView()), duration: .seconds(2))
        scheduler.advance(by: .seconds(1))
        model.showToast(AnyView(EmptyView()), duration: .seconds(2))
        scheduler.advance(by: .seconds(1))
        #expect(model.state == .toast)
        scheduler.advance(by: .seconds(1))
        #expect(model.state == .open("clipboard"))
    }

    @Test func toastOverATabWhoseModuleStoppedFallsBackToTheFirstTab() {
        var tabs: [ModuleID] = ["battery", "clipboard"]
        let model = NotchViewModel(scheduler: scheduler, availableTabs: { tabs }, delays: { (.milliseconds(150), .milliseconds(300)) })
        model.open(tab: "clipboard")
        model.showToast(AnyView(EmptyView()), duration: .seconds(2))
        tabs = ["battery"]
        scheduler.advance(by: .seconds(2))
        #expect(model.state == .open("battery"))
    }

    @Test func tabUnderToastNamesTheCoveredTabOnlyWhileAToastCoversIt() {
        let model = makeModel()
        model.showToast(AnyView(EmptyView()), duration: .seconds(2))
        #expect(model.tabUnderToast == nil)
        scheduler.advance(by: .seconds(2))

        model.open(tab: "clipboard")
        #expect(model.tabUnderToast == nil)
        model.showToast(AnyView(EmptyView()), duration: .seconds(2))
        #expect(model.tabUnderToast == "clipboard")
        model.showToast(AnyView(EmptyView()), duration: .seconds(2))
        #expect(model.tabUnderToast == "clipboard")
        scheduler.advance(by: .seconds(2))
        #expect(model.state == .open("clipboard"))
        #expect(model.tabUnderToast == nil)

        model.showToast(AnyView(EmptyView()), duration: .seconds(2))
        model.close()
        #expect(model.tabUnderToast == nil)
    }

    @Test func hoverOpensWithoutPurposeAndExplicitOpensSetIt() {
        let model = makeModel()
        model.pointerEntered()
        scheduler.advance(by: .milliseconds(150))
        #expect(model.state == .open("battery"))
        #expect(!model.isOpenedOnPurpose)
        model.open(tab: "clipboard")
        #expect(model.isOpenedOnPurpose)
        model.close()
        #expect(!model.isOpenedOnPurpose)

        model.click()
        #expect(model.isOpenedOnPurpose)
        model.toggle()
        #expect(!model.isOpenedOnPurpose)
        model.toggle()
        #expect(model.isOpenedOnPurpose)
    }

    @Test func toastExpiryKeepsHowTheCoveredTabWasOpened() {
        let model = makeModel()
        model.open(tab: "clipboard")
        model.showToast(AnyView(EmptyView()), duration: .seconds(2))
        scheduler.advance(by: .seconds(2))
        #expect(model.state == .open("clipboard"))
        #expect(model.isOpenedOnPurpose)

        let hovered = makeModel()
        hovered.pointerEntered()
        scheduler.advance(by: .milliseconds(150))
        hovered.showToast(AnyView(EmptyView()), duration: .seconds(2))
        scheduler.advance(by: .seconds(2))
        #expect(hovered.state == .open("battery"))
        #expect(!hovered.isOpenedOnPurpose)
    }

    @Test func closingDuringAToastOverATabForgetsTheTab() {
        let model = makeModel()
        model.open(tab: "clipboard")
        model.showToast(AnyView(EmptyView()), duration: .seconds(2))
        model.close()
        scheduler.advance(by: .seconds(5))
        #expect(model.state == .closed)

        model.showToast(AnyView(EmptyView()), duration: .seconds(2))
        scheduler.advance(by: .seconds(2))
        #expect(model.state == .closed)
    }

    @Test func closeClearsPinAndToggleClosesAToast() {
        let model = makeModel()
        model.click()
        model.isPinned = true
        model.close()
        #expect(!model.isPinned)
        model.showToast(AnyView(EmptyView()), duration: .seconds(5))
        model.toggle()
        #expect(model.state == .closed)
    }
}
