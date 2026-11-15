import EventKit
import Foundation
import MyNotchCore

nonisolated enum CalendarServiceError: Error, Equatable {
    /// Reminders access is missing, so nothing can be read or changed.
    case accessDenied
    case reminderNotFound
    /// Every calendar is read-only, so there is nowhere to put the event.
    case noWritableCalendar
}

/// Carries EventKit's reminders out of its callback thread unchanged: they aren't `Sendable`, and reading them is
/// left to the actor so every EventKit object is only touched there.
private nonisolated struct FetchedReminders: @unchecked Sendable {
    let reminders: [EKReminder]
}

/// The real data source: one `EKEventStore` behind an actor. EventKit's objects aren't `Sendable`, so each is
/// turned into a value before it leaves, and the synchronous `events(matching:)` runs here, off the main actor.
actor CalendarService: CalendarDataSource {
    /// How long the store must stay quiet before `changes` signals.
    static let changeQuietPeriod = Duration.seconds(1)

    /// Created on first use, which only happens once access is granted: a store made before that can keep
    /// showing nothing after the user allows it.
    private lazy var store = EKEventStore()
    private let authorizationStatus: @Sendable (Permission) -> PermissionStatus

    /// Tests pass `authorizationStatus` so no check reaches EventKit.
    init(authorizationStatus: @escaping @Sendable (Permission) -> PermissionStatus = CalendarService.systemStatus(of:)) {
        self.authorizationStatus = authorizationStatus
    }

    nonisolated func authorization(for permission: Permission) -> PermissionStatus {
        authorizationStatus(permission)
    }

    func events(from start: Date, to end: Date) async -> [AgendaEvent] {
        guard authorization(for: .calendars) == .granted else { return [] }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate).map(AgendaEvent.init)
    }

    func reminders(dueBy end: Date) async -> [AgendaReminder] {
        guard authorization(for: .reminders) == .granted else { return [] }
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: end, calendars: nil)
        let fetched = await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { continuation.resume(returning: FetchedReminders(reminders: $0 ?? [])) }
        }
        let now = Date.now
        let calendar = Calendar.current
        return fetched.reminders.map { AgendaReminder($0, now: now, calendar: calendar) }
    }

    func calendars() async -> [CalendarInfo] {
        guard authorization(for: .calendars) == .granted else { return [] }
        let defaultID = store.defaultCalendarForNewEvents?.calendarIdentifier
        return store.calendars(for: .event).map { CalendarInfo($0, isDefault: $0.calendarIdentifier == defaultID) }
    }

    /// The calendar is the chosen one, else the system's, else any that takes events (`QuickAddTarget`); a calendar that
    /// cannot take events is never written to. The times are `NewEvent.eventKitTiming`.
    func createEvent(_ new: NewEvent) async throws {
        guard authorization(for: .calendars) == .granted else { throw CalendarServiceError.accessDenied }
        let defaultID = store.defaultCalendarForNewEvents?.calendarIdentifier
        let known = store.calendars(for: .event).map { CalendarInfo($0, isDefault: $0.calendarIdentifier == defaultID) }
        guard let target = QuickAddTarget.resolve(chosenID: new.calendarID ?? "", in: known),
              let calendar = store.calendar(withIdentifier: target.id)
        else { throw CalendarServiceError.noWritableCalendar }
        let timing = new.eventKitTiming
        let event = EKEvent(eventStore: store)
        event.calendar = calendar
        event.title = new.title
        event.isAllDay = new.isAllDay
        event.timeZone = timing.timeZone
        event.startDate = timing.start
        event.endDate = timing.end
        try store.save(event, span: .thisEvent, commit: true)
    }

    func complete(reminderID: String) async throws {
        guard authorization(for: .reminders) == .granted else { throw CalendarServiceError.accessDenied }
        guard let reminder = store.calendarItem(withIdentifier: reminderID) as? EKReminder else {
            throw CalendarServiceError.reminderNotFound
        }
        reminder.isCompleted = true
        try store.save(reminder, commit: true)
    }

    /// Not tied to this actor's store: the notification of any store means the same database changed.
    nonisolated var changes: AsyncStream<Void> {
        // `Notification` isn't `Sendable`, so it is read inside the task and only a plain signal goes on.
        let (raw, input) = AsyncStream<Void>.makeStream()
        let listener = Task {
            for await _ in NotificationCenter.default.notifications(named: .EKEventStoreChanged) { input.yield() }
        }
        input.onTermination = { _ in listener.cancel() }
        return ChangeCoalescer.coalescing(raw, quietPeriod: Self.changeQuietPeriod)
    }

    /// What the app reads from the system. Only `.calendars` and `.reminders` have an answer.
    nonisolated static func systemStatus(of permission: Permission) -> PermissionStatus {
        switch permission {
        case .calendars: status(of: .event)
        case .reminders: status(of: .reminder)
        default: .denied
        }
    }

    /// Write-only access can't read events, so it counts as denied.
    private nonisolated static func status(of entity: EKEntityType) -> PermissionStatus {
        switch EKEventStore.authorizationStatus(for: entity) {
        case .fullAccess: .granted
        case .notDetermined: .notDetermined
        default: .denied
        }
    }
}
