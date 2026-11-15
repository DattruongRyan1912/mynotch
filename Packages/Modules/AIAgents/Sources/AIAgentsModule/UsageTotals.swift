import Foundation

/// Running token counts, without the per-message metadata of `AgentUsage`. The kinds are billed at different
/// prices, so they are kept apart.
nonisolated struct UsageTotals: Equatable, Sendable {
    var input = 0
    /// Includes reasoning tokens.
    var output = 0
    var cacheRead = 0
    var cacheWrite = 0
    /// The part of `output` spent on reasoning; informational, never added to `allTokens` or to the cost.
    var reasoning = 0

    init(input: Int = 0, output: Int = 0, cacheRead: Int = 0, cacheWrite: Int = 0, reasoning: Int = 0) {
        self.input = input
        self.output = output
        self.cacheRead = cacheRead
        self.cacheWrite = cacheWrite
        self.reasoning = reasoning
    }

    init(_ usage: AgentUsage) {
        self.init(input: usage.input, output: usage.output, cacheRead: usage.cacheRead, cacheWrite: usage.cacheWrite, reasoning: usage.reasoning)
    }

    var allTokens: Int { input + output + cacheRead + cacheWrite }
    var isEmpty: Bool { self == UsageTotals() }

    /// False when any kind went down, which for a running total means the agent started counting again.
    func isAtLeast(_ other: UsageTotals) -> Bool {
        input >= other.input && output >= other.output && cacheRead >= other.cacheRead
            && cacheWrite >= other.cacheWrite && reasoning >= other.reasoning
    }

    static func + (lhs: UsageTotals, rhs: UsageTotals) -> UsageTotals {
        UsageTotals(
            input: lhs.input + rhs.input, output: lhs.output + rhs.output, cacheRead: lhs.cacheRead + rhs.cacheRead,
            cacheWrite: lhs.cacheWrite + rhs.cacheWrite, reasoning: lhs.reasoning + rhs.reasoning
        )
    }

    static func - (lhs: UsageTotals, rhs: UsageTotals) -> UsageTotals {
        UsageTotals(
            input: lhs.input - rhs.input, output: lhs.output - rhs.output, cacheRead: lhs.cacheRead - rhs.cacheRead,
            cacheWrite: lhs.cacheWrite - rhs.cacheWrite, reasoning: lhs.reasoning - rhs.reasoning
        )
    }

    static func += (lhs: inout UsageTotals, rhs: UsageTotals) {
        lhs = lhs + rhs
    }
}
