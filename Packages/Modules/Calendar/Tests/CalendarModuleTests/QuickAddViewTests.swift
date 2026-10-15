import AppKit
import Foundation
import MyNotchCore
import SwiftUI
import Testing
@testable import CalendarModule

/// Sizes and words of the quick-add views, measured by hosting them off screen.
@Suite struct QuickAddViewTests {
    let calendar = fixedCalendar()
    /// The narrowest the open notch gets (480 pt) less its padding on both sides.
    static let narrowestWidth: CGFloat = 480 - 2 * 14
    /// What the tab can use: its height less the notch's inner padding and the tab bar.
    static let room = CalendarTabView.height - 14 - 30

    func state() -> CalendarState {
        let state = CalendarState(now: calendar.on(14, at: 9, 57), calendar: calendar)
        state.daySummary = "Hôm nay: 12 sự kiện, rảnh 14:00–16:00, kết thúc lúc 18:30"
        return state
    }

    func actions() -> CalendarActions {
        CalendarActions(
            open: { _ in }, join: { _ in }, snooze: { _ in }, dismiss: { _ in }, complete: { _ in },
            requestRemindersAccess: {}, appeared: {}
        )
    }

    func height(of state: CalendarState) -> CGFloat {
        NSHostingView(rootView: CalendarTabView(state: state, actions: actions()).frame(width: Self.narrowestWidth)).fittingSize.height
    }

    /// A draft with everything the preview can say at once.
    var crowdedDraft: QuickAddDraft {
        QuickAddDraft(
            title: "Họp kế hoạch quý bốn của nhóm sản phẩm và kỹ thuật cùng với khách hàng và các đối tác",
            start: calendar.on(16, at: 12, 30), end: calendar.on(16, at: 13, 30), isAllDay: true, note: .noTime
        )
    }

    // MARK: Fit

    @Test func theSummaryLeavesTheWorstCaseCardItsRoom() {
        var event = event("e", calendar.on(14, at: 10), calendar.on(14, at: 11), meetingURL: URL(string: "https://whereby.com/acme-standup"))
        event.title = "Họp kế hoạch quý bốn của nhóm sản phẩm và kỹ thuật"
        event.location = "Phòng họp 4B, tầng 12"
        let state = state()
        state.featured = event
        state.canDismissFeatured = true
        state.canSnoozeFeatured = true
        let measured = height(of: state)
        #expect(measured > 0)
        #expect(measured <= Self.room, "the tab needs \(measured) pt of \(Self.room)")
    }

    @Test func theFieldItsPreviewAndTheNoteFitTheTab() {
        let state = state()
        var quickAdd = QuickAddState(canWrite: true)
        quickAdd.text = "Họp kế hoạch quý bốn"
        quickAdd.draft = crowdedDraft
        quickAdd.phase = .failed
        quickAdd.calendar = CalendarInfo(id: "work", title: "Lịch công việc của công ty", color: .gray)
        state.quickAdd = quickAdd
        let measured = height(of: state)
        #expect(measured > 0)
        #expect(measured <= Self.room, "the field needs \(measured) pt of \(Self.room)")
    }

    @Test func theHintInPlaceOfTheFieldFitsToo() {
        let state = state()
        state.quickAdd = QuickAddState(canWrite: false)
        let measured = height(of: state)
        #expect(measured > 0)
        #expect(measured <= Self.room, "the hint needs \(measured) pt of \(Self.room)")
    }

    // MARK: Words

    @Test func theKeysAreNamedAndSavingIsSaid() {
        #expect(QuickAddView.hint(for: .editing) == "Return để lưu · Esc để hủy")
        #expect(QuickAddView.hint(for: .failed) == "Không lưu được sự kiện. Nhấn Return để thử lại.")
        #expect(QuickAddView.hint(for: .saving) == "Đang lưu…")
    }

    @Test func theButtonSaysWhatItDoes() {
        #expect(AddEventButton.help(isOpen: false) == "Thêm sự kiện")
        #expect(AddEventButton.help(isOpen: true) == "Đóng (Esc)")
    }

    @Test func withoutAccessTheHintIsTheOneThatNamesTheStepToGrantIt() {
        #expect(QuickAddView.noAccess.hasPrefix("Cần quyền truy cập Lịch đầy đủ để thêm sự kiện."))
        #expect(QuickAddView.noAccess.contains(Permission.calendars.instruction))
    }

    @Test func workingHoursReadAsTimes() {
        #expect(CalendarSettingsView.clock(9) == "09:00")
        #expect(CalendarSettingsView.clock(24) == "24:00")
    }
}
