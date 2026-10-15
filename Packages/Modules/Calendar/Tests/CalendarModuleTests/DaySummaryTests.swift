import Foundation
import Testing
@testable import CalendarModule

/// The day at a glance, worked out from the agenda: how many events, the first free slot of 30 minutes or more inside
/// working hours, and when the last event ends.
@Suite struct DaySummaryTests {
    let calendar = fixedCalendar()

    /// Wednesday 14 October 2026.
    func at(_ hour: Int, _ minute: Int = 0, day: Int = 14) -> Date { calendar.on(day, at: hour, minute) }

    func meeting(_ id: String, _ from: (Int, Int), _ to: (Int, Int), day: Int = 14) -> AgendaEvent {
        event(id, at(from.0, from.1, day: day), at(to.0, to.1, day: day))
    }

    func summary(
        _ events: [AgendaEvent], now: Date? = nil, hours: WorkingHours = .standard
    ) -> String {
        let now = now ?? at(8)
        let agenda = AgendaBuilder.build(events: events, now: now, calendar: calendar)
        return DaySummary.text(for: agenda, now: now, workingHours: hours, calendar: calendar)
    }

    // MARK: The line of the brief

    @Test func countsFreeSlotAndEnd() {
        let events = [
            meeting("a", (9, 0), (10, 0)), meeting("b", (10, 0), (12, 0)),
            meeting("c", (12, 0), (14, 0)), meeting("d", (16, 0), (18, 30)),
        ]
        #expect(summary(events) == "Hôm nay: 4 sự kiện, rảnh 14:00–16:00, kết thúc lúc 18:30")
    }

    @Test func oneEventIsCountedAsOne() {
        #expect(summary([meeting("a", (9, 0), (10, 0))]) == "Hôm nay: 1 sự kiện, rảnh 10:00–18:00, kết thúc lúc 10:00")
    }

    // MARK: The free slot

    @Test func theFirstSlotIsThirtyMinutesOrMore() {
        let events = [
            meeting("a", (9, 0), (10, 0)), meeting("b", (10, 20), (11, 0)), meeting("c", (11, 30), (18, 0)),
        ]
        // 10:00 to 10:20 is 20 minutes; 11:00 to 11:30 is exactly 30.
        #expect(summary(events) == "Hôm nay: 3 sự kiện, rảnh 11:00–11:30, kết thúc lúc 18:00")
        let tighter = [meeting("a", (9, 0), (10, 0)), meeting("b", (10, 29), (18, 0))]
        #expect(summary(tighter) == "Hôm nay: 2 sự kiện, kết thúc lúc 18:00")
    }

    @Test func aDayFullFromStartToEndHasNoSlot() {
        #expect(summary([meeting("a", (9, 0), (18, 0))]) == "Hôm nay: 1 sự kiện, kết thúc lúc 18:00")
    }

    @Test func theSlotStaysInsideWorkingHours() {
        // Free before 9:00 and after 18:00 does not count.
        #expect(summary([meeting("a", (9, 0), (17, 45))]) == "Hôm nay: 1 sự kiện, kết thúc lúc 17:45")
        #expect(summary([meeting("a", (7, 0), (8, 30))]) == "Hôm nay: 1 sự kiện, rảnh 09:00–18:00, kết thúc lúc 08:30")
    }

    @Test func workingHoursComeFromTheSetting() {
        let events = [meeting("a", (8, 0), (10, 0))]
        #expect(summary(events, hours: WorkingHours(start: 8, end: 12)) == "Hôm nay: 1 sự kiện, rảnh 10:00–12:00, kết thúc lúc 10:00")
        #expect(summary(events, hours: WorkingHours(start: 6, end: 8)) == "Hôm nay: 1 sự kiện, kết thúc lúc 10:00")
    }

    @Test func workingHoursThatMakeNoSenseFallBackToTheStandardOnes() {
        #expect(WorkingHours(start: 18, end: 9) == .standard)
        #expect(WorkingHours(start: 9, end: 9) == .standard)
        #expect(WorkingHours(start: -3, end: 40) == WorkingHours(start: 0, end: 24))
        #expect(WorkingHours.standard == WorkingHours(start: 9, end: 18))
    }

    @Test func overlappingEventsBlockOnce() {
        let events = [meeting("a", (9, 0), (12, 0)), meeting("b", (10, 0), (11, 0)), meeting("c", (13, 0), (14, 0))]
        #expect(summary(events) == "Hôm nay: 3 sự kiện, rảnh 12:00–13:00, kết thúc lúc 14:00")
    }

