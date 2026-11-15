import Foundation
import Testing
@testable import AIAgentsModule

@Suite struct AgentFormatTests {
    @Test(arguments: [
        (0, "0"), (7, "7"), (999, "999"), (1_000, "1K"), (1_234, "1.2K"), (12_345, "12.3K"), (99_950, "100K"),
        (123_456, "123K"), (999_400, "999K"), (999_500, "1M"), (1_234_567, "1.2M"), (12_000_000, "12M"), (123_400_000, "123M"),
    ])
    func tokensAreShortened(count: Int, text: String) {
        #expect(AgentFormat.tokens(count) == text)
    }

    @Test func costsShowCents() {
        #expect(AgentFormat.cost(0) == "$0.00")
        #expect(AgentFormat.cost(0.5) == "$0.50")
        #expect(AgentFormat.cost(3.456) == "$3.46")
        #expect(AgentFormat.cost(1234.5) == "$1234.50")
    }

    @Test func aTinyCostIsNotShownAsZero() {
        #expect(AgentFormat.cost(0.004) == "<$0.01")
    }

    @Test func anUnknownCostIsADash() {
        #expect(AgentFormat.cost(nil) == "—")
    }

    @Test(arguments: [(-5.0, "0:00"), (0, "0:00"), (45, "0:45"), (59.9, "0:59"), (125, "2:05"), (3_599, "59:59"), (3_723, "1:02:03")])
    func durationsLookLikeTheTimer(seconds: Double, text: String) {
        #expect(AgentFormat.duration(seconds) == text)
    }

    @Test func rateLimitWindowsAreNamedByLength() {
        #expect(AgentFormat.windowName(minutes: 300) == "5 giờ")
        #expect(AgentFormat.windowName(minutes: 10_080) == "Tuần")
        #expect(AgentFormat.windowName(minutes: 1_440) == "1 ngày")
        #expect(AgentFormat.windowName(minutes: 2_880) == "2 ngày")
        #expect(AgentFormat.windowName(minutes: 90) == "90 phút")
        #expect(AgentFormat.windowName(minutes: 120) == "2 giờ")
        #expect(AgentFormat.windowName(minutes: nil) == nil)
        #expect(AgentFormat.windowName(minutes: 0) == nil)
    }

    @Test func aResetLaterTodayShowsTheClockTime() {
        // 12:00 local; the reset is at 15:30 the same day.
        #expect(AgentFormat.reset(utc("2026-10-14T08:30:00Z"), now: utc("2026-10-14T05:00:00Z"), calendar: hoChiMinhCalendar()) == "15:30")
    }

    @Test func aResetOnAnotherDayAddsTheWeekday() {
        let now = utc("2026-10-14T05:00:00Z")
        let calendar = hoChiMinhCalendar()
        // Friday 09:05 and Sunday 00:00 local, in Vietnamese weekday names.
        #expect(AgentFormat.reset(utc("2026-10-16T02:05:00Z"), now: now, calendar: calendar) == "T6 09:05")
        #expect(AgentFormat.reset(utc("2026-10-17T17:00:00Z"), now: now, calendar: calendar) == "CN 00:00")
        // Local midnight has passed by 11 minutes, so this is already tomorrow (Thursday).
        #expect(AgentFormat.reset(utc("2026-10-14T17:11:00Z"), now: now, calendar: calendar) == "T5 00:11")
    }
}
