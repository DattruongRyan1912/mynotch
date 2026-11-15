import Foundation
import Testing
@testable import CalendarModule

@Suite struct CalendarLinksTests {
    @Test func anEventOpensThroughTheIcalScheme() {
        #expect(CalendarLinks.eventURL(calendarItemIdentifier: "A1B2-C3D4")?.absoluteString == "ical://ekevent/A1B2-C3D4")
    }

    @Test func identifiersWithSpecialCharactersAreEscaped() {
        let url = CalendarLinks.eventURL(calendarItemIdentifier: "AB:12/x y?z#1")
        #expect(url?.scheme == "ical")
        #expect(url?.host() == "ekevent")
        #expect(url?.absoluteString == "ical://ekevent/AB:12%2Fx%20y%3Fz%231")
    }

    @Test func calendarAppIsTheSystemOne() {
        #expect(CalendarLinks.calendarApp.path == "/System/Applications/Calendar.app")
        #expect(CalendarLinks.calendarApp.isFileURL)
    }
}
