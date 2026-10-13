import Foundation
import Testing
@testable import AIAgentsModule

/// Hand-written lines shaped like Codex rollout records; the text is placeholder content.
private enum Fixture {
    static let session = "0199aaaa-bbbb-7ccc-8ddd-eeeeeeeeeeee"
    /// Appears only in prompt, answer, instruction and tool output text, which no event may carry.
    static let marker = "ZEBRAPLACEHOLDER"

    static let sessionMeta = #"{"timestamp":"2026-10-13T09:00:00.000Z","type":"session_meta","payload":{"id":"0199aaaa-bbbb-7ccc-8ddd-eeeeeeeeeeee","timestamp":"2026-10-13T09:00:00.000Z","cwd":"/Users/example/Projects/tool","originator":"codex_cli_rs","cli_version":"0.46.0","instructions":"ZEBRAPLACEHOLDER guidance","git":{"commit_hash":"abc123","branch":"feature/x","repository_url":"https://example.invalid/repo.git"}}}"#
    static let turnContext = #"{"timestamp":"2026-10-13T09:00:01.000Z","type":"turn_context","payload":{"cwd":"/Users/example/Projects/tool","approval_policy":"on-request","sandbox_policy":{"mode":"workspace-write"},"model":"gpt-5-codex","effort":"medium","summary":"auto"}}"#
    static let taskStarted = #"{"timestamp":"2026-10-13T09:00:01.000Z","type":"event_msg","payload":{"type":"task_started","turn_id":"t1","model_context_window":272000}}"#
    static let turnStarted = #"{"timestamp":"2026-10-13T09:00:01.000Z","type":"event_msg","payload":{"type":"turn_started","turn_id":"t1"}}"#
    static let userMessage = #"{"timestamp":"2026-10-13T09:00:01.000Z","type":"event_msg","payload":{"type":"user_message","message":"ZEBRAPLACEHOLDER request","images":[]}}"#
    static let userItem = #"{"timestamp":"2026-10-13T09:00:01.000Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"ZEBRAPLACEHOLDER request"}]}}"#
    static let reasoning = #"{"timestamp":"2026-10-13T09:00:02.000Z","type":"response_item","payload":{"type":"reasoning","summary":[{"type":"summary_text","text":"ZEBRAPLACEHOLDER plan"}],"encrypted_content":"opaque"}}"#
    static let shellCall = #"{"timestamp":"2026-10-13T09:00:02.500Z","type":"response_item","payload":{"type":"function_call","name":"shell","arguments":"{\"command\":[\"bash\",\"-lc\",\"rg --files | head\"],\"workdir\":\"/Users/example/Projects/tool\"}","call_id":"call_1"}}"#
    static let callOutput = #"{"timestamp":"2026-10-13T09:00:03.000Z","type":"response_item","payload":{"type":"function_call_output","call_id":"call_1","output":"{\"output\":\"ZEBRAPLACEHOLDER files\",\"metadata\":{\"exit_code\":0}}"}}"#
    static let patchCall = #"{"timestamp":"2026-10-13T09:00:03.000Z","type":"response_item","payload":{"type":"custom_tool_call","status":"completed","call_id":"call_2","name":"apply_patch","input":"*** Begin Patch\nZEBRAPLACEHOLDER\n*** End Patch"}}"#
    static let patchOutput = #"{"timestamp":"2026-10-13T09:00:03.000Z","type":"response_item","payload":{"type":"custom_tool_call_output","call_id":"call_2","output":"ZEBRAPLACEHOLDER applied"}}"#
    static let agentMessage = #"{"timestamp":"2026-10-13T09:00:04.000Z","type":"event_msg","payload":{"type":"agent_message","message":"ZEBRAPLACEHOLDER answer"}}"#
    static let tokenCount = #"{"timestamp":"2026-10-13T09:00:04.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":20000,"cached_input_tokens":15000,"output_tokens":800,"reasoning_output_tokens":300,"total_tokens":20800},"last_token_usage":{"input_tokens":5000,"cached_input_tokens":4000,"output_tokens":200,"reasoning_output_tokens":100,"total_tokens":5200},"model_context_window":272000},"rate_limits":{"primary":{"used_percent":12.5,"window_minutes":300,"resets_at":1791878400},"secondary":{"used_percent":40,"window_minutes":10080,"resets_at":1792310400}}}}"#
    static let rateLimitsOnly = #"{"timestamp":"2026-10-13T09:00:01.000Z","type":"event_msg","payload":{"type":"token_count","info":null,"rate_limits":{"primary":{"used_percent":3.0,"window_minutes":300},"secondary":null}}}"#
    static let taskComplete = #"{"timestamp":"2026-10-13T09:00:05.000Z","type":"event_msg","payload":{"type":"task_complete","turn_id":"t1","last_agent_message":"ZEBRAPLACEHOLDER answer","duration_ms":4000}}"#
    static let turnAborted = #"{"timestamp":"2026-10-13T09:00:06.000Z","type":"event_msg","payload":{"type":"turn_aborted","turn_id":"t2","reason":"interrupted"}}"#

