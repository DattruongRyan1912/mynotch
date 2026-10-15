import Foundation

public struct MCPServerInfo: Sendable {
    public var name: String
    public var title: String
    public var version: String
    public var instructions: String?

    public init(name: String, title: String, version: String, instructions: String?) {
        self.name = name
        self.title = title
        self.version = version
        self.instructions = instructions
    }
}

public struct MCPTool: Sendable {
    public var name: String
    public var title: String
    public var description: String
    public var inputSchema: JSON
    public var annotations: [String: JSON]

    public init(name: String, title: String, description: String, inputSchema: JSON, annotations: [String: JSON]) {
        self.name = name
        self.title = title
        self.description = description
        self.inputSchema = inputSchema
        self.annotations = annotations
    }
}

/// What a tool answered. A failure the agent can act on (bad arguments, a limit, the feature being off) is `isError`, which
/// the agent reads; a protocol error is for a request that is itself wrong.
public struct MCPToolResult: Equatable, Sendable {
    public var text: String
    public var isError: Bool

    public init(text: String, isError: Bool) {
        self.text = text
        self.isError = isError
    }
}

/// One MCP server connection on a byte stream: JSON-RPC 2.0 requests in, responses out, with the `tools` capability only.
///
/// Written against modelcontextprotocol.io/specification. Two revisions are served, as a server that supports both must:
/// 2025-11-25 and earlier (a handshake, `initialize` then `notifications/initialized`, and `ping`) and 2026-07-28 (no
/// handshake: every request carries its version and capabilities in `_meta`, results say `resultType`, `server/discover`
/// tells what the server is). A request with the version in `_meta` is served the new way; any other follows an `initialize`.
public final class MCPSession {
    public typealias ToolCall = (String, [String: JSON]) -> MCPToolResult

    public static let modernVersion = "2026-07-28"
    /// Newest first.
    public static let legacyVersions = ["2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05"]

    private static let versionKey = "io.modelcontextprotocol/protocolVersion"
    private static let capabilitiesKey = "io.modelcontextprotocol/clientCapabilities"
    private static let serverInfoKey = "io.modelcontextprotocol/serverInfo"
    /// How long a client may keep the answer to `tools/list` and `server/discover`: the tools never change while the helper runs.
    private static let cacheMilliseconds = 3_600_000

    private let info: MCPServerInfo
    private let tools: [MCPTool]
    private let callTool: ToolCall
    /// An `initialize` was answered, which lets requests without `_meta` through.
    private var isInitialized = false

    private enum Era {
        case legacy, modern
    }

    public init(info: MCPServerInfo, tools: [MCPTool], callTool: @escaping ToolCall) {
        self.info = info
        self.tools = tools
        self.callTool = callTool
    }

    /// The response to one message, without its newline; nil for a notification or a response, which get none.
    public func handle(_ line: Data) -> Data? {
        respond(to: line).flatMap { try? $0.encoded() }
    }

    /// A response to a message that could not be read at all.
    public static func errorLine(code: Int, message: String) -> Data? {
        try? failure(id: nil, code: code, message: message).encoded()
    }

    // MARK: Messages

    private func respond(to line: Data) -> JSON? {
        guard let value = try? JSON(decoding: line) else { return Self.failure(id: nil, code: -32700, message: "Parse error") }
        guard case .object(let message) = value else {
            if case .array = value { return Self.failure(id: nil, code: -32600, message: "Invalid Request: batches are not supported") }
            return Self.failure(id: nil, code: -32600, message: "Invalid Request")
        }
        // The client answering something: this server asks nothing, so there is nothing to do with it.
        if message["method"] == nil, message["result"] != nil || message["error"] != nil { return nil }
        let id: JSON?
        switch message["id"] {
        case nil: id = nil
        case .string?, .int?: id = message["id"]
        default: return Self.failure(id: nil, code: -32600, message: "Invalid Request: id must be a string or an integer")
        }
        guard message["jsonrpc"] == .string("2.0"), case .string(let method)? = message["method"] else {
            return Self.failure(id: id, code: -32600, message: "Invalid Request")
        }
        let params: [String: JSON]
        switch message["params"] {
        case nil: params = [:]
        case .object(let object)?: params = object
        default: return id.map { Self.failure(id: $0, code: -32602, message: "Invalid params: params must be an object") }
        }
        // A notification is never answered, whatever it says: `notifications/initialized`, `notifications/cancelled` (there
        // is nothing in flight to cancel, since calls are answered one at a time) and the rest need nothing from this server.
        guard let id else { return nil }
        return method == "initialize" ? initialize(id: id, params: params) : request(id: id, method: method, params: params)
    }

    private func initialize(id: JSON, params: [String: JSON]) -> JSON {
        guard case .string(let requested)? = params["protocolVersion"] else {
            return Self.failure(id: id, code: -32602, message: "Invalid params: protocolVersion is required")
        }
        isInitialized = true
        var result: [String: JSON] = [
            "protocolVersion": .string(Self.legacyVersions.contains(requested) ? requested : Self.legacyVersions[0]),
            "capabilities": .object(["tools": .object(["listChanged": .bool(false)])]),
            "serverInfo": serverInfo,
        ]
        if let instructions = info.instructions { result["instructions"] = .string(instructions) }
        return Self.success(id: id, result: result)
    }

