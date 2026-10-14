import Foundation
import MyNotchCore
import Testing
@testable import CalendarModule

@Suite struct MeetingActivityContentTests {
    let calendar = fixedCalendar()
    let policy = UpcomingMeetingPolicy(leadMinutes: 5)
    var standup: AgendaEvent { event("standup", calendar.on(14, at: 10), calendar.on(14, at: 11)) }

    func content(at now: Date, for event: AgendaEvent? = nil, policy: UpcomingMeetingPolicy? = nil) -> MeetingActivityContent? {
        MeetingActivityContent(event: event ?? standup, policy: policy ?? self.policy, now: now)
    }

    @Test func nothingWhileThePolicyHidesTheEvent() {
        #expect(content(at: calendar.on(14, at: 9)) == nil)
        #expect(content(at: calendar.on(14, at: 10, 5)) == nil)
        #expect(MeetingActivityContent(event: nil, policy: policy, now: calendar.on(14, at: 10)) == nil)
        #expect(content(at: calendar.on(14, at: 9, 58), policy: policy.dismissed(standup)) == nil)
    }

    @Test func theContentCarriesTheCountdownAndTheCalendarColour() {
        var coloured = standup
        coloured.calendarColor = RGBAColor(red: 1, green: 0.2, blue: 0.1)
        let shown = content(at: calendar.on(14, at: 9, 56), for: coloured)
        #expect(shown?.eventID == "standup")
        #expect(shown?.color == RGBAColor(red: 1, green: 0.2, blue: 0.1))
        #expect(shown?.state == .upcoming(minutesLeft: 4))
        #expect(shown?.countdown == "4 phút")
        #expect(content(at: calendar.on(14, at: 10, 2))?.state == .inProgress)
        #expect(content(at: calendar.on(14, at: 10, 2))?.countdown == "Đang diễn ra")
    }

    @Test func thePriorityIsHighOnlyWithinAMinuteOfTheStart() {
        #expect(content(at: calendar.on(14, at: 9, 55))?.priority == .normal)
        #expect(content(at: calendar.on(14, at: 9, 58, 59))?.priority == .normal)
        #expect(content(at: calendar.on(14, at: 9, 59))?.priority == .high)
        #expect(content(at: calendar.on(14, at: 10))?.priority == .high)
        #expect(content(at: calendar.on(14, at: 10, 1))?.priority == .high)
        #expect(content(at: calendar.on(14, at: 10, 1, 1))?.priority == .normal)
        #expect(content(at: calendar.on(14, at: 10, 4))?.priority == .normal)
    }
}
