import Foundation
import Testing
@testable import CalendarModule

@Suite struct AgendaFormatTests {
    let calendar = fixedCalendar()
    /// Wednesday 14 October 2026, 10:30.
    var now: Date { calendar.on(14, at: 10, 30) }

    @Test func theHeaderIsTheVietnameseWeekdayDayAndMonth() {
        #expect(AgendaFormat.dayHeader(calendar.on(14, at: 10), calendar: calendar) == "Thứ Tư, 14 tháng 10")
        #expect(AgendaFormat.dayHeader(calendar.on(15, at: 0), calendar: calendar) == "Thứ Năm, 15 tháng 10")
        #expect(AgendaFormat.dayHeader(calendar.on(18, at: 23, 59), calendar: calendar) == "Chủ Nhật, 18 tháng 10")
    }

    @Test func theHeaderDoesNotFollowTheMachineLocale() {
        // Every string in the notch is Vietnamese, so the header is too, whatever language the Mac is set to.
        #expect(AgendaFormat.locale.identifier == "vi_VN")
        let english = AgendaFormat.dayHeader(calendar.on(14, at: 10), calendar: calendar, locale: Locale(identifier: "en_US"))
        #expect(english == "Wednesday, October 14")
    }

    @Test func theHeaderFollowsTheCalendarTimeZone() {
        // 17:30 UTC on the 14th is already the 15th in Ho Chi Minh City.
        let instant = fixedCalendar("UTC").on(14, at: 17, 30)
        #expect(AgendaFormat.dayHeader(instant, calendar: calendar) == "Thứ Năm, 15 tháng 10")
        #expect(AgendaFormat.dayHeader(instant, calendar: fixedCalendar("UTC")) == "Thứ Tư, 14 tháng 10")
    }

    @Test func aTimeIsTwentyFourHourAndFollowsTheTimeZone() {
        #expect(AgendaFormat.time(calendar.on(14, at: 9, 5), calendar: calendar) == "09:05")
        #expect(AgendaFormat.time(calendar.on(14, at: 17, 45), calendar: calendar) == "17:45")
        #expect(AgendaFormat.time(fixedCalendar("UTC").on(14, at: 3), calendar: calendar) == "10:00")
    }

    @Test func aTimedEventShowsItsTimeRange() {
        let standup = event("standup", calendar.on(14, at: 10), calendar.on(14, at: 10, 45))
        #expect(AgendaFormat.timeRange(of: standup, calendar: calendar) == "10:00 – 10:45")
        let overnight = event("overnight", calendar.on(14, at: 23), calendar.on(15, at: 1))
        #expect(AgendaFormat.timeRange(of: overnight, calendar: calendar) == "23:00 – 01:00")
    }

    @Test func anAllDayEventShowsAllDay() {
        #expect(AgendaFormat.timeRange(of: allDayEvent("holiday", on: 14, in: calendar), calendar: calendar) == "Cả ngày")
    }

    @Test func aDayLabelIsOnlyGivenForOtherDays() {
        #expect(AgendaFormat.dayLabel(for: calendar.on(14, at: 23, 59), now: now, calendar: calendar) == nil)
        #expect(AgendaFormat.dayLabel(for: calendar.on(15, at: 0), now: now, calendar: calendar) == "Ngày mai")
        #expect(AgendaFormat.dayLabel(for: calendar.on(16, at: 9), now: now, calendar: calendar) == "Thứ Sáu, 16/10")
        #expect(AgendaFormat.dayLabel(for: calendar.on(20, at: 9), now: now, calendar: calendar) == "Thứ Ba, 20/10")
    }

    @Test func theCountdownIsMinutesOrInProgress() {
        #expect(AgendaFormat.countdown(.upcoming(minutesLeft: 5)) == "5 phút")
        #expect(AgendaFormat.countdown(.upcoming(minutesLeft: 1)) == "1 phút")
        #expect(AgendaFormat.countdown(.inProgress) == "Đang diễn ra")
        #expect(AgendaFormat.countdown(.hidden) == nil)
    }

    @Test func aReminderShowsItsTimeTodayAndOverdueAfterItsDay() {
        func label(_ due: DateComponents?, overdue: Bool) -> String? {
            AgendaFormat.dueLabel(of: reminder("r", due: due, overdue: overdue), calendar: calendar, now: now)
        }
        #expect(label(DateComponents(year: 2026, month: 10, day: 14, hour: 17, minute: 0), overdue: false) == "17:00")
        #expect(label(DateComponents(year: 2026, month: 10, day: 14, hour: 9, minute: 15), overdue: true) == "09:15")
        #expect(label(DateComponents(year: 2026, month: 10, day: 14), overdue: false) == nil)
        #expect(label(DateComponents(year: 2026, month: 10, day: 13), overdue: true) == "Quá hạn")
        #expect(label(DateComponents(year: 2026, month: 10, day: 13, hour: 18, minute: 0), overdue: true) == "Quá hạn")
        #expect(label(nil, overdue: false) == nil)
    }
}
