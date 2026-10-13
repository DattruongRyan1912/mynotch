import Foundation
import Testing
@testable import CalendarModule

@Suite struct CalendarDataSourceTests {
    let calendar = fixedCalendar()
    /// Wednesday 14 October 2026, 10:30.
    var now: Date { calendar.on(14, at: 10, 30) }

    @Test func eventsFetchedOverTheRangeFeedTheAgenda() async {
        let source = FakeCalendarDataSource(events: [
            event("yesterday", calendar.on(13, at: 9), calendar.on(13, at: 10)),
            event("standup", calendar.on(14, at: 8), calendar.on(14, at: 8, 30)),
            event("workshop", calendar.on(14, at: 10), calendar.on(14, at: 11)),
            event("review", calendar.on(14, at: 14), calendar.on(14, at: 15)),
            event("tomorrow", calendar.on(15, at: 9), calendar.on(15, at: 10)),
            event("next week", calendar.on(20, at: 9), calendar.on(20, at: 10)),
            event("too far", calendar.on(25, at: 9), calendar.on(25, at: 10)),
        ])
        let range = AgendaBuilder.fetchRange(now: now, calendar: calendar)

        let fetched = await source.events(from: range.start, to: range.end)
        let agenda = AgendaBuilder.build(events: fetched, now: now, calendar: calendar)

        #expect(fetched.map(\.id) == ["standup", "workshop", "review", "tomorrow", "next week"])
        #expect(agenda.today.map(\.id) == ["standup", "workshop", "review"])
        #expect(agenda.next?.id == "workshop")
        #expect(agenda.upcomingToday.map(\.id) == ["workshop", "review"])
    }

    @Test func aWeekWithoutEventsGivesAnEmptyAgenda() async {
        let source = FakeCalendarDataSource()
        let range = AgendaBuilder.fetchRange(now: now, calendar: calendar)
        let agenda = AgendaBuilder.build(events: await source.events(from: range.start, to: range.end), now: now, calendar: calendar)
        #expect(agenda == Agenda())
    }

    @Test func theCalendarListComesFromTheSource() async {
        let source = FakeCalendarDataSource()
        #expect(await source.calendars().isEmpty)
        source.calendars = [CalendarInfo(id: "work", title: "Work", color: .gray)]
        #expect(await source.calendars().map(\.title) == ["Work"])
    }
}
