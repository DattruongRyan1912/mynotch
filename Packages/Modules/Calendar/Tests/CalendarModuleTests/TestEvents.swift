import Foundation
@testable import CalendarModule

/// A Gregorian calendar pinned to one time zone, so day boundaries don't depend on the machine running the tests.
func fixedCalendar(_ timeZone: String = "Asia/Ho_Chi_Minh") -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: timeZone)!
    return calendar
}

extension Calendar {
    /// October `day`, 2026 at `hour:minute:second` in this calendar's time zone.
    func on(_ day: Int, at hour: Int, _ minute: Int = 0, _ second: Int = 0) -> Date {
        date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute, second: second))!
    }
}

/// An accepted, confirmed event in the "Work" calendar unless told otherwise.
func event(
    _ id: String,
    _ start: Date,
    _ end: Date,
    title: String? = nil,
    allDay: Bool = false,
    calendarID: String = "work",
    location: String? = nil,
    meetingURL: URL? = nil,
    status: AgendaEvent.Status = .confirmed,
    participation: AgendaEvent.Participation = .accepted
) -> AgendaEvent {
    AgendaEvent(
        id: id, calendarItemIdentifier: id, title: title ?? id, start: start, end: end, isAllDay: allDay,
        calendarID: calendarID, calendarTitle: calendarID.capitalized, calendarColor: .gray,
        location: location, meetingURL: meetingURL, status: status, myParticipation: participation
    )
}

/// A one-day all-day event: EventKit ends it at the start of the next day.
func allDayEvent(_ id: String, on day: Int, in calendar: Calendar) -> AgendaEvent {
    event(id, calendar.on(day, at: 0), calendar.on(day + 1, at: 0), allDay: true)
}
