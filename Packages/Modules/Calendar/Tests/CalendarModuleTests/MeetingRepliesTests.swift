import Foundation
import Testing
@testable import CalendarModule

@Suite struct MeetingRepliesTests {
    let calendar = fixedCalendar()
    let replies = MeetingReplies()
    var standup: AgendaEvent { event("standup", calendar.on(14, at: 10), calendar.on(14, at: 11)) }

    func hidden(_ replies: MeetingReplies, _ event: AgendaEvent? = nil, at now: Date) -> Bool {
        replies.isHidden(event ?? standup, now: now)
    }

    @Test func nothingIsHiddenBeforeAnAnswer() {
        #expect(replies.isEmpty)
        #expect(!hidden(replies, at: calendar.on(14, at: 9, 57)))
    }

    // MARK: Snooze

    @Test func aSnoozeHidesTheMeetingForFiveMinutes() {
        let snoozed = replies.snoozing(standup, now: calendar.on(14, at: 9, 40))
        #expect(hidden(snoozed, at: calendar.on(14, at: 9, 40)))
        #expect(hidden(snoozed, at: calendar.on(14, at: 9, 44, 59)))
        #expect(!hidden(snoozed, at: calendar.on(14, at: 9, 45)))
        #expect(!hidden(snoozed, at: calendar.on(14, at: 9, 50)))
    }

    @Test func aSnoozeNeverOutlastsTheStart() {
        let snoozed = replies.snoozing(standup, now: calendar.on(14, at: 9, 57))
        #expect(hidden(snoozed, at: calendar.on(14, at: 9, 59, 59)))
        #expect(!hidden(snoozed, at: calendar.on(14, at: 10)))
        #expect(MeetingReplies.snoozeEnd(for: standup, now: calendar.on(14, at: 9, 57)) == calendar.on(14, at: 10))
        #expect(MeetingReplies.snoozeEnd(for: standup, now: calendar.on(14, at: 9, 55)) == calendar.on(14, at: 10))
        #expect(MeetingReplies.snoozeEnd(for: standup, now: calendar.on(14, at: 9, 54)) == calendar.on(14, at: 9, 59))
    }

    @Test func aSnoozeCanBeRepeated() {
        let first = replies.snoozing(standup, now: calendar.on(14, at: 9, 40))
        let second = first.snoozing(standup, now: calendar.on(14, at: 9, 45))
        #expect(hidden(second, at: calendar.on(14, at: 9, 49, 59)))
        #expect(!hidden(second, at: calendar.on(14, at: 9, 50)))
        #expect(second.count == 1)
    }

    @Test func aMeetingThatHasStartedCannotBeSnoozed() {
        #expect(replies.snoozing(standup, now: calendar.on(14, at: 10)) == replies)
        #expect(replies.snoozing(standup, now: calendar.on(14, at: 10, 2)) == replies)
    }

    @Test func snoozingDoesNotMutateTheOriginal() {
        _ = replies.snoozing(standup, now: calendar.on(14, at: 9, 40))
        #expect(replies.isEmpty)
    }

    // MARK: Dismiss

    @Test func aDismissalHidesTheMeetingFromThenOn() {
        let dismissed = replies.dismissing(standup)
        for now in [calendar.on(14, at: 9), calendar.on(14, at: 9, 57), calendar.on(14, at: 10, 2), calendar.on(14, at: 10, 30)] {
            #expect(hidden(dismissed, at: now))
        }
    }

    @Test func aDismissalWinsOverASnooze() {
        let snoozed = replies.snoozing(standup, now: calendar.on(14, at: 9, 40))
        #expect(hidden(snoozed.dismissing(standup), at: calendar.on(14, at: 9, 50)))
        #expect(hidden(replies.dismissing(standup).snoozing(standup, now: calendar.on(14, at: 9, 40)), at: calendar.on(14, at: 9, 50)))
    }

    // MARK: Per occurrence

    @Test func anAnswerBelongsToOneOccurrenceOnly() {
        let dismissed = replies.dismissing(standup)
        // Same series on the next day: same item, another start.
        let tomorrow = event("standup", calendar.on(15, at: 10), calendar.on(15, at: 11))
        // The same occurrence moved by an hour: same id, another start.
        let moved = event("standup", calendar.on(14, at: 11), calendar.on(14, at: 12))
        let other = event("retro", calendar.on(14, at: 10), calendar.on(14, at: 11))
        let now = calendar.on(14, at: 9, 57)
        #expect(hidden(dismissed, standup, at: now))
        #expect(!hidden(dismissed, tomorrow, at: now))
        #expect(!hidden(dismissed, moved, at: now))
        #expect(!hidden(dismissed, other, at: now))
    }

