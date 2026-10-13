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
}
