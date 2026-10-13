import Foundation
import Testing
@testable import AIAgentsModule

/// Hand-written lines shaped like Claude Code transcript records; the text is placeholder content.
private enum Fixture {
    static let session = "11111111-2222-4333-8444-555555555555"
    /// Appears only in prompt, answer and tool output text, which no event may carry.
    static let marker = "ZEBRAPLACEHOLDER"

    static let prompt = #"{"parentUuid":null,"isSidechain":false,"userType":"external","cwd":"/Users/example/Projects/demo","sessionId":"11111111-2222-4333-8444-555555555555","version":"2.0.0","gitBranch":"main","type":"user","message":{"role":"user","content":"Please tidy the ZEBRAPLACEHOLDER notes"},"uuid":"u-1","timestamp":"2026-10-13T08:00:00.000Z"}"#
    static let promptBlocks = #"{"isSidechain":false,"cwd":"/Users/example/Projects/demo","sessionId":"11111111-2222-4333-8444-555555555555","gitBranch":"","type":"user","message":{"role":"user","content":[{"type":"text","text":"ZEBRAPLACEHOLDER again"},{"type":"image","source":{"type":"base64","media_type":"image/png","data":"AAAA"}}]},"uuid":"u-2","timestamp":"2026-10-13T08:00:00Z"}"#
    static let bash = #"{"parentUuid":"u-1","isSidechain":false,"cwd":"/Users/example/Projects/demo","sessionId":"11111111-2222-4333-8444-555555555555","version":"2.0.0","gitBranch":"main","type":"assistant","message":{"id":"msg_01","type":"message","role":"assistant","model":"claude-opus-4-1","content":[{"type":"tool_use","id":"toolu_01","name":"Bash","input":{"command":"  git status --short\necho done","description":"Show status"}}],"stop_reason":"tool_use","stop_sequence":null,"usage":{"input_tokens":12,"cache_creation_input_tokens":300,"cache_read_input_tokens":4000,"output_tokens":56,"service_tier":"standard"}},"requestId":"req_1","uuid":"a-1","timestamp":"2026-10-13T08:00:02.500Z"}"#
    static let toolResult = #"{"parentUuid":"a-1","isSidechain":false,"cwd":"/Users/example/Projects/demo","sessionId":"11111111-2222-4333-8444-555555555555","gitBranch":"main","type":"user","message":{"role":"user","content":[{"tool_use_id":"toolu_01","type":"tool_result","content":"ZEBRAPLACEHOLDER output","is_error":false}]},"toolUseResult":{"stdout":"ZEBRAPLACEHOLDER output","stderr":""},"uuid":"u-3","timestamp":"2026-10-13T08:00:03.000Z"}"#
    static let thinkingAndText = #"{"isSidechain":false,"sessionId":"11111111-2222-4333-8444-555555555555","type":"assistant","message":{"id":"msg_02","model":"claude-opus-4-1","role":"assistant","content":[{"type":"thinking","thinking":"ZEBRAPLACEHOLDER plan","signature":"sig"},{"type":"text","text":"ZEBRAPLACEHOLDER reply"}],"stop_reason":null,"usage":{"input_tokens":3,"cache_creation_input_tokens":0,"cache_read_input_tokens":5000,"output_tokens":20}},"uuid":"a-2","timestamp":"2026-10-13T08:00:04.000Z"}"#
    static let endTurn = #"{"isSidechain":false,"sessionId":"11111111-2222-4333-8444-555555555555","type":"assistant","message":{"id":"msg_02","model":"claude-opus-4-1","role":"assistant","content":[{"type":"text","text":"ZEBRAPLACEHOLDER done"}],"stop_reason":"end_turn","usage":{"input_tokens":3,"cache_creation_input_tokens":10,"cache_read_input_tokens":5000,"output_tokens":90}},"uuid":"a-3","timestamp":"2026-10-13T08:00:05.000Z"}"#
    static let stopHook = #"{"type":"system","subtype":"stop_hook_summary","hookCount":2,"hookInfos":[{"command":"placeholder-hook"}],"hookErrors":[],"preventedContinuation":false,"stopReason":"","hasOutput":false,"level":"suggestion","isSidechain":false,"sessionId":"11111111-2222-4333-8444-555555555555","uuid":"s-1","timestamp":"2026-10-13T08:00:06.000Z"}"#
    static let costState = #"{"type":"cost-state","totalCostUSD":1.25,"sessionId":"11111111-2222-4333-8444-555555555555","timestamp":"2026-10-13T08:00:07.000Z"}"#

    static func toolUse(_ name: String, input: String) -> String {
        #"{"isSidechain":false,"sessionId":"11111111-2222-4333-8444-555555555555","type":"assistant","message":{"id":"msg_09","model":"claude-opus-4-1","role":"assistant","content":[{"type":"tool_use","id":"toolu_09","name":""# + name + #"","input":"# + input + #"}],"stop_reason":"tool_use"},"timestamp":"2026-10-13T08:00:00Z"}"#
    }
}

