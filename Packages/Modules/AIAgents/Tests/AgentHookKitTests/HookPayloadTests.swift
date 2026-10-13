import Foundation
import Testing
@testable import AgentHookKit

@Suite struct HookPayloadTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func filter(_ json: String, source: String = "claude") -> HookPayload? {
        HookPayloadFilter.make(source: source, hookJSON: Data(json.utf8), now: now)
    }

    @Test func keepsOnlyTheAllowListedFields() throws {
        let payload = try #require(filter("""
        {"hook_event_name":"PostToolUse","session_id":"s1","cwd":"/work/demo","tool_name":"Bash",
         "tool_input":{"command":"ls -la","description":"SECRET-DESC"},
         "tool_response":{"stdout":"SECRET-OUTPUT"},"prompt":"SECRET-PROMPT","message":"SECRET-MESSAGE",
         "transcript_path":"/Users/x/SECRET.jsonl","last_assistant_message":"SECRET-ANSWER"}
        """))
        #expect(payload.source == "claude")
        #expect(payload.event == "PostToolUse")
        #expect(payload.sessionID == "s1")
        #expect(payload.cwd == "/work/demo")
        #expect(payload.tool == "Bash")
        #expect(payload.summary == "ls -la")
        #expect(payload.timestamp == now)
        let datagram = String(decoding: try #require(payload.encodedDatagram()), as: UTF8.self)
        #expect(!datagram.contains("SECRET"))
    }

    @Test func notificationKeepsItsType() throws {
        let payload = try #require(filter(#"{"hook_event_name":"Notification","session_id":"s","notification_type":"permission_prompt","message":"SECRET"}"#))
        #expect(payload.notificationType == "permission_prompt")
        #expect(payload.summary == nil)
    }

    @Test func theSummaryIsTheFirstLineCutTo120Characters() throws {
        let command = String(repeating: "a", count: 300)
        let json = try String(decoding: JSONSerialization.data(withJSONObject: [
            "hook_event_name": "PreToolUse", "session_id": "s", "tool_name": "Bash",
            "tool_input": ["command": "\n  \(command)\nsecond line"],
        ]), as: UTF8.self)
        #expect(filter(json)?.summary == String(repeating: "a", count: 120))
    }

    @Test func aFileToolShowsOnlyTheLastPathComponent() {
        #expect(filter(#"{"hook_event_name":"PreToolUse","session_id":"s","tool_name":"Edit","tool_input":{"file_path":"/a/b/Main.swift","old_string":"SECRET"}}"#)?.summary == "Main.swift")
        #expect(filter(#"{"hook_event_name":"PreToolUse","session_id":"s","tool_name":"Grep","tool_input":{"path":"/a/b/src","pattern":"SECRET"}}"#)?.summary == "src")
        #expect(filter(#"{"hook_event_name":"PreToolUse","session_id":"s","tool_name":"WebFetch","tool_input":{"url":"https://x"}}"#)?.summary == nil)
    }

    @Test func codexInputIsReadTheSameWay() {
        #expect(filter(#"{"hook_event_name":"Stop","session_id":"c1"}"#, source: "codex")?.source == "codex")
    }

    @Test func unknownOrMalformedInputGivesNothing() {
        #expect(filter("not json") == nil)
        #expect(filter("[1,2]") == nil)
        #expect(filter(#"{"session_id":"s"}"#) == nil)
        #expect(filter(#"{"hook_event_name":"Stop"}"#) == nil)
        #expect(filter(#"{"hook_event_name":"Stop","session_id":"s"}"#, source: "gemini") == nil)
        #expect(filter(#"{"hook_event_name":7,"session_id":"s"}"#) == nil)
    }

    // MARK: Datagram

    func payload(cwd: String? = "/work", summary: String? = "ls") -> HookPayload {
        HookPayload(source: "claude", event: "PreToolUse", sessionID: "s", cwd: cwd, tool: "Bash", summary: summary, notificationType: nil, timestamp: now)
    }

    @Test func aSmallPayloadRoundTripsThroughItsDatagram() throws {
        let original = payload()
        let datagram = try #require(original.encodedDatagram())
        #expect(datagram.count <= HookPayload.maxDatagramSize)
        #expect(try HookPayload.decode(datagram) == original)
    }

    @Test func anOversizedPayloadDropsTheSummaryFirstThenTheCwd() throws {
        let long = String(repeating: "x", count: 1_900)
        let noSummary = try #require(payload(cwd: long, summary: String(repeating: "y", count: 120)).encodedDatagram())
        let decoded = try HookPayload.decode(noSummary)
        #expect(decoded.summary == nil)
        #expect(decoded.cwd == long)

        let noCwd = try #require(payload(cwd: String(repeating: "x", count: 3_000), summary: "ls").encodedDatagram())
        let decodedNoCwd = try HookPayload.decode(noCwd)
        #expect(decodedNoCwd.summary == nil)
        #expect(decodedNoCwd.cwd == nil)
        #expect(noCwd.count <= HookPayload.maxDatagramSize)
    }

    @Test func aPayloadStillTooLargeGivesNothing() {
        let huge = HookPayload(source: "claude", event: "Stop", sessionID: String(repeating: "s", count: 3_000), cwd: nil, tool: nil, summary: nil, notificationType: nil, timestamp: now)
        #expect(huge.encodedDatagram() == nil)
    }
}
