import Foundation
import Testing
@testable import CalendarModule

/// What EventKit is given for a new event, worked out without EventKit: the end of an all-day event, the zone.
@Suite struct NewEventTimingTests {
    func newEvent(_ start: Date, _ end: Date, allDay: Bool, in zone: TimeZone) -> NewEvent {
        NewEvent(title: "Họp", start: start, end: end, isAllDay: allDay, calendarID: nil, timeZone: zone)
    }

    @Test func aTimedEventKeepsItsTimesAndItsZone() {
        let calendar = fixedCalendar()
        let event = newEvent(calendar.on(15, at: 15), calendar.on(15, at: 16), allDay: false, in: calendar.timeZone)
        let timing = event.eventKitTiming
        #expect(timing.start == calendar.on(15, at: 15))
        #expect(timing.end == calendar.on(15, at: 16))
        #expect(timing.timeZone == calendar.timeZone)
    }

    @Test func anAllDayEventEndsOnTheLastSecondOfItsDayAndHasNoZone() {
        let calendar = fixedCalendar()
        let event = newEvent(calendar.on(14, at: 0), calendar.on(15, at: 0), allDay: true, in: calendar.timeZone)
        let timing = event.eventKitTiming
        #expect(timing.start == calendar.on(14, at: 0))
        #expect(timing.end == calendar.on(14, at: 23, 59, 59))
        #expect(timing.timeZone == nil)
    }

    @Test(arguments: [(3, 8), (11, 1), (6, 15)])
    func anAllDayEventOnAnyDayEndsOnThatDaysLastSecond(_ month: Int, _ day: Int) {
        // 8 March is 23 hours long in New York and 1 November 25 hours long; the last second is still 23:59:59.
        let calendar = fixedCalendar("America/New_York")
        let start = calendar.date(from: DateComponents(year: 2026, month: month, day: day))!
        let next = calendar.date(byAdding: .day, value: 1, to: start)!
        let timing = newEvent(start, next, allDay: true, in: calendar.timeZone).eventKitTiming
        let last = calendar.dateComponents([.month, .day, .hour, .minute, .second], from: timing.end)
        #expect(last.month == month && last.day == day)
        #expect(last.hour == 23 && last.minute == 59 && last.second == 59)
    }
}
