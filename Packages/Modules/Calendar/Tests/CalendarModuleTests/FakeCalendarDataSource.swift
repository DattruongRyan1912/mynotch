import Foundation
import MyNotchCore
import Synchronization
@testable import CalendarModule

/// Stands in for EventKit: tests set what the "calendar" holds, change it, and read back what was asked of it.
nonisolated final class FakeCalendarDataSource: CalendarDataSource {
    private struct State {
        var events: [AgendaEvent]
        var reminders: [AgendaReminder]
        var statuses: [Permission: PermissionStatus] = [.calendars: .granted, .reminders: .granted]
        var completedIDs: [String] = []
        var observers: [AsyncStream<Void>.Continuation] = []
    }

    private let state: Mutex<State>

    init(events: [AgendaEvent] = [], reminders: [AgendaReminder] = []) {
        state = Mutex(State(events: events, reminders: reminders))
    }

    var events: [AgendaEvent] {
        get { state.withLock { $0.events } }
        set { state.withLock { $0.events = newValue } }
    }

    var reminders: [AgendaReminder] {
        get { state.withLock { $0.reminders } }
        set { state.withLock { $0.reminders = newValue } }
    }

    var completedIDs: [String] { state.withLock { $0.completedIDs } }

    func setAuthorization(_ status: PermissionStatus, for permission: Permission) {
        state.withLock { $0.statuses[permission] = status }
    }

    /// Plays the calendar database changing, to everyone listening to `changes`.
    func emitChange() {
        let observers = state.withLock { $0.observers }
        for observer in observers { observer.yield() }
    }

    func authorization(for permission: Permission) -> PermissionStatus {
        state.withLock { $0.statuses[permission] ?? .denied }
    }

    /// Like EventKit's predicate, every event overlapping the range.
    func events(from start: Date, to end: Date) async -> [AgendaEvent] {
        state.withLock { $0.events.filter { $0.start < end && $0.end > start } }
    }

    func reminders(dueBy end: Date) async -> [AgendaReminder] {
        state.withLock { $0.reminders }
    }

    func complete(reminderID: String) async throws {
        state.withLock {
            $0.completedIDs.append(reminderID)
            $0.reminders.removeAll { $0.id == reminderID }
        }
    }

    var changes: AsyncStream<Void> {
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        state.withLock { $0.observers.append(continuation) }
        return stream
    }
}