    @Test func eachOccurrenceKeepsItsOwnAnswer() {
        let tomorrow = event("standup", calendar.on(15, at: 10), calendar.on(15, at: 11))
        let both = replies.dismissing(standup).snoozing(tomorrow, now: calendar.on(14, at: 11))
        #expect(both.count == 2)
        #expect(hidden(both, standup, at: calendar.on(14, at: 9, 57)))
        #expect(hidden(both, tomorrow, at: calendar.on(14, at: 11, 4)))
        #expect(!hidden(both, tomorrow, at: calendar.on(14, at: 11, 5)))
    }

    // MARK: Pruning

    @Test func anAnswerIsKeptUntilItsMeetingEnds() {
        let dismissed = replies.dismissing(standup)
        #expect(dismissed.pruned(now: calendar.on(14, at: 9, 57)) == dismissed)
        #expect(dismissed.pruned(now: calendar.on(14, at: 10, 59, 59)) == dismissed)
        #expect(dismissed.pruned(now: calendar.on(14, at: 11)).isEmpty)
        #expect(dismissed.pruned(now: calendar.on(15, at: 9)).isEmpty)
    }

    /// The card shows until five minutes after the start, so a short meeting's answer must outlive the meeting.
    @Test func aShortMeetingsAnswerOutlastsTheCardNotJustTheMeeting() {
        let blink = event("blink", calendar.on(14, at: 10), calendar.on(14, at: 10))
        let short = event("short", calendar.on(14, at: 10), calendar.on(14, at: 10, 2))
        let dismissed = replies.dismissing(blink).dismissing(short)
        #expect(dismissed.pruned(now: calendar.on(14, at: 10, 4, 59)).count == 2)
        #expect(dismissed.pruned(now: calendar.on(14, at: 10, 5)).isEmpty)
    }

    @Test func pruningKeepsWhatHasNotEnded() {
        let later = event("later", calendar.on(14, at: 14), calendar.on(14, at: 15))
        let both = replies.dismissing(standup).snoozing(later, now: calendar.on(14, at: 13, 30))
        let pruned = both.pruned(now: calendar.on(14, at: 12))
        #expect(pruned.count == 1)
        #expect(hidden(pruned, later, at: calendar.on(14, at: 13, 31)))
        #expect(!hidden(pruned, standup, at: calendar.on(14, at: 9, 57)))
    }

    // MARK: When a snooze ends

    @Test func theNextWakeIsTheEarliestSnoozeStillRunning() {
        let early = event("early", calendar.on(14, at: 10), calendar.on(14, at: 11))
        let late = event("late", calendar.on(14, at: 10, 30), calendar.on(14, at: 11))
        let now = calendar.on(14, at: 9, 40)
        let both = replies.snoozing(late, now: now).snoozing(early, now: now.addingTimeInterval(60))
        #expect(both.nextWake(after: now) == calendar.on(14, at: 9, 45))
        #expect(both.nextWake(after: calendar.on(14, at: 9, 45)) == calendar.on(14, at: 9, 46))
        #expect(both.nextWake(after: calendar.on(14, at: 9, 46)) == nil)
    }

    @Test func aDismissalNeverWakes() {
        #expect(replies.dismissing(standup).nextWake(after: calendar.on(14, at: 9)) == nil)
        #expect(replies.snoozing(standup, now: calendar.on(14, at: 9, 40)).dismissing(standup).nextWake(after: calendar.on(14, at: 9, 41)) == nil)
        #expect(replies.nextWake(after: calendar.on(14, at: 9)) == nil)
    }

    // MARK: Storage

    @Test func theAnswersSurviveBeingEncodedAndDecoded() throws {
        let tomorrow = event("standup", calendar.on(15, at: 10), calendar.on(15, at: 11))
        let before = replies.dismissing(standup).snoozing(tomorrow, now: calendar.on(14, at: 11))
        let decoded = try JSONDecoder().decode(MeetingReplies.self, from: JSONEncoder().encode(before))
        #expect(decoded == before)
        #expect(hidden(decoded, standup, at: calendar.on(14, at: 10, 30)))
        #expect(hidden(decoded, tomorrow, at: calendar.on(14, at: 11, 4)))
    }

    @Test func theEncodedBytesDoNotDependOnTheOrderOfTheAnswers() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let retro = event("retro", calendar.on(14, at: 10), calendar.on(14, at: 11))
        let one = replies.dismissing(standup).dismissing(retro)
        let other = replies.dismissing(retro).dismissing(standup)
        #expect(try encoder.encode(one) == encoder.encode(other))
    }
}
