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

    func payload(_ event: String, source: String = "claude", tool: String? = nil, summary: String? = nil, type: String? = nil) -> HookPayload {
        HookPayload(source: source, event: event, sessionID: "s1", tool: tool, summary: summary, notificationType: type, timestamp: clock.now)
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
}
