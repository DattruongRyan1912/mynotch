import Foundation

/// How each agent is named and drawn.
nonisolated extension AgentSource {
    var displayName: String {
        switch self {
        case .claude: "Claude Code"
        case .codex: "Codex"
        }
    }

    /// An SF Symbol: a spark for Claude, code brackets for Codex.
    var systemImage: String {
        switch self {
        case .claude: "sparkle"
        case .codex: "chevron.left.forwardslash.chevron.right"
        }
    }
}
