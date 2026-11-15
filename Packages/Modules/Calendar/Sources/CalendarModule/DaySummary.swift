import Foundation

/// The hours of the day the user works, whole hours, for finding free time. Hours that make no sense (the end not after
/// the start) are the standard 9 to 18.
nonisolated struct WorkingHours: Equatable, Sendable {
    static let standard = WorkingHours(unchecked: 9, 18)

    let start: Int
    /// 24 is the end of the day.
    let end: Int

    init(start: Int, end: Int) {
        let start = min(max(start, 0), 23)
        let end = min(max(end, 1), 24)
        self = end > start ? WorkingHours(unchecked: start, end) : .standard
    }

    private init(unchecked start: Int, _ end: Int) {
        self.start = start
        self.end = end
    }
}

/// The compact line at the top of the Calendar tab: "Hôm nay: 4 sự kiện, rảnh 14:00–16:00, kết thúc lúc 18:30".
nonisolated enum DaySummary {
    /// A gap shorter than this is not time to do something in.
    static let minimumFreeSlot: TimeInterval = 30 * 60
    /// Free time starts on a quarter of an hour, not at 10:37.
    private static let roundingMinutes = 15

    /// Today's events counted, the first free slot from now on, and the end of the last event. Once every event of the day
    /// has ended it says so and, if tomorrow has one, when tomorrow starts.
    static func text(for agenda: Agenda, now: Date, workingHours: WorkingHours, calendar: Calendar) -> String {
        let timed = agenda.today.filter { !$0.isAllDay }
        let count = agenda.today.isEmpty ? "không có sự kiện" : "\(agenda.today.count) sự kiện"
        var parts = ["Hôm nay: \(count)"]
        guard let lastEnd = timed.map(\.end).max() else {
            if let slot = freeSlot(among: timed, now: now, hours: workingHours, calendar: calendar) {
                parts.append("rảnh \(range(slot, calendar: calendar))")
            }
            return parts.joined(separator: ", ")
        }
        let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        let end = lastEnd > startOfTomorrow ? "sau nửa đêm" : "lúc \(time(lastEnd, endOfDay: startOfTomorrow, calendar: calendar))"
        guard lastEnd > now else {
            parts.append("đã kết thúc \(end)")
            if let first = firstStart(on: startOfTomorrow, in: agenda, calendar: calendar) {
                parts.append("mai bắt đầu lúc \(AgendaFormat.time(first, calendar: calendar))")
            }
            return parts.joined(separator: ", ")
        }
        if let slot = freeSlot(among: timed, now: now, hours: workingHours, calendar: calendar) {
            parts.append("rảnh \(range(slot, calendar: calendar))")
        }
        parts.append("kết thúc \(end)")
        return parts.joined(separator: ", ")
    }

    private static func range(_ slot: DateInterval, calendar: Calendar) -> String {
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: slot.start)) ?? slot.end
        return "\(AgendaFormat.time(slot.start, calendar: calendar))–\(time(slot.end, endOfDay: endOfDay, calendar: calendar))"
    }

    /// The end of the day is 24:00, not 00:00 of a day that has not begun.
    private static func time(_ date: Date, endOfDay: Date, calendar: Calendar) -> String {
        date >= endOfDay ? "24:00" : AgendaFormat.time(date, calendar: calendar)
    }

    /// The first start of a timed event on the day beginning at `day`.
    private static func firstStart(on day: Date, in agenda: Agenda, calendar: Calendar) -> Date? {
        guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { return nil }
        return agenda.upcoming.map(\.start).filter { $0 >= day && $0 < next }.min()
    }

    /// The first gap of at least `minimumFreeSlot` between `events`, inside working hours and not before the next quarter
    /// of an hour from now.
    static func freeSlot(among events: [AgendaEvent], now: Date, hours: WorkingHours, calendar: Calendar) -> DateInterval? {
        let day = calendar.startOfDay(for: now)
        // By the clock, not by counting hours: on the day the clocks change 9 o'clock is still 9 o'clock.
        guard let open = calendar.date(bySettingHour: hours.start, minute: 0, second: 0, of: day),
              let close = hours.end == 24
                ? calendar.date(byAdding: .day, value: 1, to: day)
                : calendar.date(bySettingHour: hours.end, minute: 0, second: 0, of: day)
        else { return nil }
        var cursor = max(open, roundedUp(now, from: day))
        for event in events.sorted(by: { $0.start < $1.start }) where event.end > cursor {
            if min(event.start, close).timeIntervalSince(cursor) >= minimumFreeSlot {
                return DateInterval(start: cursor, end: min(event.start, close))
            }
            cursor = max(cursor, event.end)
        }
        return close.timeIntervalSince(cursor) >= minimumFreeSlot ? DateInterval(start: cursor, end: close) : nil
    }

    private static func roundedUp(_ date: Date, from day: Date) -> Date {
        let step = Double(roundingMinutes * 60)
        let seconds = date.timeIntervalSince(day)
        return day.addingTimeInterval((seconds / step).rounded(.up) * step)
    }
}
