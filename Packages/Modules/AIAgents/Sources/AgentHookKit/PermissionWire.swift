import Foundation

/// What the user can answer to an agent that asks for permission.
public enum PermissionAnswer: String, Sendable {
    case allow, deny
    /// "Hỏi trong terminal": the agent asks in its own prompt, as if MyNotch had not been there.
    case ask
}

/// The bytes the helper and the app exchange over the permission socket: one JSON line each way, and the JSON the
/// agent's hook prints. Foundation only, so the tiny helper can link it.
public enum PermissionWire {
    /// The hook event this is about, in Claude Code and Codex alike.
    public static let eventName = "PermissionRequest"
    /// The most the app reads for a request, so a client that never stops cannot make it buffer without end. A real
    /// request line is far under it: the detail is at most `PermissionDetail.maxLength` characters of four bytes each,
    /// and the rest is a few hundred bytes.
    public static let maxRequestLength = 16_384

    private static let sources: Set<String> = ["claude", "codex"]
    private static let newline = UInt8(ascii: "\n")

    /// The request, ended by a newline. What does not fit `maxRequestLength` goes in this order: the summary, the cwd, the
    /// detail (a request without it is never shown as whole). The JSON has no raw newline, so one line is one request.
    /// Nil when it is still too large.
    public static func requestLine(_ payload: HookPayload) -> Data? {
        guard var line = payload.encoded(within: maxRequestLength - 1) else { return nil }
        line.append(newline)
        return line
    }

    /// Nil unless `line` is a permission request of a known agent that names its tool.
    public static func decodeRequest(_ line: Data) -> HookPayload? {
        guard let payload = try? HookPayload.decode(withoutTrailingNewlines(line)), payload.event == eventName,
              sources.contains(payload.source), payload.tool?.isEmpty == false
        else { return nil }
        return payload
    }

    public static func replyLine(_ answer: PermissionAnswer) -> Data {
        Data("{\"decision\":\"\(answer.rawValue)\"}\n".utf8)
    }

    /// Nil for anything that is not one of the three answers.
    public static func decodeReply(_ data: Data) -> PermissionAnswer? {
        guard let object = (try? JSONSerialization.jsonObject(with: withoutTrailingNewlines(data))) as? [String: Any],
              let name = object["decision"] as? String
        else { return nil }
        return PermissionAnswer(rawValue: name)
    }

    /// What the hook prints to stdout for an answer, in the shape the Claude Code hooks reference gives for
    /// `PermissionRequest` and Codex's hooks page gives for its own. Codex fails closed on `updatedInput`,
    /// `updatedPermissions` and `interrupt`, so a decision carries nothing beyond the behavior and, to deny, a message.
    /// Nil for `ask`: the hook prints nothing and the agent asks as usual.
    public static func hookOutput(for answer: PermissionAnswer) -> Data? {
        let decision: String
        switch answer {
        case .allow: decision = "{\"behavior\":\"allow\"}"
        case .deny: decision = "{\"behavior\":\"deny\",\"message\":\"The user denied this request from the MyNotch notch.\"}"
        case .ask: return nil
        }
        return Data("{\"hookSpecificOutput\":{\"hookEventName\":\"\(eventName)\",\"decision\":\(decision)}}".utf8)
    }

    private static func withoutTrailingNewlines(_ data: Data) -> Data {
        var end = data.endIndex
        while end > data.startIndex, data[data.index(before: end)] == newline { end = data.index(before: end) }
        return data[data.startIndex..<end]
    }
}
