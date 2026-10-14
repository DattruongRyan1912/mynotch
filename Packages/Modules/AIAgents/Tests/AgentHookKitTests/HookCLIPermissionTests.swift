import Foundation
import Testing
@testable import AgentHookKit

/// The helper on a `PermissionRequest`: it asks the app over the stream socket and prints the hook's decision, or nothing.
@Suite struct HookCLIPermissionTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let allow = #"{"decision":"allow"}"# + "\n"
    let deny = #"{"decision":"deny"}"# + "\n"

    func hookJSON(tool: String = "Bash") -> Data {
        Data("""
        {"hook_event_name":"PermissionRequest","session_id":"s1","cwd":"/p","tool_name":"\(tool)",
         "tool_input":{"command":"npm test\\nSECRET second line"},"prompt":"SECRET PROMPT"}
        """.utf8)
    }

    /// What the helper printed, and its exit status.
    func run(
        _ app: FakePermissionApp, source: String = "claude", stdin: Data? = nil, timeout: TimeInterval = 30
    ) -> (status: Int32, output: [Data]) {
        var output: [Data] = []
        let status = HookCLI.run(
            arguments: ["--source", source], stdin: stdin ?? hookJSON(), socketPath: app.datagramPath, now: now,
            permissionTimeout: timeout, output: { output.append($0) }
        )
        return (status, output)
    }

    func printedDecision(_ output: [Data]) throws -> (behavior: String?, message: String?) {
        let data = try #require(output.first)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let specific = try #require(object["hookSpecificOutput"] as? [String: Any])
        #expect(specific["hookEventName"] as? String == "PermissionRequest")
        let decision = try #require(specific["decision"] as? [String: Any])
        return (decision["behavior"] as? String, decision["message"] as? String)
    }

    @Test func allowingPrintsTheAllowDecisionOnceAndExitsZero() throws {
        let app = try FakePermissionApp(behavior: .reply(allow))
        let result = run(app)
        #expect(result.status == 0)
        #expect(result.output.count == 1)
        #expect(try printedDecision(result.output).behavior == "allow")
    }

    @Test func denyingPrintsTheDenyDecisionWithAMessage() throws {
        let app = try FakePermissionApp(behavior: .reply(deny))
        let result = run(app, source: "codex")
        #expect(result.status == 0)
        let decision = try printedDecision(result.output)
        #expect(decision.behavior == "deny")
        #expect(!(decision.message ?? "").isEmpty)
    }

    @Test func askingInTheTerminalTimeoutsAndMalformedRepliesPrintNothing() throws {
        let quiet: [(FakePermissionApp.Behavior, TimeInterval)] = [
            (.reply(#"{"decision":"ask"}"# + "\n"), 30), (.silent, 0.3), (.hangUp, 30), (.reply("garbage\n"), 30),
            (.reply(#"{"decision":"maybe"}"# + "\n"), 30),
        ]
        for (behavior, timeout) in quiet {
            let app = try FakePermissionApp(behavior: behavior)
            let result = run(app, timeout: timeout)
            #expect(result.status == 0)
            #expect(result.output.isEmpty, "\(behavior)")
        }
    }

    @Test func theWaitNeverOutlastsTheTimeout() throws {
        let app = try FakePermissionApp(behavior: .silent)
        let start = DispatchTime.now().uptimeNanoseconds
        let result = run(app, timeout: 0.4)
        let seconds = Double(DispatchTime.now().uptimeNanoseconds - start) / 1e9
        #expect(result.status == 0)
        #expect(result.output.isEmpty)
        #expect(seconds < 8)
    }

    @Test func noAppPrintsNothingAndStillTellsTheDatagramSocketWhichIsAllTheOldHelperDid() throws {
        let directory = "/tmp/mn-\(UUID().uuidString.prefix(8))"
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: directory) }
        let receiver = try TestDatagramReceiver(path: directory + "/agent.sock")
        var output: [Data] = []
        let status = HookCLI.run(
            arguments: ["--source", "claude"], stdin: hookJSON(), socketPath: directory + "/agent.sock", now: now,
            permissionTimeout: 30, output: { output.append($0) }
        )
        #expect(status == 0)
        #expect(output.isEmpty)
        let payload = try HookPayload.decode(try #require(receiver.receive()))
        #expect(payload.event == "PermissionRequest")
        #expect(payload.tool == "Bash")
    }

    @Test func noAppAndNoSocketAtAllPrintsNothing() {
        var output: [Data] = []
        let status = HookCLI.run(
            arguments: ["--source", "claude"], stdin: hookJSON(), socketPath: "/tmp/mn-\(UUID().uuidString.prefix(8))/agent.sock", now: now,
            permissionTimeout: 30, output: { output.append($0) }
        )
        #expect(status == 0)
        #expect(output.isEmpty)
    }

    @Test func theAppGetsTheToolAndTheSummaryAndNothingOfThePrompt() throws {
        let app = try FakePermissionApp(behavior: .reply(allow))
        _ = run(app)
        let line = try #require(app.requests.first)
        let text = String(decoding: line, as: UTF8.self)
        #expect(!text.contains("SECRET"))
        let payload = try #require(PermissionWire.decodeRequest(line))
        #expect(payload.tool == "Bash")
        #expect(payload.summary == "npm test")
        #expect(payload.sessionID == "s1")
        #expect(payload.source == "claude")
    }

    /// An allow with no answers would make these tools proceed as if the user had nothing to say.
    @Test func toolsThatNeedTheUsersAnswerAreNeverAskedAbout() throws {
        for tool in ["AskUserQuestion", "ExitPlanMode"] {
            let app = try FakePermissionApp(behavior: .reply(allow))
            let result = run(app, stdin: hookJSON(tool: tool))
            #expect(result.status == 0)
            #expect(result.output.isEmpty, "\(tool)")
            #expect(app.connectionCount == 0, "\(tool)")
        }
    }

    @Test func aRequestWithoutAToolIsNeverAskedAbout() throws {
        let app = try FakePermissionApp(behavior: .reply(allow))
        let json = Data(#"{"hook_event_name":"PermissionRequest","session_id":"s1"}"#.utf8)
        let result = run(app, stdin: json)
        #expect(result.output.isEmpty)
        #expect(app.connectionCount == 0)
    }

    @Test func otherEventsNeverAskAndNeverPrint() throws {
        let app = try FakePermissionApp(behavior: .reply(allow))
        let json = Data(#"{"hook_event_name":"PostToolUse","session_id":"s1","tool_name":"Bash"}"#.utf8)
        let result = run(app, stdin: json)
        #expect(result.status == 0)
        #expect(result.output.isEmpty)
        #expect(app.connectionCount == 0)
    }

    @Test func badInputExitsZeroWithoutAskingOrPrinting() throws {
        let app = try FakePermissionApp(behavior: .reply(allow))
        #expect(run(app, source: "gemini").output.isEmpty)
        #expect(run(app, stdin: Data("garbage".utf8)).output.isEmpty)
        #expect(app.connectionCount == 0)
    }
}
