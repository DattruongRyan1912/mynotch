import Foundation

/// Turns one line of a Claude Code transcript (`~/.claude/projects/<slug>/<sessionId>.jsonl`) into events.
/// The format is undocumented, so unknown or malformed records yield no events rather than errors, and a
/// missing field only drops that field. Prompt, answer and tool output text is read at most to classify a
/// record and never copied into an event.
nonisolated enum ClaudeTranscriptParser {
    /// Tools whose summary is the name of the file they work on.
    private static let fileTools: Set<String> = ["Read", "Edit", "MultiEdit", "Write"]
    /// Claude Code records an interruption (Esc) as a user message starting with this text instead of finishing the turn.
    private static let interruptionPrefix = "[Request interrupted by user"

    /// - Parameter fallbackSessionID: the session the transcript belongs to (its file name), for records that
    ///   don't name one.
    static func parse(line: String, sessionID fallbackSessionID: String? = nil) -> [AgentEvent] {
        guard let record = JSONFields.object(from: line),
              let type = record["type"] as? String,
              let sessionID = JSONFields.string(record["sessionId"]) ?? fallbackSessionID else { return [] }
        // Subagent (sidechain) records belong to a turn of the main conversation; they must not start or end it.
        let isSidechain = record["isSidechain"] as? Bool ?? false
        let message = record["message"] as? [String: Any]
        var usage: AgentUsage?
        var costUSD: Double?
        let kinds: [AgentEvent.Kind]
        switch type {
        case "user":
            kinds = userKinds(record, content: message?["content"], isSidechain: isSidechain)
        case "assistant":
            usage = message.flatMap { Self.usage(of: $0) }
            kinds = assistantKinds(message, isSidechain: isSidechain, hasUsage: usage != nil)
        case "system":
            kinds = record["subtype"] as? String == "stop_hook_summary" && !isSidechain ? [.turnFinished] : []
        case "cost-state":
            costUSD = record["totalCostUSD"] as? Double
            kinds = costUSD == nil ? [] : [.usageUpdated]
        default:
            kinds = []
        }
        let timestamp = JSONFields.date(record["timestamp"])
        return kinds.map {
            AgentEvent(source: .claude, sessionID: sessionID, timestamp: timestamp, kind: $0, usage: usage, costUSD: costUSD)
        }
    }

    private static func userKinds(_ record: [String: Any], content: Any?, isSidechain: Bool) -> [AgentEvent.Kind] {
        // Context Claude Code injects itself (command caveats, compaction summaries) is not a new prompt.
        if record["isMeta"] as? Bool == true || record["isCompactSummary"] as? Bool == true { return [] }
        let blocks = JSONFields.objects(content)
        if blocks.contains(where: { $0["type"] as? String == "tool_result" }) { return [.toolFinished] }
        if isSidechain { return [] }
        let textBlock = blocks.first { $0["type"] as? String == "text" }
        let text = content as? String ?? textBlock?["text"] as? String
        if text?.hasPrefix(interruptionPrefix) == true { return [.turnAborted] }
        let cwd = JSONFields.string(record["cwd"])
        let branch = JSONFields.string(record["gitBranch"])
        return (cwd == nil && branch == nil ? [] : [.sessionStarted(cwd: cwd, branch: branch)]) + [.turnStarted]
    }

    private static func assistantKinds(_ message: [String: Any]?, isSidechain: Bool, hasUsage: Bool) -> [AgentEvent.Kind] {
        var kinds: [AgentEvent.Kind] = JSONFields.objects(message?["content"]).compactMap { block in
            guard block["type"] as? String == "tool_use", let name = JSONFields.string(block["name"]) else { return nil }
            return .toolStarted(name: name, summary: summary(tool: name, input: block["input"] as? [String: Any]))
        }
        if message?["stop_reason"] as? String == "end_turn", !isSidechain { kinds.append(.turnFinished) }
        // Thinking and text records still carry the message's usage.
        if kinds.isEmpty, hasUsage { kinds = [.usageUpdated] }
        return kinds
    }

    private static func summary(tool: String, input: [String: Any]?) -> String? {
        if tool == "Bash", let command = input?["command"] as? String { return ToolSummary.command(command) }
        if fileTools.contains(tool), let path = input?["file_path"] as? String { return ToolSummary.fileName(path) }
        return nil
    }

    private static func usage(of message: [String: Any]) -> AgentUsage? {
        guard let usage = message["usage"] as? [String: Any] else { return nil }
        return AgentUsage(
            input: JSONFields.count(usage["input_tokens"]),
            output: JSONFields.count(usage["output_tokens"]),
            cacheRead: JSONFields.count(usage["cache_read_input_tokens"]),
            cacheWrite: JSONFields.count(usage["cache_creation_input_tokens"]),
            model: JSONFields.string(message["model"]),
            messageID: JSONFields.string(message["id"])
        )
    }
}
