import Foundation
import MyNotchCore
import MyNotchTestSupport
import Observation
import Testing
@testable import AIAgentsModule

/// The store driven by a fake clock and scheduler. Local time is UTC+7, so the clock below reads 12:00.
@Suite struct AgentSessionStoreTests {
    let scheduler = ManualScheduler()
    let clock = TestClock(utc("2026-10-14T05:00:00Z"))
    let store: AgentSessionStore
    let demoPath = "/Users/example/Projects/demo"

    init() {
        let clock = clock
        store = AgentSessionStore(scheduler: scheduler, now: { clock.now }, calendar: hoChiMinhCalendar())
    }

    /// An event that happened `age` seconds before the clock's now.
    func event(
        _ kind: AgentEvent.Kind, _ source: AgentSource = .claude, id: String = "s1",
        usage: AgentUsage? = nil, costUSD: Double? = nil, rateLimits: AgentRateLimits? = nil, age: TimeInterval = 0
    ) -> AgentEvent {
        AgentEvent(source: source, sessionID: id, timestamp: clock.now - age, kind: kind, usage: usage, costUSD: costUSD, rateLimits: rateLimits)
    }

    func session(_ id: String = "s1", _ source: AgentSource = .claude) -> AgentSession? {
        store.sessions[AgentSessionKey(source: source, sessionID: id)]
    }

    func state(_ id: String = "s1", _ source: AgentSource = .claude) -> AgentState? {
        session(id, source)?.state
    }

    /// Moves wall-clock time and timer time together, one step at a time.
    func elapse(_ seconds: Int, step: Int = 1) {
        for _ in 0..<(seconds / step) {
            clock.advance(by: TimeInterval(step))
            scheduler.advance(by: .seconds(step))
        }
    }

    func claudeUsage(_ id: String, input: Int = 0, output: Int = 0, cacheRead: Int = 0, cacheWrite: Int = 0, model: String = "claude-opus-4-1") -> AgentUsage {
        AgentUsage(input: input, output: output, cacheRead: cacheRead, cacheWrite: cacheWrite, model: model, messageID: id)
    }

    func registryEntry(
        _ id: String = "s1", pid: pid_t = 100, status: ClaudeSessionInfo.Status? = .busy, statusUpdatedAt: Date? = nil, cwd: String? = nil
    ) -> ClaudeSessionInfo {
        ClaudeSessionInfo(pid: pid, sessionID: id, cwd: cwd, status: status, statusUpdatedAt: statusUpdatedAt)
    }

    // MARK: State table

    @Test func aPromptStartsAWorkingTurnInTheProject() {
        store.apply(event(.sessionStarted(cwd: demoPath, branch: "main")))
        store.apply(event(.turnStarted))
        let session = session()
        #expect(session?.state == .working(tool: nil, summary: nil))
        #expect(session?.project == "demo")
        #expect(session?.cwd == demoPath)
        #expect(session?.branch == "main")
        #expect(session?.turnStartedAt == clock.now)
        #expect(session?.lastEventAt == clock.now)
    }

    @Test func toolsShowWhileRunningAndClearWhenTheirResultArrives() {
        store.apply(event(.turnStarted))
        store.apply(event(.toolStarted(name: "Bash", summary: "git status")))
        #expect(state() == .working(tool: "Bash", summary: "git status"))
        store.apply(event(.toolFinished))
        #expect(state() == .working(tool: nil, summary: nil))
        #expect(session()?.turnStartedAt == clock.now)
    }

    @Test func finishedBecomesIdleAfterFinishedSeconds() {
        store.apply(event(.turnStarted))
        store.apply(event(.turnFinished))
        #expect(state() == .finished)
        elapse(4)
        #expect(state() == .finished)
        elapse(1)
        #expect(state() == .idle)
    }

    @Test func finishedSecondsIsConfigurable() {
        store.finishedSeconds = 2
        store.apply(event(.turnStarted))
        store.apply(event(.turnFinished))
        elapse(1)
        #expect(state() == .finished)
        elapse(1)
        #expect(state() == .idle)
    }

