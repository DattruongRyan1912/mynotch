import Foundation

/// Why the app did not answer a request with results. `message` goes to the agent.
public enum ClipboardMCPFailure: String, CaseIterable, Sendable {
    /// Turned off in Settings, or turned off while the call was on its way.
    case disabled
    case rateLimited
    case invalidArguments
    /// No such item, or one the agent may not see: the two are not told apart.
    case notFound
    case versionMismatch
    case failed
}

public enum ClipboardMCPWireReply: Equatable, Sendable {
    case success(JSON)
    case failure(ClipboardMCPFailure, String)
}

/// What the helper and the app say to each other on the socket: one JSON line each way, then the connection is closed. The
/// helper asks, the app answers from the history it keeps in memory.
public enum ClipboardMCPWire {
    public static let version = 1
    /// A request holds a text of at most 500 characters (2 KB) and a few small fields.
    public static let maxRequestLength = 4096
    /// Fifty items of 8 KB, and what escaping makes of them.
    public static let maxReplyLength = 4 << 20

    public enum DecodedRequest: Equatable, Sendable {
        case request(ClipboardMCPRequest)
        /// Well formed, but it must not be served: another version, or arguments that break the rules.
        case rejected(ClipboardMCPFailure, String)
        case unreadable
    }

    public static func requestLine(_ request: ClipboardMCPRequest) -> Data? {
        let object = JSON.object(["version": .int(version), "tool": .string(request.tool), "arguments": request.arguments])
        return (try? object.encoded()).map { $0 + Data("\n".utf8) }
    }

    /// `line` has no newline.
    public static func decodeRequest(_ line: Data) -> DecodedRequest {
        guard line.count <= maxRequestLength, let object = (try? JSON(decoding: line))?.object, let sent = object["version"]?.int,
              case .string(let tool)? = object["tool"], case .object(let arguments)? = object["arguments"]
        else { return .unreadable }
        guard sent == version else {
            return .rejected(.versionMismatch, "The MyNotch app and its helper (mynotch-clipboard-mcp) are different versions. Restart MyNotch, then restart the agent.")
        }
        do {
            return .request(try ClipboardMCPRequest.parse(tool: tool, arguments: arguments))
        } catch {
            return .rejected(.invalidArguments, error.message)
        }
    }

    public static func replyLine(_ reply: ClipboardMCPWireReply) -> Data? {
        let object: JSON = switch reply {
        case .success(let result): .object(["ok": .bool(true), "result": result])
        case .failure(let reason, let message): .object(["ok": .bool(false), "failure": .string(reason.rawValue), "message": .string(message)])
        }
        return (try? object.encoded()).map { $0 + Data("\n".utf8) }
    }

    /// `line` has no newline.
    public static func decodeReply(_ line: Data) -> ClipboardMCPWireReply? {
        guard line.count <= maxReplyLength, let object = (try? JSON(decoding: line))?.object, case .bool(let ok)? = object["ok"] else { return nil }
        if ok { return object["result"].map(ClipboardMCPWireReply.success) }
        guard case .string(let raw)? = object["failure"], let reason = ClipboardMCPFailure(rawValue: raw),
              case .string(let message)? = object["message"]
        else { return nil }
        return .failure(reason, message)
    }
}
