import Foundation

/// A reminder to add, as the quick-add line read it.
nonisolated struct NewTodo: Equatable, Sendable {
    var title: String
    var due: DateComponents
    var priority: TodoPriority
    /// The list the user chose for new reminders; nil lets `TodoListChoice` pick the system's.
    var listID: String?
}

nonisolated enum TodoServiceError: Error, Equatable {
    /// Reminders access is missing, so nothing can be read or changed.
    case accessDenied
    case reminderNotFound
    /// Every list is read-only, so there is nowhere to put the reminder.
    case noWritableList
    /// EventKit's fetch answered with nothing at all (not an empty list): the read failed.
    case fetchFailed
}

/// Where the module gets reminders. A protocol so tests can fake it and EventKit stays in one type.
nonisolated protocol TodoDataSource: Sendable {
    /// The lists reminders live in, for the settings and for finding the default one. Empty without Reminders access.
    func lists() async -> [TodoListInfo]
    /// Incomplete reminders due by `end` (overdue ones included), from every list, and, when `undatedIn` names a list,
    /// that list's reminders with no date. Empty without Reminders access; throws when the read itself fails, which is not
    /// the same as nothing being due.
    func incomplete(dueBy end: Date, undatedIn listID: String?) async throws -> [TodoReminder]
    /// Reminders completed from `start` up to `end`. Empty without Reminders access; throws when the read fails.
    func completed(from start: Date, to end: Date) async throws -> [TodoReminder]
    /// Ticks a reminder off, or takes the tick back. Throws without access, or for a reminder that is gone. For a repeating
    /// reminder this is all it takes: Apple documents that "only the first incomplete reminder of a recurring set is
    /// obtainable ... When the reminder is completed, the next reminder in the recurrence set becomes available", so the
    /// store brings the next occurrence itself and this ticks only the one on the list.
    func setCompleted(_ completed: Bool, reminderID: String) async throws
    /// Saves a new reminder. Throws without access or when no list can take it.
    func create(_ new: NewTodo) async throws
    /// Signals that reminders changed, with bursts coalesced. Every access starts a new stream.
    var changes: AsyncStream<Void> { get }
    /// Called when access goes from missing to granted, before the next read. A store that existed before the grant can keep
    /// answering with nothing, so the source starts over with a new one. Apple: "If you request reminders before prompting
    /// the person for access with this method, you'll need to reset the event store with the reset() method to receive data
    /// after they grant access."
    func accessWasGranted() async
}

/// Which list a new reminder goes to, and where the undated ones are read from.
nonisolated enum TodoListChoice {
    /// The list chosen in Settings if it still exists and takes reminders, else the one the system uses for new
    /// reminders, else the first that takes any. Nil when no list takes reminders (or none is known); saving then fails
    /// with `TodoServiceError.noWritableList`.
    static func resolve(chosenID: String?, in lists: [TodoListInfo]) -> TodoListInfo? {
        let writable = sorted(lists.filter(\.allowsModifications))
        return writable.first { $0.id == chosenID } ?? writable.first(where: \.isDefaultForNewReminders) ?? writable.first
    }

    /// By title as the user would sort them, then by id so equal titles keep a fixed order.
    static func sorted(_ lists: [TodoListInfo]) -> [TodoListInfo] {
        lists.sorted {
            switch $0.title.localizedStandardCompare($1.title) {
            case .orderedAscending: true
            case .orderedDescending: false
            case .orderedSame: $0.id < $1.id
            }
        }
    }

    /// The "hidden lists" setting stores what is hidden, so a list added later shows up by itself.
    static func isVisible(_ id: String, hidden: [String]) -> Bool {
        !hidden.contains(id)
    }

    /// `hidden` with `id` added or removed; hiding twice adds it once.
    static func setting(_ id: String, visible: Bool, in hidden: [String]) -> [String] {
        if visible { return hidden.filter { $0 != id } }
        return hidden.contains(id) ? hidden : hidden + [id]
    }
}
