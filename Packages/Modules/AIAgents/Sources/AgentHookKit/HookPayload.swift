import Foundation

/// What the hook helper tells MyNotch: which session did what, and nothing of the conversation.
public struct HookPayload: Codable, Equatable, Sendable {
    /// A datagram larger than this is not sent: it must fit one small socket message.
    public static let maxDatagramSize = 2048
    /// The longest `summary`, in characters.
    public static let maxSummaryLength = 120

    /// "claude" or "codex".
    public var source: String
    /// The hook event name, e.g. `PreToolUse`.
    public var event: String
    public var sessionID: String
    public var cwd: String?
    public var tool: String?
    /// The head of a shell command or a file name, never file contents.
    public var summary: String?
    public var notificationType: String?
    public var timestamp: Date

    public init(
        source: String, event: String, sessionID: String, cwd: String? = nil, tool: String? = nil,
        summary: String? = nil, notificationType: String? = nil, timestamp: Date
    ) {
        self.source = source
        self.event = event
        self.sessionID = sessionID
        self.cwd = cwd
        self.tool = tool
        self.summary = summary
        self.notificationType = notificationType
        self.timestamp = timestamp
    }

    /// The JSON to send. Over the size limit the summary goes first, then the cwd; nil if it is still too large.
    public func encodedDatagram() -> Data? {
        var candidate = self
        for step in 0...2 {
            if step == 1 { candidate.summary = nil }
            if step == 2 { candidate.cwd = nil }
            if let data = try? Self.encoder.encode(candidate), data.count <= Self.maxDatagramSize { return data }
        }
        return nil
    }

    public static func decode(_ data: Data) throws -> HookPayload {
        try JSONDecoder.hook.decode(HookPayload.self, from: data)
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }
}

private extension JSONDecoder {
    static var hook: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }
}

/// Builds a payload from the JSON a Claude Code or Codex hook receives on stdin. Only a fixed list of keys is
/// read, so prompts, answers and tool output can never reach the payload.
public enum HookPayloadFilter {
    private static let sources: Set<String> = ["claude", "codex"]

    public static func make(source: String, hookJSON: Data, now: Date) -> HookPayload? {
        guard sources.contains(source),
              let object = (try? JSONSerialization.jsonObject(with: hookJSON)) as? [String: Any],
              let event = string(object["hook_event_name"]),
              let sessionID = string(object["session_id"])
        else { return nil }
        let tool = string(object["tool_name"])
        return HookPayload(
            source: source, event: event, sessionID: sessionID, cwd: string(object["cwd"]), tool: tool,
            summary: summary(tool: tool, input: object["tool_input"] as? [String: Any]),
            notificationType: string(object["notification_type"]), timestamp: now
        )
    }

    private static func string(_ value: Any?) -> String? {
        guard let text = value as? String, !text.isEmpty else { return nil }
        return text
    }

    private static func summary(tool: String?, input: [String: Any]?) -> String? {
        guard let input else { return nil }
        let text: String
        if tool == "Bash", let command = string(input["command"]) {
            let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
            text = trimmed.split(whereSeparator: \.isNewline).first.map { String($0).trimmingCharacters(in: .whitespaces) } ?? ""
        } else if let path = string(input["file_path"]) ?? string(input["path"]) {
            text = (path.trimmingCharacters(in: .whitespacesAndNewlines) as NSString).lastPathComponent
        } else {
            return nil
        }
        return text.isEmpty ? nil : String(text.prefix(HookPayload.maxSummaryLength))
    }
}
