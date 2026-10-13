import Foundation

/// An incomplete reminder, copied out of EventKit as plain values.
nonisolated struct AgendaReminder: Equatable, Sendable {
    /// The item identifier, which `CalendarDataSource.complete(reminderID:)` takes.
    var id: String
    var title: String
    /// As the user set it: a date alone, or a date with a time.
    var due: DateComponents?
    var isOverdue: Bool
    var listTitle: String
    var listColor: RGBAColor

    /// A reminder with a time is late once that time passes; one with only a date stays on time through its day.
    static func isOverdue(due: DateComponents?, now: Date, calendar: Calendar) -> Bool {
        guard let due, let dueDate = dueDate(of: due, calendar: calendar) else { return false }
        if due.hour != nil { return dueDate < now }
        return dueDate < calendar.startOfDay(for: now)
    }

    /// The components are read in the calendar they were written in (EventKit stamps Gregorian ones, whatever the
    /// user's calendar is), and in `calendar`'s time zone unless they name their own.
    static func dueDate(of due: DateComponents, calendar: Calendar) -> Date? {
        var dueCalendar = due.calendar ?? calendar
        if due.timeZone == nil { dueCalendar.timeZone = calendar.timeZone }
        return dueCalendar.date(from: due)
    }

    /// Earliest first, so overdue ones lead; a reminder without a date goes last. Ties fall back to the title and
    /// id so the order never depends on the order EventKit returned them in.
    static func sortedByDue(_ reminders: [AgendaReminder], calendar: Calendar) -> [AgendaReminder] {
        func key(_ reminder: AgendaReminder) -> (Int, Date, String, String) {
            let date = reminder.due.flatMap { dueDate(of: $0, calendar: calendar) }
            return (date == nil ? 1 : 0, date ?? .distantPast, reminder.title, reminder.id)
        }
        return reminders.sorted { key($0) < key($1) }
    }
}
