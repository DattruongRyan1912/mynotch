import AgentHookKit
import Foundation
import MyNotchCore
import MyNotchTestSupport
import Testing
@testable import AIAgentsModule

/// Hook payloads turned into the events the store takes, and the store's states they lead to.
@Suite struct HookEventMappingTests {
    let clock = TestClock(utc("2026-10-14T05:00:00Z"))
    let store: AgentSessionStore

    init() {
        let clock = clock
        store = AgentSessionStore(scheduler: ManualScheduler(), now: { clock.now }, calendar: hoChiMinhCalendar())
    }

    func payload(
        _ event: String, source: String = "claude", tool: String? = nil, summary: String? = nil, type: String? = nil,
        agentID: String? = nil, agentType: String? = nil, processID: Int32? = nil
    ) -> HookPayload {
        HookPayload(
            source: source, event: event, sessionID: "s1", tool: tool, summary: summary, notificationType: type, timestamp: clock.now,
            agentID: agentID, agentType: agentType, processID: processID
        )
    }

    func feed(_ payloads: HookPayload...) {
        for payload in payloads { store.apply(payload.agentEvents) }
    }

    var state: AgentState? { store.sessions[AgentSessionKey(source: .claude, sessionID: "s1")]?.state }

    @Test func eachHookEventMapsToItsKind() {
        #expect(payload("UserPromptSubmit").agentEvents.map(\.kind) == [.turnStarted])
        #expect(payload("PreToolUse", tool: "Bash", summary: "ls").agentEvents.map(\.kind) == [.toolStarted(name: "Bash", summary: "ls")])
        #expect(payload("PostToolUse", tool: "Bash").agentEvents.map(\.kind) == [.toolFinished])
        #expect(payload("PermissionRequest").agentEvents.map(\.kind) == [.waitingForInput])
        #expect(payload("Stop").agentEvents.map(\.kind) == [.turnFinished])
        #expect(payload("StopFailure").agentEvents.map(\.kind) == [.turnFailed])
        #expect(payload("SessionEnd").agentEvents.map(\.kind) == [.sessionEnded])
    }

    @Test func onlyPermissionAndElicitationNotificationsWait() {
        #expect(payload("Notification", type: "permission_prompt").agentEvents.map(\.kind) == [.waitingForInput])
        #expect(payload("Notification", type: "elicitation_dialog").agentEvents.map(\.kind) == [.waitingForInput])
        #expect(payload("Notification", type: "idle_prompt").agentEvents.isEmpty)
        #expect(payload("Notification").agentEvents.isEmpty)
        #expect(payload("SomethingNew").agentEvents.isEmpty)
    }

    @Test func theEventKeepsTheSourceSessionAndTime() throws {
        let event = try #require(payload("Stop", source: "codex").agentEvents.first)
        #expect(event.source == .codex)
        #expect(event.sessionID == "s1")
        #expect(event.timestamp == clock.now)
        #expect(payload("Stop", source: "gemini").agentEvents.isEmpty)
    }

    @Test func aPermissionRequestPutsTheSessionInWaitingUntilTheToolRuns() {
        feed(payload("UserPromptSubmit"), payload("PreToolUse", tool: "Bash", summary: "rm x"))
        #expect(state == .working(tool: "Bash", summary: "rm x"))
        feed(payload("PermissionRequest"))
        #expect(state == .waitingForInput)
        feed(payload("PostToolUse", tool: "Bash"))
        #expect(state == .working(tool: nil, summary: nil))
    }

    @Test func stopFinishesTheTurnOnceEvenWhenRepeated() {
        feed(payload("UserPromptSubmit"), payload("Stop"), payload("Stop"))
        #expect(state == .finished)
    }

    @Test func aFailureShowsAnErrorAndSessionEndRemovesTheSession() {
        feed(payload("UserPromptSubmit"), payload("StopFailure"))
        #expect(state == .error)
        feed(payload("SessionEnd"))
        #expect(state == nil)
    }

    // MARK: Subagents

    var session: AgentSession? { store.sessions[AgentSessionKey(source: .claude, sessionID: "s1")] }

    @Test func subagentStartAndStopMapToTheirKindsWithTheAgentId() throws {
        let start = try #require(payload("SubagentStart", agentID: "a1", agentType: "Explore").agentEvents.first)
        #expect(start.kind == .subagentStarted(type: "Explore"))
        #expect(start.subagentID == "a1")
        let stop = try #require(payload("SubagentStop", source: "codex", agentID: "a1", agentType: "worker").agentEvents.first)
        #expect(stop.kind == .subagentStopped(type: "worker"))
        #expect(stop.source == .codex)
        #expect(payload("SubagentStart", agentID: "a1").agentEvents.map(\.kind) == [.subagentStarted(type: nil)])
    }

