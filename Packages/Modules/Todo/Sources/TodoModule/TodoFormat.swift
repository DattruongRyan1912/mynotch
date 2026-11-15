import Foundation

/// How the list's words read. Pure, so tests pin the exact Vietnamese text.
nonisolated enum TodoFormat {
    /// Every string in the notch is Vietnamese, so times are too, whatever the Mac's own language is.
    static let locale = Locale(identifier: "vi_VN")

    /// "hôm qua" for one day late, "quá hạn 3 ngày" for more; nil for one that is not late.
    static func overdueBadge(days: Int) -> String? {
        switch days {
        case ..<1: nil
        case 1: "hôm qua"
        default: "quá hạn \(days) ngày"
        }
    }

    /// "15:30" (24-hour) for a reminder with a time; nil for a date alone or none.
    static func time(of due: DateComponents?, calendar: Calendar) -> String? {
        guard let due, due.hour != nil, let date = TodoReminder.dueDate(of: due, calendar: calendar) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    /// "Xong 4/7".
    static func progress(_ progress: TodoProgress) -> String {
        "Xong \(progress.done)/\(progress.total)"
    }

    /// "Còn 3 việc": the collapsed notch's line.
    static func remaining(_ count: Int) -> String {
        "Còn \(count) việc"
    }

    /// What the field says about how the line was read, so a surprise shows before Return: "Ngày mai · 15:00 · !!". Only
    /// what differs from the plain default (today, no time, no priority); nil when the line changed nothing.
    static func hint(for draft: TodoDraft, now: Date, calendar: Calendar) -> String? {
        var parts: [String] = []
        let isTomorrow: Bool
        if let due = draft.due, let date = TodoReminder.dueDate(of: due, calendar: calendar), !calendar.isDate(date, inSameDayAs: now) {
            isTomorrow = true
            parts.append("Ngày mai")
        } else {
            isTomorrow = false
        }
        if let time = time(of: draft.due, calendar: calendar) { parts.append(time) }
        if draft.priority != .none { parts.append(draft.priority.marks) }
        if !isTomorrow, let quadrant = draft.quadrant {
            parts.append("\(quadrant.shortCode) · \(quadrant.label)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
