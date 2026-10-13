import Foundation

/// One occurrence of a calendar event, copied out of EventKit as plain values.
nonisolated struct AgendaEvent: Equatable, Sendable {
    /// Identifies this occurrence: the item identifier plus the occurrence start. Every occurrence of a recurring
    /// event shares the item identifier, and rescheduling one gives it a new id, so a dismissal doesn't outlive the change.
    var id: String
    /// What `ical://ekevent/` opens; shared by all occurrences of a recurring event.
    var calendarItemIdentifier: String
    var title: String
    var start: Date
    var end: Date
    var isAllDay: Bool
    /// Identifies the calendar for the "hidden calendars" setting; titles can repeat across accounts.
    var calendarID: String
    var calendarTitle: String
    var calendarColor: RGBAColor
    var location: String?
    /// The first `notesLimit` bytes only: notes can be huge and the notch needs a hint, not the whole text.
    var notes: String?
    var url: URL?
    var meetingURL: URL?
    var status: Status
    var myParticipation: Participation

    enum Status: Equatable, Sendable {
        case confirmed, tentative, canceled
    }

    /// The current user's answer to the invitation.
    enum Participation: Equatable, Sendable {
        case accepted, declined, tentative, pending, unknown
    }

    static let notesLimit = 2_048
}

nonisolated extension AgendaEvent {
    /// Builds an event from the fields EventKit reports. The id, the notes limit and the link search live here
    /// rather than in the EventKit glue so they can be tested without an event store.
    init(
        calendarItemIdentifier: String,
        title: String?,
        start: Date,
        end: Date,
        isAllDay: Bool,
        calendarID: String,
        calendarTitle: String,
        calendarColor: RGBAColor,
        location: String?,
        notes: String?,
        url: URL?,
        status: Status,
        myParticipation: Participation
    ) {
        self.init(
            id: "\(calendarItemIdentifier)@\(Int(start.timeIntervalSince1970))",
            calendarItemIdentifier: calendarItemIdentifier,
            title: title ?? "",
            start: start,
            end: end,
            isAllDay: isAllDay,
            calendarID: calendarID,
            calendarTitle: calendarTitle,
            calendarColor: calendarColor,
            location: location,
            // Searched whole: an invite's join link often sits below pages of boilerplate.
            notes: notes.map(Self.limitedNotes),
            url: url,
            meetingURL: MeetingLinkDetector.detect(url: url, location: location, notes: notes)?.url,
            status: status,
            myParticipation: myParticipation
        )
    }

    /// Cuts on a character boundary, so a multi-byte character is dropped whole rather than left half there.
    private static func limitedNotes(_ notes: String) -> String {
        guard notes.utf8.count > notesLimit else { return notes }
        var bytes = 0
        var kept = String.UnicodeScalarView()
        for scalar in notes.unicodeScalars {
            bytes += UTF8.width(scalar)
            if bytes > notesLimit { break }
            kept.append(scalar)
        }
        return String(kept)
    }
}
