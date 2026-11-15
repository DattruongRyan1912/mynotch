import Foundation
import MyNotchCore
import MyNotchTestSupport
import Testing
@testable import AIAgentsModule

/// Subagents and the agent's process in the store: counted by hooks only, timed out when a stop never comes.
@Suite struct AgentSessionStoreSubagentTests {
    let scheduler = ManualScheduler()
    let clock = TestClock(utc("2026-10-14T05:00:00Z"))
    let store: AgentSessionStore

    init() {
        let clock = clock
        store = AgentSessionStore(scheduler: scheduler, now: { clock.now }, calendar: hoChiMinhCalendar())
    }

    func event(_ kind: AgentEvent.Kind, _ source: AgentSource = .claude, subagent: String? = nil, pid: pid_t? = nil) -> AgentEvent {
        AgentEvent(source: source, sessionID: "s1", timestamp: clock.now, kind: kind, subagentID: subagent, pid: pid)
    }

    func hook(_ kind: AgentEvent.Kind, _ source: AgentSource = .claude, subagent: String? = nil, pid: pid_t? = nil) {
        store.apply([event(kind, source, subagent: subagent, pid: pid)], fromHooks: true)
    }

    func session(_ source: AgentSource = .claude) -> AgentSession? {
        store.sessions[AgentSessionKey(source: source, sessionID: "s1")]
    }

    func elapse(_ seconds: Int, step: Int = 10) {
        for _ in 0..<(seconds / step) {
            clock.advance(by: TimeInterval(step))
            scheduler.advance(by: .seconds(step))
        }
    }

    @Test func subagentsAreCountedFromStartToStop() {
        hook(.turnStarted)
        hook(.subagentStarted(type: "Explore"), subagent: "a1")
        hook(.subagentStarted(type: "Plan"), subagent: "a2")
        #expect(session()?.subagents.runningCount == 2)
        hook(.subagentStopped(type: "Explore"), subagent: "a1")
        #expect(session()?.subagents.runningCount == 1)
        #expect(session()?.subagents.lastFinished?.label == "Explore")
    }

    @Test func theCallsDescriptionNamesTheSubagentThatFollows() {
        hook(.toolStarted(name: "Agent", summary: "Find API endpoints"))
        hook(.subagentRequested(type: "Explore", description: "Find API endpoints"))
        hook(.subagentStarted(type: "Explore"), subagent: "a1")
        hook(.subagentStopped(type: "Explore"), subagent: "a1")
        #expect(session()?.subagents.lastFinished?.label == "Find API endpoints")
    }

    @Test func subagentEventsLeaveTheStateAsItIs() {
        hook(.turnStarted)
        hook(.toolStarted(name: "Agent", summary: "Look"))
        let working = session()?.state
        hook(.subagentStarted(type: "Explore"), subagent: "a1")
        #expect(session()?.state == working)
        hook(.waitingForInput)
        hook(.subagentStopped(type: "Explore"), subagent: "a1")
        #expect(session()?.state == .waitingForInput)
        hook(.turnFinished)
        #expect(session()?.state == .finished)
    }

    @Test func aBackgroundSubagentOutlivesTheTurnThatStartedIt() {
        hook(.turnStarted)
        hook(.subagentStarted(type: "Explore"), subagent: "a1")
        hook(.turnFinished)
        elapse(60)
        #expect(session()?.subagents.runningCount == 1)
        hook(.subagentStopped(type: "Explore"), subagent: "a1")
        #expect(session()?.subagents.runningCount == 0)
    }

    @Test func aStopThatNeverComesTimesOutAfterTheSilenceLimit() {
        hook(.turnStarted)
        hook(.subagentStarted(type: "Explore"), subagent: "a1")
        elapse(Int(SubagentTracker.silenceTimeout) - 10)
        #expect(session()?.subagents.runningCount == 1)
        elapse(20)
        #expect(session()?.subagents.runningCount == 0)
        #expect(session()?.subagents.lastFinished == nil)
    }

    @Test func aToolRunInsideTheSubagentShowsItIsStillAlive() {
        hook(.subagentStarted(type: "Explore"), subagent: "a1")
        elapse(Int(SubagentTracker.silenceTimeout) - 60)
        hook(.toolStarted(name: "Read", summary: "b.swift"), subagent: "a1")
        elapse(Int(SubagentTracker.silenceTimeout) - 60)
        #expect(session()?.subagents.runningCount == 1)
        elapse(Int(SubagentTracker.silenceTimeout))
        #expect(session()?.subagents.runningCount == 0)
    }

    @Test func aToolOfTheMainThreadDoesNotKeepASubagentAlive() {
        hook(.subagentStarted(type: "Explore"), subagent: "a1")
        for _ in 0..<(Int(SubagentTracker.silenceTimeout) / 60 + 1) {
            elapse(60)
            hook(.toolStarted(name: "Read", summary: nil))
        }
        #expect(session()?.subagents.runningCount == 0)
    }

    @Test func aSessionThatEndsTakesItsSubagentsWithIt() {
        hook(.subagentStarted(type: "Explore"), subagent: "a1")
        hook(.sessionEnded)
        #expect(session() == nil)
    }

    @Test func anInterruptedTurnEndsItsSubagentsButKeepsWhatFinished() {
        store.updateRegistry([ClaudeSessionInfo(pid: 100, sessionID: "s1", cwd: nil, status: .busy)])
        hook(.turnStarted)
        hook(.subagentStarted(type: "Plan"), subagent: "p")
        hook(.subagentStopped(type: "Plan"), subagent: "p")
        hook(.subagentStarted(type: "Explore"), subagent: "a1")
        store.updateRegistry([ClaudeSessionInfo(pid: 100, sessionID: "s1", cwd: nil, status: .idle)])
        elapse(Int(AgentSessionStore.interruptSeconds) + 10)
        #expect(session()?.state == .idle)
        #expect(session()?.subagents.runningCount == 0)
        #expect(session()?.subagents.lastFinished?.label == "Plan")
    }

    @Test func aSubagentOfOneSessionIsNotCountedInAnother() {
        hook(.subagentStarted(type: "Explore"), subagent: "a1")
        store.apply([AgentEvent(source: .claude, sessionID: "s2", timestamp: clock.now, kind: .turnStarted)], fromHooks: true)
        #expect(store.sessions[AgentSessionKey(source: .claude, sessionID: "s2")]?.subagents.runningCount == 0)
        #expect(session()?.subagents.runningCount == 1)
    }

    // MARK: The agent's process

    @Test func aHooksProcessIsTheSessionsProcess() {
        hook(.turnStarted, .codex, pid: 555)
        #expect(session(.codex)?.pid == 555)
        hook(.turnFinished, .codex, pid: 556)
        #expect(session(.codex)?.pid == 556)
        hook(.toolFinished, .codex)
        #expect(session(.codex)?.pid == 556)
    }

    @Test func claudesRegistryNamesItsProcessAndAHookDoesNotOverrideIt() {
        hook(.turnStarted, pid: 700)
        #expect(session()?.pid == 700)
        store.updateRegistry([ClaudeSessionInfo(pid: 100, sessionID: "s1", cwd: nil, status: .busy)])
        #expect(session()?.pid == 100)
        hook(.toolFinished, pid: 700)
        #expect(session()?.pid == 100)
    }

    @Test func theRegistryNeverCreatesASessionJustForItsProcess() {
        store.updateRegistry([ClaudeSessionInfo(pid: 100, sessionID: "nobody", cwd: nil, status: .busy)])
        #expect(store.sessions.isEmpty)
    }
}
