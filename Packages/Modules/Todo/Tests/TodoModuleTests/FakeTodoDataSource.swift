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
    func incomplete(dueBy end: Date, undatedIn listID: String?) async -> [TodoReminder] {
        state.withLock { state in
            state.fetchCount += 1
            state.undatedLists.append(listID)
            return state.reminders.filter { reminder in
                guard !reminder.isCompleted else { return false }
                guard let due = reminder.due else { return reminder.listID == listID }
                return TodoReminder.dueDate(of: due, calendar: calendar).map { $0 <= end } ?? false
            }
        }
    }

    func completed(from start: Date, to end: Date) async -> [TodoReminder] {
        state.withLock { state in
            state.reminders.filter { reminder in
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
        }
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
