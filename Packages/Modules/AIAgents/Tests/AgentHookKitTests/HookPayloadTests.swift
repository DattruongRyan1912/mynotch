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

    // MARK: Subagents

    /// The example of the Claude Code hooks reference for `SubagentStart`, with extra fields it may carry.
    let subagentStart = """
    {"session_id":"abc123","transcript_path":"/Users/x/.claude/projects/p/SECRET.jsonl","cwd":"/Users/x/demo",
     "hook_event_name":"SubagentStart","agent_id":"agent-abc123","agent_type":"Explore"}
    """

    /// The example of the same page for `SubagentStop`: the answer and the subagent's transcript never travel on.
    let subagentStop = """
    {"session_id":"abc123","transcript_path":"~/.claude/projects/p/abc123.jsonl","cwd":"/Users/x/demo","permission_mode":"default",
     "hook_event_name":"SubagentStop","stop_hook_active":false,"agent_id":"def456","agent_type":"Explore",
     "agent_transcript_path":"~/.claude/projects/p/abc123/subagents/SECRET-agent-def456.jsonl",
     "last_assistant_message":"SECRET-ANSWER Analysis complete. Found 3 potential issues...","background_tasks":[],"session_crons":[]}
    """

    func agentCall(tool: String = "Agent", input: [String: Any]) throws -> String {
        try String(decoding: JSONSerialization.data(withJSONObject: [
            "hook_event_name": "PreToolUse", "session_id": "s", "tool_name": tool, "tool_input": input,
        ]), as: UTF8.self)
    }

    @Test func aSubagentStartKeepsTheAgentIdAndType() throws {
        let payload = try #require(filter(subagentStart))
        #expect(payload.event == "SubagentStart")
        #expect(payload.sessionID == "abc123")
        #expect(payload.agentID == "agent-abc123")
        #expect(payload.agentType == "Explore")
        #expect(payload.tool == nil)
        #expect(payload.summary == nil)
        #expect(!String(decoding: try #require(payload.encodedDatagram()), as: UTF8.self).contains("SECRET"))
    }

    @Test func aSubagentStopNeverCarriesTheAnswerOrTheTranscript() throws {
        let payload = try #require(filter(subagentStop))
        #expect(payload.event == "SubagentStop")
        #expect(payload.agentID == "def456")
        #expect(payload.agentType == "Explore")
        let datagram = String(decoding: try #require(payload.encodedDatagram()), as: UTF8.self)
        #expect(!datagram.contains("SECRET"))
        #expect(!datagram.contains("Analysis"))
    }

    @Test func codexSubagentEventsAreReadTheSameWay() throws {
        let payload = try #require(filter("""
        {"session_id":"c1","transcript_path":null,"cwd":"/p","hook_event_name":"SubagentStop","model":"gpt-5","turn_id":"t1",
         "agent_id":"a1","agent_type":"worker","agent_transcript_path":"/x/SECRET","stop_hook_active":false,"last_assistant_message":"SECRET"}
        """, source: "codex"))
        #expect(payload.source == "codex")
        #expect(payload.agentID == "a1")
        #expect(payload.agentType == "worker")
        #expect(!String(decoding: try #require(payload.encodedDatagram()), as: UTF8.self).contains("SECRET"))
    }

    @Test func aSubagentEventWithoutAnAgentTypeStillHasItsId() throws {
        let payload = try #require(filter(#"{"hook_event_name":"SubagentStop","session_id":"s","agent_id":"a1"}"#))
        #expect(payload.agentID == "a1")
        #expect(payload.agentType == nil)
    }

    @Test func theAgentToolCallShowsItsDescriptionAndTypeButNotItsPrompt() throws {
        for tool in ["Agent", "Task"] {
            let payload = try #require(filter(agentCall(tool: tool, input: [
                "prompt": "SECRET-PROMPT find the keys", "description": "Find API endpoints", "subagent_type": "Explore", "model": "sonnet",
            ])))
            #expect(payload.tool == tool)
            #expect(payload.summary == "Find API endpoints")
            #expect(payload.agentType == "Explore")
            #expect(payload.agentID == nil)
            let datagram = String(decoding: try #require(payload.encodedDatagram()), as: UTF8.self)
            #expect(!datagram.contains("SECRET"))
            #expect(!datagram.contains("sonnet"))
        }
    }

    @Test func theDescriptionIsOneCleanLineOfAtMost120Characters() throws {
        let long = try #require(filter(agentCall(input: ["description": "  " + String(repeating: "d", count: 300) + "\nsecond line"])))
        #expect(long.summary == String(repeating: "d", count: 120))
        let odd = try #require(filter(agentCall(input: ["description": "a\u{202E}b\u{200B}c\nSECOND"])))
        #expect(odd.summary == "a\u{FFFD}b\u{FFFD}c")
        #expect(try #require(filter(agentCall(input: ["prompt": "p"]))).summary == nil)
        #expect(try #require(filter(agentCall(input: ["description": "   "]))).summary == nil)
    }

    @Test func otherToolsAreNotTakenForAnAgentCall() throws {
        let payload = try #require(filter(agentCall(tool: "Bash", input: ["command": "ls", "description": "SECRET", "subagent_type": "Explore"])))
        #expect(payload.summary == "ls")
        #expect(payload.agentType == nil)
        #expect(try #require(filter(agentCall(tool: "WebFetch", input: ["description": "x"]))).summary == nil)
    }

    @Test func aToolRunInsideASubagentKeepsOnlyItsAgentId() throws {
        let payload = try #require(filter("""
        {"hook_event_name":"PreToolUse","session_id":"s","tool_name":"Read","tool_input":{"file_path":"/a/b.swift"},
         "agent_id":"def456","agent_type":"Explore"}
        """))
        #expect(payload.agentID == "def456")
        #expect(payload.agentType == nil)
        #expect(payload.summary == "b.swift")
    }

    @Test func aMainThreadRunAsAnAgentIsNotASubagent() throws {
        let payload = try #require(filter(#"{"hook_event_name":"Stop","session_id":"s","agent_type":"security-reviewer"}"#))
        #expect(payload.agentID == nil)
        #expect(payload.agentType == nil)
    }

    @Test func theAgentIdAndTypeAreCleanedAndCut() throws {
        let long = String(repeating: "x", count: 500)
        let payload = try #require(filter("""
        {"hook_event_name":"SubagentStart","session_id":"s","agent_id":"\(long)","agent_type":"E\u{202E}x\(long)"}
        """))
        #expect(payload.agentID == String(repeating: "x", count: HookPayload.maxAgentFieldLength))
        #expect(payload.agentType?.count == HookPayload.maxAgentFieldLength)
        #expect(payload.agentType?.hasPrefix("E\u{FFFD}x") == true)
        #expect(payload.encodedDatagram() != nil)
        #expect(filter(#"{"hook_event_name":"SubagentStart","session_id":"s","agent_id":"","agent_type":""}"#)?.agentID == nil)
        #expect(filter(#"{"hook_event_name":"SubagentStart","session_id":"s","agent_id":7,"agent_type":["x"]}"#)?.agentType == nil)
    }

    @Test func theSubagentFieldsSurviveTheDatagram() throws {
        let original = HookPayload(
            source: "claude", event: "SubagentStop", sessionID: "s", cwd: "/work", timestamp: now, agentID: "a1", agentType: "Explore", processID: 4_242
        )
        let datagram = try #require(original.encodedDatagram())
        #expect(try HookPayload.decode(datagram) == original)
    }

    @Test func anOldAppReadsAPayloadWithTheNewFieldsAndTheOtherWayRound() throws {
        let withNew = try #require(HookPayload(source: "claude", event: "Stop", sessionID: "s", timestamp: now, agentID: "a", processID: 9).encodedDatagram())
        #expect(try HookPayload.decode(withNew).agentID == "a")
        let old = Data(#"{"source":"claude","event":"Stop","sessionID":"s","timestamp":1800000000}"#.utf8)
        let decoded = try HookPayload.decode(old)
        #expect(decoded.agentID == nil && decoded.agentType == nil && decoded.processID == nil)
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
