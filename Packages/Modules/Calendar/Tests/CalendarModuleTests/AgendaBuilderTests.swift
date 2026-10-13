import Foundation
import Testing
@testable import CalendarModule

@Suite struct AgendaBuilderTests {
    let calendar = fixedCalendar()
    /// Wednesday 14 October 2026, 10:30.
    var now: Date { calendar.on(14, at: 10, 30) }

    func build(_ events: [AgendaEvent], now: Date? = nil, in calendar: Calendar? = nil) -> Agenda {
        AgendaBuilder.build(events: events, now: now ?? self.now, calendar: calendar ?? self.calendar)
    }

    @Test func noEventsGivesAnEmptyAgenda() {
        #expect(build([]) == Agenda(today: [], next: nil, upcomingToday: []))
    }

    @Test func canceledAndDeclinedEventsAreDropped() {
        let canceled = event("canceled", calendar.on(14, at: 11), calendar.on(14, at: 12), status: .canceled)
        let declined = event("declined", calendar.on(14, at: 11, 30), calendar.on(14, at: 12), participation: .declined)
        let declinedAllDay = event("declined all-day", calendar.on(14, at: 0), calendar.on(15, at: 0), allDay: true, participation: .declined)
        let tentative = event("tentative", calendar.on(14, at: 13), calendar.on(14, at: 14), status: .tentative)
        let pending = event("pending", calendar.on(14, at: 15), calendar.on(14, at: 16), participation: .pending)
        let unknown = event("unknown", calendar.on(14, at: 16), calendar.on(14, at: 17), participation: .unknown)

        let agenda = build([canceled, declined, declinedAllDay, tentative, pending, unknown])

        #expect(agenda.today.map(\.id) == ["tentative", "pending", "unknown"])
        #expect(agenda.next?.id == "tentative")
        #expect(agenda.upcomingToday.map(\.id) == ["tentative", "pending", "unknown"])
    }

    @Test func allDayEventsComeFirstThenTimedEventsByStart() {
        let holiday = allDayEvent("Holiday", on: 14, in: calendar)
        let birthday = allDayEvent("Birthday", on: 14, in: calendar)
        let lunch = event("lunch", calendar.on(14, at: 12), calendar.on(14, at: 13))
        let standup = event("standup", calendar.on(14, at: 9), calendar.on(14, at: 9, 15))
        let sync = event("sync", calendar.on(14, at: 9), calendar.on(14, at: 10))

        let agenda = build([lunch, holiday, sync, standup, birthday])

        #expect(agenda.today.map(\.id) == ["Birthday", "Holiday", "standup", "sync", "lunch"])
    }

    @Test func theOrderOfTheInputDoesNotMatter() {
        let events = [
            event("b", calendar.on(14, at: 12), calendar.on(14, at: 13)),
            event("a", calendar.on(14, at: 12), calendar.on(14, at: 13)),
            event("c", calendar.on(14, at: 11), calendar.on(14, at: 14)),
            allDayEvent("d", on: 14, in: calendar),
        ]
        #expect(build(events) == build(events.reversed()))
        #expect(build(events).today.map(\.id) == ["d", "c", "a", "b"])
    }

    @Test func todayHoldsOnlyEventsOverlappingToday() {
        let yesterday = event("yesterday", calendar.on(13, at: 21), calendar.on(13, at: 23))
        let endedAtMidnight = event("ended at midnight", calendar.on(13, at: 22), calendar.on(14, at: 0))
        let tomorrow = event("tomorrow", calendar.on(15, at: 9), calendar.on(15, at: 10))
        let startsAtMidnight = event("starts at midnight", calendar.on(15, at: 0), calendar.on(15, at: 1))
        let yesterdayAllDay = allDayEvent("yesterday all-day", on: 13, in: calendar)
        let todayAllDay = allDayEvent("today all-day", on: 14, in: calendar)
        let tomorrowAllDay = allDayEvent("tomorrow all-day", on: 15, in: calendar)
        let lunch = event("lunch", calendar.on(14, at: 12), calendar.on(14, at: 13))

        let agenda = build([yesterday, endedAtMidnight, tomorrow, startsAtMidnight, yesterdayAllDay, todayAllDay, tomorrowAllDay, lunch])

        #expect(agenda.today.map(\.id) == ["today all-day", "lunch"])
    }

    @Test func anAllDayEventThatEndsOneSecondBeforeMidnightStillBelongsToThatDay() {
        let lastSecond = calendar.on(15, at: 0).addingTimeInterval(-1)
        let today = event("today", calendar.on(14, at: 0), lastSecond, allDay: true)
        let yesterday = event("yesterday", calendar.on(13, at: 0), calendar.on(14, at: 0).addingTimeInterval(-1), allDay: true)
        #expect(build([today, yesterday]).today.map(\.id) == ["today"])
    }

    @Test func aZeroLengthEventAtMidnightBelongsToThatDay() {
        let reminderLike = event("zero", calendar.on(14, at: 0), calendar.on(14, at: 0))
        #expect(build([reminderLike]).today.map(\.id) == ["zero"])
    }

