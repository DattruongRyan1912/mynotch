import Foundation
import Testing
@testable import ClipboardMCPKit

/// The helper from the agent's side: a tool call in, the app asked over the socket, text out.
@Suite struct ClipboardMCPHelperTests {
    private final class Clock: @unchecked Sendable {
        var now = 1_000.0
    }

    private final class Asked: @unchecked Sendable {
        var requests: [ClipboardMCPRequest] = []
        var outcome = ClipboardMCPClient.Outcome.reply(.success(.object(["count": .int(0), "items": .array([])])))
    }

    private let clock = Clock()
    private let asked = Asked()
    private let runner: ClipboardMCPHelper.ToolRunner

    init() {
        let clock = clock
        let asked = asked
        runner = ClipboardMCPHelper.ToolRunner(now: { clock.now }) { request in
            asked.requests.append(request)
            return asked.outcome
        }
    }

    private func search(_ query: String = "x") -> MCPToolResult {
        runner.call("search_clipboard", ["query": .string(query)])
    }

    @Test func theAnswerIsTheAppsResultAsCompactTextAndNotAnError() {
        asked.outcome = .reply(.success(.object(["count": .int(1), "items": .array([.object(["id": .string("a"), "text": .string("hi")])])])))
        let result = search()
        #expect(result == MCPToolResult(text: #"{"count":1,"items":[{"id":"a","text":"hi"}]}"#, isError: false))
        #expect(asked.requests == [.search(ClipboardMCPSearch(query: "x"))])
    }

    @Test func anItemIsAskedForByItsId() {
        let id = UUID()
        _ = runner.call("get_clipboard_item", ["id": .string(id.uuidString)])
        #expect(asked.requests == [.item(id)])
    }

    @Test func badArgumentsAreTheAgentsToFixAndTheAppIsNotAsked() {
        let result = runner.call("search_clipboard", ["query": .string("x"), "limit": .int(100)])
        #expect(result == MCPToolResult(text: "limit must be a whole number from 1 to 50", isError: true))
        let tooLong = search(String(repeating: "a", count: 501))
        #expect(tooLong == MCPToolResult(text: "query must be at most 500 characters", isError: true))
        #expect(asked.requests.isEmpty)
    }

    @Test func aQueryThatIsTooBigOnceWrittenOutIsTheAgentsToShortenAndSaysSo() {
        let heavy = String(repeating: "a" + String(repeating: "\u{0301}", count: 20), count: 100)
        let result = search(heavy)
        #expect(result.isError)
        #expect(result.text.contains("query is too long"))
        #expect(!result.text.contains("did not answer"))
        #expect(asked.requests.isEmpty)
    }

    @Test func aRefusalFromTheAppIsToldAsItIs() {
        asked.outcome = .reply(.failure(.disabled, "The clipboard is not shared right now."))
        #expect(search() == MCPToolResult(text: "The clipboard is not shared right now.", isError: true))
    }

    @Test func anAppThatIsNotThereSaysWhatToDoAboutIt() {
        asked.outcome = .unreachable
        let result = search()
        #expect(result.isError)
        #expect(result.text.contains("MyNotch is not running"))
        #expect(result.text.contains(ClipboardMCPMessages.settingName))
    }

    @Test func anUntrustedSocketIsNotUsedAndTheAgentIsToldWhy() {
        asked.outcome = .untrusted
        let result = search()
        #expect(result.isError)
        #expect(result.text.contains("not private to your user"))
    }

    @Test func noAnswerIsATimeout() {
        asked.outcome = .noAnswer
        #expect(search().text.contains("did not answer"))
        #expect(search().isError)
    }

    @Test func theEleventhCallInASecondIsRefusedWithoutAskingTheApp() {
        for _ in 0..<10 { #expect(!search().isError) }
        let result = search()
        #expect(result.isError)
        #expect(result.text.contains("at most 10 calls per second"))
        #expect(asked.requests.count == 10)
        // A second later the gate is open again.
        clock.now += 1
        #expect(!search().isError)
    }

    @Test func aCallWithBadArgumentsDoesNotUseUpAPlace() {
        for _ in 0..<50 { _ = runner.call("search_clipboard", ["limit": .int(1)]) }
        for _ in 0..<10 { #expect(!search().isError) }
    }

    // MARK: Over a real socket

    private func session(socketPath: String) -> MCPSession {
        let runner = ClipboardMCPHelper.ToolRunner(socketPath: socketPath, timeout: 60)
        return MCPSession(info: ClipboardMCPTools.serverInfo, tools: ClipboardMCPTools.definitions, callTool: runner.call)
    }

    @Test func aToolCallThroughTheSessionReachesTheFakeAppAndComesBack() throws {
        let reply = ClipboardMCPWireReply.success(.object(["count": .int(0), "items": .array([])]))
        let app = try FakeMCPApp(behavior: .reply(String(decoding: ClipboardMCPWire.replyLine(reply) ?? Data(), as: UTF8.self)))
        let session = session(socketPath: app.socketPath)
        _ = session.handle(Data(#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25"}}"#.utf8))
        let answer = try #require(session.handle(Data(#"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"search_clipboard","arguments":{"query":"link","kind":"link"}}}"#.utf8)))
        let json = try JSON(decoding: answer)
        #expect(json["result"]?["isError"] == .bool(false))
        #expect(json["result"]?["content"] == .array([.object(["type": .string("text"), "text": .string(#"{"count":0,"items":[]}"#)])]))
        let received = try #require(app.requests.first)
        #expect(ClipboardMCPWire.decodeRequest(received) == .request(.search(ClipboardMCPSearch(query: "link", kind: .link))))
    }

    @Test func withNoAppTheSessionStillAnswersWithAClearError() throws {
        let session = session(socketPath: "/tmp/mn-\(UUID().uuidString.prefix(8))/mcp.sock")
        let answer = try #require(session.handle(Data(#"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"search_clipboard","arguments":{"query":"x"},"_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28","io.modelcontextprotocol/clientCapabilities":{}}}}"#.utf8)))
        let json = try JSON(decoding: answer)
        #expect(json["result"]?["isError"] == .bool(true))
        #expect(json["result"]?["resultType"] == .string("complete"))
        #expect(json["error"] == nil)
    }
}
