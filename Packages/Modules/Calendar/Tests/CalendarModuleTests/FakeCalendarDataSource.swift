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
        var calendars: [CalendarInfo] = []
        var completedIDs: [String] = []
        var completionFailure: (any Error)?
        var createdEvents: [NewEvent] = []
        var createCalls = 0
        var creationFailure: (any Error)?
        var createGate: (@Sendable () async -> Void)?
        var eventRanges: [DateInterval] = []
        var eventsGate: (@Sendable () async -> Void)?
        var reminderFetchCount = 0
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

    var calendars: [CalendarInfo] {
        get { state.withLock { $0.calendars } }
        set { state.withLock { $0.calendars = newValue } }
    }

    var completedIDs: [String] { state.withLock { $0.completedIDs } }

    /// Makes `complete(reminderID:)` throw, like EventKit refusing the save.
    var completionFailure: (any Error)? {
        get { state.withLock { $0.completionFailure } }
        set { state.withLock { $0.completionFailure = newValue } }
    }

    /// What was saved through `createEvent`, in order. Nothing here ever reaches a real calendar.
    var createdEvents: [NewEvent] { state.withLock { $0.createdEvents } }
    /// How many saves were asked for, those held by `createGate` or failed included.
    var createCalls: Int { state.withLock { $0.createCalls } }

    /// Makes `createEvent` throw, like EventKit refusing the save.
    var creationFailure: (any Error)? {
        get { state.withLock { $0.creationFailure } }
        set { state.withLock { $0.creationFailure = newValue } }
    }

    /// Awaited by every save after it is counted and before it answers, to hold one in the middle of its work.
    var createGate: (@Sendable () async -> Void)? {
        get { state.withLock { $0.createGate } }
        set { state.withLock { $0.createGate = newValue } }
    }

    /// Awaited by every events request after it is recorded and before it answers, so a test can hold a refresh in
    /// the middle of its read, and let the clock and the timers move meanwhile.
    var eventsGate: (@Sendable () async -> Void)? {
        get { state.withLock { $0.eventsGate } }
        set { state.withLock { $0.eventsGate = newValue } }
    }

    /// The range of every events request, in order.
    var eventRanges: [DateInterval] { state.withLock { $0.eventRanges } }
    var eventFetchCount: Int { eventRanges.count }
    var reminderFetchCount: Int { state.withLock { $0.reminderFetchCount } }

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
        let gate = state.withLock { state in
            state.eventRanges.append(DateInterval(start: start, end: end))
            return state.eventsGate
        }
        await gate?()
        return state.withLock { $0.events.filter { $0.start < end && $0.end > start } }
    }

    func reminders(dueBy end: Date) async -> [AgendaReminder] {
        state.withLock {
            $0.reminderFetchCount += 1
            return $0.reminders
        }
    }

    func calendars() async -> [CalendarInfo] {
        state.withLock { $0.calendars }
    }

    func complete(reminderID: String) async throws {
        try state.withLock {
            if let failure = $0.completionFailure { throw failure }
            $0.completedIDs.append(reminderID)
            $0.reminders.removeAll { $0.id == reminderID }
        }
    }

    /// Like the real one, an event saved shows up in the next read of the range.
    func createEvent(_ new: NewEvent) async throws {
        let gate = state.withLock { state in
            state.createCalls += 1
            return state.createGate
        }
        await gate?()
        try state.withLock { state in
            if let failure = state.creationFailure { throw failure }
            guard state.statuses[.calendars] == .granted else { throw CalendarServiceError.accessDenied }
            state.createdEvents.append(new)
            let id = "created\(state.createdEvents.count)"
            state.events.append(AgendaEvent(
                id: id, calendarItemIdentifier: id, title: new.title, start: new.start, end: new.end, isAllDay: new.isAllDay,
                calendarID: new.calendarID ?? "work", calendarTitle: "Work", calendarColor: .gray, location: nil, meetingURL: nil,
                status: .confirmed, myParticipation: .unknown
            ))
        }
    }

    var changes: AsyncStream<Void> {
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        state.withLock { $0.observers.append(continuation) }
        return stream
    }
}
