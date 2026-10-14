import AgentHookKit
import Foundation
import MyNotchTestSupport
import Testing
@testable import AIAgentsModule

@Suite struct PermissionQueueTests {
    let scheduler = ManualScheduler()
    let replies = Replies()
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    /// What the queue told the helpers behind the requests, in order, by request.
    final class Replies {
        var all: [String: [PermissionAnswer]] = [:]
        func record(_ name: String) -> (PermissionAnswer) -> Void { { [self] in all[name, default: []].append($0) } }
    }

    func queue(lifetime: Duration = .seconds(65)) -> PermissionQueue {
        PermissionQueue(scheduler: scheduler, lifetime: lifetime)
    }

    func payload(
        _ session: String = "s1", tool: String = "Bash", summary: String? = "ls", source: String = "claude", cwd: String? = "/Users/x/Project/MyNotch"
    ) -> HookPayload {
        HookPayload(source: source, event: "PermissionRequest", sessionID: session, cwd: cwd, tool: tool, summary: summary, timestamp: now)
    }

    @discardableResult
    func add(_ queue: PermissionQueue, _ payload: HookPayload, as name: String) -> PermissionRequest? {
        queue.add(payload, respond: replies.record(name))
    }

    // MARK: Order and routing

    @Test func requestsWaitInTheOrderTheyCame() {
        let queue = queue()
        add(queue, payload("a", tool: "Bash"), as: "1")
        add(queue, payload("b", tool: "Edit"), as: "2")
        add(queue, payload("c", tool: "Write"), as: "3")
        #expect(queue.pending.map(\.tool) == ["Bash", "Edit", "Write"])
        #expect(queue.pending.first?.key == AgentSessionKey(source: .claude, sessionID: "a"))
    }

    @Test func aRequestCarriesTheToolTheSummaryAndTheProjectOnly() throws {
        let request = try #require(add(queue(), payload(tool: "Bash", summary: "npm test"), as: "1"))
        #expect(request.source == .claude)
        #expect(request.tool == "Bash")
        #expect(request.summary == "npm test")
        #expect(request.project == "MyNotch")
        #expect(request.key == AgentSessionKey(source: .claude, sessionID: "s1"))
        let noFolder = try #require(add(queue(), payload(cwd: nil), as: "2"))
        #expect(noFolder.project == nil)
    }

    @Test func aDecisionGoesToTheExactRequestAndOnlyToIt() throws {
        let queue = queue()
        let first = try #require(add(queue, payload("a"), as: "1"))
        let second = try #require(add(queue, payload("b"), as: "2"))
        #expect(queue.decide(second.id, .deny))
        #expect(replies.all == ["2": [.deny]])
        #expect(queue.pending == [first])
        #expect(queue.decide(first.id, .allow))
        #expect(replies.all == ["1": [.allow], "2": [.deny]])
        #expect(queue.pending.isEmpty)
    }

    @Test func theNextRequestComesUpWhenTheFirstIsDecided() throws {
        let queue = queue()
        let first = try #require(add(queue, payload("a", tool: "Bash"), as: "1"))
        add(queue, payload("b", tool: "Edit"), as: "2")
        queue.decide(first.id, .ask)
        #expect(queue.pending.first?.tool == "Edit")
        #expect(replies.all == ["1": [.ask]])
    }

    @Test func aRequestIsDecidedOnceAndAnUnknownIdDoesNothing() throws {
        let queue = queue()
        let request = try #require(add(queue, payload(), as: "1"))
        #expect(!queue.decide("not-an-id", .allow))
        #expect(!queue.decide(request.id.lowercased() + "x", .allow))
        #expect(replies.all.isEmpty)
        #expect(queue.decide(request.id, .allow))
        #expect(!queue.decide(request.id, .deny))
        #expect(replies.all == ["1": [.allow]])
    }

    @Test func idsAreRandomAndNeverRepeat() throws {
        let queue = queue()
        let ids = try (0..<200).map { try #require(add(queue, payload("s\($0)"), as: "\($0)")).id }
        #expect(Set(ids).count == 200)
        for id in ids { #expect(UUID(uuidString: id) != nil) }
    }

    @Test func aRequestOfAnUnknownAgentIsNotQueued() {
        let queue = queue()
        #expect(add(queue, payload(source: "gemini"), as: "1") == nil)
        #expect(queue.pending.isEmpty)
    }

    // MARK: Going away without an answer

    @Test func aHelperThatWentAwayLeavesTheQueueWithoutAReply() throws {
        let queue = queue()
        let first = try #require(add(queue, payload("a"), as: "1"))
        add(queue, payload("b"), as: "2")
        queue.withdraw(first.id)
        #expect(queue.pending.map(\.key.sessionID) == ["b"])
        #expect(replies.all.isEmpty)
        #expect(scheduler.pendingCount == 1)
    }

    @Test func aRequestNobodyAnswersEndsWithAskInTheTerminalWhenItsTimeIsUp() {
        let queue = queue(lifetime: .seconds(65))
        add(queue, payload("a"), as: "1")
        scheduler.advance(by: .seconds(64))
        #expect(queue.pending.count == 1)
        scheduler.advance(by: .seconds(2))
        #expect(queue.pending.isEmpty)
        #expect(replies.all == ["1": [.ask]])
    }

    @Test func aDecisionStopsTheTimeOfItsRequest() throws {
        let queue = queue()
        let request = try #require(add(queue, payload(), as: "1"))
        #expect(scheduler.pendingCount == 1)
        queue.decide(request.id, .allow)
        #expect(scheduler.pendingCount == 0)
        scheduler.advance(by: .seconds(120))
        #expect(replies.all == ["1": [.allow]])
    }

    @Test func clearingAnswersEveryRequestWithAskInTheTerminal() {
        let queue = queue()
        add(queue, payload("a"), as: "1")
        add(queue, payload("b"), as: "2")
        queue.cancelAll()
        #expect(queue.pending.isEmpty)
        #expect(replies.all == ["1": [.ask], "2": [.ask]])
        #expect(scheduler.pendingCount == 0)
    }

    // MARK: The agent went on without the notch

    @Test func theSessionMovingOnSettlesItsRequestsAndLeavesOthersAlone() {
        let queue = queue()
        add(queue, payload("a", tool: "Bash"), as: "1")
        add(queue, payload("a", tool: "Edit"), as: "2")
        add(queue, payload("b", tool: "Bash"), as: "3")
        queue.settle(AgentSessionKey(source: .claude, sessionID: "a"))
        #expect(queue.pending.map(\.key.sessionID) == ["b"])
        #expect(replies.all == ["1": [.ask], "2": [.ask]])
    }

    @Test func aFinishedToolSettlesOnlyTheRequestForThatTool() {
        let queue = queue()
        add(queue, payload("a", tool: "Bash"), as: "1")
        add(queue, payload("a", tool: "Edit"), as: "2")
        queue.settle(AgentSessionKey(source: .claude, sessionID: "a"), tool: "Bash")
        #expect(queue.pending.map(\.tool) == ["Edit"])
        #expect(replies.all == ["1": [.ask]])
    }

    @Test func aSettledSessionIsToldApartFromTheSameIdOfAnotherAgent() {
        let queue = queue()
        add(queue, payload("a", source: "codex"), as: "1")
        queue.settle(AgentSessionKey(source: .claude, sessionID: "a"))
        #expect(queue.pending.count == 1)
    }
}
