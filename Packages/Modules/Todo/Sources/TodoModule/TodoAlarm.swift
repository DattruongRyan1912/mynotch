import Foundation

/// The alert of a reminder that has a time. A due time alone is only "the date by which the reminder should be completed"
/// (EventKit's words): nothing rings, which is not what "gọi khách 15h30" means, so a timed reminder also gets an alarm at
/// that moment, as Reminders does when its "Time" switch is on.
nonisolated enum TodoAlarm {
    /// When the alarm fires: the due time, on the wall clock of `timeZone` unless the components name a zone. Nil for a day
    /// alone (it stays quiet, like an all-day reminder in Reminders) and for components that cannot be read.
    static func fireDate(for due: DateComponents, timeZone: TimeZone) -> Date? {
        guard due.hour != nil, due.year != nil, due.month != nil, due.day != nil else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = due.timeZone ?? timeZone
        var components = due
        components.calendar = nil
        components.timeZone = nil
        return calendar.date(from: components)
    }
}
