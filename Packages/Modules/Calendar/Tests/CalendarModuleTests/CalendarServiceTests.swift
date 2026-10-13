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

    @Test func authorizationComesFromTheInjectedStatus() {
        let service = CalendarService(authorizationStatus: { $0 == .calendars ? .granted : .notDetermined })
        #expect(service.authorization(for: .calendars) == .granted)
        #expect(service.authorization(for: .reminders) == .notDetermined)
    }
}
