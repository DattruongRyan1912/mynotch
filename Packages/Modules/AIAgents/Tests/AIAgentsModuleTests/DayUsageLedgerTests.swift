import Foundation
import Testing
@testable import AIAgentsModule

/// The day's usage on its own, independent of which sessions come and go.
@Suite struct DayUsageLedgerTests {
    let calendar = hoChiMinhCalendar()
    let noon = utc("2026-10-14T05:00:00Z")

    func message(_ id: String, output: Int = 1) -> AgentUsage {
        AgentUsage(output: output, model: "claude-opus-4-1", messageID: id)
    }

    func total(_ input: Int, fromStart: Bool = false) -> AgentUsage {
        AgentUsage(input: input, model: "gpt-5-codex", isCumulative: true, startsFromZero: fromStart)
    }

    func record(_ ledger: inout DayUsageLedger, _ usage: AgentUsage, _ source: AgentSource = .claude, session: String = "s1", at: Date? = nil, now: Date? = nil) {
        ledger.record(usage, source: source, sessionID: session, at: at ?? now ?? noon, now: now ?? noon, calendar: calendar)
    }

    @Test func aRepeatedMessageCountsOnceKeepingTheLastRecord() {
        var ledger = DayUsageLedger()
        record(&ledger, message("m", output: 5))
        record(&ledger, message("m", output: 40))
        record(&ledger, message("m", output: 40))
        #expect(ledger.usage(now: noon, calendar: calendar)[.claude]?.tokens.output == 40)
    }

    @Test func theSameMessageIdOfAnotherAgentIsAnotherMessage() {
        var ledger = DayUsageLedger()
        record(&ledger, message("m", output: 5), .claude)
        record(&ledger, message("m", output: 7), .codex)
        let usage = ledger.usage(now: noon, calendar: calendar)
        #expect(usage[.claude]?.tokens.output == 5)
        #expect(usage[.codex]?.tokens.output == 7)
    }

    @Test func recordsOlderThanTodayAreIgnoredAndNotRemembered() {
        var ledger = DayUsageLedger()
        record(&ledger, message("old"), at: noon - 86_400)
        #expect(ledger.usage(now: noon, calendar: calendar).isEmpty)
        #expect(ledger.rememberedMessageCount == 0)
    }

    @Test func theMessageMemoryIsBoundedAndKeepsTheLatestMessages() {
        var ledger = DayUsageLedger()
        let count = DayUsageLedger.messageMemory + 100
        for number in 0..<count {
            record(&ledger, message("msg_\(number)"))
        }
        #expect(ledger.rememberedMessageCount <= DayUsageLedger.messageMemory)
        // The latest message is recognised when another record of it arrives.
        record(&ledger, message("msg_\(count - 1)"))
        #expect(ledger.usage(now: noon, calendar: calendar)[.claude]?.tokens.output == count)
    }

    @Test func theMessageMemoryStartsOverAtMidnight() {
        var ledger = DayUsageLedger()
        let lastNight = utc("2026-10-14T16:50:00Z")
        let thisMorning = utc("2026-10-14T17:10:00Z")
        record(&ledger, message("a"), now: lastNight)
        record(&ledger, message("b"), now: lastNight)
        #expect(ledger.rememberedMessageCount == 2)
        record(&ledger, message("c"), now: thisMorning)
        #expect(ledger.rememberedMessageCount == 1)
        #expect(ledger.usage(now: thisMorning, calendar: calendar)[.claude]?.tokens.output == 1)
    }

    @Test func aRunningTotalIsRememberedPerSessionAcrossDays() {
        var ledger = DayUsageLedger()
        let lastNight = utc("2026-10-14T16:50:00Z")
        let thisMorning = utc("2026-10-14T17:10:00Z")
        record(&ledger, total(1_000, fromStart: true), .codex, session: "x", now: lastNight)
        record(&ledger, total(1_300), .codex, session: "x", now: thisMorning)
        #expect(ledger.usage(now: thisMorning, calendar: calendar)[.codex]?.tokens.input == 300)
        #expect(ledger.rememberedTotalCount == 1)
    }

    @Test func runningTotalsOfDifferentSessionsAreSeparate() {
        var ledger = DayUsageLedger()
        record(&ledger, total(1_000, fromStart: true), .codex, session: "x")
        record(&ledger, total(500, fromStart: true), .codex, session: "y")
        record(&ledger, total(1_200), .codex, session: "x")
        #expect(ledger.usage(now: noon, calendar: calendar)[.codex]?.tokens.input == 1_700)
    }

    @Test func aFirstTotalThatMayHoldEarlierWorkIsOnlyABaseline() {
        var ledger = DayUsageLedger()
        record(&ledger, total(50_000), .codex, session: "x")
        #expect(ledger.usage(now: noon, calendar: calendar).isEmpty)
        record(&ledger, total(52_000), .codex, session: "x")
        #expect(ledger.usage(now: noon, calendar: calendar)[.codex]?.tokens.input == 2_000)
    }

    @Test func aTotalFromBeforeTodayStillSetsTheBaseline() {
        var ledger = DayUsageLedger()
        record(&ledger, total(1_000, fromStart: true), .codex, session: "x", at: noon - 86_400)
        record(&ledger, total(1_100), .codex, session: "x")
        #expect(ledger.usage(now: noon, calendar: calendar)[.codex]?.tokens.input == 100)
    }

    @Test func theRunningTotalMemoryIsBounded() {
        var ledger = DayUsageLedger()
        for number in 0..<(DayUsageLedger.totalMemory + 50) {
            record(&ledger, total(10, fromStart: true), .codex, session: "session-\(number)")
        }
        #expect(ledger.rememberedTotalCount <= DayUsageLedger.totalMemory)
        // The most recent session is still remembered.
        record(&ledger, total(15), .codex, session: "session-\(DayUsageLedger.totalMemory + 49)")
        #expect(ledger.usage(now: noon, calendar: calendar)[.codex]?.tokens.input == 10 * (DayUsageLedger.totalMemory + 50) + 5)
    }

    @Test func usageWithoutAMessageIdAddsUp() {
        var ledger = DayUsageLedger()
        record(&ledger, AgentUsage(output: 2, model: "claude-opus-4-1"))
        record(&ledger, AgentUsage(output: 2, model: "claude-opus-4-1"))
        #expect(ledger.usage(now: noon, calendar: calendar)[.claude]?.tokens.output == 4)
    }
}
