import Foundation
import MyNotchTestSupport
import Testing
@testable import AIAgentsModule

/// What the AI tab lists, as text and numbers, before any view draws it.
@Suite struct AgentTabStateTests {
    let now = utc("2026-10-14T05:00:00Z")
    let calendar = hoChiMinhCalendar()

    func session(
        _ state: AgentState = .idle, id: String = "s1", source: AgentSource = .claude, cwd: String? = "/Users/example/Projects/demo",
        branch: String? = "main", started: TimeInterval? = nil, last: TimeInterval = 0
    ) -> AgentSession {
        var result = AgentSession(key: AgentSessionKey(source: source, sessionID: id), lastEventAt: now + last)
        result.cwd = cwd
        result.branch = branch
        result.state = state
        result.turnStartedAt = started.map { now + $0 }
        return result
    }

    func state(_ sessions: [AgentSession] = [], usage: [AgentSource: AgentDayUsage] = [:]) -> AgentTabState {
        AgentTabState(sessions: sessions, dayUsage: usage, now: now, calendar: calendar)
    }

    // MARK: Rows

    @Test func noSessionsMeansTheEmptyState() {
        let empty = state()
        #expect(empty.isEmpty)
        #expect(empty.rows.isEmpty)
        #expect(empty.usage.isEmpty)
        #expect(empty.limits.isEmpty)
        #expect(AgentTabState.emptyMessage == "Không có phiên Claude Code hay Codex nào đang chạy")
    }

    @Test func aWorkingSessionShowsItsProjectBranchToolAndALiveTimer() {
        let working = session(.working(tool: "Bash", summary: "git status"), started: -90)
        let row = state([working]).rows.first
        #expect(row?.source == .claude)
        #expect(row?.title == "demo • main")
        #expect(row?.status == .working)
        #expect(row?.detail == "Bash · git status")
        #expect(row?.timing == .running(since: now - 90))
        #expect(row?.cwd == "/Users/example/Projects/demo")
    }

    @Test func aRowWithoutABranchShowsTheProjectAlone() {
        #expect(state([session(branch: nil)]).rows.first?.title == "demo")
    }

    @Test func aRowWithoutAWorkingDirectoryIsNamedByItsSessionID() {
        let row = state([session(id: "0123abcd-4567-4def-8901-234567890abc", cwd: nil, branch: nil)]).rows.first
        #expect(row?.title == "Phiên 0123abcd")
        #expect(row?.cwd == nil)
    }

    @Test func aToolWithoutASummaryShowsOnlyItsName() {
        #expect(state([session(.working(tool: "Read", summary: nil))]).rows.first?.detail == "Read")
    }

    @Test func anAgentThatIsThinkingShowsNoTool() {
        #expect(state([session(.working(tool: nil, summary: nil))]).rows.first?.detail == nil)
    }

    @Test func onlyAWorkingSessionShowsATool() {
        for other in [AgentState.waitingForInput, .finished, .idle, .error] {
            #expect(state([session(other)]).rows.first?.detail == nil)
        }
    }

    @Test func everyStateHasItsLabel() {
        #expect(AgentTabState.Status.working.label == "Đang chạy")
        #expect(AgentTabState.Status.waitingForInput.label == "Chờ bạn")
        #expect(AgentTabState.Status.finished.label == "Xong")
        #expect(AgentTabState.Status.idle.label == "Rảnh")
        #expect(AgentTabState.Status.error.label == "Lỗi")
        let states: [AgentState] = [.working(tool: nil, summary: nil), .waitingForInput, .finished, .idle, .error]
        let statuses: [AgentTabState.Status] = [.working, .waitingForInput, .finished, .idle, .error]
        let sessions = states.enumerated().map { session($1, id: "s\($0)") }
        #expect(state(sessions).rows.map(\.status) == statuses)
    }

    @Test func aTurnThatEndedShowsHowLongItTook() {
        for ended in [AgentState.finished, .idle, .error] {
            #expect(state([session(ended, started: -150, last: -30)]).rows.first?.timing == .took(120))
        }
    }

    @Test func aWaitingSessionKeepsCountingItsTurn() {
        #expect(state([session(.waitingForInput, started: -20)]).rows.first?.timing == .running(since: now - 20))
    }

    @Test func noTurnMeansNoTime() {
        #expect(state([session(.idle, started: nil)]).rows.first?.timing == AgentTabState.Timing.unknown)
        #expect(state([session(.working(tool: nil, summary: nil), started: nil)]).rows.first?.timing == AgentTabState.Timing.unknown)
    }

    @Test func rowsKeepTheOrderTheyAreGivenIn() {
        let sessions = [session(id: "b", source: .codex, cwd: "/tmp/tool", branch: nil), session(id: "a")]
        #expect(state(sessions).rows.map(\.title) == ["tool", "demo • main"])
        #expect(state(sessions).rows.map(\.id) == sessions.map(\.key))
    }

    // MARK: Usage footer

    @Test func todaysTokensAndCostAreListedPerAgent() {
        let usage: [AgentSource: AgentDayUsage] = [
            .claude: AgentDayUsage(tokens: UsageTotals(input: 1_000, output: 200_000, cacheRead: 1_000_000, cacheWrite: 33_000), estimatedCostUSD: 3.456),
            .codex: AgentDayUsage(tokens: UsageTotals(input: 5_000, output: 800), estimatedCostUSD: 0.05),
        ]
        let lines = state(usage: usage).usage
        #expect(lines.map(\.source) == [.claude, .codex])
        #expect(lines.map(\.tokens) == ["1.2M", "5.8K"])
        #expect(lines.map(\.cost) == ["$3.46", "$0.05"])
        #expect(lines.allSatisfy { $0.isEstimated })
    }

