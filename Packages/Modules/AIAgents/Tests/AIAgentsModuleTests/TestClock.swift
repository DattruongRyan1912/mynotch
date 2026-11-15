import Foundation

/// Wall-clock time that a test moves by hand, next to a `ManualScheduler` that moves timer time.
final class TestClock {
    var now: Date

    init(_ now: Date) {
        self.now = now
    }

    func advance(by seconds: TimeInterval) {
        now += seconds
    }
}

/// A calendar in UTC+7 (no daylight saving), so "local midnight" is the same instant on every test machine.
func hoChiMinhCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh")!
    return calendar
}
