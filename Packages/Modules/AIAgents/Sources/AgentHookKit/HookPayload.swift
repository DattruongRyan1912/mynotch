import Foundation

/// What the hook helper tells MyNotch: which session did what, and nothing of the conversation.
public struct HookPayload: Codable, Equatable, Sendable {
    /// A datagram larger than this is not sent: it must fit one small socket message.
    public static let maxDatagramSize = 2048
    /// The longest `summary`, in characters.
    public static let maxSummaryLength = 120
    /// The longest `agentID` or `agentType`, in characters.
    public static let maxAgentFieldLength = 80

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
    /// The subagent the event is about (`SubagentStart`, `SubagentStop`) or runs in (a tool a subagent calls). Nil on the
    /// main thread.
    public var agentID: String?
    /// The kind of subagent: the type a `SubagentStart` or `SubagentStop` names, or the one a call of the Agent tool asks for.
    public var agentType: String?
    /// The process that ran the hook's command, which is the agent's, so MyNotch can find the terminal it runs in.
    public var processID: Int32?
    /// Set only on a permission request, and only on the stream socket: what the request asks to do, which the status
    /// datagram never carries. A request without it is from a helper that predates it, and is never shown as whole.
    public var detail: PermissionDetail?

    public init(
        source: String, event: String, sessionID: String, cwd: String? = nil, tool: String? = nil,
        summary: String? = nil, notificationType: String? = nil, timestamp: Date, detail: PermissionDetail? = nil,
        agentID: String? = nil, agentType: String? = nil, processID: Int32? = nil
    ) {
        self.source = source
        self.event = event
        self.sessionID = sessionID
        self.cwd = cwd
        self.tool = tool
        self.summary = summary
        self.notificationType = notificationType
        self.timestamp = timestamp
        self.detail = detail
        self.agentID = agentID
        self.agentType = agentType
        self.processID = processID
    }

    /// The JSON to send as a datagram, which is about status only and so never has the detail. Over the size limit the
    /// summary goes first, then the cwd; nil if it is still too large.
    public func encodedDatagram() -> Data? {
        var status = self
        status.detail = nil
        return status.encoded(within: Self.maxDatagramSize)
    }

    /// The JSON within `limit` bytes. What does not fit goes in this order: the summary, the cwd, the detail. Nil if it is
    /// still too large.
    func encoded(within limit: Int) -> Data? {
        var candidate = self
        for step in 0...3 {
            switch step {
            case 1: candidate.summary = nil
            case 2: candidate.cwd = nil
            case 3: candidate.detail = nil
            default: break
            }
            if let data = try? Self.encoder.encode(candidate), data.count <= limit { return data }
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
    /// The tool that starts a subagent: `Agent` now, `Task` before it was renamed.
    public static let subagentTools: Set<String> = ["Agent", "Task"]
    private static let subagentEvents: Set<String> = ["SubagentStart", "SubagentStop"]

    public static func make(source: String, hookJSON: Data, now: Date) -> HookPayload? {
        guard sources.contains(source),
              let object = (try? JSONSerialization.jsonObject(with: hookJSON)) as? [String: Any],
              let event = string(object["hook_event_name"]),
              let sessionID = string(object["session_id"])
        else { return nil }
        let tool = string(object["tool_name"])
        let input = object["tool_input"] as? [String: Any]
        var detail = event == PermissionWire.eventName ? PermissionDetail.describing(tool: tool, input: input) : nil
        // A name too long to show whole is cut, and then the request is not whole either.
        if let tool, tool.count > PermissionDetail.maxToolLength { detail?.isComplete = false }
        return HookPayload(
            source: source, event: event, sessionID: sessionID, cwd: string(object["cwd"]).map(HookText.cleanLine),
            tool: tool.map { String(HookText.cleanLine($0).prefix(PermissionDetail.maxToolLength)) },
            summary: summary(tool: tool, input: input), notificationType: string(object["notification_type"]), timestamp: now,
            detail: detail, agentID: agentField(object["agent_id"]),
            agentType: agentType(event: event, tool: tool, object: object, input: input)
        )
    }

    private static func string(_ value: Any?) -> String? {
        guard let text = value as? String, !text.isEmpty else { return nil }
        return text
    }

    /// An id or a type on one line, cut so that the datagram stays small.
    private static func agentField(_ value: Any?) -> String? {
        guard let text = string(value) else { return nil }
        let cleaned = String(HookText.cleanLine(text).prefix(HookPayload.maxAgentFieldLength))
        return cleaned.isEmpty ? nil : cleaned
    }

    /// Of a subagent only: `agent_type` is also on every event of a session started with `--agent`, which is not one.
    private static func agentType(event: String, tool: String?, object: [String: Any], input: [String: Any]?) -> String? {
        if subagentEvents.contains(event) { return agentField(object["agent_type"]) }
        if let tool, subagentTools.contains(tool) { return agentField(input?["subagent_type"]) }
        return nil
    }

    /// A short line for the list of sessions: the first line of a command, the name of a file, or what an Agent call is for.
    /// The card of a permission request shows the `detail`, not this.
    private static func summary(tool: String?, input: [String: Any]?) -> String? {
        guard let input else { return nil }
        let text: String
        if tool == "Bash", let command = string(input["command"]) {
            let trimmed = HookText.clean(command).trimmingCharacters(in: .whitespacesAndNewlines)
            text = trimmed.split(whereSeparator: \.isNewline).first.map { String($0).trimmingCharacters(in: .whitespaces) } ?? ""
        } else if let tool, subagentTools.contains(tool) {
            // The few words Claude gives the call, not the prompt it sends.
            let described = string(input["description"]).map { HookText.clean($0).trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
            text = described.split(whereSeparator: \.isNewline).first.map { String($0).trimmingCharacters(in: .whitespaces) } ?? ""
        } else if let path = string(input["file_path"]) ?? string(input["path"]) {
            text = (HookText.cleanLine(path).trimmingCharacters(in: .whitespacesAndNewlines) as NSString).lastPathComponent
        } else {
            return nil
        }
        return text.isEmpty ? nil : String(text.prefix(HookPayload.maxSummaryLength))
    }
}
