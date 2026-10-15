import Foundation
import Testing
@testable import ClipboardMCPKit

/// The JSON-RPC and MCP layer, against `modelcontextprotocol.io/specification`: the 2025-11-25 revision (a handshake with
/// `initialize`) and the 2026-07-28 one (every request carries its version and capabilities in `_meta`).
@Suite struct MCPSessionTests {
    private final class Calls: @unchecked Sendable {
        var made: [(name: String, arguments: [String: JSON])] = []
        var result = MCPToolResult(text: "answer", isError: false)
    }

    private let calls = Calls()
    private let session: MCPSession

    init() {
        let calls = calls
        session = MCPSession(
            info: MCPServerInfo(name: "demo", title: "Demo", version: "9.9", instructions: "Read me."),
            tools: ClipboardMCPTools.definitions
        ) { name, arguments in
            calls.made.append((name, arguments))
            return calls.result
        }
    }

    private func send(_ text: String) -> JSON? {
        guard let reply = session.handle(Data(text.utf8)) else { return nil }
        #expect(!String(decoding: reply, as: UTF8.self).contains("\n"))
        return try? JSON(decoding: reply)
    }

    private func errorCode(_ reply: JSON?) -> Int? { reply?["error"]?["code"]?.int }

    private func initialize(version: String = "2025-11-25") {
        _ = send(#"{"jsonrpc":"2.0","id":0,"method":"initialize","params":{"protocolVersion":"\#(version)","capabilities":{},"clientInfo":{"name":"t","version":"1"}}}"#)
        _ = send(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#)
    }

    private static let meta = #""_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28","io.modelcontextprotocol/clientCapabilities":{}}"#

    // MARK: Framing errors

    @Test func textThatIsNotJSONIsAParseErrorWithANullId() {
        let reply = send("{nope")
        #expect(errorCode(reply) == -32700)
        #expect(reply?["id"] == JSON.null)
        #expect(reply?["jsonrpc"] == .string("2.0"))
    }

    @Test func aBatchIsNotSupported() {
        let reply = send(#"[{"jsonrpc":"2.0","id":1,"method":"ping"}]"#)
        #expect(errorCode(reply) == -32600)
        #expect(reply?["id"] == JSON.null)
    }

    @Test func aValueThatIsNotAnObjectIsAnInvalidRequest() {
        for text in ["3", "\"x\"", "null", "true"] {
            #expect(errorCode(send(text)) == -32600, "\(text)")
        }
    }

    @Test func aRequestMissingItsVersionOrItsMethodIsInvalidAndKeepsItsId() {
        let wrongVersion = send(#"{"jsonrpc":"1.0","id":4,"method":"ping"}"#)
        #expect(errorCode(wrongVersion) == -32600)
        #expect(wrongVersion?["id"] == .int(4))
        #expect(errorCode(send(#"{"id":5,"method":"ping"}"#)) == -32600)
        #expect(errorCode(send(#"{"jsonrpc":"2.0","id":6}"#)) == -32600)
        #expect(errorCode(send(#"{"jsonrpc":"2.0","id":7,"method":3}"#)) == -32600)
    }

    @Test func anIdThatIsNullOrNotAStringOrIntegerIsInvalid() {
        for id in ["null", "true", "1.5", "[1]", "{}"] {
            let reply = send(#"{"jsonrpc":"2.0","id":\#(id),"method":"ping"}"#)
            #expect(errorCode(reply) == -32600, "\(id)")
            #expect(reply?["id"] == JSON.null)
        }
    }

    @Test func aStringIdComesBackAsIs() {
        #expect(send(#"{"jsonrpc":"2.0","id":"abc","method":"ping"}"#)?["id"] == .string("abc"))
    }

    @Test func paramsThatAreNotAnObjectAreInvalidParams() {
        #expect(errorCode(send(#"{"jsonrpc":"2.0","id":1,"method":"tools/list","params":[1]}"#)) == -32602)
    }

    @Test func aResponseFromTheClientIsIgnored() {
        #expect(send(#"{"jsonrpc":"2.0","id":1,"result":{}}"#) == nil)
        #expect(send(#"{"jsonrpc":"2.0","id":1,"error":{"code":-1,"message":"m"}}"#) == nil)
    }

    @Test func aNotificationNeverGetsAnAnswerEvenWhenItIsWrong() {
        #expect(send(#"{"jsonrpc":"2.0","method":"notifications/cancelled","params":{"requestId":1}}"#) == nil)
        #expect(send(#"{"jsonrpc":"2.0","method":"notifications/whatever"}"#) == nil)
        #expect(send(#"{"jsonrpc":"2.0","method":"tools/call","params":{"name":"search_clipboard","arguments":{"query":"x"}}}"#) == nil)
        #expect(calls.made.isEmpty)
    }

    // MARK: The handshake (2025-11-25 and earlier)

    @Test func initializeAnswersWithTheSameVersionWhenItIsSupported() {
        for version in ["2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05"] {
            let reply = send(#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"\#(version)","capabilities":{},"clientInfo":{"name":"t","version":"1"}}}"#)
            #expect(reply?["result"]?["protocolVersion"] == .string(version))
        }
    }

    @Test func initializeAnswersWithTheLatestVersionItKnowsWhenTheRequestedOneIsNot() {
        for version in ["1999-01-01", "2026-07-28", "latest"] {
            let reply = send(#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"\#(version)","capabilities":{}}}"#)
            #expect(reply?["result"]?["protocolVersion"] == .string("2025-11-25"))
        }
    }

    @Test func initializeDeclaresToolsAndNamesTheServer() {
        let result = send(#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{}}}"#)?["result"]
        #expect(result?["capabilities"]?["tools"] == .object(["listChanged": .bool(false)]))
        #expect(result?["serverInfo"] == .object(["name": .string("demo"), "title": .string("Demo"), "version": .string("9.9")]))
        #expect(result?["instructions"] == .string("Read me."))
        #expect(result?["resultType"] == nil)
    }

    @Test func initializeWithoutAVersionIsInvalid() {
        #expect(errorCode(send(#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"capabilities":{}}}"#)) == -32602)
        #expect(errorCode(send(#"{"jsonrpc":"2.0","id":1,"method":"initialize"}"#)) == -32602)
        #expect(errorCode(send(#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":3}}"#)) == -32602)
    }

    @Test func theInitializedNotificationGetsNoAnswer() {
        #expect(send(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#) == nil)
    }

    @Test func pingAnswersWithAnEmptyResultBeforeAndAfterTheHandshake() {
        #expect(send(#"{"jsonrpc":"2.0","id":1,"method":"ping"}"#)?["result"] == .object([:]))
        initialize()
        #expect(send(#"{"jsonrpc":"2.0","id":2,"method":"ping"}"#)?["result"] == .object([:]))
    }

    @Test func nothingElseIsAnsweredBeforeTheHandshakeOrWithoutVersionMetadata() {
        let reply = send(#"{"jsonrpc":"2.0","id":1,"method":"tools/list"}"#)
        #expect(errorCode(reply) == -32602)
        #expect(reply?["error"]?["message"]?.string?.contains("initialize") == true)
        #expect(errorCode(send(#"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"search_clipboard","arguments":{"query":"x"}}}"#)) == -32602)
        #expect(calls.made.isEmpty)
    }

    // MARK: Tools after the handshake

    @Test func theToolListIsTheTwoToolsWithTheirSchemas() throws {
        initialize()
        let result = try #require(send(#"{"jsonrpc":"2.0","id":3,"method":"tools/list"}"#)?["result"])
        guard case .array(let tools)? = result["tools"] else {
            Issue.record("no tools")
            return
        }
        #expect(tools.compactMap { $0["name"]?.string } == ["search_clipboard", "get_clipboard_item"])
        #expect(tools.allSatisfy { $0["inputSchema"]?["type"] == .string("object") && $0["annotations"]?["readOnlyHint"] == .bool(true) })
        #expect(tools.allSatisfy { $0["title"]?.string?.isEmpty == false && $0["description"]?.string?.isEmpty == false })
        #expect(result["nextCursor"] == nil)
        #expect(result["resultType"] == nil)
    }

    @Test func aCursorIsInvalidSinceTheListIsOnePage() {
        initialize()
        #expect(errorCode(send(#"{"jsonrpc":"2.0","id":3,"method":"tools/list","params":{"cursor":"abc"}}"#)) == -32602)
        #expect(send(#"{"jsonrpc":"2.0","id":4,"method":"tools/list","params":{}}"#)?["result"] != nil)
    }

    @Test func aCallPassesTheNameAndArgumentsAndReturnsTheTextAsContent() {
        initialize()
        let reply = send(#"{"jsonrpc":"2.0","id":9,"method":"tools/call","params":{"name":"search_clipboard","arguments":{"query":"x","limit":3}}}"#)
        #expect(reply?["id"] == .int(9))
        #expect(reply?["result"]?["content"] == .array([.object(["type": .string("text"), "text": .string("answer")])]))
        #expect(reply?["result"]?["isError"] == .bool(false))
        #expect(calls.made.count == 1)
        #expect(calls.made.first?.name == "search_clipboard")
        #expect(calls.made.first?.arguments == ["query": .string("x"), "limit": .int(3)])
    }

    @Test func aToolFailureIsAResultWithIsErrorSoTheAgentCanReadIt() {
        initialize()
        calls.result = MCPToolResult(text: "limit must be a whole number from 1 to 50", isError: true)
        let reply = send(#"{"jsonrpc":"2.0","id":9,"method":"tools/call","params":{"name":"search_clipboard","arguments":{"query":"x"}}}"#)
        #expect(reply?["error"] == nil)
        #expect(reply?["result"]?["isError"] == .bool(true))
        #expect(reply?["result"]?["content"]?.arrayFirst?["text"] == .string("limit must be a whole number from 1 to 50"))
    }

    @Test func aCallWithoutArgumentsPassesAnEmptyObject() {
        initialize()
        _ = send(#"{"jsonrpc":"2.0","id":9,"method":"tools/call","params":{"name":"get_clipboard_item"}}"#)
        #expect(calls.made.first?.arguments == [:])
    }

    @Test func anUnknownToolIsAProtocolErrorAndIsNeverCalled() {
        initialize()
        let reply = send(#"{"jsonrpc":"2.0","id":9,"method":"tools/call","params":{"name":"rm_rf","arguments":{}}}"#)
        #expect(errorCode(reply) == -32602)
        #expect(reply?["error"]?["message"] == .string("Unknown tool: rm_rf"))
        #expect(calls.made.isEmpty)
    }

    @Test func aCallWithABadShapeIsInvalidParams() {
        initialize()
        for params in ["{}", #"{"name":3}"#, #"{"name":"search_clipboard","arguments":[1]}"#, #"{"name":"search_clipboard","arguments":"x"}"#] {
            #expect(errorCode(send(#"{"jsonrpc":"2.0","id":9,"method":"tools/call","params":\#(params)}"#)) == -32602, "\(params)")
        }
        #expect(errorCode(send(#"{"jsonrpc":"2.0","id":9,"method":"tools/call"}"#)) == -32602)
        #expect(calls.made.isEmpty)
    }

    @Test func anUnknownMethodIsNotFound() {
        initialize()
        let reply = send(#"{"jsonrpc":"2.0","id":9,"method":"resources/list"}"#)
        #expect(errorCode(reply) == -32601)
        #expect(reply?["id"] == .int(9))
        #expect(errorCode(send(#"{"jsonrpc":"2.0","id":10,"method":"server/discover"}"#)) == -32601)
    }

    // MARK: Per-request metadata (2026-07-28)

    @Test func discoverNamesTheVersionsToolsAndServer() {
        let result = send(#"{"jsonrpc":"2.0","id":"d","method":"server/discover","params":{\#(Self.meta)}}"#)?["result"]
        #expect(result?["resultType"] == .string("complete"))
        #expect(result?["supportedVersions"] == .array(["2026-07-28", "2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05"].map(JSON.string)))
        #expect(result?["capabilities"]?["tools"] == .object([:]))
        #expect(result?["_meta"]?["io.modelcontextprotocol/serverInfo"] == .object(["name": .string("demo"), "title": .string("Demo"), "version": .string("9.9")]))
        #expect(result?["instructions"] == .string("Read me."))
        #expect(result?["ttlMs"]?.int != nil)
        #expect(result?["cacheScope"] != nil)
    }

    @Test func aRequestWithMetadataNeedsNoHandshake() {
        let list = send(#"{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{\#(Self.meta)}}"#)?["result"]
        #expect(list?["resultType"] == .string("complete"))
        #expect(list?["ttlMs"]?.int != nil)
        #expect(list?["cacheScope"] == .string("private"))
        #expect(list?["_meta"]?["io.modelcontextprotocol/serverInfo"]?["name"] == .string("demo"))
        #expect(list?["tools"]?.arrayCount == 2)

        let call = send(#"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"get_clipboard_item","arguments":{"id":"x"},\#(Self.meta)}}"#)?["result"]
        #expect(call?["resultType"] == .string("complete"))
        #expect(call?["isError"] == .bool(false))
        #expect(calls.made.first?.arguments == ["id": .string("x")])
    }

    @Test func theMetadataIsNotPassedToTheTool() {
        _ = send(#"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"search_clipboard","arguments":{"query":"x"},\#(Self.meta)}}"#)
        #expect(calls.made.first?.arguments == ["query": .string("x")])
    }

    @Test func aVersionTheServerDoesNotKnowIsNamedBackWithTheOnesItDoes() {
        let reply = send(#"{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{"_meta":{"io.modelcontextprotocol/protocolVersion":"1900-01-01","io.modelcontextprotocol/clientCapabilities":{}}}}"#)
        #expect(errorCode(reply) == -32022)
        #expect(reply?["error"]?["data"]?["requested"] == .string("1900-01-01"))
        #expect(reply?["error"]?["data"]?["supported"]?.arrayFirst == .string("2026-07-28"))
    }

    @Test func aRequestWithoutCapabilitiesOrWithAVersionOfTheWrongTypeIsInvalid() {
        #expect(errorCode(send(#"{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{"_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28"}}}"#)) == -32602)
        #expect(errorCode(send(#"{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{"_meta":{"io.modelcontextprotocol/protocolVersion":20260728,"io.modelcontextprotocol/clientCapabilities":{}}}}"#)) == -32602)
    }

    @Test func aProgressTokenAloneIsNotVersionMetadata() {
        initialize()
        let reply = send(#"{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{"_meta":{"progressToken":"p"}}}"#)
        #expect(reply?["result"]?["tools"] != nil)
        #expect(reply?["result"]?["resultType"] == nil)
    }

    @Test func pingStillAnswersToARequestWithMetadata() {
        let reply = send(#"{"jsonrpc":"2.0","id":1,"method":"ping","params":{\#(Self.meta)}}"#)
        #expect(reply?["result"]?["resultType"] == .string("complete"))
    }
}

private extension JSON {
    /// The first element of an array.
    var arrayFirst: JSON? {
        if case .array(let values) = self { values.first } else { nil }
    }

    var arrayCount: Int? {
        if case .array(let values) = self { values.count } else { nil }
    }
}
