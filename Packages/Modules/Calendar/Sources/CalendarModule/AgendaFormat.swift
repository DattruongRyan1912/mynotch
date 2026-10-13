import Foundation

/// How dates, times and countdowns read in the tab and the activity. Pure, so tests pin the exact Vietnamese text.
nonisolated enum AgendaFormat {
    /// Every string in the notch is Vietnamese, so dates are too, whatever the Mac's own language is.
    static let locale = Locale(identifier: "vi_VN")

    /// "Thứ Tư, 14 tháng 10".
    static func dayHeader(_ date: Date, calendar: Calendar, locale: Locale = AgendaFormat.locale) -> String {
        formatted(date, template: "EEEEdMMMM", calendar: calendar, locale: locale)
    }

    /// "09:05" (24-hour), in the calendar's time zone.
    static func time(_ date: Date, calendar: Calendar) -> String {
        formatter(calendar: calendar, locale: locale, dateFormat: "HH:mm").string(from: date)
    }

    /// "10:00 – 11:00", or "Cả ngày".
    static func timeRange(of event: AgendaEvent, calendar: Calendar) -> String {
        guard !event.isAllDay else { return "Cả ngày" }
        return "\(time(event.start, calendar: calendar)) – \(time(event.end, calendar: calendar))"
    }

    /// nil for today, "Ngày mai" for tomorrow, else "Thứ Sáu, 16/10".
    static func dayLabel(for date: Date, now: Date, calendar: Calendar) -> String? {
        if calendar.isDate(date, inSameDayAs: now) { return nil }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) {
            return "Ngày mai"
        }
        return formatted(date, template: "EEEEdM", calendar: calendar, locale: locale)
    }

    /// "5 phút" before the start, "Đang diễn ra" after it; nil while the activity is hidden.
    static func countdown(_ state: UpcomingMeetingPolicy.State) -> String? {
        switch state {
        case .hidden: nil
        case .upcoming(let minutesLeft): "\(minutesLeft) phút"
        case .inProgress: "Đang diễn ra"
        }
    }

    /// The time of a reminder due today, "Quá hạn" for one from an earlier day; nil when there is nothing to add.
    /// Lateness is worked out against `now`, not read from the reminder, which only knew it when it was fetched.
    static func dueLabel(of reminder: AgendaReminder, calendar: Calendar, now: Date) -> String? {
        guard let due = reminder.due, let dueDate = AgendaReminder.dueDate(of: due, calendar: calendar) else { return nil }
        if due.hour != nil, calendar.isDate(dueDate, inSameDayAs: now) { return time(dueDate, calendar: calendar) }
        return AgendaReminder.isOverdue(due: due, now: now, calendar: calendar) ? "Quá hạn" : nil
    }

    private static func formatted(_ date: Date, template: String, calendar: Calendar, locale: Locale) -> String {
        formatter(calendar: calendar, locale: locale, template: template).string(from: date)
    }

    private static func formatter(calendar: Calendar, locale: Locale, dateFormat: String? = nil, template: String? = nil) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        if let dateFormat { formatter.dateFormat = dateFormat }
        if let template { formatter.setLocalizedDateFormatFromTemplate(template) }
        return formatter
    }
}
