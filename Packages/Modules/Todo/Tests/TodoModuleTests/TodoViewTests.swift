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

    @Test func aRowWithQuadrantBadgeStaysWithinHeightBudget() {
        let shortRow = TodoRow(
            item: TodoItem(reminder: todo("Mua sữa"), overdueDays: 0),
            isLingering: false,
            now: calendar.on(14, at: 9),
            calendar: calendar,
            showsQuadrantBadge: true,
            complete: {},
            undo: {},
            move: { _ in }
        )
        #expect(size(of: shortRow).height <= 28)

        let crowdedRow = TodoRow(
            item: TodoItem(reminder: crowdedReminder, overdueDays: 40),
            isLingering: false,
            now: calendar.on(14, at: 9),
            calendar: calendar,
            showsQuadrantBadge: true,
            complete: {},
            undo: {},
            move: { _ in }
        )
        #expect(size(of: crowdedRow).height <= 40)
    }

    @Test func theTabInMatrixAndListModesFitsRoom() {
        let s = state(items: [
            TodoItem(reminder: todo("Task 1", due: due(14), priority: .high), overdueDays: 0),
            TodoItem(reminder: todo("Task 2", priority: .high), overdueDays: 0),
            TodoItem(reminder: todo("Task 3", due: due(14)), overdueDays: 0),
            TodoItem(reminder: todo("Task 4"), overdueDays: 0)
        ])
        s.viewMode = .list
        let listHeight = size(of: TodoTabView(state: s, actions: actions())).height
        #expect(listHeight <= Self.room)

        s.viewMode = .matrix
        let matrixHeight = size(of: TodoTabView(state: s, actions: actions())).height
        #expect(matrixHeight <= Self.room)
    }

    @Test func noticeDoesNotCauseVerticalLayoutShift() {
        let sWithoutNotice = state(items: [
            TodoItem(reminder: todo("Task 1"), overdueDays: 0)
        ])
        sWithoutNotice.viewMode = .matrix
        let heightWithoutNotice = size(of: TodoTabView(state: sWithoutNotice, actions: actions())).height

        let sWithNotice = state(items: [
            TodoItem(reminder: todo("Task 1"), overdueDays: 0)
        ])
        sWithNotice.viewMode = .matrix
        sWithNotice.notice = "Đã chuyển sang Q2."
        let heightWithNotice = size(of: TodoTabView(state: sWithNotice, actions: actions())).height

        print("Fitting height WITHOUT notice: \(heightWithoutNotice) pt")
        print("Fitting height WITH notice:    \(heightWithNotice) pt")
        print("Layout shift delta:            \(abs(heightWithNotice - heightWithoutNotice)) pt (ZERO SHIFT)")

        #expect(heightWithNotice == heightWithoutNotice, "Notice in header must introduce ZERO vertical layout shift to the tab")
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

    @Test func quickAddPromptContainsSyntaxGuidance() {
        #expect(TodoQuickAddField.prompt.contains("!q1"))
        #expect(TodoQuickAddField.prompt.contains("#q4"))
        #expect(TodoQuickAddField.prompt.contains("!!!"))
    }

    @Test func theSettingsRowsBuildWithoutPermissionOrStore() throws {
        let fixture = ModuleFixture()
        let environment = try #require(fixture.harness.settingsEnvironment(for: "todo"))
        let view = try #require(fixture.module.makeSettingsView(environment))
        let hosted = NSHostingView(rootView: Form { view }.frame(width: 480))
        #expect(hosted.fittingSize.height > 0)
    }
}
