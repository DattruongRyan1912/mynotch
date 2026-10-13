import AgentHookKit
import Foundation

extension HookPayload {
    /// The events this hook adds to the session stream. Like the transcript path it is idempotent: the store
    /// ignores a repeated finish, and a repeated tool or wait leaves the state as it is.
    var agentEvents: [AgentEvent] {
        guard let source = AgentSource(rawValue: source), let kind else { return [] }
        return [AgentEvent(source: source, sessionID: sessionID, timestamp: timestamp, kind: kind)]
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
        default: nil
        }
    }
}