    @Test func repeatedFinishEventsDoNotRestartTheTimer() {
        store.apply(event(.turnStarted))
        store.apply(event(.turnFinished))
        elapse(3)
        store.apply(event(.turnFinished))
        elapse(2)
        #expect(state() == .idle)
    }

    @Test func aFinishAfterTheSessionWentIdleStaysIdle() {
        store.apply(event(.turnStarted))
        store.apply(event(.turnFinished))
        elapse(5)
        store.apply(event(.turnFinished))
        #expect(state() == .idle)
        elapse(10)
        #expect(state() == .idle)
    }

    @Test func workAfterAFinishCancelsTheIdleTimer() {
        store.apply(event(.turnStarted))
        store.apply(event(.turnFinished))
        elapse(2)
        store.apply(event(.toolStarted(name: "Read", summary: "App.swift")))
        elapse(10)
        #expect(state() == .working(tool: "Read", summary: "App.swift"))
        store.apply(event(.turnFinished))
        #expect(state() == .finished)
        elapse(5)
        #expect(state() == .idle)
    }

    @Test func aNewPromptAfterAFinishStartsANewTurn() {
        store.apply(event(.turnStarted))
        store.apply(event(.turnFinished))
        elapse(2)
        store.apply(event(.turnStarted))
        #expect(state() == .working(tool: nil, summary: nil))
        #expect(session()?.turnStartedAt == clock.now)
    }

    @Test func aFinishFromLongAgoGoesStraightToIdle() {
        store.apply(event(.turnStarted, age: 120))
        store.apply(event(.turnFinished, age: 60))
        #expect(state() == .idle)
    }

    @Test func aRecentFinishShowsForTheRestOfItsFiveSeconds() {
        store.apply(event(.turnStarted, age: 10))
        store.apply(event(.turnFinished, age: 3))
        #expect(state() == .finished)
        elapse(1)
        #expect(state() == .finished)
        elapse(1)
        #expect(state() == .idle)
    }

    @Test func aSessionFirstSeenFinishingShowsFinished() {
        store.apply(event(.turnFinished))
        #expect(state() == .finished)
    }

    @Test func anAbortedTurnIsIdleAndCancelsTheFinishTimer() {
        store.apply(event(.turnStarted))
        store.apply(event(.turnAborted))
        #expect(state() == .idle)
        store.apply(event(.turnStarted))
        store.apply(event(.turnFinished))
        store.apply(event(.turnAborted))
        elapse(10)
        #expect(state() == .idle)
    }

    @Test func aFailedTurnIsAnErrorUntilTheNextTurn() {
        store.apply(event(.turnStarted))
        store.apply(event(.turnFailed))
        #expect(state() == .error)
        elapse(30)
        #expect(state() == .error)
        store.apply(event(.turnStarted))
        #expect(state() == .working(tool: nil, summary: nil))
    }

    @Test func waitingForInputResumesWhenTheToolResultArrives() {
        store.apply(event(.turnStarted))
        store.apply(event(.toolStarted(name: "Bash", summary: nil)))
        store.apply(event(.waitingForInput))
        #expect(state() == .waitingForInput)
        let turnStart = session()?.turnStartedAt
        elapse(20)
        store.apply(event(.toolFinished))
        #expect(state() == .working(tool: nil, summary: nil))
        #expect(session()?.turnStartedAt == turnStart)
    }

    @Test func aSessionFirstSeenInTheMiddleOfATurnStartsItsTurnThere() {
        store.apply(event(.toolStarted(name: "Edit", summary: "A.swift"), age: 7))
        #expect(state() == .working(tool: "Edit", summary: "A.swift"))
        #expect(session()?.turnStartedAt == clock.now - 7)
    }

    @Test func aSessionAnnouncedByItsStartIsIdleUntilItWorks() {
        store.apply(event(.sessionStarted(cwd: demoPath, branch: nil)))
        #expect(state() == .idle)
        #expect(session()?.turnStartedAt == nil)
    }