    @Test func aSubagentEventWithoutAnAgentIdIsIgnored() {
        #expect(payload("SubagentStart", agentType: "Explore").agentEvents.isEmpty)
        #expect(payload("SubagentStop").agentEvents.isEmpty)
    }

    @Test func anAgentCallIsAToolAndAlsoTellsWhatTheNextSubagentIsFor() {
        for tool in ["Agent", "Task"] {
            let kinds = payload("PreToolUse", tool: tool, summary: "Find API endpoints", agentType: "Explore").agentEvents.map(\.kind)
            #expect(kinds == [.toolStarted(name: tool, summary: "Find API endpoints"), .subagentRequested(type: "Explore", description: "Find API endpoints")])
        }
        #expect(payload("PreToolUse", tool: "Agent", summary: "Look").agentEvents.map(\.kind) == [
            .toolStarted(name: "Agent", summary: "Look"), .subagentRequested(type: nil, description: "Look"),
        ])
    }

    @Test func anAgentCallWithoutADescriptionAndOtherToolsAreOnlyTools() {
        #expect(payload("PreToolUse", tool: "Agent").agentEvents.map(\.kind) == [.toolStarted(name: "Agent", summary: nil)])
        #expect(payload("PreToolUse", tool: "Bash", summary: "ls", agentType: "Explore").agentEvents.map(\.kind) == [.toolStarted(name: "Bash", summary: "ls")])
        #expect(payload("PostToolUse", tool: "Agent", summary: "Look").agentEvents.map(\.kind) == [.toolFinished])
    }

    @Test func everyEventOfASubagentCarriesItsIdAndEveryEventTheProcess() throws {
        let tool = try #require(payload("PreToolUse", tool: "Read", agentID: "a1", processID: 4_242).agentEvents.first)
        #expect(tool.subagentID == "a1")
        #expect(tool.pid == 4_242)
        let main = try #require(payload("Stop").agentEvents.first)
        #expect(main.subagentID == nil)
        #expect(main.pid == nil)
        #expect(try #require(payload("Stop", processID: 1).agentEvents.first).pid == nil)
        #expect(try #require(payload("Stop", processID: -5).agentEvents.first).pid == nil)
    }

    @Test func theAppCleansWhatAHelperThatDidNotSent() throws {
        let long = String(repeating: "x", count: 500)
        let start = try #require(payload("SubagentStart", agentID: "a\u{202E}1" + long, agentType: "E\u{200B}x").agentEvents.first)
        #expect(start.kind == .subagentStarted(type: "E\u{FFFD}x"))
        #expect(start.subagentID?.hasPrefix("a\u{FFFD}1") == true)
        #expect((start.subagentID?.count ?? 0) <= HookPayload.maxAgentFieldLength)
        let call = try #require(payload("PreToolUse", tool: "Agent", summary: "a\u{202E}b\nc" + long).agentEvents.last)
        guard case let .subagentRequested(_, description) = call.kind else { Issue.record("not a request"); return }
        #expect(description.hasPrefix("a\u{FFFD}b c"))
        #expect(description.count <= HookPayload.maxSummaryLength)
    }

    @Test func aSubagentRunsFromItsStartToItsStopWithoutChangingTheSessionsState() {
        feed(payload("UserPromptSubmit"), payload("PreToolUse", tool: "Agent", summary: "Find API endpoints", agentType: "Explore"))
        let working = state
        feed(payload("SubagentStart", agentID: "a1", agentType: "Explore"))
        #expect(session?.subagents.runningCount == 1)
        #expect(state == working)
        feed(payload("PreToolUse", tool: "Read", summary: "b.swift", agentID: "a1"))
        feed(payload("SubagentStop", agentID: "a1", agentType: "Explore"))
        #expect(session?.subagents.runningCount == 0)
        #expect(session?.subagents.lastFinished?.label == "Find API endpoints")
    }

    @Test func codexSubagentsAreCountedToo() {
        let codex = AgentSessionKey(source: .codex, sessionID: "s1")
        store.apply(payload("SubagentStart", source: "codex", agentID: "w1", agentType: "worker").agentEvents, fromHooks: true)
        #expect(store.sessions[codex]?.subagents.runningCount == 1)
        store.apply(payload("SubagentStop", source: "codex", agentID: "w1", agentType: "worker").agentEvents, fromHooks: true)
        #expect(store.sessions[codex]?.subagents.lastFinished?.label == "worker")
    }
}
