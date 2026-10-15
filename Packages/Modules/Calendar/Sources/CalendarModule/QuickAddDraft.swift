import Foundation

/// What a line typed into the quick-add field means: the event it would make, shown to the user before it is saved.
nonisolated struct QuickAddDraft: Equatable, Sendable {
    var title: String
    var start: Date
    /// For an all-day event, the start of the day after it, like the days of the agenda.
    var end: Date
    var isAllDay: Bool
    var note: Note?

    /// Something the user should know about what was made of the line.
    enum Note: Equatable, Sendable {
        /// The line had no time that could be read, so the event lasts all day.
        case noTime
    }
}

/// An event to be saved. `calendarID` is nil for "the calendar the system uses for new events".
nonisolated struct NewEvent: Equatable, Sendable {
    var title: String
    var start: Date
    var end: Date
    var isAllDay: Bool
    var calendarID: String?
    /// The zone the times were typed in (the module's calendar), so the saved event and its preview agree.
    var timeZone: TimeZone
}
