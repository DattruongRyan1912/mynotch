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

    /// A request whose whole text is shown, so "Cho phép" is offered, unless `complete` says otherwise.
    func payload(
        _ session: String = "s1", tool: String = "Bash", summary: String? = "ls", source: String = "claude", cwd: String? = "/Users/x/Project/MyNotch",
        complete: Bool = true
    ) -> HookPayload {
        HookPayload(
            source: source, event: "PermissionRequest", sessionID: session, cwd: cwd, tool: tool, summary: summary, timestamp: now,
            detail: PermissionDetail(text: summary ?? "", hiddenLines: complete ? 0 : 3, isComplete: complete)
        )
    }

    /// The card has been on screen long enough to be answered.
    func arm() {
        scheduler.advance(by: PermissionQueue.armingDelay)
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
        #expect(request.detail == PermissionDetail(text: "npm test", hiddenLines: 0, isComplete: true))
        #expect(request.canAllow)
        #expect(request.key == AgentSessionKey(source: .claude, sessionID: "s1"))
        let noFolder = try #require(add(queue(), payload(cwd: nil), as: "2"))
        #expect(noFolder.project == nil)
    }

    @Test func aDecisionGoesToTheRequestOnScreenAndOnlyToIt() throws {
        let queue = queue()
        let first = try #require(add(queue, payload("a"), as: "1"))
        let second = try #require(add(queue, payload("b"), as: "2"))
        arm()
        // Only the card that is shown can be answered: the one behind it is not on screen.
        #expect(!queue.decide(second.id, .deny))
        #expect(replies.all.isEmpty)
        #expect(queue.decide(first.id, .deny))
        #expect(replies.all == ["1": [.deny]])
        #expect(queue.pending == [second])
        arm()
        #expect(queue.decide(second.id, .allow))
        #expect(replies.all == ["1": [.deny], "2": [.allow]])
        #expect(queue.pending.isEmpty)
    }

    @Test func theNextRequestComesUpWhenTheFirstIsDecided() throws {
        let queue = queue()
        let first = try #require(add(queue, payload("a", tool: "Bash"), as: "1"))
        add(queue, payload("b", tool: "Edit"), as: "2")
        arm()
        queue.decide(first.id, .ask)
        #expect(queue.pending.first?.tool == "Edit")
        #expect(replies.all == ["1": [.ask]])
    }

    @Test func aRequestIsDecidedOnceAndAnUnknownIdDoesNothing() throws {
        let queue = queue()
        let request = try #require(add(queue, payload(), as: "1"))
        arm()
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
        // What is left: the time of the request that stays and the delay of the card that came up.
        #expect(scheduler.pendingCount == 2)
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
        // Its time, and the delay before its card takes answers.
        #expect(scheduler.pendingCount == 2)
        arm()
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

    // MARK: A card that has just come up takes no answer yet

    /// A click aimed at the card that was there before lands on the one that replaced it, unless the new one waits.
    @Test func aCardThatJustAppearedTakesNoAnswerUntilItsDelayIsOver() throws {
        let queue = queue()
        let request = try #require(add(queue, payload(), as: "1"))
        #expect(queue.armedID == nil)
        for answer in [PermissionAnswer.allow, .deny, .ask] { #expect(!queue.decide(request.id, answer)) }
        scheduler.advance(by: PermissionQueue.armingDelay - .milliseconds(1))
        #expect(queue.armedID == nil)
        #expect(!queue.decide(request.id, .allow))
        #expect(replies.all.isEmpty)
        #expect(queue.pending == [request])
        scheduler.advance(by: .milliseconds(1))
        #expect(queue.armedID == request.id)
        #expect(queue.decide(request.id, .allow))
        #expect(replies.all == ["1": [.allow]])
    }

    @Test func theNextCardInTheSlotWaitsToo() throws {
        let queue = queue()
        let first = try #require(add(queue, payload("a"), as: "1"))
        let second = try #require(add(queue, payload("b"), as: "2"))
        arm()
        #expect(queue.decide(first.id, .allow))
        // A second click on the same spot, as from a double click, arrives while the next card is already there.
        #expect(queue.pending == [second])
        #expect(queue.armedID == nil)
        #expect(!queue.decide(second.id, .allow))
        #expect(!queue.decide(second.id, .deny))
        #expect(replies.all == ["1": [.allow]])
        arm()
        #expect(queue.armedID == second.id)
        #expect(queue.decide(second.id, .deny))
        #expect(replies.all == ["1": [.allow], "2": [.deny]])
    }

    @Test func theNextCardWaitsAlsoWhenTheFirstWasTakenAwayByTheAgentAndNotByTheUser() throws {
        let queue = queue()
        add(queue, payload("a"), as: "1")
        let second = try #require(add(queue, payload("b"), as: "2"))
        arm()
        queue.settle(AgentSessionKey(source: .claude, sessionID: "a"))
        #expect(queue.pending == [second])
        #expect(!queue.decide(second.id, .allow))
        arm()
        #expect(queue.decide(second.id, .allow))
    }

    @Test func aRequestThatComesInBehindTheCardOnScreenDoesNotDisarmIt() throws {
        let queue = queue()
        let first = try #require(add(queue, payload("a"), as: "1"))
        arm()
        add(queue, payload("b"), as: "2")
        #expect(queue.armedID == first.id)
        #expect(queue.decide(first.id, .allow))
    }

    @Test func aRequestLeavingFromBehindTheCardOnScreenDoesNotDisarmIt() throws {
        let queue = queue()
        let first = try #require(add(queue, payload("a"), as: "1"))
        let second = try #require(add(queue, payload("b"), as: "2"))
        arm()
        queue.withdraw(second.id)
        #expect(queue.armedID == first.id)
        #expect(queue.decide(first.id, .allow))
    }

    @Test func aCardThatLeavesBeforeItsDelayLeavesNoDelayRunningAndTheNextOneStartsItsOwn() throws {
        let queue = queue()
        let first = try #require(add(queue, payload("a"), as: "1"))
        let second = try #require(add(queue, payload("b"), as: "2"))
        scheduler.advance(by: .milliseconds(400))
        queue.withdraw(first.id)
        // The first card's delay would end 200 ms from now; the second card has a full one of its own.
        scheduler.advance(by: .milliseconds(300))
        #expect(queue.armedID == nil)
        #expect(!queue.decide(second.id, .allow))
        scheduler.advance(by: .milliseconds(300))
        #expect(queue.armedID == second.id)
    }

    @Test func anEmptyQueueHasNothingArmedAndTheNextRequestStartsDisarmed() throws {
        let queue = queue()
        let first = try #require(add(queue, payload("a"), as: "1"))
        arm()
        queue.decide(first.id, .allow)
        #expect(queue.armedID == nil)
        let again = try #require(add(queue, payload("b"), as: "2"))
        #expect(!queue.decide(again.id, .allow))
        arm()
        #expect(queue.decide(again.id, .allow))
    }

    @Test func whatTheAgentOrTheAppEndsIsNotHeldUpByTheDelay() throws {
        let queue = queue()
        add(queue, payload("a"), as: "1")
        add(queue, payload("b"), as: "2")
        queue.withdraw(queue.pending[0].id)
        queue.cancelAll()
        #expect(replies.all == ["2": [.ask]])
        #expect(queue.pending.isEmpty)
    }

    @Test func theDelayIsLongerThanTheDoubleClickIntervalAndShortEnoughToNotBeFelt() {
        // The system's default double-click interval is half a second; a click that began on the previous card is over by then.
        #expect(PermissionQueue.armingDelay > .milliseconds(500))
        #expect(PermissionQueue.armingDelay <= .seconds(1))
    }

    // MARK: A request that is not shown whole cannot be allowed

    @Test func aRequestNotShownWholeCannotBeAllowedAtAllButCanBeDeniedOrLeftToTheTerminal() throws {
        let queue = queue()
        let request = try #require(add(queue, payload("a", complete: false), as: "1"))
        #expect(!request.canAllow)
        arm()
        #expect(!queue.decide(request.id, .allow))
        #expect(queue.pending == [request])
        #expect(replies.all.isEmpty)
        #expect(queue.decide(request.id, .deny))
        #expect(replies.all == ["1": [.deny]])

        let other = try #require(add(queue, payload("b", complete: false), as: "2"))
        arm()
        #expect(queue.decide(other.id, .ask))
        #expect(replies.all == ["1": [.deny], "2": [.ask]])
    }

    @Test func aRequestFromAnOlderHelperWithNoDetailCannotBeAllowed() throws {
        let queue = queue()
        let old = HookPayload(source: "claude", event: "PermissionRequest", sessionID: "s1", tool: "Bash", summary: "ls", timestamp: now)
        let request = try #require(queue.add(old, respond: replies.record("1")))
        #expect(request.detail == nil)
        #expect(!request.canAllow)
        arm()
        #expect(!queue.decide(request.id, .allow))
    }

    @Test func onlyAWholeDetailWithTextCanBeAllowed() throws {
        func request(_ detail: PermissionDetail?) throws -> PermissionRequest {
            var made = payload()
            made.detail = detail
            return try #require(PermissionRequest(payload: made, id: "x"))
        }
        #expect(try request(PermissionDetail(text: "ls", hiddenLines: 0, isComplete: true)).canAllow)
        #expect(try !request(PermissionDetail(text: "ls", hiddenLines: 0, isComplete: false)).canAllow)
        #expect(try !request(PermissionDetail(text: "ls", hiddenLines: 1, isComplete: true)).canAllow)
        #expect(try !request(PermissionDetail(text: "", hiddenLines: 0, isComplete: true)).canAllow)
        #expect(try !request(nil).canAllow)
    }
}
