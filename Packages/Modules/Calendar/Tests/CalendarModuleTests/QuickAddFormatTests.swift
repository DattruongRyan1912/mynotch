import Foundation
import Testing
@testable import CalendarModule

/// How the preview of a quick-added event reads: the day, the hours, the note.
@Suite struct QuickAddFormatTests {
    let calendar = fixedCalendar()
    /// Wednesday 14 October 2026, 09:00.
    var now: Date { calendar.on(14, at: 9) }

    func draft(_ start: Date, _ end: Date, allDay: Bool = false) -> QuickAddDraft {
        QuickAddDraft(title: "Họp", start: start, end: end, isAllDay: allDay, note: nil)
    }

    @Test func todayIsNamedAndTheHoursFollow() {
        let today = draft(calendar.on(14, at: 15), calendar.on(14, at: 16))
        #expect(AgendaFormat.when(of: today, now: now, calendar: calendar) == "Hôm nay · 15:00 – 16:00")
    }

    @Test func tomorrowAndLaterDaysUseTheTabsOwnLabels() {
        #expect(AgendaFormat.when(of: draft(calendar.on(15, at: 9, 5), calendar.on(15, at: 10)), now: now, calendar: calendar) == "Ngày mai · 09:05 – 10:00")
        #expect(AgendaFormat.when(of: draft(calendar.on(16, at: 12, 30), calendar.on(16, at: 13, 30)), now: now, calendar: calendar) == "Thứ Sáu, 16/10 · 12:30 – 13:30")
    }

    @Test func anAllDayEventHasNoHours() {
        let allDay = draft(calendar.on(14, at: 0), calendar.on(15, at: 0), allDay: true)
        #expect(AgendaFormat.when(of: allDay, now: now, calendar: calendar) == "Hôm nay · Cả ngày")
        let tomorrow = draft(calendar.on(15, at: 0), calendar.on(16, at: 0), allDay: true)
        #expect(AgendaFormat.when(of: tomorrow, now: now, calendar: calendar) == "Ngày mai · Cả ngày")
    }

    @Test func anEventThatCrossesMidnightShowsBothTimes() {
        let late = draft(calendar.on(14, at: 23), calendar.on(15, at: 1))
        #expect(AgendaFormat.when(of: late, now: now, calendar: calendar) == "Hôm nay · 23:00 – 01:00")
    }

    @Test func theNoteSaysWhyTheEventIsAllDay() {
        #expect(AgendaFormat.text(of: .noTime) == "Không đọc được giờ nên tạo sự kiện cả ngày.")
    }
}