    @Test func sessionsAreKeyedBySourceAndID() {
        store.apply(event(.turnStarted, .claude, id: "same"))
        store.apply(event(.turnFinished, .codex, id: "same"))
        store.apply(event(.turnStarted, .claude, id: "other"))
        #expect(state("same", .claude) == .working(tool: nil, summary: nil))
        #expect(state("same", .codex) == .finished)
        #expect(store.sessions.count == 3)
    }

    @Test func sessionStartedKeepsTrackOfWhereTheSessionRuns() {
        store.apply(event(.sessionStarted(cwd: demoPath, branch: "main")))
        store.apply(event(.sessionStarted(cwd: nil, branch: "feature/x")))
        #expect(session()?.cwd == demoPath)
        #expect(session()?.branch == "feature/x")
        store.apply(event(.sessionStarted(cwd: "/Users/example/Projects/other/", branch: nil)))
        #expect(session()?.project == "other")
        #expect(session()?.branch == nil)
    }

    @Test func aMissingTimestampUsesTheTimeTheLineWasRead() {
        var undated = event(.turnStarted)
        undated.timestamp = nil
        store.apply(undated)
        #expect(session()?.lastEventAt == clock.now)
        #expect(session()?.turnStartedAt == clock.now)
    }

    @Test func eventTimesNeverRunAheadOfTheClockOrBackwards() {
        store.apply(event(.turnStarted, age: -600))
        #expect(session()?.lastEventAt == clock.now)
        store.apply(event(.toolStarted(name: "Bash", summary: nil), age: 30))
        #expect(session()?.lastEventAt == clock.now)
    }

    @Test func eventsAppliedInABatchBehaveLikeOneByOne() {
        store.apply([event(.sessionStarted(cwd: demoPath, branch: "main")), event(.turnStarted), event(.toolStarted(name: "Bash", summary: "ls"))])
        #expect(state() == .working(tool: "Bash", summary: "ls"))
        #expect(session()?.project == "demo")
    }

    @Test func sessionsAreListedNewestActivityFirst() {
        store.apply(event(.turnStarted, id: "old", age: 60))
        store.apply(event(.turnStarted, .codex, id: "new"))
        store.apply(event(.turnStarted, id: "middle", age: 30))
        #expect(store.orderedSessions.map(\.key.sessionID) == ["new", "middle", "old"])
    }

    // MARK: Usage

    @Test func usageIsCountedOncePerClaudeMessageKeepingTheLastRecord() {
        store.apply(event(.toolStarted(name: "Bash", summary: nil), usage: claudeUsage("msg_1", input: 10, output: 5, cacheRead: 1000, cacheWrite: 300)))
        store.apply(event(.usageUpdated, usage: claudeUsage("msg_1", input: 10, output: 40, cacheRead: 1000, cacheWrite: 300)))
        store.apply(event(.turnFinished, usage: claudeUsage("msg_1", input: 10, output: 90, cacheRead: 1000, cacheWrite: 300)))
        store.apply(event(.usageUpdated, usage: claudeUsage("msg_2", input: 2, output: 7, cacheRead: 2000)))
        #expect(session()?.usage == UsageTotals(input: 12, output: 97, cacheRead: 3000, cacheWrite: 300))
    }

    @Test func claudeUsageWithoutAMessageIDAddsUp() {
        let anonymous = AgentUsage(input: 1, output: 2, model: "claude-opus-4-1")
        store.apply(event(.usageUpdated, usage: anonymous))
        store.apply(event(.usageUpdated, usage: anonymous))
        #expect(session()?.usage == UsageTotals(input: 2, output: 4))
    }

    @Test func codexCumulativeTotalsReplaceEarlierOnes() {
        func total(_ input: Int, _ output: Int, fromStart: Bool = false) -> AgentUsage {
            AgentUsage(input: input, output: output, cacheRead: 100, reasoning: 5, model: "gpt-5-codex", isCumulative: true, startsFromZero: fromStart)
        }
        store.apply(event(.usageUpdated, .codex, usage: total(1000, 200, fromStart: true)))
        store.apply(event(.usageUpdated, .codex, usage: total(1500, 450)))
        #expect(session("s1", .codex)?.usage == UsageTotals(input: 1500, output: 450, cacheRead: 100, reasoning: 5))
        #expect(store.todayUsage[.codex]?.tokens == UsageTotals(input: 1500, output: 450, cacheRead: 100, reasoning: 5))
    }