@Suite struct ClaudeTranscriptParserTests {
    let start = utc("2026-10-13T08:00:00Z")

    func event(_ kind: AgentEvent.Kind, at seconds: Double, usage: AgentUsage? = nil) -> AgentEvent {
        AgentEvent(source: .claude, sessionID: Fixture.session, timestamp: start + seconds, kind: kind, usage: usage)
    }

    @Test func promptStartsATurnAndReportsWhereTheSessionRuns() {
        #expect(ClaudeTranscriptParser.parse(line: Fixture.prompt) == [
            event(.sessionStarted(cwd: "/Users/example/Projects/demo", branch: "main"), at: 0),
            event(.turnStarted, at: 0),
        ])
    }

    @Test func promptWithContentBlocksAndNoBranchStartsATurn() {
        #expect(ClaudeTranscriptParser.parse(line: Fixture.promptBlocks) == [
            event(.sessionStarted(cwd: "/Users/example/Projects/demo", branch: nil), at: 0),
            event(.turnStarted, at: 0),
        ])
    }

    @Test func toolUseStartsAToolWithTheBashCommandHeadAndUsage() {
        let usage = AgentUsage(input: 12, output: 56, cacheRead: 4000, cacheWrite: 300, model: "claude-opus-4-1", messageID: "msg_01")
        #expect(ClaudeTranscriptParser.parse(line: Fixture.bash) == [
            event(.toolStarted(name: "Bash", summary: "git status --short"), at: 2.5, usage: usage),
        ])
    }

    @Test func toolResultFinishesTheTool() {
        #expect(ClaudeTranscriptParser.parse(line: Fixture.toolResult) == [event(.toolFinished, at: 3)])
    }

    @Test func assistantTextOnlyReportsUsage() {
        let usage = AgentUsage(input: 3, output: 20, cacheRead: 5000, cacheWrite: 0, model: "claude-opus-4-1", messageID: "msg_02")
        #expect(ClaudeTranscriptParser.parse(line: Fixture.thinkingAndText) == [event(.usageUpdated, at: 4, usage: usage)])
    }

    @Test func endTurnFinishesTheTurnWithUsage() {
        let usage = AgentUsage(input: 3, output: 90, cacheRead: 5000, cacheWrite: 10, model: "claude-opus-4-1", messageID: "msg_02")
        #expect(ClaudeTranscriptParser.parse(line: Fixture.endTurn) == [event(.turnFinished, at: 5, usage: usage)])
    }

    @Test func recordsOfOneAPIMessageCarryItsIDSoUsageCanBeCountedOnce() {
        let usages = [Fixture.thinkingAndText, Fixture.endTurn].flatMap { ClaudeTranscriptParser.parse(line: $0) }.compactMap(\.usage)
        #expect(usages.map(\.messageID) == ["msg_02", "msg_02"])
        #expect(usages.map(\.output) == [20, 90])
    }

    @Test func stopHookSummaryFinishesTheTurn() {
        #expect(ClaudeTranscriptParser.parse(line: Fixture.stopHook) == [event(.turnFinished, at: 6)])
    }

    @Test func costStateCarriesTheSessionCost() {
        var expected = event(.usageUpdated, at: 7)
        expected.costUSD = 1.25
        #expect(ClaudeTranscriptParser.parse(line: Fixture.costState) == [expected])
    }

    @Test func fileToolsAreSummarisedByFileName() {
        for name in ["Read", "Edit", "Write", "MultiEdit"] {
            let line = Fixture.toolUse(name, input: #"{"file_path":"/Users/example/Projects/demo/Sources/App.swift","old_string":"ZEBRAPLACEHOLDER"}"#)
            #expect(ClaudeTranscriptParser.parse(line: line).map(\.kind) == [.toolStarted(name: name, summary: "App.swift")])
        }
    }

    @Test func otherToolsHaveNoSummary() {
        let line = Fixture.toolUse("Grep", input: #"{"pattern":"ZEBRAPLACEHOLDER","path":"/Users/example"}"#)
        #expect(ClaudeTranscriptParser.parse(line: line).map(\.kind) == [.toolStarted(name: "Grep", summary: nil)])
    }

    @Test func longCommandIsCutTo120Characters() throws {
        let command = String(repeating: "x", count: 150)
        let line = Fixture.toolUse("Bash", input: #"{"command":""# + command + #""}"#)
        let kind = try #require(ClaudeTranscriptParser.parse(line: line).first?.kind)
        #expect(kind == .toolStarted(name: "Bash", summary: String(repeating: "x", count: 120)))
    }

    @Test func toolInputsOfUnexpectedTypesKeepTheToolWithoutSummary() {
        let line = Fixture.toolUse("Bash", input: #"{"command":42}"#)
        #expect(ClaudeTranscriptParser.parse(line: line).map(\.kind) == [.toolStarted(name: "Bash", summary: nil)])
        let missing = Fixture.toolUse("Read", input: "null")
        #expect(ClaudeTranscriptParser.parse(line: missing).map(\.kind) == [.toolStarted(name: "Read", summary: nil)])
    }

    @Test func interruptionAbortsTheTurn() {
        let line = #"{"isSidechain":false,"sessionId":"11111111-2222-4333-8444-555555555555","type":"user","message":{"role":"user","content":[{"type":"text","text":"[Request interrupted by user for tool use]"}]},"timestamp":"2026-10-13T08:00:00Z"}"#
        #expect(ClaudeTranscriptParser.parse(line: line) == [event(.turnAborted, at: 0)])
    }

    @Test func injectedUserRecordsDoNotStartATurn() {
        let meta = #"{"isSidechain":false,"isMeta":true,"sessionId":"11111111-2222-4333-8444-555555555555","type":"user","message":{"role":"user","content":"ZEBRAPLACEHOLDER caveat"},"timestamp":"2026-10-13T08:00:00Z"}"#
        let summary = #"{"isSidechain":false,"isCompactSummary":true,"sessionId":"11111111-2222-4333-8444-555555555555","type":"user","message":{"role":"user","content":"ZEBRAPLACEHOLDER summary"},"timestamp":"2026-10-13T08:00:00Z"}"#
        #expect(ClaudeTranscriptParser.parse(line: meta) == [])
        #expect(ClaudeTranscriptParser.parse(line: summary) == [])
    }

    @Test func subagentRecordsNeitherStartNorFinishTheTurn() {
        let prompt = Fixture.prompt.replacingOccurrences(of: #""isSidechain":false"#, with: #""isSidechain":true"#)
        let endTurn = Fixture.endTurn.replacingOccurrences(of: #""isSidechain":false"#, with: #""isSidechain":true"#)
        let stopHook = Fixture.stopHook.replacingOccurrences(of: #""isSidechain":false"#, with: #""isSidechain":true"#)
        let bash = Fixture.bash.replacingOccurrences(of: #""isSidechain":false"#, with: #""isSidechain":true"#)
        #expect(ClaudeTranscriptParser.parse(line: prompt) == [])
        #expect(ClaudeTranscriptParser.parse(line: endTurn).map(\.kind) == [.usageUpdated])
        #expect(ClaudeTranscriptParser.parse(line: stopHook) == [])
        #expect(ClaudeTranscriptParser.parse(line: bash).map(\.kind) == [.toolStarted(name: "Bash", summary: "git status --short")])
    }

    @Test func promptAndAnswerTextNeverReachTheEvents() {
        let lines = [Fixture.prompt, Fixture.promptBlocks, Fixture.bash, Fixture.toolResult, Fixture.thinkingAndText, Fixture.endTurn]
        let events = lines.flatMap { ClaudeTranscriptParser.parse(line: $0) }
        #expect(events.count == 8)
        #expect(!String(describing: events).contains(Fixture.marker))
    }

    @Test func missingFieldsDropOnlyThatField() {
        let noTimestamp = #"{"type":"system","subtype":"stop_hook_summary","sessionId":"s-2"}"#
        #expect(ClaudeTranscriptParser.parse(line: noTimestamp) == [
            AgentEvent(source: .claude, sessionID: "s-2", timestamp: nil, kind: .turnFinished),
        ])
        let oddUsage = #"{"type":"assistant","sessionId":"s-2","timestamp":"bad","message":{"stop_reason":"end_turn","usage":{"input_tokens":"many","output_tokens":7}}}"#
        #expect(ClaudeTranscriptParser.parse(line: oddUsage) == [
            AgentEvent(source: .claude, sessionID: "s-2", timestamp: nil, kind: .turnFinished, usage: AgentUsage(output: 7)),
        ])
    }

    @Test func recordsWithoutASessionUseTheFileSession() {
        let line = #"{"type":"cost-state","totalCostUSD":0.5}"#
        #expect(ClaudeTranscriptParser.parse(line: line) == [])
        #expect(ClaudeTranscriptParser.parse(line: line, sessionID: "from-file") == [
            AgentEvent(source: .claude, sessionID: "from-file", timestamp: nil, kind: .usageUpdated, costUSD: 0.5),
        ])
    }

    @Test func malformedAndUnknownLinesYieldNothing() {
        let lines = [
            "", "not json", "[]", "{}", "42", #"{"type":"user""#,
            #"{"type":"summary","summary":"ZEBRAPLACEHOLDER","leafUuid":"x"}"#,
            #"{"type":"custom-title","customTitle":"ZEBRAPLACEHOLDER","sessionId":"s"}"#,
            #"{"type":"system","subtype":"informational","sessionId":"s"}"#,
            #"{"type":"cost-state","sessionId":"s"}"#,
            #"{"type":"assistant","sessionId":"s","message":{"content":"ZEBRAPLACEHOLDER","stop_reason":"tool_use"}}"#,
            #"{"type":"assistant","sessionId":"s","message":{"content":[{"type":"tool_use","input":{}}]}}"#,
        ]
        for line in lines {
            #expect(ClaudeTranscriptParser.parse(line: line) == [], "\(line)")
        }
    }
}
