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
        guard let due, let dueDate = calendar.date(from: due) else { return false }
        if due.hour != nil { return dueDate < now }
        return dueDate < calendar.startOfDay(for: now)
    }
}
