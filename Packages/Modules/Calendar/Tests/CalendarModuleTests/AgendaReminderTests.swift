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

    @Test func aDueDateIsReadInTheCalendarItWasWrittenIn() {
        var buddhist = Calendar(identifier: .buddhist)
        buddhist.timeZone = calendar.timeZone
        func gregorian(_ components: DateComponents) -> DateComponents {
            var components = components
            components.calendar = calendar
            return components
        }
        func overdue(_ due: DateComponents) -> Bool {
            AgendaReminder.isOverdue(due: gregorian(due), now: now, calendar: buddhist)
        }

        #expect(!overdue(due(day: 14, hour: 17, minute: 0)))
        #expect(overdue(due(day: 14, hour: 9, minute: 0)))
        #expect(!overdue(due(day: 14)))
        #expect(!overdue(due(day: 15)))
        #expect(overdue(due(day: 13)))
    }

    @Test func aDueDateWithoutItsOwnCalendarUsesTheCurrentOne() {
        var buddhist = Calendar(identifier: .buddhist)
        buddhist.timeZone = calendar.timeZone
        // The same moment as 14 October 2026 17:00, written in the Buddhist era.
        let due = DateComponents(year: 2569, month: 10, day: 14, hour: 17, minute: 0)
        #expect(!AgendaReminder.isOverdue(due: due, now: now, calendar: buddhist))
    }

    @Test func aDueDateWithoutATimeZoneIsReadInTheCurrentOne() {
        var due = due(day: 14, hour: 10, minute: 0)
        // Ten o'clock wherever the user is, even when the components' calendar sits in another zone.
        due.calendar = fixedCalendar("UTC")
        #expect(overdue(due))
        due.timeZone = TimeZone(identifier: "UTC")
        #expect(!overdue(due))
    }

    @Test func remindersAreOrderedByDueDateWithUndatedLast() {
        let reminders = [
            reminder("undated"),
            reminder("evening", due: due(day: 14, hour: 18, minute: 0)),
            reminder("yesterday", due: due(day: 13, hour: 9, minute: 0)),
            reminder("all day", due: due(day: 14)),
            reminder("b same time", due: due(day: 14, hour: 12, minute: 0)),
            reminder("a same time", due: due(day: 14, hour: 12, minute: 0)),
        ]
        let sorted = AgendaReminder.sortedByDue(reminders, calendar: calendar)
        #expect(sorted.map(\.id) == ["yesterday", "all day", "a same time", "b same time", "evening", "undated"])
    }
}
