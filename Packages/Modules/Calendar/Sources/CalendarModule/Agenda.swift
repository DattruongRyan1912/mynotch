import Foundation

/// What the Calendar tab shows: today's events and the one to watch for next.
nonisolated struct Agenda: Equatable, Sendable {
    /// Events overlapping today, all-day first, then by start.
    var today: [AgendaEvent] = []
    /// The first timed event that hasn't ended yet, today or within the next week.
    var next: AgendaEvent?
    /// Today's timed events that haven't ended yet (the one running now included).
    var upcomingToday: [AgendaEvent] = []
}

nonisolated enum AgendaBuilder {
    /// How far ahead "next" looks.
    static let lookAheadDays = 7

    /// The span to ask the calendar for: from the start of today, so an event that began earlier and still runs is
    /// there, to the end of the look-ahead week.
    static func fetchRange(now: Date, calendar: Calendar) -> DateInterval {
        DateInterval(start: calendar.startOfDay(for: now), end: lookAheadEnd(now: now, calendar: calendar))
    }

    /// Canceled events and events the user declined never show. The calendar decides where days begin and end.
    static func build(events: [AgendaEvent], now: Date, calendar: Calendar) -> Agenda {
        let startOfToday = calendar.startOfDay(for: now)
        let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? startOfToday.addingTimeInterval(86_400)
        let horizon = lookAheadEnd(now: now, calendar: calendar)

        let shown = events
            .filter { $0.status != .canceled && $0.myParticipation != .declined }
            .sorted(by: isDisplayedBefore)
        let today = shown.filter { overlaps($0, from: startOfToday, to: startOfTomorrow) }
        let timed = shown.filter { !$0.isAllDay && $0.end > now }
        return Agenda(
            today: today,
            next: timed.first { $0.start < horizon },
            upcomingToday: today.filter { !$0.isAllDay && $0.end > now }
        )
    }

    private static func lookAheadEnd(now: Date, calendar: Calendar) -> Date {
        calendar.date(byAdding: .day, value: lookAheadDays, to: now) ?? now.addingTimeInterval(Double(lookAheadDays) * 86_400)
    }

    /// An all-day event ends at the start of the next day (some calendars use the last second of the day), so
    /// touching the day's edge doesn't count. A zero-length event overlaps the day it starts in, edge included.
    private static func overlaps(_ event: AgendaEvent, from dayStart: Date, to dayEnd: Date) -> Bool {
        guard event.start < dayEnd else { return false }
        return event.end > dayStart || (event.start == event.end && event.start >= dayStart)
    }

    /// Ties fall back to title and id so the order never depends on the order EventKit returned them in.
    private static func isDisplayedBefore(_ lhs: AgendaEvent, _ rhs: AgendaEvent) -> Bool {
        (lhs.isAllDay ? 0 : 1, lhs.start, lhs.end, lhs.title, lhs.id) < (rhs.isAllDay ? 0 : 1, rhs.start, rhs.end, rhs.title, rhs.id)
    }
}
