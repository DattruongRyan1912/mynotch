import Foundation
import Testing
@testable import CalendarModule

@Suite struct AgendaReminderTests {
    let calendar = fixedCalendar()
    /// Wednesday 14 October 2026, 10:30.
    var now: Date { calendar.on(14, at: 10, 30) }

    func overdue(_ due: DateComponents?) -> Bool {
        AgendaReminder.isOverdue(due: due, now: now, calendar: calendar)
    }

    func due(day: Int, hour: Int? = nil, minute: Int? = nil) -> DateComponents {
        DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute)
    }

    @Test func aTimedReminderIsOverdueOnceItsTimePasses() {
        #expect(overdue(due(day: 14, hour: 9, minute: 0)))
        #expect(overdue(due(day: 14, hour: 10, minute: 29)))
        #expect(!overdue(due(day: 14, hour: 10, minute: 30)))
        #expect(!overdue(due(day: 14, hour: 17, minute: 0)))
    }

    @Test func aReminderWithoutATimeIsOverdueOnlyAfterItsDay() {
        #expect(!overdue(due(day: 14)))
        #expect(!overdue(due(day: 15)))
        #expect(overdue(due(day: 13)))
    }

    @Test func aTimedReminderFromAnEarlierDayIsOverdue() {
        #expect(overdue(due(day: 13, hour: 23, minute: 59)))
    }

    @Test func aReminderWithoutADueDateIsNeverOverdue() {
        #expect(!overdue(nil))
    }
}
