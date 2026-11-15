import Foundation

/// Turns the lines of one Codex rollout file (`~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`) into events.
/// Only `session_meta` names its session and only `turn_context` names the model, so one parser serves one
/// file and remembers the model for later token counts. Unknown or malformed lines yield no events; prompt,
/// answer, instruction and tool output text is never read into an event.
nonisolated struct CodexRolloutParser: Sendable {
    /// The session every event of this file belongs to, normally `sessionID(fromFileName:)`: tailing may start
    /// after the `session_meta` line.
    let sessionID: String
    /// The model of the latest `turn_context`, attached to the token counts that follow it.
    private(set) var model: String?

    init(sessionID: String) {
        self.sessionID = sessionID
    }

    /// The session id at the end of a `rollout-<time>-<uuid>.jsonl` name.
    static func sessionID(fromFileName name: String) -> String? {
        guard name.hasPrefix("rollout-"), name.hasSuffix(".jsonl") else { return nil }
        let id = String(name.dropLast(".jsonl".count).suffix(36))
        return UUID(uuidString: id) == nil ? nil : id
    }

    mutating func parse(line: String) -> [AgentEvent] {
        guard let record = JSONFields.object(from: line),
              let type = record["type"] as? String,
              let payload = record["payload"] as? [String: Any] else { return [] }
        let timestamp = JSONFields.date(record["timestamp"])
        switch type {
        case "session_meta":
            let branch = JSONFields.string((payload["git"] as? [String: Any])?["branch"])
            return [event(.sessionStarted(cwd: JSONFields.string(payload["cwd"]), branch: branch), at: timestamp)]
        case "turn_context":
            model = JSONFields.string(payload["model"]) ?? model
            return []
        case "response_item":
            return responseItemKind(payload).map { [event($0, at: timestamp)] } ?? []
        case "event_msg":
            return eventMessage(payload, at: timestamp)
        default:
            return []
        }
    }

    private func responseItemKind(_ payload: [String: Any]) -> AgentEvent.Kind? {
        switch payload["type"] as? String {
        case "function_call", "custom_tool_call":
            guard let name = JSONFields.string(payload["name"]) else { return nil }
            return .toolStarted(name: name, summary: Self.commandSummary(arguments: payload["arguments"] as? String))
        case "function_call_output", "custom_tool_call_output":
            return .toolFinished
        default:
            return nil
        }
    }

    private func eventMessage(_ payload: [String: Any], at timestamp: Date?) -> [AgentEvent] {
        switch payload["type"] as? String {
        case "task_started", "turn_started":
            return [event(.turnStarted, at: timestamp)]
        case "task_complete":
            return [event(.turnFinished, at: timestamp)]
        case "turn_aborted":
            return [event(.turnAborted, at: timestamp)]
        case "token_count":
            let totals = (payload["info"] as? [String: Any])?["total_token_usage"] as? [String: Any]
            let totalUsage = totals.map { usage($0) }
            let rateLimits = Self.rateLimits(payload["rate_limits"] as? [String: Any])
            guard totalUsage != nil || rateLimits != nil else { return [] }
            var update = event(.usageUpdated, at: timestamp)
            update.usage = totalUsage
            update.rateLimits = rateLimits
            return [update]
        default:
            return []
        }
    }

    private func event(_ kind: AgentEvent.Kind, at timestamp: Date?) -> AgentEvent {
        AgentEvent(source: .codex, sessionID: sessionID, timestamp: timestamp, kind: kind)
    }

    private func usage(_ totals: [String: Any]) -> AgentUsage {
        let input = JSONFields.count(totals["input_tokens"])
        let cached = JSONFields.count(totals["cached_input_tokens"])
        return AgentUsage(
            input: max(input - cached, 0),
            output: JSONFields.count(totals["output_tokens"]),
            cacheRead: cached,
            reasoning: JSONFields.count(totals["reasoning_output_tokens"]),
            model: model,
            isCumulative: true
        )
    }

    /// The head of a `command` argument: a string, or an argument list where a `bash -lc <script>` wrapper is
    /// reduced to its script.
    private static func commandSummary(arguments: String?) -> String? {
        guard let arguments, let command = JSONFields.object(from: arguments)?["command"] else { return nil }
        if let command = command as? String { return ToolSummary.command(command) }
        guard let parts = command as? [String], !parts.isEmpty else { return nil }
        if parts.count == 3, ["-c", "-lc"].contains(parts[1]) { return ToolSummary.command(parts[2]) }
        return ToolSummary.command(parts.joined(separator: " "))
    }

    private static func rateLimits(_ limits: [String: Any]?) -> AgentRateLimits? {
        let primary = window(limits?["primary"])
        let secondary = window(limits?["secondary"])
        return primary == nil && secondary == nil ? nil : AgentRateLimits(primary: primary, secondary: secondary)
    }

    private static func window(_ value: Any?) -> AgentRateLimits.Window? {
        guard let window = value as? [String: Any], let usedPercent = window["used_percent"] as? Double else { return nil }
        return AgentRateLimits.Window(
            usedPercent: usedPercent,
            windowMinutes: window["window_minutes"] as? Int,
            resetsAt: JSONFields.date(window["resets_at"])
        )
    }
}
