import MyNotchCore
import Testing
@testable import CalendarModule

/// The real service with its authorization faked: without access it must answer before touching EventKit, so these
/// run without a prompt, a permission or an event store.
@Suite struct CalendarServiceTests {
    let denied = CalendarService(authorizationStatus: { _ in .denied })

    @Test func withoutAccessThereAreNoEventsReminderOrCalendars() async {
        #expect(await denied.events(from: .now, to: .now.addingTimeInterval(3_600)).isEmpty)
        #expect(await denied.reminders(dueBy: .now).isEmpty)
        #expect(await denied.calendars().isEmpty)
    }

    @Test func completingWithoutAccessSaysAccessWasDenied() async {
        await #expect(throws: CalendarServiceError.accessDenied) {
            try await denied.complete(reminderID: "r1")
        }
    }

    @Test func savingWithoutAccessSaysAccessWasDeniedBeforeTouchingEventKit() async {
        let event = NewEvent(title: "Họp", start: .now, end: .now.addingTimeInterval(3_600), isAllDay: false, calendarID: nil, timeZone: .current)
        await #expect(throws: CalendarServiceError.accessDenied) {
            try await denied.createEvent(event)
        }
        // Write-only access cannot read events, so it counts as denied here too.
        let notAsked = CalendarService(authorizationStatus: { _ in .notDetermined })
        await #expect(throws: CalendarServiceError.accessDenied) {
            try await notAsked.createEvent(event)
        }
    }

    @Test func authorizationComesFromTheInjectedStatus() {
        let service = CalendarService(authorizationStatus: { $0 == .calendars ? .granted : .notDetermined })
        #expect(service.authorization(for: .calendars) == .granted)
        #expect(service.authorization(for: .reminders) == .notDetermined)
    }
}
