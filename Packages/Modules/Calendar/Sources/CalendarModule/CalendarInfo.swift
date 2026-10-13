/// A calendar the user can show or hide, copied out of EventKit as plain values.
nonisolated struct CalendarInfo: Equatable, Sendable, Identifiable {
    /// The identifier `AgendaEvent.calendarID` carries; titles can repeat across accounts.
    var id: String
    var title: String
    var color: RGBAColor
}
