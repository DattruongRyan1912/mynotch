/// The quick-add field of the Calendar tab while it is open: the line, what it was read as, and where it would be saved.
nonisolated struct QuickAddState: Equatable, Sendable {
    var text = ""
    /// The line as read now; nil while it is empty.
    var draft: QuickAddDraft?
    /// Where the event will go. Nil until the calendars have been read, or when there are none to choose from; the
    /// system then picks.
    var calendar: CalendarInfo?
    /// Whether the app may add events. Without full access the tab shows a hint where the field would be.
    var canWrite: Bool
    var phase = Phase.editing

    enum Phase: Equatable, Sendable {
        case editing
        /// Return was pressed and the event is being saved; another Return does nothing.
        case saving
        /// The save failed. The line is kept, and Return tries again.
        case failed
    }
}

/// Which calendar a new event goes to.
nonisolated enum QuickAddTarget {
    /// The calendar chosen in Settings if it still exists and takes events, else the one the system uses for new events,
    /// else the first that takes any. Nil when no calendar takes events (or none is known): the system decides then.
    static func resolve(chosenID: String, in calendars: [CalendarInfo]) -> CalendarInfo? {
        let writable = HiddenCalendars.sorted(calendars.filter(\.allowsModifications))
        return writable.first { $0.id == chosenID } ?? writable.first(where: \.isDefaultForNewEvents) ?? writable.first
    }
}
