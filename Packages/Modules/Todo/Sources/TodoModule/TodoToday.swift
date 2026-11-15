import Foundation

/// A reminder on today's list, with how many days it has been waiting.
nonisolated struct TodoItem: Equatable, Sendable, Identifiable {
    var reminder: TodoReminder
    /// Whole days since the day it was due; 0 for one due today and for one without a date.
    var overdueDays: Int

    var id: String { reminder.id }
}

/// What the counter says: how many of today's items are done.
nonisolated struct TodoProgress: Equatable, Sendable {
    var done: Int
    var total: Int

    var remaining: Int { total - done }
}

/// What decides which reminders are on the list, from the settings.
nonisolated struct TodoRules: Equatable, Sendable {
    /// Lists the user turned off: nothing from them shows, not even a reminder with no date.
    var hiddenListIDs: Set<String> = []
    /// Whether reminders with no date count as today's, when they are in `defaultListID`.
    var includeUndated = true
    /// The list the undated reminders come from; nil when there is none to take them from.
    var defaultListID: String?
}

/// Picks today's reminders and puts them in order. Pure, so what is on the list and why is checked on plain values.
nonisolated enum TodoToday {
    /// The reminders due today, the ones overdue (carried over from earlier days: Reminders keeps them, so nothing is
    /// stored here), the undated ones of the default list, and what was completed today among those. Overdue first,
    /// oldest first; then today's by due time (a time, then a date alone, then no date at all), most urgent first within
    /// a time. A reminder done today keeps the place it had, so ticking it off moves nothing.
    static func items(from reminders: [TodoReminder], rules: TodoRules, now: Date, calendar: Calendar) -> [TodoItem] {
        let today = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today.addingTimeInterval(86_400)
        let entries = reminders.compactMap { entry(for: $0, rules: rules, today: today, tomorrow: tomorrow, calendar: calendar) }
        return entries.sorted { $0.key < $1.key }.map(\.item)
    }

    static func progress(of items: [TodoItem]) -> TodoProgress {
        TodoProgress(done: items.count { $0.reminder.isCompleted }, total: items.count)
    }

    private struct Entry {
        var item: TodoItem
        var key: Key
    }

    /// Fields in the order they decide; a tuple compares them one after the other.
    private typealias Key = (group: Int, kind: Int, when: Date, urgency: Int, title: String, id: String)

    private static func entry(
        for reminder: TodoReminder, rules: TodoRules, today: Date, tomorrow: Date, calendar: Calendar
    ) -> Entry? {
        guard !rules.hiddenListIDs.contains(reminder.listID) else { return nil }
        if reminder.isCompleted {
            guard let completed = reminder.completionDate, completed >= today, completed < tomorrow else { return nil }
        }
        let dueDate = reminder.due.flatMap { TodoReminder.dueDate(of: $0, calendar: calendar) }
        var overdueDays = 0
        if let dueDate {
            let dueDay = calendar.startOfDay(for: dueDate)
            guard dueDay < tomorrow else { return nil }
            if dueDay < today { overdueDays = calendar.dateComponents([.day], from: dueDay, to: today).day ?? 1 }
        } else if !(rules.includeUndated && reminder.listID == rules.defaultListID) {
            return nil
        }
        let isTimed = reminder.due?.hour != nil
        let kind = overdueDays > 0 ? 0 : dueDate == nil ? 3 : isTimed ? 1 : 2
        let key: Key = (
            overdueDays > 0 ? 0 : 1, kind, (overdueDays > 0 || isTimed ? dueDate : nil) ?? .distantPast,
            -reminder.priority.rawValue, reminder.title.lowercased(), reminder.id
        )
        return Entry(item: TodoItem(reminder: reminder, overdueDays: overdueDays), key: key)
    }
}