    @Test func tokensOfAnUnpricedModelShowADashForTheCost() {
        let usage: [AgentSource: AgentDayUsage] = [.codex: AgentDayUsage(tokens: UsageTotals(input: 4_000), estimatedCostUSD: nil)]
        let line = state(usage: usage).usage.first
        #expect(line?.tokens == "4K")
        #expect(line?.cost == "—")
        #expect(line?.isEstimated == false)
    }

    @Test func anAgentWithoutUsageTodayHasNoLine() {
        let usage: [AgentSource: AgentDayUsage] = [.claude: AgentDayUsage(tokens: UsageTotals(), estimatedCostUSD: nil)]
        #expect(state(usage: usage).usage.isEmpty)
    }

    @Test func todaysUsageStartsOverAtMidnightWithoutAnyNewEvent() {
        let clock = TestClock(utc("2026-10-14T16:50:00Z"))
        let store = AgentSessionStore(scheduler: ManualScheduler(), now: { clock.now }, calendar: calendar)
        let usage = AgentUsage(output: 100, model: "claude-opus-4-1", messageID: "m1")
        store.apply(AgentEvent(source: .claude, sessionID: "s1", timestamp: clock.now, kind: .usageUpdated, usage: usage))
        #expect(AgentTabState(store: store, now: clock.now).usage.map(\.tokens) == ["100"])
        // Ten minutes after local midnight: the tab is drawn again from the clock alone.
        #expect(AgentTabState(store: store, now: clock.now + 20 * 60).usage.isEmpty)
    }

    @Test func usageStillShowsWithNoSessions() {
        let usage: [AgentSource: AgentDayUsage] = [.claude: AgentDayUsage(tokens: UsageTotals(output: 10), estimatedCostUSD: 0.001)]
        let result = state(usage: usage)
        #expect(result.isEmpty)
        #expect(result.usage.first?.cost == "<$0.01")
    }

    // MARK: Rate limits

    func limits(primary: AgentRateLimits.Window? = nil, secondary: AgentRateLimits.Window? = nil) -> AgentRateLimits {
        AgentRateLimits(primary: primary, secondary: secondary)
    }

    func codex(_ id: String, last: TimeInterval, limits: AgentRateLimits?) -> AgentSession {
        var result = session(id: id, source: .codex, last: last)
        result.rateLimits = limits
        return result
    }

    @Test func codexRateLimitsShowUsedPercentAndResetTime() {
        let limits = limits(
            primary: .init(usedPercent: 42.4, windowMinutes: 300, resetsAt: utc("2026-10-14T08:30:00Z")),
            secondary: .init(usedPercent: 7, windowMinutes: 10_080, resetsAt: utc("2026-10-18T02:00:00Z"))
        )
        let bars = state([codex("c", last: 0, limits: limits)]).limits
        #expect(bars.map(\.label) == ["5 giờ", "Tuần"])
        #expect(bars.map(\.percent) == [42, 7])
        #expect(bars.map(\.resets) == ["15:30", "CN 09:00"])
    }

    @Test func theLimitsComeFromTheCodexSessionHeardFromLast() {
        let older = limits(primary: .init(usedPercent: 10, windowMinutes: 300, resetsAt: now + 3_600))
        let newer = limits(primary: .init(usedPercent: 60, windowMinutes: 300, resetsAt: now + 3_600))
        let sessions = [codex("old", last: -600, limits: older), codex("new", last: -5, limits: newer), codex("none", last: 0, limits: nil)]
        #expect(state(sessions).limits.map(\.percent) == [60])
    }

    @Test func aWindowThatHasResetIsLeftOut() {
        let limits = limits(
            primary: .init(usedPercent: 95, windowMinutes: 300, resetsAt: now - 1),
            secondary: .init(usedPercent: 20, windowMinutes: 10_080, resetsAt: now + 86_400)
        )
        #expect(state([codex("c", last: 0, limits: limits)]).limits.map(\.label) == ["Tuần"])
    }

    @Test func aWindowWithoutAResetTimeStaysWithoutIt() {
        let limits = limits(primary: .init(usedPercent: 30, windowMinutes: 300, resetsAt: nil))
        let bar = state([codex("c", last: 0, limits: limits)]).limits.first
        #expect(bar?.percent == 30)
        #expect(bar?.resets == nil)
    }

    @Test func windowsWithoutALengthAreNamedByTheirSlot() {
        let limits = limits(primary: .init(usedPercent: 1, windowMinutes: nil, resetsAt: nil), secondary: .init(usedPercent: 2, windowMinutes: nil, resetsAt: nil))
        #expect(state([codex("c", last: 0, limits: limits)]).limits.map(\.label) == ["Ngắn hạn", "Dài hạn"])
    }

    @Test func percentagesStayWithinZeroAndAHundred() {
        let limits = limits(primary: .init(usedPercent: 140, windowMinutes: 300, resetsAt: nil), secondary: .init(usedPercent: -3, windowMinutes: 10_080, resetsAt: nil))
        #expect(state([codex("c", last: 0, limits: limits)]).limits.map(\.percent) == [100, 0])
    }

    @Test func noCodexLimitsMeansNoBars() {
        #expect(state([session(id: "a")]).limits.isEmpty)
        #expect(state([codex("c", last: 0, limits: AgentRateLimits())]).limits.isEmpty)
    }
}