    private func request(id: JSON, method: String, params: [String: JSON]) -> JSON {
        let era: Era
        switch eraOfRequest(params, method: method) {
        case .failure(let code, let message, let data): return Self.failure(id: id, code: code, message: message, data: data)
        case .success(let found): era = found
        }
        switch method {
        case "ping":
            return success(id: id, result: [:], era: era)
        case "server/discover" where era == .modern:
            var result: [String: JSON] = [
                "supportedVersions": .array(([Self.modernVersion] + Self.legacyVersions).map(JSON.string)),
                "capabilities": .object(["tools": .object([:])]),
                "ttlMs": .int(Self.cacheMilliseconds), "cacheScope": .string("private"),
            ]
            if let instructions = info.instructions { result["instructions"] = .string(instructions) }
            return success(id: id, result: result, era: era)
        case "tools/list":
            // One page: a cursor could only be one this server did not make.
            if let cursor = params["cursor"], cursor != .null {
                return Self.failure(id: id, code: -32602, message: "Invalid params: unknown cursor")
            }
            // The caching fields belong to the revision that defined them.
            var result: [String: JSON] = ["tools": .array(tools.map(Self.toolJSON))]
            if era == .modern {
                result["ttlMs"] = .int(Self.cacheMilliseconds)
                result["cacheScope"] = .string("private")
            }
            return success(id: id, result: result, era: era)
        case "tools/call":
            return call(id: id, params: params, era: era)
        default:
            return Self.failure(id: id, code: -32601, message: "Method not found: \(method)")
        }
    }

    private func call(id: JSON, params: [String: JSON], era: Era) -> JSON {
        guard case .string(let name)? = params["name"] else {
            return Self.failure(id: id, code: -32602, message: "Invalid params: name is required")
        }
        guard tools.contains(where: { $0.name == name }) else {
            return Self.failure(id: id, code: -32602, message: "Unknown tool: \(name)")
        }
        let arguments: [String: JSON]
        switch params["arguments"] {
        case nil, .null?: arguments = [:]
        case .object(let object)?: arguments = object
        default: return Self.failure(id: id, code: -32602, message: "Invalid params: arguments must be an object")
        }
        let result = callTool(name, arguments)
        return success(id: id, result: [
            "content": .array([.object(["type": .string("text"), "text": .string(result.text)])]),
            "isError": .bool(result.isError),
        ], era: era)
    }

    // MARK: Versions

    private enum EraCheck {
        case success(Era)
        case failure(code: Int, message: String, data: JSON?)
    }

    /// Which revision a request speaks. The version in `_meta` makes it a request of 2026-07-28, which then must be
    /// well formed; without one it needs a handshake before it (a `ping` does not).
    private func eraOfRequest(_ params: [String: JSON], method: String) -> EraCheck {
        guard let version = params["_meta"]?[Self.versionKey] else {
            if method == "ping" || isInitialized { return .success(.legacy) }
            return .failure(
                code: -32602,
                message: "Invalid params: send initialize first, or put \(Self.versionKey) and \(Self.capabilitiesKey) in _meta",
                data: nil
            )
        }
        guard case .string(let requested) = version else {
            return .failure(code: -32602, message: "Invalid params: \(Self.versionKey) must be a string", data: nil)
        }
        guard requested == Self.modernVersion else {
            return .failure(code: -32022, message: "Unsupported protocol version", data: .object([
                "supported": .array(([Self.modernVersion] + Self.legacyVersions).map(JSON.string)), "requested": .string(requested),
            ]))
        }
        guard case .object? = params["_meta"]?[Self.capabilitiesKey] else {
            return .failure(code: -32602, message: "Invalid params: _meta is missing \(Self.capabilitiesKey)", data: nil)
        }
        return .success(.modern)
    }

    // MARK: Results

    private var serverInfo: JSON {
        .object(["name": .string(info.name), "title": .string(info.title), "version": .string(info.version)])
    }

    private func success(id: JSON, result: [String: JSON], era: Era) -> JSON {
        var result = result
        if era == .modern {
            result["resultType"] = .string("complete")
            result["_meta"] = .object([Self.serverInfoKey: serverInfo])
        }
        return Self.success(id: id, result: result)
    }

    private static func success(id: JSON, result: [String: JSON]) -> JSON {
        .object(["jsonrpc": .string("2.0"), "id": id, "result": .object(result)])
    }

    private static func failure(id: JSON?, code: Int, message: String, data: JSON? = nil) -> JSON {
        var error: [String: JSON] = ["code": .int(code), "message": .string(message)]
        if let data { error["data"] = data }
        return .object(["jsonrpc": .string("2.0"), "id": id ?? .null, "error": .object(error)])
    }

    private static func toolJSON(_ tool: MCPTool) -> JSON {
        .object([
            "name": .string(tool.name), "title": .string(tool.title), "description": .string(tool.description),
            "inputSchema": tool.inputSchema, "annotations": .object(tool.annotations),
        ])
    }
}
