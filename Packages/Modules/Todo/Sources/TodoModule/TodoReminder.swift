import Foundation

/// How urgent a reminder is, in the three steps Reminders offers. Ordered, so the most urgent compares greatest.
nonisolated enum TodoPriority: Int, Comparable, Sendable {
    case none, low, medium, high

    /// EventKit's 0 is none, 1...4 high, 5 medium and 6...9 low; anything else is read as none.
    init(eventKit value: Int) {
        self = switch value {
        case 1...4: .high
        case 5: .medium
        case 6...9: .low
        default: .none
        }
    }

    /// The numbers Reminders itself writes for each step.
    var eventKit: Int {
        switch self {
        case .none: 0
        case .low: 9
        case .medium: 5
        case .high: 1
        }
    }

    /// "!", "!!" or "!!!": what the row shows and what the quick-add line starts with.
    var marks: String { String(repeating: "!", count: rawValue) }

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// A reminder copied out of EventKit as plain values.
nonisolated struct TodoReminder: Equatable, Sendable, Identifiable {
    /// The item identifier, which `TodoDataSource.setCompleted` takes.
    var id: String
    var title: String
    /// As the user set it: a date alone, or a date with a time.
    var due: DateComponents?
    var priority: TodoPriority
    var isCompleted: Bool
    var completionDate: Date?
    var listID: String
    var listTitle: String
    var listColor: TodoColor
    /// Whether it repeats. Completing one hands the next occurrence over, which EventKit does (see `TodoDataSource.setCompleted`);
    /// the row only tells the user it repeats.
    var isRecurring = false

    /// The components are read in the calendar they were written in (EventKit stamps Gregorian ones, whatever the
    /// user's calendar is), and in `calendar`'s time zone unless they name their own. A day alone is that day wherever it
    /// is read, so it never takes a zone of its own: midnight UTC would otherwise be the evening before in the Americas.
    static func dueDate(of due: DateComponents, calendar: Calendar) -> Date? {
        var dueCalendar = due.calendar ?? calendar
        var components = due
        if due.timeZone == nil || due.hour == nil {
            dueCalendar.timeZone = calendar.timeZone
            components.timeZone = nil
        }
        return dueCalendar.date(from: components)
    }
}

/// A list of Reminders the user can show, hide or add to, copied out of EventKit as plain values.
nonisolated struct TodoListInfo: Equatable, Sendable, Identifiable {
    /// The identifier `TodoReminder.listID` carries; titles can repeat across accounts.
    var id: String
    var title: String
    var color: TodoColor
    /// Subscribed and shared-read-only lists can be read but not added to.
    var allowsModifications = true
    /// The list the system puts a new reminder in when none is chosen.
    var isDefaultForNewReminders = false
}