    @Test func eventsCrossingMidnightShowOnBothDays() {
        let late = event("late", calendar.on(14, at: 23), calendar.on(15, at: 1))
        let early = event("early", calendar.on(13, at: 23), calendar.on(14, at: 1))

        #expect(build([late, early]).today.map(\.id) == ["early", "late"])
        #expect(build([late, early], now: calendar.on(15, at: 0, 30)).today.map(\.id) == ["late"])
    }

    @Test func anEventRunningPastMidnightIsNextUntilItEnds() {
        let overnight = event("overnight", calendar.on(14, at: 23), calendar.on(15, at: 1))
        let morning = event("morning", calendar.on(15, at: 9), calendar.on(15, at: 10))

        #expect(build([overnight, morning], now: calendar.on(15, at: 0, 30)).next?.id == "overnight")
        #expect(build([overnight, morning], now: calendar.on(15, at: 1)).next?.id == "morning")
    }

    @Test func nextIsTheFirstTimedEventThatHasNotEnded() {
        let over = event("over", calendar.on(14, at: 9), calendar.on(14, at: 10))
        let running = event("running", calendar.on(14, at: 10), calendar.on(14, at: 11))
        let later = event("later", calendar.on(14, at: 12), calendar.on(14, at: 13))
        let allDay = allDayEvent("all-day", on: 14, in: calendar)

        #expect(build([later, allDay, over, running]).next?.id == "running")
        #expect(build([later, allDay, over, running], now: calendar.on(14, at: 11, 30)).next?.id == "later")
        #expect(build([later, allDay, over, running], now: calendar.on(14, at: 11)).next?.id == "later")
    }

    @Test func nextLooksAcrossDaysButNotPastAWeek() {
        let tomorrow = event("tomorrow", calendar.on(15, at: 9), calendar.on(15, at: 10))
        let sixDays = event("six days", calendar.on(20, at: 9), calendar.on(20, at: 10))
        let tenDays = event("ten days", calendar.on(24, at: 9), calendar.on(24, at: 10))

        #expect(build([tenDays, sixDays, tomorrow]).next?.id == "tomorrow")
        #expect(build([tenDays, sixDays]).next?.id == "six days")
        #expect(build([tenDays]).next == nil)
        #expect(build([tenDays]).today.isEmpty)
    }

    @Test func nextIgnoresAllDayCanceledAndDeclinedEventsOnLaterDays() {
        let allDay = allDayEvent("all-day", on: 15, in: calendar)
        let canceled = event("canceled", calendar.on(15, at: 8), calendar.on(15, at: 9), status: .canceled)
        let declined = event("declined", calendar.on(15, at: 8, 30), calendar.on(15, at: 9), participation: .declined)
        let kept = event("kept", calendar.on(16, at: 8), calendar.on(16, at: 9))

        #expect(build([allDay, canceled, declined, kept]).next?.id == "kept")
    }

    @Test func upcomingTodayIsTheTimedEventsOfTodayThatHaveNotEnded() {
        let over = event("over", calendar.on(14, at: 8), calendar.on(14, at: 9))
        let running = event("running", calendar.on(14, at: 10), calendar.on(14, at: 11))
        let later = event("later", calendar.on(14, at: 14), calendar.on(14, at: 15))
        let allDay = allDayEvent("all-day", on: 14, in: calendar)
        let tomorrow = event("tomorrow", calendar.on(15, at: 9), calendar.on(15, at: 10))

        let agenda = build([over, running, later, allDay, tomorrow])

        #expect(agenda.upcomingToday.map(\.id) == ["running", "later"])
        #expect(agenda.today.map(\.id) == ["all-day", "over", "running", "later"])
    }

    @Test func dayBoundariesFollowTheCalendarTimeZone() {
        // 18:00 UTC on the 14th is 01:00 on the 15th in Ho Chi Minh City.
        let utc = fixedCalendar("UTC")
        let lateEvening = event("late evening", utc.on(14, at: 18), utc.on(14, at: 19))
        let now = utc.on(14, at: 3)   // 10:00 in Ho Chi Minh City

        #expect(build([lateEvening], now: now, in: utc).today.map(\.id) == ["late evening"])
        #expect(build([lateEvening], now: now, in: calendar).today.isEmpty)
    }

    @Test func theFetchRangeStartsAtTodayAndEndsAWeekFromNow() {
        let range = AgendaBuilder.fetchRange(now: now, calendar: calendar)
        #expect(range.start == calendar.on(14, at: 0))
        #expect(range.end == calendar.on(21, at: 10, 30))
    }

    @Test func theFetchRangeFollowsTheCalendarTimeZone() {
        let utc = fixedCalendar("UTC")
        let range = AgendaBuilder.fetchRange(now: utc.on(14, at: 3), calendar: utc)
        #expect(range.start == utc.on(14, at: 0))
        #expect(range.end == utc.on(21, at: 3))
    }
}
