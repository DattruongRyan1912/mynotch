import AgentHookKit
import Foundation
import MyNotchCore
import Testing
@testable import AIAgentsModule

/// Permission requests through the module: the helper's own client on a real socket, the queue, the card and the
/// answers. `PermissionClient` is what the `mynotch-hook` helper calls, so this is the helper's side too.
extension AIAgentsModuleTests {
    var permissionSocketPath: String { AgentSocket.permissionPath(besides: socketPath) }
    var queue: PermissionQueue { module.permissions! }

    func requestPayload(_ session: String = "s1", tool: String = "Bash", summary: String? = "npm test", source: String = "claude") -> HookPayload {
        HookPayload(source: source, event: "PermissionRequest", sessionID: session, cwd: "/Users/x/Project/MyNotch", tool: tool, summary: summary, timestamp: Date())
    }

    /// The helper asks, off the main actor, and waits.
    func ask(_ payload: HookPayload? = nil, timeout: TimeInterval = 10) -> Task<PermissionClient.Outcome, Never> {
        let payload = payload ?? requestPayload()
        let path = permissionSocketPath
        return runBlocking { PermissionClient.ask(payload, socketPath: path, timeout: timeout) }
    }

    /// Polls for what has to come through the socket and the main queue, with room for a loaded machine.
    func eventually(_ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }

    /// The request on screen; the test fails, and does not crash, when there is none.
    func head() throws -> PermissionRequest {
        try #require(queue.pending.first)
    }

    func startListening() async {
        harness.settings.set(true, for: keys.preciseStatus)
        await start()
        _ = await eventually { FileManager.default.fileExists(atPath: permissionSocketPath) }
    }