    @Test func aCodexSessionFirstSeenMidwayCountsOnlyWhatItAddsAfterwardsToday() {
        func total(_ input: Int) -> AgentUsage {
            AgentUsage(input: input, output: 10, model: "gpt-5-codex", isCumulative: true)
        }
        store.apply(event(.usageUpdated, .codex, usage: total(50_000)))
        #expect(session("s1", .codex)?.usage.input == 50_000)
        #expect(store.todayUsage[.codex] == nil)
        store.apply(event(.usageUpdated, .codex, usage: total(52_000)))
        #expect(session("s1", .codex)?.usage.input == 52_000)
        #expect(store.todayUsage[.codex]?.tokens == UsageTotals(input: 2_000))
    }

    @Test func aCodexTotalThatGoesDownStartsCountingAgain() {
        func total(_ input: Int, fromStart: Bool = false) -> AgentUsage {
            AgentUsage(input: input, model: "gpt-5-codex", isCumulative: true, startsFromZero: fromStart)
        }
        store.apply(event(.usageUpdated, .codex, usage: total(5_000, fromStart: true)))
        store.apply(event(.usageUpdated, .codex, usage: total(300)))
        #expect(store.todayUsage[.codex]?.tokens.input == 5_300)
    }

    @Test func usageIsKeptPerModelAndPricedFromTheTable() {
        store.apply(event(.usageUpdated, usage: claudeUsage("a", input: 1_000_000, model: "claude-opus-4-1")))
        store.apply(event(.usageUpdated, usage: claudeUsage("b", output: 1_000_000, model: "claude-haiku-4-5-20251001")))
        #expect(session()?.usageByModel["claude-opus-4-1"] == UsageTotals(input: 1_000_000))
        #expect(session()?.usageByModel["claude-haiku-4-5-20251001"] == UsageTotals(output: 1_000_000))
        #expect(session()?.costUSD == 20)
        #expect(session()?.isCostEstimated == true)
    }

    @Test func aSessionWithoutPricedUsageHasNoCost() {
        #expect(AgentSession(key: AgentSessionKey(source: .claude, sessionID: "x"), lastEventAt: clock.now).costUSD == nil)
        store.apply(event(.usageUpdated, usage: claudeUsage("a", input: 5, model: "mystery-model")))
        #expect(session()?.costUSD == nil)
        #expect(session()?.usage.input == 5)
    }

    @Test func aCostReportedByTheAgentIsPreferredToTheEstimate() {
        store.apply(event(.usageUpdated, usage: claudeUsage("a", input: 1_000_000)))
        store.apply(event(.usageUpdated, costUSD: 1.25))
        #expect(session()?.costUSD == 1.25)
        #expect(session()?.isCostEstimated == false)
    }

    @Test func usageAfterAReportedCostIsAddedAsAnEstimate() {
        store.apply(event(.usageUpdated, costUSD: 2))
        store.apply(event(.usageUpdated, usage: claudeUsage("a", output: 1_000_000)))
        #expect(session()?.costUSD == 77)
        #expect(session()?.isCostEstimated == true)
        store.apply(event(.usageUpdated, costUSD: 80))
        #expect(session()?.costUSD == 80)
        #expect(session()?.isCostEstimated == false)
    }

    @Test func codexRateLimitsAreKept() {
        let limits = AgentRateLimits(primary: .init(usedPercent: 12.5, windowMinutes: 300, resetsAt: clock.now + 3600), secondary: nil)
        store.apply(event(.usageUpdated, .codex, rateLimits: limits))
        #expect(session("s1", .codex)?.rateLimits == limits)
        let newer = AgentRateLimits(primary: .init(usedPercent: 20, windowMinutes: 300, resetsAt: clock.now + 3000), secondary: nil)
        store.apply(event(.usageUpdated, .codex, rateLimits: newer))
        store.apply(event(.turnStarted, .codex))
        #expect(session("s1", .codex)?.rateLimits == newer)
    }

