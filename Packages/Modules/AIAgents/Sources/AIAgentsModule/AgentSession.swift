import Foundation

nonisolated struct AgentSessionKey: Hashable, Sendable {
    var source: AgentSource
    var sessionID: String
}

nonisolated enum AgentState: Equatable, Sendable {
    /// `tool` and `summary` describe the tool running now; both are nil while the agent is thinking.
    case working(tool: String?, summary: String?)
    case waitingForInput
    /// The turn just ended; shown for a few seconds before the session goes idle.
    case finished
    case idle
    case error
}

/// One Claude Code or Codex session as the tab and the activity show it.
nonisolated struct AgentSession: Identifiable, Equatable, Sendable {
    let key: AgentSessionKey
    var id: AgentSessionKey { key }
    var cwd: String?
    var branch: String?
    var state = AgentState.idle
    /// When the latest turn began. Kept after the turn ends, so a view can show how long it took.
    var turnStartedAt: Date?
    var lastEventAt: Date
    var rateLimits: AgentRateLimits?
    var ledger = SessionUsage()
    /// The subagents that run, and the one that finished last; hooks only.
    var subagents = SubagentTracker()
    /// The agent's process, if known: from Claude Code's registry, or from the process that ran a hook. It leads to the terminal.
    var pid: pid_t?

    init(key: AgentSessionKey, lastEventAt: Date) {
        self.key = key
        self.lastEventAt = lastEventAt
    }

    /// The last component of the working directory.
    var project: String? { cwd.map { ($0 as NSString).lastPathComponent } }
    /// Counted from the lines MyNotch read, so a session already running when it started may have used more.
    var usage: UsageTotals { ledger.total }
    var usageByModel: [String: UsageTotals] { ledger.byModel }
    /// What the session cost: the agent's own total when it wrote one, else the estimate. Nil when unknown.
    var costUSD: Double? { ledger.costUSD }
    /// True when any of `costUSD` comes from the price table and must be labelled `UsageCalculator.estimateLabel`.
    var isCostEstimated: Bool { ledger.isCostEstimated }
}
