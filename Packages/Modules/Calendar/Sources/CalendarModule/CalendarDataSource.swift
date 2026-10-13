import Foundation
import MyNotchCore

/// Where the module gets events and reminders. A protocol so tests can fake it and EventKit stays in one type.
nonisolated protocol CalendarDataSource: Sendable {
    /// Events overlapping the range, one per occurrence, in no particular order. Empty without Calendars access.
    func events(from start: Date, to end: Date) async -> [AgendaEvent]
    /// Incomplete reminders due by `end`, overdue ones included. Empty without Reminders access.
    func reminders(dueBy end: Date) async -> [AgendaReminder]
    /// The calendars events can come from, for the "hidden calendars" setting. Empty without Calendars access.
    func calendars() async -> [CalendarInfo]
    func complete(reminderID: String) async throws
    /// Signals that events or reminders changed, with bursts coalesced. Every access starts a new stream.
    var changes: AsyncStream<Void> { get }
    /// Never prompts. Only `.calendars` and `.reminders` have an answer; anything else is `.denied`.
    func authorization(for permission: Permission) -> PermissionStatus
}
