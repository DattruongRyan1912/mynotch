import Foundation

/// Token counts with the same meaning for both agents, so cost is one formula over the four token kinds.
nonisolated struct AgentUsage: Equatable, Sendable {
    /// Input tokens not served from the cache. Codex counts cached tokens inside its input total, so they are
    /// subtracted here to match Claude's `input_tokens`.
    var input = 0
    /// Includes reasoning tokens.
    var output = 0
    var cacheRead = 0
    var cacheWrite = 0
    /// The part of `output` spent on reasoning, when the agent reports it (Codex); informational only.
    var reasoning = 0
    var model: String?
    /// Claude splits one API message over several records that repeat its usage, so totals must count each
    /// message id once, keeping the last record's numbers.
    var messageID: String?
    /// Codex reports running totals for the whole session: they replace, rather than add to, earlier usage.
    var isCumulative = false
    /// For a running total: it is the first of its session and that session was read from its first line, so
    /// the total is all of the session's usage and counts in full for the day it was reported. Without it, the
    /// first total seen is only a starting point: it may include work from before anything was watched.
    var startsFromZero = false
}

/// Codex plan limits: how much of each rolling window is used and when it resets.
nonisolated struct AgentRateLimits: Equatable, Sendable {
    nonisolated struct Window: Equatable, Sendable {
        var usedPercent: Double
        var windowMinutes: Int?
        var resetsAt: Date?
    }

    /// The short window (five hours on current plans).
    var primary: Window?
    /// The long window (one week on current plans).
    var secondary: Window?
}