    @Test func usageDeduplicationRemembersOnlyTheRecentMessages() {
        for number in 0..<1_100 {
            store.apply(event(.usageUpdated, usage: claudeUsage("msg_\(number)", output: 1)))
        }
        // The latest message is still recognised when another record of it arrives...
        store.apply(event(.usageUpdated, usage: claudeUsage("msg_1099", output: 1)))
        #expect(session()?.usage.output == 1_100)
        // ...and the memory stays bounded.
        #expect((session()?.ledger.rememberedMessageCount ?? .max) <= 1_000)
    }

    // MARK: Today

    @Test func todayCountsOnlyEventsSinceLocalMidnight() {
        // 00:30 on 14 October local time; the day started 30 minutes ago.
        clock.now = utc("2026-10-13T17:30:00Z")
        store.apply(event(.usageUpdated, usage: claudeUsage("before", input: 1_000, output: 100), age: 31 * 60))
        store.apply(event(.usageUpdated, usage: claudeUsage("after", input: 20, output: 5), age: 29 * 60))
        #expect(store.todayUsage[.claude]?.tokens == UsageTotals(input: 20, output: 5))
        // The session still counts everything it was told about.
        #expect(session()?.usage == UsageTotals(input: 1_020, output: 105))
    }

    @Test func aMessageCountsFromTheMomentItsTimestampSays() {
        clock.now = utc("2026-10-13T17:30:00Z")
        store.apply(event(.usageUpdated, usage: claudeUsage("at-midnight"), age: 30 * 60))
        store.apply(event(.usageUpdated, usage: claudeUsage("at-midnight", input: 7), age: 30 * 60))
        #expect(store.todayUsage[.claude]?.tokens == UsageTotals(input: 7))
    }

    @Test func todayStartsOverAtMidnight() {
        clock.now = utc("2026-10-14T16:50:00Z")
        store.apply(event(.usageUpdated, usage: claudeUsage("late", output: 100)))
        #expect(store.todayUsage[.claude]?.tokens.output == 100)
        clock.advance(by: 15 * 60)
        #expect(store.todayUsage.isEmpty)
        store.apply(event(.usageUpdated, usage: claudeUsage("next-day", output: 3)))
        #expect(store.todayUsage[.claude]?.tokens.output == 3)
    }

    @Test func todayIsPerAgentAndOutlivesTheSession() {
        store.apply(event(.usageUpdated, usage: claudeUsage("a", input: 1_000_000)))
        store.apply(event(.usageUpdated, .codex, usage: AgentUsage(output: 1_000_000, model: "gpt-5-codex", isCumulative: true, startsFromZero: true)))
        store.apply(event(.sessionEnded))
        #expect(session() == nil)
        #expect(store.todayUsage[.claude]?.tokens == UsageTotals(input: 1_000_000))
        #expect(store.todayUsage[.claude]?.estimatedCostUSD == 15)
        #expect(store.todayUsage[.codex]?.tokens == UsageTotals(output: 1_000_000))
        #expect(store.todayUsage[.codex]?.estimatedCostUSD == 10)
    }

    @Test func todayCountsAMessageOnceHoweverOftenItIsRepeated() {
        for _ in 0..<3 {
            store.apply(event(.usageUpdated, usage: claudeUsage("msg", output: 10)))
        }
        #expect(store.todayUsage[.claude]?.tokens.output == 10)
    }

    @Test func todayIsObservable() {
        let changed = Flag()
        withObservationTracking {
            _ = store.todayUsage
        } onChange: {
            changed.set()
        }
        store.apply(event(.usageUpdated, usage: claudeUsage("a", output: 1)))
        #expect(changed.isSet)
    }

    // MARK: Interrupted turns

