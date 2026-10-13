import Foundation
import Testing
@testable import CalendarModule

@Suite struct UpcomingMeetingPolicyTests {
    let calendar = fixedCalendar()
    let policy = UpcomingMeetingPolicy(leadMinutes: 5)
    var standup: AgendaEvent { event("standup", calendar.on(14, at: 10), calendar.on(14, at: 11)) }

    func state(_ policy: UpcomingMeetingPolicy? = nil, at now: Date, for event: AgendaEvent? = nil) -> UpcomingMeetingPolicy.State {
        (policy ?? self.policy).state(for: event ?? standup, now: now)
    }

    @Test func hiddenWithoutAnEvent() {
        #expect(policy.state(for: nil, now: calendar.on(14, at: 10)) == .hidden)
    }

    @Test func hiddenBeforeTheLeadWindow() {
        #expect(state(at: calendar.on(14, at: 8)) == .hidden)
        #expect(state(at: calendar.on(14, at: 9, 54)) == .hidden)
        #expect(state(at: calendar.on(14, at: 9, 55).addingTimeInterval(-1)) == .hidden)
    }

    @Test func upcomingFromExactlyTheLeadTimeBeforeStart() {
        #expect(state(at: calendar.on(14, at: 9, 55)) == .upcoming(minutesLeft: 5))
    }

    @Test func minutesLeftRoundsUp() {
        #expect(state(at: calendar.on(14, at: 9, 55).addingTimeInterval(1)) == .upcoming(minutesLeft: 5))
        #expect(state(at: calendar.on(14, at: 9, 56)) == .upcoming(minutesLeft: 4))
        #expect(state(at: calendar.on(14, at: 9, 58).addingTimeInterval(30)) == .upcoming(minutesLeft: 2))
        #expect(state(at: calendar.on(14, at: 9, 59)) == .upcoming(minutesLeft: 1))
        #expect(state(at: calendar.on(14, at: 10).addingTimeInterval(-1)) == .upcoming(minutesLeft: 1))
    }

    @Test func inProgressFromTheStartForFiveMinutes() {
        #expect(state(at: calendar.on(14, at: 10)) == .inProgress)
        #expect(state(at: calendar.on(14, at: 10, 3)) == .inProgress)
        #expect(state(at: calendar.on(14, at: 10, 5).addingTimeInterval(-1)) == .inProgress)
    }

    @Test func hiddenFiveMinutesAfterTheStart() {
        #expect(state(at: calendar.on(14, at: 10, 5)) == .hidden)
        #expect(state(at: calendar.on(14, at: 10, 30)) == .hidden)
    }

    @Test func leadMinutesSetsHowEarlyItAppears() {
        let early = UpcomingMeetingPolicy(leadMinutes: 15)
        #expect(state(early, at: calendar.on(14, at: 9, 44)) == .hidden)
        #expect(state(early, at: calendar.on(14, at: 9, 45)) == .upcoming(minutesLeft: 15))
        let late = UpcomingMeetingPolicy(leadMinutes: 1)
        #expect(state(late, at: calendar.on(14, at: 9, 58)) == .hidden)
        #expect(state(late, at: calendar.on(14, at: 9, 59)) == .upcoming(minutesLeft: 1))
    }

    @Test func dismissedHidesThatEventInEveryPhase() {
        let dismissed = policy.dismissed(eventID: "standup")
        #expect(state(dismissed, at: calendar.on(14, at: 9, 57)) == .hidden)
        #expect(state(dismissed, at: calendar.on(14, at: 10, 2)) == .hidden)
    }

    @Test func dismissingDoesNotMutateTheOriginalPolicy() {
        _ = policy.dismissed(eventID: "standup")
        #expect(state(at: calendar.on(14, at: 9, 57)) == .upcoming(minutesLeft: 3))
    }

    @Test func dismissedDoesNotHideAnotherOrAChangedEvent() {
        let dismissed = policy.dismissed(eventID: "standup")
        let other = event("retro", calendar.on(14, at: 10), calendar.on(14, at: 11))
        // A reschedule gives the event a new id (it carries the occurrence start), so it is a different event.
        let moved = event("standup@moved", calendar.on(14, at: 10, 30), calendar.on(14, at: 11))
        #expect(state(dismissed, at: calendar.on(14, at: 9, 57), for: other) == .upcoming(minutesLeft: 3))
        #expect(state(dismissed, at: calendar.on(14, at: 10, 27), for: moved) == .upcoming(minutesLeft: 3))
    }
}

@Suite struct NextMeetingTests {
    let calendar = fixedCalendar()
    let policy = UpcomingMeetingPolicy(leadMinutes: 5)
    /// Wednesday 14 October 2026, 13:56.
    var now: Date { calendar.on(14, at: 13, 56) }

    func next(_ events: [AgendaEvent], at now: Date? = nil, policy: UpcomingMeetingPolicy? = nil, includingDismissed: Bool = false) -> String? {
        (policy ?? self.policy).nextMeeting(in: events, now: now ?? self.now, includingDismissed: includingDismissed)?.id
    }

    @Test func noEventsGiveNoMeeting() {
        #expect(next([]) == nil)
    }

    @Test func aLongRunningEventDoesNotHideALaterMeeting() {
        let workshop = event("workshop", calendar.on(14, at: 9), calendar.on(14, at: 17))
        let review = event("review", calendar.on(14, at: 14), calendar.on(14, at: 15))
        #expect(next([workshop, review]) == "review")
    }

    @Test func aMeetingThatJustStartedStillCounts() {
        let started = event("started", calendar.on(14, at: 13, 52), calendar.on(14, at: 14, 30))
        let later = event("later", calendar.on(14, at: 15), calendar.on(14, at: 16))
        #expect(next([started, later]) == "started")
        #expect(next([started, later], at: calendar.on(14, at: 13, 56, 59)) == "started")
        #expect(next([started, later], at: calendar.on(14, at: 13, 57)) == "later")
    }

    @Test func aMeetingStartingNowCounts() {
        let now = event("now", calendar.on(14, at: 13, 56), calendar.on(14, at: 14, 30))
        #expect(next([now]) == "now")
    }

    @Test func aFinishedOrLongRunningEventAloneGivesNothing() {
        let workshop = event("workshop", calendar.on(14, at: 9), calendar.on(14, at: 17))
        let over = event("over", calendar.on(14, at: 8), calendar.on(14, at: 9))
        #expect(next([over, workshop]) == nil)
    }

    @Test func theFirstOneInTheOrderGivenWins() {
        let early = event("early", calendar.on(14, at: 14), calendar.on(14, at: 15))
        let late = event("late", calendar.on(14, at: 16), calendar.on(14, at: 17))
        #expect(next([early, late]) == "early")
    }

    @Test func aDismissedMeetingStepsAsideForTheNextOne() {
        let early = event("early", calendar.on(14, at: 14), calendar.on(14, at: 15))
        let overlapping = event("overlapping", calendar.on(14, at: 14, 2), calendar.on(14, at: 15))
        let dismissed = policy.dismissed(eventID: "early")
        #expect(next([early, overlapping], policy: dismissed) == "overlapping")
        #expect(next([early, overlapping], policy: dismissed, includingDismissed: true) == "early")
        #expect(next([early], policy: dismissed) == nil)
    }
}
