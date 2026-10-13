import EventKit
import Foundation
import Testing
@testable import CalendarModule

@Suite struct AgendaEventMappingTests {
    let calendar = fixedCalendar()

    func mapped(
        identifier: String = "ABC-123",
        title: String? = "Standup",
        start: Date? = nil,
        location: String? = nil,
        notes: String? = nil,
        url: URL? = nil
    ) -> AgendaEvent {
        AgendaEvent(
            calendarItemIdentifier: identifier, title: title, start: start ?? calendar.on(14, at: 10), end: calendar.on(14, at: 11),
            isAllDay: false, calendarID: "cal-1", calendarTitle: "Work", calendarColor: .gray,
            location: location, notes: notes, url: url, status: .confirmed, myParticipation: .accepted
        )
    }

    @Test func copiesTheFieldsOver() {
        let event = mapped(location: "Room 4", notes: "Bring slides", url: URL(string: "https://example.com/agenda"))
        #expect(event.calendarItemIdentifier == "ABC-123")
        #expect(event.title == "Standup")
        #expect(event.start == calendar.on(14, at: 10))
        #expect(event.end == calendar.on(14, at: 11))
        #expect(!event.isAllDay)
        #expect(event.calendarID == "cal-1")
        #expect(event.calendarTitle == "Work")
        #expect(event.location == "Room 4")
        #expect(event.notes == "Bring slides")
        #expect(event.url == URL(string: "https://example.com/agenda"))
        #expect(event.meetingURL == nil)
        #expect(event.status == .confirmed)
        #expect(event.myParticipation == .accepted)
    }

    @Test func aMissingTitleBecomesEmpty() {
        #expect(mapped(title: nil).title == "")
    }

    @Test func idCombinesTheItemIdentifierWithTheOccurrenceStart() {
        let monday = mapped(start: calendar.on(12, at: 10))
        let wednesday = mapped(start: calendar.on(14, at: 10))
        #expect(monday.id != wednesday.id)
        #expect(wednesday.id == mapped(start: calendar.on(14, at: 10)).id)
        #expect(wednesday.id.hasPrefix("ABC-123"))
        #expect(wednesday.id != mapped(identifier: "XYZ-789", start: calendar.on(14, at: 10)).id)
        #expect(wednesday.calendarItemIdentifier == monday.calendarItemIdentifier)
    }

    @Test func movingTheEventChangesItsID() {
        #expect(mapped(start: calendar.on(14, at: 10)).id != mapped(start: calendar.on(14, at: 10, 30)).id)
    }

    @Test func meetingURLComesFromTheURLThenLocationThenNotes() {
        let zoom = "https://zoom.us/j/111"
        let meet = "https://meet.google.com/abc-defg-hij"
        let teams = "https://teams.live.com/meet/222"
        #expect(mapped(location: meet, notes: teams, url: URL(string: zoom)).meetingURL == URL(string: zoom))
        #expect(mapped(location: "Room 4, \(meet)", notes: teams).meetingURL == URL(string: meet))
        #expect(mapped(location: "Room 4", notes: "Join \(teams).").meetingURL == URL(string: teams))
        #expect(mapped(location: "Room 4", notes: "Bring slides").meetingURL == nil)
    }

    @Test func notesKeepOnlyTheirFirst2KB() {
        let long = String(repeating: "a", count: 5_000)
        #expect(mapped(notes: long).notes == String(repeating: "a", count: 2_048))
        #expect(mapped(notes: "short").notes == "short")
        #expect(mapped(notes: String(repeating: "a", count: 2_048)).notes?.utf8.count == 2_048)
        #expect(mapped(notes: nil).notes == nil)
    }

    @Test func notesAreCutOnACharacterBoundary() {
        // 3 bytes each: 682 of them fit in 2,048 bytes, a 683rd would not.
        let euros = mapped(notes: String(repeating: "€", count: 1_000)).notes
        #expect(euros == String(repeating: "€", count: 682))
        #expect(euros?.contains("\u{FFFD}") == false)
    }

    @Test func aMeetingLinkPastTheNotesLimitIsStillFound() {
        let link = "https://meet.google.com/abc-defg-hij"
        let notes = String(repeating: "x", count: 3_000) + " " + link
        let event = mapped(notes: notes)
        #expect(event.meetingURL == URL(string: link))
        #expect(event.notes?.utf8.count == 2_048)
    }

    @Test func eventKitStatusesMapToOurs() {
        #expect(AgendaEvent.Status(EKEventStatus.none) == .confirmed)
        #expect(AgendaEvent.Status(EKEventStatus.confirmed) == .confirmed)
        #expect(AgendaEvent.Status(EKEventStatus.tentative) == .tentative)
        #expect(AgendaEvent.Status(EKEventStatus.canceled) == .canceled)
    }

    @Test func eventKitParticipantStatusesMapToOurs() {
        #expect(AgendaEvent.Participation(EKParticipantStatus.accepted) == .accepted)
        #expect(AgendaEvent.Participation(EKParticipantStatus.declined) == .declined)
        #expect(AgendaEvent.Participation(EKParticipantStatus.tentative) == .tentative)
        #expect(AgendaEvent.Participation(EKParticipantStatus.pending) == .pending)
        #expect(AgendaEvent.Participation(EKParticipantStatus.unknown) == .unknown)
        #expect(AgendaEvent.Participation(EKParticipantStatus.delegated) == .unknown)
        #expect(AgendaEvent.Participation(EKParticipantStatus.completed) == .unknown)
        #expect(AgendaEvent.Participation(EKParticipantStatus.inProcess) == .unknown)
        // An event with no attendee list is one the user made, with no answer to give.
        #expect(AgendaEvent.Participation(nil) == .unknown)
    }
}
