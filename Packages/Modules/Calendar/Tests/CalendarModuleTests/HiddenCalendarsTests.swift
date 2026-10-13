import Testing
@testable import CalendarModule

@Suite struct HiddenCalendarsTests {
    func info(_ id: String, _ title: String) -> CalendarInfo {
        CalendarInfo(id: id, title: title, color: .gray)
    }

    @Test func aCalendarIsVisibleUnlessListed() {
        #expect(HiddenCalendars.isVisible("work", hidden: []))
        #expect(HiddenCalendars.isVisible("work", hidden: ["home"]))
        #expect(!HiddenCalendars.isVisible("work", hidden: ["home", "work"]))
    }

    @Test func hidingAddsOnceAndShowingRemoves() {
        #expect(HiddenCalendars.setting("work", visible: false, in: []) == ["work"])
        #expect(HiddenCalendars.setting("work", visible: false, in: ["work"]) == ["work"])
        #expect(HiddenCalendars.setting("home", visible: false, in: ["work"]) == ["work", "home"])
        #expect(HiddenCalendars.setting("work", visible: true, in: ["home", "work"]) == ["home"])
        #expect(HiddenCalendars.setting("work", visible: true, in: []) == [])
    }

    @Test func calendarsAreListedByTitleThenID() {
        let calendars = [info("3", "Work"), info("1", "Birthdays"), info("2", "Work"), info("4", "Home")]
        #expect(HiddenCalendars.sorted(calendars).map(\.id) == ["1", "4", "2", "3"])
    }

    @Test func titlesSortTheWayPeopleReadThem() {
        let calendars = [info("1", "Calendar 10"), info("2", "calendar 2"), info("3", "Ăn uống"), info("4", "An")]
        #expect(HiddenCalendars.sorted(calendars).map(\.id) == ["4", "3", "2", "1"])
    }
}
