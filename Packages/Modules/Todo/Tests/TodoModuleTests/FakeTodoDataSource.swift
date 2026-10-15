import Foundation
import Synchronization
@testable import TodoModule

/// Stands in for EventKit: tests set what "Reminders" holds, change it, and read back what was asked of it. Like EventKit's
/// predicates it answers from one store of every reminder, so what the module reads is what it would read for real.
nonisolated final class FakeTodoDataSource: TodoDataSource {
    private struct State {
        var reminders: [TodoReminder]
        var lists: [TodoListInfo] = [
            TodoListInfo(id: "inbox", title: "Inbox", color: .gray, isDefaultForNewReminders: true),
            TodoListInfo(id: "work", title: "Work", color: .gray),
            TodoListInfo(id: "home", title: "Home", color: .gray),
        ]
        var now: Date
        var completionCalls: [(id: String, completed: Bool)] = []
        var completionFailure: (any Error)?
        var completionGate: (@Sendable () async -> Void)?
        var created: [NewTodo] = []
        var createCalls = 0
        var creationFailure: (any Error)?
        var createGate: (@Sendable () async -> Void)?
        var fetchCount = 0
        var fetchFailure: (any Error)?
        /// A completed repeating reminder's id and the id of the occurrence that took its place.
        var successors: [String: String] = [:]
        var undatedLists: [String?] = []
        var observers: [AsyncStream<Void>.Continuation] = []
    }

    private let state: Mutex<State>
    let calendar: Calendar

    /// `now` is the moment a completion is stamped with; tests move it with `now`.
    init(reminders: [TodoReminder] = [], now: Date, calendar: Calendar = fixedCalendar()) {
        state = Mutex(State(reminders: reminders, now: now))
        self.calendar = calendar
    }

    var reminders: [TodoReminder] {
        get { state.withLock { $0.reminders } }
        set { state.withLock { $0.reminders = newValue } }
    }

    var listInfos: [TodoListInfo] {
        get { state.withLock { $0.lists } }
        set { state.withLock { $0.lists = newValue } }
    }

    var now: Date {
        get { state.withLock { $0.now } }
        set { state.withLock { $0.now = newValue } }
    }

    /// Every `setCompleted` asked for, in order, those that failed included.
    var completionCalls: [(id: String, completed: Bool)] { state.withLock { $0.completionCalls } }
    var created: [NewTodo] { state.withLock { $0.created } }
    var createCalls: Int { state.withLock { $0.createCalls } }
    /// How many times the incomplete reminders were read: one per refresh.
    var fetchCount: Int { state.withLock { $0.fetchCount } }
    /// The `undatedIn` of every read, in order.
    var undatedLists: [String?] { state.withLock { $0.undatedLists } }

    var completionFailure: (any Error)? {
        get { state.withLock { $0.completionFailure } }
        set { state.withLock { $0.completionFailure = newValue } }
    }

    /// Awaited by every completion after it is recorded and before it answers, to hold one in the middle of its work.
    var completionGate: (@Sendable () async -> Void)? {
        get { state.withLock { $0.completionGate } }
        set { state.withLock { $0.completionGate = newValue } }
    }

    /// Makes the reads throw, like EventKit's fetch answering with nothing.
    var fetchFailure: (any Error)? {
        get { state.withLock { $0.fetchFailure } }
        set { state.withLock { $0.fetchFailure = newValue } }
    }

    var creationFailure: (any Error)? {
        get { state.withLock { $0.creationFailure } }
        set { state.withLock { $0.creationFailure = newValue } }
    }

    var createGate: (@Sendable () async -> Void)? {
        get { state.withLock { $0.createGate } }
        set { state.withLock { $0.createGate = newValue } }
    }

    /// Plays the Reminders database changing (the iPhone, the Reminders app), to everyone listening to `changes`.
    func emitChange() {
        let observers = state.withLock { $0.observers }
        for observer in observers { observer.yield() }
    }

    func lists() async -> [TodoListInfo] {
        state.withLock { $0.lists }
    }

    /// Like EventKit's predicate: due on or before `end`; reminders with no date only come from `undatedIn`.
    func incomplete(dueBy end: Date, undatedIn listID: String?) async throws -> [TodoReminder] {
        try state.withLock { state in
            state.fetchCount += 1
            state.undatedLists.append(listID)
            if let failure = state.fetchFailure { throw failure }
            return state.reminders.filter { reminder in
                guard !reminder.isCompleted else { return false }
                guard let due = reminder.due else { return reminder.listID == listID }
                return TodoReminder.dueDate(of: due, calendar: calendar).map { $0 <= end } ?? false
            }
        }
    }

    func completed(from start: Date, to end: Date) async throws -> [TodoReminder] {
        try state.withLock { state in
            if let failure = state.fetchFailure { throw failure }
            return state.reminders.filter { reminder in
                reminder.isCompleted && (reminder.completionDate.map { $0 >= start && $0 < end } ?? false)
            }
        }
    }

    func setCompleted(_ completed: Bool, reminderID: String) async throws {
        let gate = state.withLock { state in
            state.completionCalls.append((reminderID, completed))
            return state.completionGate
        }
        await gate?()
        try state.withLock { state in
            if let failure = state.completionFailure { throw failure }
            guard let index = state.reminders.firstIndex(where: { $0.id == reminderID }) else { throw TodoServiceError.reminderNotFound }
            state.reminders[index].isCompleted = completed
            state.reminders[index].completionDate = completed ? state.now : nil
            advanceRecurrence(&state, at: index, completed: completed)
        }
    }

    /// What Apple documents for repeating reminders: "only the first incomplete reminder of a recurring set is obtainable ...
    /// When the reminder is completed, the next reminder in the recurrence set becomes available." So completing one leaves it
    /// done and brings the next occurrence (a day later here: the fake's rule is daily), and taking the tick back leaves
    /// the set as it was, with that next occurrence gone again.
    private func advanceRecurrence(_ state: inout State, at index: Int, completed: Bool) {
        let reminder = state.reminders[index]
        guard reminder.isRecurring else { return }
        guard completed else {
            if let successor = state.successors.removeValue(forKey: reminder.id) {
                state.reminders.removeAll { $0.id == successor }
            }
            return
        }
        guard let due = reminder.due, let date = TodoReminder.dueDate(of: due, calendar: calendar),
              let nextDate = calendar.date(byAdding: .day, value: 1, to: date)
        else { return }
        var next = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: nextDate)
        if due.hour == nil { (next.hour, next.minute) = (nil, nil) }
        next.calendar = Calendar(identifier: .gregorian)
        var successor = reminder
        successor.id = "\(reminder.id)#next"
        successor.isCompleted = false
        successor.completionDate = nil
        successor.due = next
        state.reminders.append(successor)
        state.successors[reminder.id] = successor.id
    }

    /// Like the real one, a reminder saved shows up in the next read.
    func create(_ new: NewTodo) async throws {
        let gate = state.withLock { state in
            state.createCalls += 1
            return state.createGate
        }
        await gate?()
        try state.withLock { state in
            if let failure = state.creationFailure { throw failure }
            guard let list = TodoListChoice.resolve(chosenID: new.listID, in: state.lists) else { throw TodoServiceError.noWritableList }
            state.created.append(new)
            let id = "created\(state.created.count)"
            state.reminders.append(TodoReminder(
                id: id, title: new.title, due: new.due, priority: new.priority, isCompleted: false, completionDate: nil,
                listID: list.id, listTitle: list.title, listColor: list.color
            ))
        }
    }

    var changes: AsyncStream<Void> {
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        state.withLock { $0.observers.append(continuation) }
        return stream
    }
}