    static func call(arguments: String) -> String {
        #"{"timestamp":"2026-10-13T09:00:00Z","type":"response_item","payload":{"type":"function_call","name":"shell","arguments":"# + arguments + #","call_id":"call_9"}}"#
    }
}

@Suite struct CodexRolloutParserTests {
    let start = utc("2026-10-13T09:00:00Z")

    func event(_ kind: AgentEvent.Kind, at seconds: Double) -> AgentEvent {
        AgentEvent(source: .codex, sessionID: Fixture.session, timestamp: start + seconds, kind: kind)
    }

    func parse(_ lines: String...) -> [AgentEvent] {
        var parser = CodexRolloutParser(sessionID: Fixture.session)
        return lines.flatMap { parser.parse(line: $0) }
    }

    @Test func sessionMetaStartsTheSessionWithCwdAndBranch() {
        #expect(parse(Fixture.sessionMeta) == [
            event(.sessionStarted(cwd: "/Users/example/Projects/tool", branch: "feature/x"), at: 0),
        ])
    }

    @Test func taskOrTurnStartedStartsATurn() {
        #expect(parse(Fixture.taskStarted, Fixture.turnStarted) == [event(.turnStarted, at: 1), event(.turnStarted, at: 1)])
    }

    @Test func functionCallStartsAToolWithTheScriptOfAShellWrapper() {
        #expect(parse(Fixture.shellCall) == [event(.toolStarted(name: "shell", summary: "rg --files | head"), at: 2.5)])
    }

    @Test func functionCallSummariesTakeTheFirst120CharactersOfACommand() {
        let long = String(repeating: "y", count: 130)
        #expect(parse(Fixture.call(arguments: #""{\"command\":\"ls -la\\nmore\"}""#)).map(\.kind) == [.toolStarted(name: "shell", summary: "ls -la")])
        #expect(parse(Fixture.call(arguments: #""{\"command\":[\"git\",\"status\"]}""#)).map(\.kind) == [.toolStarted(name: "shell", summary: "git status")])
        #expect(parse(Fixture.call(arguments: #""{\"command\":\""# + long + #"\"}""#)).map(\.kind) == [
            .toolStarted(name: "shell", summary: String(repeating: "y", count: 120)),
        ])
    }

    @Test func functionCallWithoutACommandHasNoSummary() {
        #expect(parse(Fixture.call(arguments: #""{\"path\":\"/tmp\"}""#)).map(\.kind) == [.toolStarted(name: "shell", summary: nil)])
        #expect(parse(Fixture.call(arguments: #""not json""#)).map(\.kind) == [.toolStarted(name: "shell", summary: nil)])
        #expect(parse(Fixture.call(arguments: "null")).map(\.kind) == [.toolStarted(name: "shell", summary: nil)])
    }

    @Test func toolOutputsFinishTheTool() {
        #expect(parse(Fixture.callOutput) == [event(.toolFinished, at: 3)])
        #expect(parse(Fixture.patchCall, Fixture.patchOutput) == [
            event(.toolStarted(name: "apply_patch", summary: nil), at: 3),
            event(.toolFinished, at: 3),
        ])
    }

    @Test func taskCompleteFinishesAndTurnAbortedAbortsTheTurn() {
        #expect(parse(Fixture.taskComplete, Fixture.turnAborted) == [event(.turnFinished, at: 5), event(.turnAborted, at: 6)])
    }

    @Test func tokenCountReportsCumulativeTotalsWithTheTurnModelAndRateLimits() {
        var expected = event(.usageUpdated, at: 4)
        expected.usage = AgentUsage(input: 5000, output: 800, cacheRead: 15000, reasoning: 300, model: "gpt-5-codex", isCumulative: true)
        expected.rateLimits = AgentRateLimits(
            primary: .init(usedPercent: 12.5, windowMinutes: 300, resetsAt: Date(timeIntervalSince1970: 1_791_878_400)),
            secondary: .init(usedPercent: 40, windowMinutes: 10080, resetsAt: Date(timeIntervalSince1970: 1_792_310_400))
        )
        #expect(parse(Fixture.turnContext, Fixture.tokenCount) == [expected])
    }

    @Test func tokenCountBeforeAnyTurnContextHasNoModel() {
        #expect(parse(Fixture.tokenCount).first?.usage?.model == nil)
    }

    @Test func tokenCountWithoutInfoReportsOnlyRateLimits() {
        var expected = event(.usageUpdated, at: 1)
        expected.rateLimits = AgentRateLimits(primary: .init(usedPercent: 3, windowMinutes: 300, resetsAt: nil), secondary: nil)
        #expect(parse(Fixture.rateLimitsOnly) == [expected])
        #expect(parse(#"{"timestamp":"2026-10-13T09:00:01Z","type":"event_msg","payload":{"type":"token_count","info":null,"rate_limits":null}}"#) == [])
    }

    @Test func promptAnswerAndOutputTextNeverReachTheEvents() {
        let events = parse(
            Fixture.sessionMeta, Fixture.turnContext, Fixture.taskStarted, Fixture.userMessage, Fixture.userItem,
            Fixture.reasoning, Fixture.shellCall, Fixture.callOutput, Fixture.patchCall, Fixture.patchOutput,
            Fixture.agentMessage, Fixture.tokenCount, Fixture.taskComplete
        )
        #expect(events.count == 8)
        #expect(!String(describing: events).contains(Fixture.marker))
    }

    @Test func malformedAndUnknownLinesYieldNothing() {
        let lines = [
            "", "not json", "[]", "{}", #"{"type":"event_msg""#,
            #"{"timestamp":"2026-10-13T09:00:00Z","type":"event_msg"}"#,
            #"{"timestamp":"2026-10-13T09:00:00Z","type":"event_msg","payload":{"type":"exec_command_begin"}}"#,
            #"{"timestamp":"2026-10-13T09:00:00Z","type":"compacted","payload":{"message":"ZEBRAPLACEHOLDER"}}"#,
            #"{"timestamp":"2026-10-13T09:00:00Z","type":"response_item","payload":{"type":"function_call","arguments":"{}"}}"#,
        ]
        for line in lines {
            var parser = CodexRolloutParser(sessionID: Fixture.session)
            #expect(parser.parse(line: line) == [], "\(line)")
        }
    }

    @Test func sessionIDComesFromTheRolloutFileName() {
        #expect(CodexRolloutParser.sessionID(fromFileName: "rollout-2026-10-13T09-00-00-0199aaaa-bbbb-7ccc-8ddd-eeeeeeeeeeee.jsonl") == Fixture.session)
        #expect(CodexRolloutParser.sessionID(fromFileName: "rollout-2026-10-13T09-00-00.jsonl") == nil)
        #expect(CodexRolloutParser.sessionID(fromFileName: "notes.txt") == nil)
    }
}
