import Foundation
import Testing
@testable import TodoModule

@Suite struct TodoAlarmTests {
    let hanoi = TimeZone(identifier: "Asia/Ho_Chi_Minh")!

    @Test func aTimedReminderAlertsAtItsTime() {
        let fire = TodoAlarm.fireDate(for: due(14, 15, 30), timeZone: hanoi)
        #expect(fire == fixedCalendar().on(14, at: 15, 30))
    }

    @Test func theTimeIsTheOneTypedWhicheverZoneTheMacIsIn() {
        // A floating time means the clock on the wall where the user is, so 15:30 follows the zone the Mac is in.
        let newYork = TimeZone(identifier: "America/New_York")!
        let fire = TodoAlarm.fireDate(for: due(14, 15, 30), timeZone: newYork)
        #expect(fire == fixedCalendar("America/New_York").on(14, at: 15, 30))
    }

    @Test func aDayAloneHasNoAlert() {
        #expect(TodoAlarm.fireDate(for: due(14), timeZone: hanoi) == nil)
    }

    @Test func aTimeInItsOwnZoneKeepsThatZone() {
        var components = due(14, 15, 30)
        components.timeZone = TimeZone(identifier: "America/New_York")
        #expect(TodoAlarm.fireDate(for: components, timeZone: hanoi) == fixedCalendar("America/New_York").on(14, at: 15, 30))
    }

    @Test func nothingReadableMeansNoAlert() {
        #expect(TodoAlarm.fireDate(for: DateComponents(hour: 9), timeZone: hanoi) == nil)
    }
}