    @Test func aWorkingClaudeSessionWhoseRegistryIsIdleStopsAfterNinetySeconds() {
        store.apply(event(.turnStarted))
        store.updateRegistry([registryEntry(status: .idle)])
        elapse(89)
        #expect(state() == .working(tool: nil, summary: nil))
        elapse(1)
        #expect(state() == .idle)
    }

    @Test func aNewEventRestartsTheNinetySeconds() {
        store.apply(event(.turnStarted))
        store.updateRegistry([registryEntry(status: .idle)])
        elapse(60)
        store.apply(event(.toolStarted(name: "Bash", summary: nil)))
        elapse(60)
        #expect(state() == .working(tool: "Bash", summary: nil))
        elapse(30)
        #expect(state() == .idle)
    }

    @Test func aBusyRegistryKeepsALongTurnWorking() {
        store.apply(event(.turnStarted))
        store.updateRegistry([registryEntry(status: .busy)])
        elapse(600, step: 5)
        #expect(state() == .working(tool: nil, summary: nil))
    }

    @Test func aClaudeSessionWithoutRegistryInformationKeepsWorking() {
        store.apply(event(.turnStarted))
        store.updateRegistry([registryEntry(status: nil)])
        elapse(300, step: 5)
        #expect(state() == .working(tool: nil, summary: nil))
    }

    @Test func aWorkingCodexSessionHasNoRegistryAndStopsAfterNinetySeconds() {
        store.apply(event(.turnStarted, .codex))
        elapse(89)
        #expect(state("s1", .codex) == .working(tool: nil, summary: nil))
        elapse(1)
        #expect(state("s1", .codex) == .idle)
    }

    @Test func aTurnReplayedFromLongAgoIsNeverShownAsWorking() {
        store.apply([event(.turnStarted, .codex, age: 600), event(.toolStarted(name: "shell", summary: nil), .codex, age: 590)])
        #expect(state("s1", .codex) == .idle)
    }

    @Test func aReplayedClaudeTurnEndsAsSoonAsTheRegistryShowsItIdle() {
        store.apply(event(.turnStarted, age: 600))
        store.updateRegistry([registryEntry(status: .idle)])
        #expect(state() == .idle)
    }

    @Test func waitingForInputIsNotAnInterruptedTurn() {
        store.apply(event(.waitingForInput))
        store.updateRegistry([registryEntry(status: .idle)])
        elapse(300, step: 5)
        #expect(state() == .waitingForInput)
    }

    @Test func theFallbackCanBeDrivenByHandWithAnExplicitTime() {
        store.apply(event(.turnStarted, .codex))
        store.tick(now: clock.now + 89)
        #expect(state("s1", .codex) == .working(tool: nil, summary: nil))
        store.tick(now: clock.now + 90)
        #expect(state("s1", .codex) == .idle)
    }

    // MARK: Removal

    @Test func aSessionEndRemovesTheSession() {
        store.apply(event(.turnStarted))
        store.apply(event(.turnFinished))
        store.apply(event(.sessionEnded))
        #expect(session() == nil)
        elapse(10)
        #expect(session() == nil)
    }

    @Test func sessionsLeaveWhenTheRegistryStopsListingThem() {
        store.apply(event(.turnStarted, id: "gone"))
        store.apply(event(.turnStarted, id: "kept"))
        store.apply(event(.turnStarted, id: "unlisted"))
        store.apply(event(.turnStarted, .codex, id: "gone"))
        store.updateRegistry([registryEntry("gone", pid: 1), registryEntry("kept", pid: 2)])
        #expect(store.sessions.count == 4)
        store.updateRegistry([registryEntry("kept", pid: 2)])
        #expect(session("gone") == nil)
        #expect(session("kept") != nil)
        #expect(session("unlisted") != nil)
        #expect(session("gone", .codex) != nil)
    }

    @Test func aSessionWithoutEventsForTwoHoursIsRemoved() {
        store.apply(event(.turnStarted))
        store.apply(event(.turnFinished))
        elapse(7_199, step: 1)
        #expect(session() != nil)
        elapse(1)
        #expect(session() == nil)
    }

