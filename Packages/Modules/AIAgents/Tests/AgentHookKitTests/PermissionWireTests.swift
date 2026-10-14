import Foundation
import Testing
@testable import AgentHookKit

@Suite struct PermissionWireTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    /// What Claude Code sends a `PermissionRequest` hook, with the fields that must never travel on.
    let hookJSON = Data("""
    {"hook_event_name":"PermissionRequest","session_id":"s1","cwd":"/Users/x/project","transcript_path":"/Users/x/.claude/t.jsonl",
     "permission_mode":"default","tool_name":"Bash",
     "tool_input":{"command":"rm -rf build\\nSECRET second line","description":"SECRET description"},
     "prompt":"SECRET PROMPT","permission_suggestions":[{"type":"addRules","rules":[{"toolName":"Bash","ruleContent":"SECRET rule"}]}]}
    """.utf8)

    func payload(event: String = "PermissionRequest", tool: String? = "Bash", source: String = "claude") -> HookPayload {
        HookPayload(source: source, event: event, sessionID: "s1", cwd: "/p", tool: tool, summary: "ls", timestamp: now)
    }

    // MARK: Request

    @Test func aRequestIsOneLineThatCarriesOnlyTheFilteredFields() throws {
        let filtered = try #require(HookPayloadFilter.make(source: "claude", hookJSON: hookJSON, now: now))
        let line = try #require(PermissionWire.requestLine(filtered))
        #expect(line.last == 0x0A)
        #expect(line.dropLast().contains(0x0A) == false)
        #expect(line.count <= PermissionWire.maxRequestLength)
        let text = String(decoding: line, as: UTF8.self)
        #expect(!text.contains("SECRET"))
        #expect(!text.contains("transcript"))
        let decoded = try #require(PermissionWire.decodeRequest(line))
        #expect(decoded.tool == "Bash")
        #expect(decoded.summary == "rm -rf build")
        #expect(decoded.sessionID == "s1")
    }

    @Test func aRequestIsDecodedWithOrWithoutItsNewline() throws {
        let line = try #require(PermissionWire.requestLine(payload()))
        #expect(PermissionWire.decodeRequest(line) == payload())
        #expect(PermissionWire.decodeRequest(line.dropLast()) == payload())
    }

    @Test func onlyAWellFormedPermissionRequestIsDecoded() throws {
        func line(_ payload: HookPayload) throws -> Data { try #require(PermissionWire.requestLine(payload)) }
        #expect(PermissionWire.decodeRequest(try line(payload(event: "PreToolUse"))) == nil)
        #expect(PermissionWire.decodeRequest(try line(payload(tool: nil))) == nil)
        #expect(PermissionWire.decodeRequest(try line(payload(tool: ""))) == nil)
        #expect(PermissionWire.decodeRequest(try line(payload(source: "gemini"))) == nil)
        #expect(PermissionWire.decodeRequest(Data("not json\n".utf8)) == nil)
        #expect(PermissionWire.decodeRequest(Data()) == nil)
    }

    @Test func aRequestTooLargeForALineIsNotMade() {
        var big = payload()
        big.cwd = String(repeating: "c", count: 5_000)
        big.summary = String(repeating: "s", count: 5_000)
        // The datagram rules apply: the summary goes first, then the cwd, and what is still too large is nil.
        #expect(PermissionWire.requestLine(big)?.count ?? 0 <= PermissionWire.maxRequestLength)
        big.tool = String(repeating: "t", count: 5_000)
        #expect(PermissionWire.requestLine(big) == nil)
    }

    // MARK: Reply

    @Test func eachAnswerRoundTripsAsOneLine() throws {
        for answer in [PermissionAnswer.allow, .deny, .ask] {
            let line = PermissionWire.replyLine(answer)
            #expect(line.last == 0x0A)
            #expect(PermissionWire.decodeReply(line) == answer)
        }
        #expect(String(decoding: PermissionWire.replyLine(.allow), as: UTF8.self) == "{\"decision\":\"allow\"}\n")
    }

    @Test func aReplyThatIsNotOneOfTheAnswersIsNotAnAnswer() {
        #expect(PermissionWire.decodeReply(Data("garbage".utf8)) == nil)
        #expect(PermissionWire.decodeReply(Data(#"{"decision":"maybe"}"#.utf8)) == nil)
        #expect(PermissionWire.decodeReply(Data(#"{"decision":true}"#.utf8)) == nil)
        #expect(PermissionWire.decodeReply(Data(#"{"other":"allow"}"#.utf8)) == nil)
        #expect(PermissionWire.decodeReply(Data(#"["allow"]"#.utf8)) == nil)
        #expect(PermissionWire.decodeReply(Data()) == nil)
    }

    // MARK: What the hook prints

    private func decision(_ answer: PermissionAnswer) throws -> (event: String?, decision: [String: Any])? {
        guard let data = PermissionWire.hookOutput(for: answer) else { return nil }
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object.keys.sorted() == ["hookSpecificOutput"])
        let specific = try #require(object["hookSpecificOutput"] as? [String: Any])
        return (specific["hookEventName"] as? String, try #require(specific["decision"] as? [String: Any]))
    }

    /// The shape `code.claude.com/docs/en/hooks` gives for `PermissionRequest`, and Codex's hooks page for its own.
    @Test func allowingPrintsTheDocumentedDecisionAndNothingElse() throws {
        let result = try #require(try decision(.allow))
        #expect(result.event == "PermissionRequest")
        #expect(result.decision as NSDictionary == ["behavior": "allow"] as NSDictionary)
    }

    /// Codex fails closed on `interrupt` and `updatedInput`, so a deny carries the behavior and a message only.
    @Test func denyingPrintsTheBehaviorAndAMessageForTheAgent() throws {
        let result = try #require(try decision(.deny))
        #expect(result.event == "PermissionRequest")
        #expect(result.decision["behavior"] as? String == "deny")
        #expect(!(result.decision["message"] as? String ?? "").isEmpty)
        #expect(result.decision.keys.sorted() == ["behavior", "message"])
    }

    @Test func askingInTheTerminalPrintsNothing() {
        #expect(PermissionWire.hookOutput(for: .ask) == nil)
    }
}
