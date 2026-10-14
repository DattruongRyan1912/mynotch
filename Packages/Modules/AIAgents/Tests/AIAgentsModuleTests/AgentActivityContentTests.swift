import Foundation
import MyNotchCore
import Testing
@testable import AIAgentsModule

/// Which of the sessions the notch's live activity shows, and how.
@Suite struct AgentActivityContentTests {
    let t0 = utc("2026-10-14T05:00:00Z")

    func session(
        _ state: AgentState, id: String = "a", source: AgentSource = .claude, started: TimeInterval? = nil, last: TimeInterval = 0
    ) -> AgentSession {
        var result = AgentSession(key: AgentSessionKey(source: source, sessionID: id), lastEventAt: t0 + last)
        result.state = state
        result.turnStartedAt = started.map { t0 + $0 }
        return result
    }

    func content(_ sessions: [AgentSession], showWorking: Bool = true) -> AgentActivityContent? {
        AgentActivityContent(sessions: sessions, showWorking: showWorking)
    }

    @Test func noSessionsShowNothing() {
        #expect(content([]) == nil)
    }

    @Test func idleAndFailedSessionsShowNothing() {
        #expect(content([session(.idle, id: "a"), session(.error, id: "b")]) == nil)
    }

    @Test func aWorkingSessionShowsItsAgentAndWhenTheTurnBegan() {
        let working = AgentState.working(tool: "Bash", summary: "git status")
        #expect(content([session(working, id: "a", source: .codex, started: -30)]) == AgentActivityContent(kind: .working(since: t0 - 30), source: .codex))
    }

    @Test func theLongestRunningTurnWins() {
        let working = AgentState.working(tool: nil, summary: nil)
        let sessions = [
            session(working, id: "recent", source: .claude, started: -10),
            session(working, id: "old", source: .codex, started: -120),
            session(working, id: "middle", source: .claude, started: -60),
        ]
        #expect(content(sessions) == AgentActivityContent(kind: .working(since: t0 - 120), source: .codex))
    }

    @Test func aWorkingSessionWithoutATurnStartCountsFromItsLastEvent() {
        let working = AgentState.working(tool: nil, summary: nil)
        #expect(content([session(working, id: "a", started: nil, last: -15)])?.kind == .working(since: t0 - 15))
    }

    @Test func waitingBeatsWorkingAndRunsAtHighPriority() {
        let sessions = [
            session(.working(tool: nil, summary: nil), id: "busy", source: .claude, started: -300),
            session(.waitingForInput, id: "asking", source: .codex, started: -20),
        ]
        let result = content(sessions)
        #expect(result == AgentActivityContent(kind: .waitingForInput, source: .codex))
        #expect(result?.priority == .high)
    }

    @Test func workingRunsAtLowPriorityAndFinishedAtNormal() {
        #expect(content([session(.working(tool: nil, summary: nil), id: "a", started: -5)])?.priority == .low)
        #expect(content([session(.finished, id: "a")])?.priority == .normal)
    }

    @Test func aFinishedTurnShowsTheCheckmark() {
        #expect(content([session(.finished, id: "a", source: .codex), session(.idle, id: "b")]) == AgentActivityContent(kind: .finished, source: .codex))
    }

    @Test func workingBeatsFinished() {
        let sessions = [session(.finished, id: "done", source: .claude), session(.working(tool: nil, summary: nil), id: "busy", source: .codex, started: -5)]
        #expect(content(sessions)?.kind == .working(since: t0 - 5))
    }

    @Test func theMostRecentOfSeveralWaitingOrFinishedSessionsWins() {
        let waiting = [session(.waitingForInput, id: "a", source: .claude, last: -30), session(.waitingForInput, id: "b", source: .codex, last: -5)]
        #expect(content(waiting)?.source == .codex)
        let finished = [session(.finished, id: "a", source: .claude, last: -2), session(.finished, id: "b", source: .codex, last: -9)]
        #expect(content(finished)?.source == .claude)
    }

    @Test func switchingWorkingOffHidesOnlyTheWorkingActivity() {
        let working = session(.working(tool: nil, summary: nil), id: "busy", source: .claude, started: -5)
        #expect(content([working], showWorking: false) == nil)
        #expect(content([working, session(.waitingForInput, id: "asking", source: .codex)], showWorking: false)?.kind == .waitingForInput)
        #expect(content([working, session(.finished, id: "done", source: .codex)], showWorking: false)?.kind == .finished)
    }
}