    func sendToolHook(_ event: String, tool: String, id: String = "s1") throws {
        let payload = HookPayload(source: "claude", event: event, sessionID: id, tool: tool, timestamp: Date())
        HookDatagramSender.send(try #require(payload.encodedDatagram()), to: socketPath)
    }

    // MARK: The card

    @Test func aRequestShowsTheCardAndTheSessionWaits() async throws {
        await startListening()
        let outcome = ask()
        #expect(await eventually { queue.pending.count == 1 })
        _ = await eventually { module.publishedActivity?.ask != nil }
        let shown = try #require(module.publishedActivity)
        #expect(shown.kind == .waitingForInput)
        #expect(shown.ask?.request.tool == "Bash")
        #expect(shown.ask?.request.summary == "npm test")
        #expect(shown.ask?.others == 0)
        let activity = try #require(current?.activity)
        #expect(activity.priority == .critical)
        #expect(activity.hasBottom)
        #expect(activity.bottomHeight == PermissionCard.stripHeight)
        #expect(activity.summary?.contains("Bash") == true)
        #expect(store.sessions[key()]?.state == .waitingForInput)
        #expect(alerts.count == 1)
        queue.cancelAll()
        _ = await outcome.value
    }

    @Test func aRequestFromAnOldHelperThatOnlySendsTheDatagramMakesNoCard() async throws {
        await startListening()
        try sendHook("PermissionRequest")
        #expect(await eventually { store.sessions[key()]?.state == .waitingForInput })
        #expect(queue.pending.isEmpty)
        #expect(alerts.count == 0)
        _ = await eventually { module.publishedActivity != nil }
        #expect(module.publishedActivity?.ask == nil)
        #expect(current?.activity.hasBottom == false)
    }

    @Test func severalRequestsQueueAndTheNextCardComesUpWhenTheFirstIsDecided() async throws {
        await startListening()
        let first = ask(requestPayload("a", tool: "Bash", summary: "one"))
        #expect(await eventually { queue.pending.count == 1 })
        let second = ask(requestPayload("b", tool: "Edit", summary: "two"))
        #expect(await eventually { queue.pending.count == 2 })
        _ = await eventually { module.publishedActivity?.ask?.others == 1 }
        #expect(module.publishedActivity?.ask?.request.tool == "Bash")
        #expect(module.publishedActivity?.ask?.others == 1)
        #expect(alerts.count == 2)

        module.decide(try head().id, .allow)
        #expect(await first.value == .answered(.allow))
        _ = await eventually { module.publishedActivity?.ask?.request.tool == "Edit" }
        #expect(module.publishedActivity?.ask?.request.tool == "Edit")
        #expect(module.publishedActivity?.ask?.others == 0)

        module.decide(try head().id, .deny)
        #expect(await second.value == .answered(.deny))
        #expect(queue.pending.isEmpty)
    }

    // MARK: Answers

    @Test func allowingAnswersTheHelperAndTheSessionRunsTheTool() async throws {
        await startListening()
        let outcome = ask()
        #expect(await eventually { queue.pending.count == 1 })
        module.decide(try head().id, .allow)
        #expect(await outcome.value == .answered(.allow))
        #expect(queue.pending.isEmpty)
        #expect(store.sessions[key()]?.state == .working(tool: "Bash", summary: "npm test"))
        _ = await eventually { module.publishedActivity?.ask == nil }
        #expect(module.publishedActivity?.ask == nil)
        #expect(module.publishedActivity?.kind != .waitingForInput)
    }

    @Test func denyingAnswersTheHelperAndTheAgentGoesOnThinking() async throws {
        await startListening()
        let outcome = ask()
        #expect(await eventually { queue.pending.count == 1 })
        module.decide(try head().id, .deny)
        #expect(await outcome.value == .answered(.deny))
        #expect(store.sessions[key()]?.state == .working(tool: nil, summary: nil))
    }

    @Test func askingInTheTerminalLeavesTheSessionWaitingAndTheCardGone() async throws {
        await startListening()
        let outcome = ask()
        #expect(await eventually { queue.pending.count == 1 })
        module.decide(try head().id, .ask)
        #expect(await outcome.value == .answered(.ask))
        #expect(queue.pending.isEmpty)
        #expect(store.sessions[key()]?.state == .waitingForInput)
        _ = await eventually { module.publishedActivity?.ask == nil }
        #expect(module.publishedActivity?.kind == .waitingForInput)
        #expect(module.publishedActivity?.ask == nil)
    }

    @Test func aDecisionForAnIdThatIsNotPendingChangesNothing() async throws {
        await startListening()
        let outcome = ask()
        #expect(await eventually { queue.pending.count == 1 })
        let id = try head().id
        module.decide("00000000-0000-4000-8000-000000000000", .allow)
        module.decide(id.lowercased() + "0", .allow)
        #expect(queue.pending.count == 1)
        #expect(store.sessions[key()]?.state == .waitingForInput)
        module.decide(id, .deny)
        #expect(await outcome.value == .answered(.deny))
        // Already decided: a second decision, as from a double click, is not routed anywhere.
        module.decide(id, .allow)
        #expect(store.sessions[key()]?.state == .working(tool: nil, summary: nil))
    }

    // MARK: When there is no card

    @Test func theSoundIsASettingThatIsOnByDefault() async throws {
        #expect(harness.settingsEnvironment(for: "aiagents")!.settings.value(keys.soundOnRequest))
        harness.settings.set(false, for: keys.soundOnRequest)
        await startListening()
        let outcome = ask()
        #expect(await eventually { queue.pending.count == 1 })
        #expect(alerts.count == 0)
        module.decide(try head().id, .allow)
        _ = await outcome.value
    }

    @Test func anAgentThatIsTurnedOffGetsNoCardAndIsToldToAskInTheTerminal() async throws {
        harness.settings.set(false, for: keys.claudeEnabled)
        await startListening()
        let outcome = ask()
        #expect(await outcome.value == .answered(.ask))
        #expect(queue.pending.isEmpty)
        #expect(alerts.count == 0)
        #expect(store.sessions[key()] == nil)
    }

    @Test func aCodexRequestGetsACardToo() async throws {
        await startListening()
        let outcome = ask(requestPayload("c1", tool: "apply_patch", summary: nil, source: "codex"))
        #expect(await eventually { queue.pending.count == 1 })
        #expect(try head().source == .codex)
        module.decide(try head().id, .allow)
        #expect(await outcome.value == .answered(.allow))
        #expect(store.sessions[key("c1", .codex)]?.state == .working(tool: "apply_patch", summary: nil))
    }

    // MARK: The request ends without the notch

    @Test func aHelperThatGaveUpTakesItsCardAway() async throws {
        await startListening()
        // A helper by hand, so it is the test that decides when it leaves, after the card was seen.
        let line = Array(try #require(PermissionWire.requestLine(requestPayload())))
        let helper = try connectRaw(to: permissionSocketPath, send: line)
        #expect(await eventually { queue.pending.count == 1 })
        close(helper)
        #expect(await eventually { queue.pending.isEmpty })
        _ = await eventually { module.publishedActivity?.ask == nil }
        #expect(module.publishedActivity?.ask == nil)
    }

    @Test func theToolRunningElsewhereTakesItsCardAwayAndTheHelperIsToldToLetTheAgentAsk() async throws {
        await startListening()
        let outcome = ask()
        #expect(await eventually { queue.pending.count == 1 })
        // The user allowed it in the terminal; another tool finishing does not count.
        try sendToolHook("PostToolUse", tool: "Edit")
        try sendToolHook("PostToolUse", tool: "Bash", id: "other-session")
        try await Task.sleep(for: .milliseconds(150))
        #expect(queue.pending.count == 1)
        try sendToolHook("PostToolUse", tool: "Bash")
        #expect(await outcome.value == .answered(.ask))
        #expect(await eventually { queue.pending.isEmpty })
    }

    @Test func theTurnEndingTakesItsCardAway() async throws {
        await startListening()
        let outcome = ask()
        #expect(await eventually { queue.pending.count == 1 })
        try sendHook("Stop")
        #expect(await outcome.value == .answered(.ask))
        #expect(await eventually { queue.pending.isEmpty })
    }

    @Test func aRequestNobodyAnswersEndsWhenItsTimeIsUp() async throws {
        await startListening()
        let outcome = ask()
        #expect(await eventually { queue.pending.count == 1 })
        harness.scheduler.advance(by: PermissionQueue.lifetime + .seconds(1))
        #expect(await outcome.value == .answered(.ask))
        #expect(queue.pending.isEmpty)
    }

    @Test func turningPreciseStatusOffEndsTheRequestsAndClosesTheSocket() async throws {
        await startListening()
        let outcome = ask()
        #expect(await eventually { queue.pending.count == 1 })
        harness.settings.set(false, for: keys.preciseStatus)
        #expect(await outcome.value == .answered(.ask))
        #expect(await eventually { !FileManager.default.fileExists(atPath: permissionSocketPath) })
        #expect(queue.pending.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: socketPath))
    }

    @Test func stoppingTheModuleEndsTheRequests() async throws {
        await startListening()
        let outcome = ask()
        #expect(await eventually { queue.pending.count == 1 })
        await harness.registry.setEnabled(false, for: "aiagents")
        #expect(await outcome.value == .answered(.ask))
        #expect(!FileManager.default.fileExists(atPath: permissionSocketPath))
        #expect(module.permissions == nil)
        #expect(current == nil)
    }

    @Test func theSocketsAreOnlyOpenWhilePreciseStatusIsOn() async {
        await start()
        #expect(!FileManager.default.fileExists(atPath: permissionSocketPath))
        harness.settings.set(true, for: keys.preciseStatus)
        #expect(await eventually { FileManager.default.fileExists(atPath: permissionSocketPath) })
        let mode = try? FileManager.default.attributesOfItem(atPath: permissionSocketPath)[.posixPermissions] as? Int
        #expect(mode == 0o600)
    }

    // MARK: Nothing of the conversation

    @Test func theCardHoldsOnlyTheToolTheSummaryAndTheFolder() async throws {
        await startListening()
        let hook = Data("""
        {"hook_event_name":"PermissionRequest","session_id":"s1","cwd":"/Users/x/Project/MyNotch","tool_name":"Bash",
         "tool_input":{"command":"npm test\\nSECRET second line"},"prompt":"SECRET PROMPT"}
        """.utf8)
        let payload = try #require(HookPayloadFilter.make(source: "claude", hookJSON: hook, now: Date()))
        let outcome = ask(payload)
        #expect(await eventually { queue.pending.count == 1 })
        let request = try head()
        let described = String(describing: request) + String(describing: module.publishedActivity as Any)
        #expect(!described.contains("SECRET"))
        #expect(request.summary == "npm test")
        module.decide(request.id, .ask)
        _ = await outcome.value
    }
}
