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

    // MARK: Leaving

    /// The tab tells the module when it leaves the screen, which is when the notch closes or another tab is chosen.
    /// Hosted in a window that is never shown, so nothing appears on screen.
    @Test func theTabSaysWhenItAppearsAndWhenItLeaves() async {
        var appeared = 0
        var disappeared = 0
        var actions = actions()
        actions.appeared = { appeared += 1 }
        actions.disappeared = { disappeared += 1 }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 452, height: 176), styleMask: [.borderless], backing: .buffered, defer: true)
        window.contentView = NSHostingView(rootView: CalendarTabView(state: state(), actions: actions))
        window.contentView?.layoutSubtreeIfNeeded()
        await settle { appeared > 0 }
        #expect(appeared == 1)
        #expect(disappeared == 0)
        window.contentView = nil
        await settle { disappeared > 0 }
        #expect(disappeared == 1)
    }

    // MARK: Words

    @Test func theKeysAreNamedAndSavingIsSaid() {
        #expect(QuickAddView.hint(for: .editing, isTyping: true) == "Return để lưu · Esc để hủy")
        #expect(QuickAddView.hint(for: .saving, isTyping: true) == "Đang lưu…")
        #expect(QuickAddView.hint(for: .failed, isTyping: true) == "Không lưu được sự kiện. Nhấn Return để thử lại.")
    }

    /// The notch can be open with the field showing and the keyboard still elsewhere (opened by hovering): then the
    /// field says it needs a click, and the keys it names would be wrong, since Esc goes to the app in front.
    @Test func aFieldThatIsNotTypedIntoSaysToClickIt() {
        #expect(QuickAddView.hint(for: .editing, isTyping: false) == "Bấm vào ô để gõ")
        #expect(QuickAddView.hint(for: .saving, isTyping: false) == "Đang lưu…")
        #expect(QuickAddView.hint(for: .failed, isTyping: false) == "Không lưu được sự kiện. Nhấn Return để thử lại.")
    }

    // MARK: The notch stays open only for a line that is being typed

    func field(_ text: String, canWrite: Bool = true) -> QuickAddState {
        var quickAdd = QuickAddState(canWrite: canWrite)
        quickAdd.text = text
        return quickAdd
    }

    @Test func anEmptyFieldDoesNotKeepTheNotchOpen() {
        #expect(!QuickAddView.pinsNotch(field(""), panelIsKey: true))
        #expect(!QuickAddView.pinsNotch(field(""), panelIsKey: false))
    }

    @Test func aLineBeingTypedKeepsTheNotchOpen() {
        #expect(QuickAddView.pinsNotch(field("họp"), panelIsKey: true))
        #expect(QuickAddView.pinsNotch(field(" "), panelIsKey: true))
    }

    @Test func aLineWhoseKeyboardWentElsewhereLetsTheNotchGo() {
        #expect(!QuickAddView.pinsNotch(field("họp"), panelIsKey: false))
    }

    @Test func theHintInsteadOfTheFieldNeverKeepsTheNotchOpen() {
        #expect(!QuickAddView.pinsNotch(field("họp", canWrite: false), panelIsKey: true))
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
