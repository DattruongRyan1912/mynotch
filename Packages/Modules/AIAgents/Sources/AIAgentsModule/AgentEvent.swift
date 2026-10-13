import Foundation

nonisolated enum AgentSource: String, Hashable, Sendable {
    case claude, codex
}

/// One thing an agent did, normalised from a Claude Code or Codex record. Holds no prompt or answer text:
/// only tool names, a short summary, timestamps, ids, usage numbers and where the session runs.
nonisolated struct AgentEvent: Equatable, Sendable {
    nonisolated enum Kind: Equatable, Sendable {
        case turnStarted
        /// `summary` is at most 120 characters: the head of a shell command or a file name.
        case toolStarted(name: String, summary: String?)
        case toolFinished
        case turnFinished
        case turnAborted
        case waitingForInput
        /// Claude has no session-start record, so each prompt reports its cwd and branch again; both can change between turns.
        case sessionStarted(cwd: String?, branch: String?)
        case sessionEnded
        /// Only reports usage, cost or rate limits; the session's state does not change.
        case usageUpdated
    }

    var source: AgentSource
    var sessionID: String
    /// Nil when the record has none or it does not parse; the store then uses the time it read the line.
    var timestamp: Date?
    var kind: Kind
    var usage: AgentUsage?
    /// The session's total cost so far, as reported by Claude Code's `cost-state` records.
    var costUSD: Double?
    var rateLimits: AgentRateLimits?
}
