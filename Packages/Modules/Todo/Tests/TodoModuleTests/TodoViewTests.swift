import AppKit
import Foundation
import MyNotchCore
import MyNotchTestSupport
import SwiftUI
import Testing
@testable import TodoModule

/// Sizes of the tab's views, measured by hosting them off screen: nothing is shown and nothing is captured.
@Suite struct TodoViewTests {
    let calendar = fixedCalendar()
    /// The narrowest the open notch gets (480 pt) less its padding on both sides.
    static let narrowestWidth: CGFloat = 480 - 2 * 14
    /// What the tab can use: its height less the notch's inner padding and the tab bar.
    static let room = TodoTabView.height - 14 - 30

    func state(phase: TodoState.Phase = .ready, items: [TodoItem] = []) -> TodoState {
        let state = TodoState(now: calendar.on(14, at: 9, 57), calendar: calendar)
        state.phase = phase
        state.items = items
        return state
    }

    func actions() -> TodoActions {
        TodoActions(complete: { _ in }, undo: { _ in }, add: { _ in true }, requestAccess: {}, retry: {}, watchAccess: {}, appeared: {})
    }

    func size<V: View>(of view: V) -> CGSize {
        NSHostingView(rootView: view.frame(width: Self.narrowestWidth)).fittingSize
    }

    var crowdedReminder: TodoReminder {
        var reminder = todo("x", due: due(9, 23, 59), priority: .high, list: "work")
        reminder.title = "Chuẩn bị báo cáo quý bốn cho nhóm sản phẩm và kỹ thuật cùng với khách hàng và các đối tác của công ty"
        return reminder
    }

    @Test func theTabHeightStaysWithinWhatTheNotchGivesATab() {
        #expect(NotchTab.heightRange.contains(TodoTabView.height))
    }

    @Test func theChromeLeavesTheListRoomWithANoticeAndAHint() {
        let state = state()
        state.notice = "Không thêm được việc. Nhấn Return để thử lại."
        let height = size(of: TodoTabView(state: state, actions: actions())).height
        #expect(height > 0)
        #expect(height <= Self.room - 60, "header, field and notice take \(height) pt of \(Self.room) and leave the list under 60 pt")
    }

    @Test func theHintOfAnAccessLessTabFits() {
        let height = size(of: TodoTabView(state: state(phase: .needsAccess), actions: actions())).height
        #expect(height > 0)
        #expect(height <= Self.room)
    }

    @Test func aRowWithEverythingAndALongTitleStaysWithinTwoLines() {
        let row = TodoRow(
            item: TodoItem(reminder: crowdedReminder, overdueDays: 40), isLingering: false, now: calendar.on(14, at: 9),
            calendar: calendar, complete: {}, undo: {}
        )
        let height = size(of: row).height
        #expect(height > 0)
        // Two lines of 12.5 pt text, and the row's own padding.
        #expect(height <= 40, "the row takes \(height) pt")
    }

    @Test func aRowWithOnlyATitleIsOneLineHigh() {
        let row = TodoRow(
            item: TodoItem(reminder: todo("Mua sữa"), overdueDays: 0), isLingering: false, now: calendar.on(14, at: 9),
            calendar: calendar, complete: {}, undo: {}
        )
        #expect(size(of: row).height <= 28)
    }

    @Test func aTickedRowWithUndoIsNoTallerThanBefore() {
        var reminder = crowdedReminder
        reminder.isCompleted = true
        let row = TodoRow(
            item: TodoItem(reminder: reminder, overdueDays: 0), isLingering: true, now: calendar.on(14, at: 9),
            calendar: calendar, complete: {}, undo: {}
        )
        #expect(size(of: row).height <= 40)
    }

    @Test func theErrorLineAndTheNoticeStillLeaveTheListRoom() {
        let state = state()
        state.loadFailed = true
        state.notice = "Không cập nhật được việc này."
        let height = size(of: TodoTabView(state: state, actions: actions())).height
        #expect(height <= Self.room - 40, "header, field, notice and error take \(height) pt of \(Self.room)")
    }

    @Test func theDeniedHintFits() {
        let state = state(phase: .needsAccess)
        state.accessIsDenied = true
        #expect(size(of: TodoTabView(state: state, actions: actions())).height <= Self.room)
    }

    @Test func aRowWithTheRepeatGlyphAndEverythingElseStaysWithinTwoLines() {
        var reminder = crowdedReminder
        reminder.isRecurring = true
        let row = TodoRow(
            item: TodoItem(reminder: reminder, overdueDays: 40), isLingering: false, now: calendar.on(14, at: 9),
            calendar: calendar, complete: {}, undo: {}
        )
        #expect(size(of: row).height <= 40)
    }

    @Test func theNotchIsPinnedOnlyWhileALineIsBeingTyped() {
        #expect(!TodoQuickAddField.pinsNotch(text: "", isFocused: true))
        #expect(!TodoQuickAddField.pinsNotch(text: "mua sữa", isFocused: false))
        #expect(TodoQuickAddField.pinsNotch(text: "mua sữa", isFocused: true))
    }

    @Test func theSettingsRowsBuildWithoutPermissionOrStore() throws {
        let fixture = ModuleFixture()
        let environment = try #require(fixture.harness.settingsEnvironment(for: "todo"))
        let view = try #require(fixture.module.makeSettingsView(environment))
        let hosted = NSHostingView(rootView: Form { view }.frame(width: 480))
        #expect(hosted.fittingSize.height > 0)
    }
}
