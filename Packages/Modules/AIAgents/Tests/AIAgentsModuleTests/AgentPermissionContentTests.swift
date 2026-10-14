import AgentHookKit
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import AIAgentsModule

/// The activity and the card an actionable permission request makes.
@Suite struct AgentPermissionContentTests {
    let t0 = utc("2026-10-14T05:00:00Z")

    func request(
        _ session: String = "a", source: String = "claude", tool: String = "Bash", summary: String? = "npm test",
        cwd: String? = "/Users/x/Project/MyNotch", id: String = "request-id"
    ) throws -> PermissionRequest {
        let payload = HookPayload(source: source, event: "PermissionRequest", sessionID: session, cwd: cwd, tool: tool, summary: summary, timestamp: t0)
        return try #require(PermissionRequest(payload: payload, id: id))
    }

    func session(_ state: AgentState, id: String = "a", source: AgentSource = .claude) -> AgentSession {
        var result = AgentSession(key: AgentSessionKey(source: source, sessionID: id), lastEventAt: t0)
        result.state = state
        result.turnStartedAt = t0
        return result
    }

    // MARK: Activity

    @Test func aPendingRequestMakesTheActivityAWaitingCardThatOutranksEverything() throws {
        let asking = try request()
        let result = try #require(AgentActivityContent(sessions: [session(.waitingForInput)], showWorking: true, pending: [asking]))
        #expect(result.kind == .waitingForInput)
        #expect(result.source == .claude)
        #expect(result.ask == AgentActivityContent.Ask(request: asking, others: 0))
        #expect(result.priority == .critical)
        // A session that only waits, without a card, stays at high priority.
        #expect(AgentActivityContent(sessions: [session(.waitingForInput)], showWorking: true)?.priority == .high)
    }

    @Test func theRequestsAgentIsTheOneShownEvenWhenAnotherWorks() throws {
        let working = session(.working(tool: nil, summary: nil), id: "busy", source: .claude)
        let result = try #require(AgentActivityContent(sessions: [working], showWorking: true, pending: [try request(source: "codex")]))
        #expect(result.source == .codex)
        #expect(result.kind == .waitingForInput)
    }

    @Test func aRequestShowsWithNoSessionAndWithTheWorkingActivityHidden() throws {
        let result = AgentActivityContent(sessions: [], showWorking: false, pending: [try request()])
        #expect(result?.ask?.request.tool == "Bash")
    }

    @Test func onlyTheFirstOfSeveralRequestsIsShownAndTheRestAreCounted() throws {
        let first = try request("a", tool: "Bash", id: "1")
        let result = try #require(AgentActivityContent(
            sessions: [], showWorking: true, pending: [first, try request("b", tool: "Edit", id: "2"), try request("c", tool: "Write", id: "3")]
        ))
        #expect(result.ask == AgentActivityContent.Ask(request: first, others: 2))
    }

    @Test func noRequestMeansTheActivityIsWhatTheSessionsMake() throws {
        let sessions = [session(.working(tool: nil, summary: nil)), session(.finished, id: "b")]
        #expect(AgentActivityContent(sessions: sessions, showWorking: true, pending: []) == AgentActivityContent(sessions: sessions, showWorking: true))
        #expect(AgentActivityContent(sessions: sessions, showWorking: true)?.ask == nil)
        #expect(AgentActivityContent(sessions: [], showWorking: true, pending: []) == nil)
    }

    @Test func aChangeOfTheRequestIsAChangeOfTheContentSoItIsPublishedAgain() throws {
        let one = AgentActivityContent(sessions: [], showWorking: true, pending: [try request(id: "1")])
        let two = AgentActivityContent(sessions: [], showWorking: true, pending: [try request(id: "2")])
        let withMore = AgentActivityContent(sessions: [], showWorking: true, pending: [try request(id: "1"), try request("b", id: "3")])
        #expect(one != two)
        #expect(one != withMore)
    }

    @Test func voiceOverNamesTheAgentTheToolAndTheSummary() throws {
        let result = try #require(AgentActivityContent(sessions: [], showWorking: true, pending: [try request(tool: "Bash", summary: "npm test")]))
        #expect(result.accessibilityLabel == "Claude Code xin quyền dùng Bash: npm test")
        let bare = try #require(AgentActivityContent(sessions: [], showWorking: true, pending: [try request(source: "codex", tool: "apply_patch", summary: nil)]))
        #expect(bare.accessibilityLabel == "Codex xin quyền dùng apply_patch")
    }

    // MARK: Card text

    @Test func theCardNamesTheAgentTheProjectTheToolAndTheSummary() throws {
        let asking = try request(tool: "Bash", summary: "npm test", cwd: "/Users/x/Project/MyNotch")
        #expect(PermissionCardText.title(of: asking) == "Claude Code • MyNotch")
        #expect(PermissionCardText.detail(of: asking) == "Bash · npm test")
        let bare = try request(source: "codex", tool: "apply_patch", summary: nil, cwd: nil)
        #expect(PermissionCardText.title(of: bare) == "Codex")
        #expect(PermissionCardText.detail(of: bare) == "apply_patch")
    }

    @Test func theCardCountsTheRequestsBehindIt() {
        #expect(PermissionCardText.queued(0) == nil)
        #expect(PermissionCardText.queued(1) == "+1 yêu cầu nữa")
        #expect(PermissionCardText.queued(4) == "+4 yêu cầu nữa")
    }

    @Test func theButtonsAreTheThreeAnswersTheBriefNames() {
        #expect(PermissionCardText.buttons.map(\.label) == ["Cho phép", "Từ chối", "Hỏi trong terminal"])
        #expect(PermissionCardText.buttons.map(\.answer) == [.allow, .deny, .ask])
    }

    @Test func theCardFitsTheStripUnderTheNotch() {
        // NotchGeometry.maxBottomHeight is 80: a taller strip would be cut.
        #expect(PermissionCard.stripHeight <= 80)
        #expect(PermissionCard.stripHeight >= 60)
    }

    // MARK: Layout

    /// The card as SwiftUI sizes it at the width of the strip, which is about the closed notch's width less its padding.
    @Test func theCardNeedsNoMoreHeightThanTheStripGivesIt() throws {
        let asking = try request(tool: "Bash", summary: String(repeating: "x", count: 120))
        for others in [0, 3] {
            let hosting = NSHostingView(rootView: PermissionCard(request: asking, others: others) { _, _ in }.frame(width: 300))
            #expect(hosting.fittingSize.height <= PermissionCard.stripHeight, "others \(others)")
            #expect(hosting.fittingSize.height >= 50, "others \(others)")
        }
    }
}
