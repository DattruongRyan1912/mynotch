import EventKit
import Foundation
import MyNotchCore

/// Carries EventKit's reminders out of its callback thread unchanged: they aren't `Sendable`, and reading them is
/// left to the actor so every EventKit object is only touched there.
private nonisolated struct FetchedReminders: @unchecked Sendable {
    let reminders: [EKReminder]
}

/// The real data source: one `EKEventStore` behind an actor, so all the EventKit work, the fetches and the saves, runs off
/// the main actor. EventKit's objects aren't `Sendable`, so each is turned into a value before it leaves.
actor TodoService: TodoDataSource {
    /// How long the store must stay quiet before `changes` signals.
    static let changeQuietPeriod = Duration.seconds(1)

    /// Created on first use, which only happens once access is granted: a store made before that can keep showing
    /// nothing after the user allows it.
    private lazy var store = EKEventStore()
    private let authorizationStatus: @Sendable () -> PermissionStatus
    private let notificationCenter: NotificationCenter
    private let quietPeriod: Duration

    /// Tests pass `authorizationStatus`, a private `notificationCenter` and a short `changeQuietPeriod`, so no check reaches
    /// EventKit and no notification of the system is heard.
    init(
        authorizationStatus: @escaping @Sendable () -> PermissionStatus = TodoService.systemStatus,
        notificationCenter: NotificationCenter = .default,
        changeQuietPeriod: Duration = TodoService.changeQuietPeriod
    ) {
        self.authorizationStatus = authorizationStatus
        self.notificationCenter = notificationCenter
        quietPeriod = changeQuietPeriod
    }

    func lists() async -> [TodoListInfo] {
        guard authorizationStatus() == .granted else { return [] }
        let defaultID = store.defaultCalendarForNewReminders()?.calendarIdentifier
        return store.calendars(for: .reminder).map { TodoListInfo($0, isDefault: $0.calendarIdentifier == defaultID) }
    }

    func incomplete(dueBy end: Date, undatedIn listID: String?) async -> [TodoReminder] {
        guard authorizationStatus() == .granted else { return [] }
        var found = await fetch(store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: end, calendars: nil))
        if let listID, let list = store.calendar(withIdentifier: listID) {
            // With no range at all, EventKit also returns the reminders that have no date.
            let all = await fetch(store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: [list]))
            found += all.filter { $0.dueDateComponents == nil }
        }
        var seen: Set<String> = []
        return found.map(TodoReminder.init).filter { seen.insert($0.id).inserted }
    }

    func completed(from start: Date, to end: Date) async -> [TodoReminder] {
        guard authorizationStatus() == .granted else { return [] }
        let predicate = store.predicateForCompletedReminders(withCompletionDateStarting: start, ending: end, calendars: nil)
        return await fetch(predicate).map(TodoReminder.init)
    }

    func setCompleted(_ completed: Bool, reminderID: String) async throws {
        guard authorizationStatus() == .granted else { throw TodoServiceError.accessDenied }
        guard let reminder = store.calendarItem(withIdentifier: reminderID) as? EKReminder else {
            throw TodoServiceError.reminderNotFound
        }
        reminder.isCompleted = completed
        try store.save(reminder, commit: true)
    }

    /// The list is the chosen one, else the system's, else any that takes reminders (`TodoListChoice`); a list that
    /// cannot take reminders is never written to.
    func create(_ new: NewTodo) async throws {
        guard authorizationStatus() == .granted else { throw TodoServiceError.accessDenied }
        let defaultID = store.defaultCalendarForNewReminders()?.calendarIdentifier
        let known = store.calendars(for: .reminder).map { TodoListInfo($0, isDefault: $0.calendarIdentifier == defaultID) }
        guard let target = TodoListChoice.resolve(chosenID: new.listID, in: known),
              let list = store.calendar(withIdentifier: target.id)
        else { throw TodoServiceError.noWritableList }
        let reminder = EKReminder(eventStore: store)
        reminder.calendar = list
        reminder.title = new.title
        reminder.priority = new.priority.eventKit
        reminder.dueDateComponents = new.due
        try store.save(reminder, commit: true)
    }

    /// Not tied to this actor's store: the notification of any store means the same database changed.
    nonisolated var changes: AsyncStream<Void> {
        // `Notification` isn't `Sendable`, so it is read inside the task and only a plain signal goes on.
        let (raw, input) = AsyncStream<Void>.makeStream()
        let center = notificationCenter
        let listener = Task {
            for await _ in center.notifications(named: .EKEventStoreChanged) { input.yield() }
        }
        input.onTermination = { _ in listener.cancel() }
        return ChangeCoalescer.coalescing(raw, quietPeriod: quietPeriod)
    }

    /// What the app reads from the system: full access is granted, nothing else is. Write-only access can't read.
    nonisolated static func systemStatus() -> PermissionStatus {
        status(of: EKEventStore.authorizationStatus(for: .reminder))
    }

    nonisolated static func status(of status: EKAuthorizationStatus) -> PermissionStatus {
        switch status {
        case .fullAccess: .granted
        case .notDetermined: .notDetermined
        default: .denied
        }
    }

    private func fetch(_ predicate: NSPredicate) async -> [EKReminder] {
        let fetched = await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { continuation.resume(returning: FetchedReminders(reminders: $0 ?? [])) }
        }
        return fetched.reminders
    }
}
