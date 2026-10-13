import MyNotchCore
import MyNotchTestSupport
import SwiftUI
import Testing
@testable import NotchUI

@Suite struct NotchHandleTests {
    let scheduler = ManualScheduler()

    func makeModel() -> NotchViewModel {
        NotchViewModel(scheduler: scheduler, availableTabs: { ["battery"] }, delays: { (.milliseconds(150), .milliseconds(300)) })
    }

    @Test func handleControlsItsNotch() {
        let model = makeModel()
        let handle = NotchHandle(model: model)
        model.click()
        handle.setPinned(true)
        #expect(model.isPinned)
        handle.setDragging(true)
        #expect(model.isDragging)
        handle.close()
        #expect(model.state == .closed)
    }

    @Test func defaultHandleDoesNothing() {
        let handle = EnvironmentValues().notch
        handle.setPinned(true)
        handle.setDragging(true)
        handle.close()
    }

    @Test func handleDoesNotKeepItsNotchAlive() {
        var handle = NotchHandle()
        weak var released: NotchViewModel?
        do {
            let model = makeModel()
            handle = NotchHandle(model: model)
            released = model
        }
        #expect(released == nil)
        handle.close()
    }
}
