import AgentHookKit
import Foundation

extension HookPayload {
    /// The events this hook adds to the session stream. Like the transcript path it is idempotent: the store
    /// ignores a repeated finish, and a repeated tool or wait leaves the state as it is.
    var agentEvents: [AgentEvent] {
        guard let source = AgentSource(rawValue: source) else { return [] }
        var kinds = kind.map { [$0] } ?? []
        // An Agent call is a tool like any other, and also says what the subagent that starts next is for.
        if event == "PreToolUse", let tool, HookPayloadFilter.subagentTools.contains(tool), let description = cleanedSummary {
            kinds.append(.subagentRequested(type: cleanedAgentType, description: description))
        }
        let subagentID = agentID.map(HookText.cleanLine).map { String($0.prefix(HookPayload.maxAgentFieldLength)) }.flatMap { $0.isEmpty ? nil : $0 }
        let pid = processID.flatMap { $0 > 1 ? pid_t($0) : nil }
        return kinds.map {
            AgentEvent(source: source, sessionID: sessionID, timestamp: timestamp, kind: $0, subagentID: subagentID, pid: pid)
        }
    }

    /// The agent went on after asking for permission: the tool ran (the user allowed it in the terminal), the turn ended,
    /// a new prompt began or the session ended. A permission request still waiting on the notch is then over.
    var settlesPermissionRequests: Bool {
        ["PostToolUse", "Stop", "StopFailure", "UserPromptSubmit", "SessionEnd"].contains(event)
    }

    /// The type of subagent on one line, cleaned again here: a helper that predates the cleaning may have sent it as it was.
    private var cleanedAgentType: String? {
        agentType.map { String(HookText.cleanLine($0).prefix(HookPayload.maxAgentFieldLength)) }.flatMap { $0.isEmpty ? nil : $0 }
    }

    private var cleanedSummary: String? {
        summary.map { String(HookText.cleanLine($0).prefix(HookPayload.maxSummaryLength)) }.flatMap { $0.isEmpty ? nil : $0 }
    }

    private var kind: AgentEvent.Kind? {
        switch event {
        case "UserPromptSubmit": .turnStarted
        case "PreToolUse": tool.map { .toolStarted(name: $0, summary: summary) }
        case "PostToolUse": .toolFinished
        case "PermissionRequest": .waitingForInput
        case "Notification": ["permission_prompt", "elicitation_dialog"].contains(notificationType) ? .waitingForInput : nil
        case "Stop": .turnFinished
        case "StopFailure": .turnFailed
        case "SessionEnd": .sessionEnded
        case "SubagentStart": agentID == nil ? nil : .subagentStarted(type: cleanedAgentType)
        case "SubagentStop": agentID == nil ? nil : .subagentStopped(type: cleanedAgentType)
        default: nil
        }
    }
}