    @Test func aSessionWhoseOnlyEventsAreOlderThanTwoHoursIsNeverShown() {
        store.apply(event(.turnStarted, age: 3 * 3600))
        store.apply(event(.turnFinished, age: 3 * 3600 - 60))
        #expect(store.sessions.isEmpty)
    }

    @Test func usageOfAnOldSessionStillCountsToday() {
        // Three hours ago is 09:00 local time, so it is still today.
        store.apply(event(.usageUpdated, usage: claudeUsage("old", output: 42), age: 3 * 3600))
        #expect(store.sessions.isEmpty)
        #expect(store.todayUsage[.claude]?.tokens.output == 42)
    }

    @Test func disablingASourceRemovesItsSessions() {
        store.apply(event(.turnStarted, .claude, id: "a"))
        store.apply(event(.turnStarted, .codex, id: "b"))
        store.removeSessions(of: .claude)
        #expect(session("a") == nil)
        #expect(session("b", .codex) != nil)
    }

    @Test func theTimerStopsWhenNoSessionsAreLeft() {
        #expect(scheduler.pendingCount == 0)
        store.apply(event(.turnStarted))
        #expect(scheduler.pendingCount == 1)
        store.apply(event(.sessionEnded))
        #expect(scheduler.pendingCount == 0)
        store.apply(event(.turnStarted))
        store.apply(event(.turnStarted, id: "other"))
        #expect(scheduler.pendingCount == 1)
    }

    // MARK: Registry

    @Test func theRegistryAloneNeverCreatesASession() {
        store.updateRegistry([registryEntry()])
        #expect(store.sessions.isEmpty)
        #expect(scheduler.pendingCount == 0)
    }

    @Test func aBusyRegistryEntryNewerThanTheLastEventStartsWork() {
        store.apply(event(.turnStarted, age: 60))
        store.apply(event(.turnFinished, age: 50))
        #expect(state() == .idle)
        store.updateRegistry([registryEntry(status: .busy, statusUpdatedAt: clock.now - 10)])
        #expect(state() == .working(tool: nil, summary: nil))
        #expect(session()?.turnStartedAt == clock.now - 10)
    }

    @Test func aBusyRegistryEntryOlderThanTheLastEventDoesNotUndoAFinish() {
        store.apply(event(.turnStarted, age: 60))
        store.apply(event(.turnFinished, age: 5))
        elapse(5)
        #expect(state() == .idle)
        store.updateRegistry([registryEntry(status: .busy, statusUpdatedAt: clock.now - 20)])
        #expect(state() == .idle)
        store.updateRegistry([registryEntry(status: .busy, statusUpdatedAt: nil)])
        #expect(state() == .idle)
    }

    @Test func theRegistryDoesNotInterruptAWorkingOrWaitingSession() {
        store.apply(event(.toolStarted(name: "Bash", summary: "ls"), age: 30))
        store.updateRegistry([registryEntry(status: .busy, statusUpdatedAt: clock.now)])
        #expect(state() == .working(tool: "Bash", summary: "ls"))
        store.apply(event(.waitingForInput, age: 10))
        store.updateRegistry([registryEntry(status: .busy, statusUpdatedAt: clock.now)])
        #expect(state() == .waitingForInput)
    }

    @Test func theRegistryFillsInAMissingProjectOnly() {
        store.apply(event(.turnStarted, id: "bare"))
        store.apply(event(.sessionStarted(cwd: demoPath, branch: nil), id: "known"))
        store.updateRegistry([registryEntry("bare", cwd: "/Users/example/Projects/from-registry"), registryEntry("known", cwd: "/elsewhere")])
        #expect(session("bare")?.project == "from-registry")
        #expect(session("known")?.project == "demo")
    }
}

/// Lets a `@Sendable` observation callback record that it ran.
private nonisolated final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var isSet: Bool { lock.withLock { value } }

    func set() {
        lock.withLock { value = true }
    }
}