    @Test func theSlotStartsNowWhenTheDayIsUnderWay() {
        // Running now (09:00–11:00), next at 13:00: the gap starts when the running one ends.
        let events = [meeting("a", (9, 0), (11, 0)), meeting("b", (13, 0), (14, 0))]
        #expect(summary(events, now: at(10, 7)) == "Hôm nay: 2 sự kiện, rảnh 11:00–13:00, kết thúc lúc 14:00")
        // Nothing on: from the next quarter of an hour.
        #expect(summary([], now: at(10, 7)) == "Hôm nay: không có sự kiện, rảnh 10:15–18:00")
        #expect(summary([], now: at(10, 15)) == "Hôm nay: không có sự kiện, rảnh 10:15–18:00")
        #expect(summary([], now: at(10, 16)) == "Hôm nay: không có sự kiện, rảnh 10:30–18:00")
    }

    @Test func afterWorkingHoursThereIsNoSlot() {
        #expect(summary([], now: at(17, 50)) == "Hôm nay: không có sự kiện")
        #expect(summary([], now: at(20)) == "Hôm nay: không có sự kiện")
        #expect(summary([], now: at(7)) == "Hôm nay: không có sự kiện, rảnh 09:00–18:00")
    }

    // MARK: Count

    @Test func allDayEventsCountButNeitherBlockNorEnd() {
        let holiday = allDayEvent("holiday", on: 14, in: calendar)
        #expect(summary([holiday]) == "Hôm nay: 1 sự kiện, rảnh 09:00–18:00")
        #expect(summary([holiday, meeting("a", (11, 0), (12, 0))]) == "Hôm nay: 2 sự kiện, rảnh 09:00–11:00, kết thúc lúc 12:00")
    }

    @Test func declinedAndCanceledEventsAreNotCounted() {
        let events = [
            meeting("kept", (9, 0), (10, 0)),
            event("declined", at(11), at(12), participation: .declined),
            event("canceled", at(13), at(14), status: .canceled),
        ]
        #expect(summary(events) == "Hôm nay: 1 sự kiện, rảnh 10:00–18:00, kết thúc lúc 10:00")
    }

    @Test func eventsOfOtherDaysAreNotToday() {
        let events = [meeting("yesterday", (9, 0), (10, 0), day: 13), meeting("tomorrow", (9, 0), (10, 0), day: 15)]
        #expect(summary(events) == "Hôm nay: không có sự kiện, rảnh 09:00–18:00")
    }

    @Test func anEventFromYesterdayThatEndsThisMorningCounts() {
        let overnight = event("night", at(22, 0, day: 13), at(8, 0))
        #expect(summary([overnight], now: at(7, 30)) == "Hôm nay: 1 sự kiện, rảnh 09:00–18:00, kết thúc lúc 08:00")
    }

    @Test func anEventPastMidnightSaysSo() {
        let late = event("late", at(20), at(1, 0, day: 15))
        #expect(summary([late]) == "Hôm nay: 1 sự kiện, rảnh 09:00–18:00, kết thúc sau nửa đêm")
    }

    // MARK: Once the day is done

    @Test func whenTheLastEventHasEndedItLooksAtTomorrow() {
        let events = [
            meeting("a", (9, 0), (10, 0)), meeting("b", (16, 0), (18, 30)),
            meeting("t2", (14, 0), (15, 0), day: 15), meeting("t1", (9, 30), (10, 0), day: 15),
        ]
        #expect(summary(events, now: at(19)) == "Hôm nay: 2 sự kiện, đã kết thúc lúc 18:30, mai bắt đầu lúc 09:30")
    }

    @Test func tomorrowIsLeftOutWhenItHasNothingTimed() {
        let events = [meeting("a", (9, 0), (10, 0)), allDayEvent("holiday", on: 15, in: calendar)]
        #expect(summary(events, now: at(12)) == "Hôm nay: 1 sự kiện, đã kết thúc lúc 10:00")
    }

    @Test func theDayIsDoneOnlyWhenEveryEventHasEnded() {
        let events = [meeting("a", (9, 0), (10, 0)), meeting("b", (16, 0), (17, 0)), meeting("t", (9, 30), (10, 0), day: 15)]
        #expect(summary(events, now: at(12)) == "Hôm nay: 2 sự kiện, rảnh 12:00–16:00, kết thúc lúc 17:00")
        #expect(summary(events, now: at(17)) == "Hôm nay: 2 sự kiện, đã kết thúc lúc 17:00, mai bắt đầu lúc 09:30")
    }

    @Test func aDayWithNothingOnDoesNotLookAtTomorrow() {
        let events = [meeting("t", (9, 30), (10, 0), day: 15)]
        #expect(summary(events, now: at(19)) == "Hôm nay: không có sự kiện")
    }
}
