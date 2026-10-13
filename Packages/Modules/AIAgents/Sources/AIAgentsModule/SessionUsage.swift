import Foundation

/// What one session has used, counted the way each agent reports it, and what it cost.
nonisolated struct SessionUsage: Equatable, Sendable {
    /// What a usage record added once repeats and running totals are accounted for.
    nonisolated struct Counted: Equatable, Sendable {
        var model: String
        /// What this record adds to the day's usage, which can be less than it adds to the session.
        let forToday: UsageTotals
    }

    private nonisolated struct ReportedCost: Equatable, Sendable {
        var usd: Double
        /// The estimate when the agent reported, so only usage after it is estimated on top.
        var estimateThen: Double
    }

    /// How many message ids are remembered for de-duplication. The records of one message are written close
    /// together, so forgetting the oldest ids only bounds memory.
    static let messageMemory = 1_000

    private(set) var total = UsageTotals()
    /// Keyed by model id; usage that names no model is under the empty string.
    private(set) var byModel: [String: UsageTotals] = [:]
    private var messages: [String: UsageTotals] = [:]
    private var messageOrder: [String] = []
    /// The latest running total of an agent that reports totals (Codex).
    private var runningTotal: UsageTotals?
    private var reported: ReportedCost?
    var rememberedMessageCount: Int { messages.count }

    /// Claude repeats a message's usage on each of its records and Codex reports running totals, so what a
    /// record adds is its difference from what was counted before.
    mutating func record(_ usage: AgentUsage) -> Counted {
        let totals = UsageTotals(usage)
        let added: UsageTotals
        let forToday: UsageTotals
        if usage.isCumulative {
            let previous = runningTotal
            runningTotal = totals
            // Fewer tokens than before means the agent counts from zero again.
            added = previous.map { totals.isAtLeast($0) ? totals - $0 : totals } ?? totals
            // A first total that may include earlier work must not be counted as today's.
            forToday = previous == nil && !usage.startsFromZero ? UsageTotals() : added
        } else if let id = usage.messageID {
            if messages[id] == nil { remember(id) }
            added = totals - (messages.updateValue(totals, forKey: id) ?? UsageTotals())
            forToday = added
        } else {
            added = totals
            forToday = added
        }
        total += added
        byModel[usage.model ?? "", default: UsageTotals()] += added
        return Counted(model: usage.model ?? "", forToday: forToday)
    }

    mutating func recordReportedCost(_ usd: Double) {
        reported = ReportedCost(usd: usd, estimateThen: estimatedCostUSD ?? 0)
    }

    /// The price-table cost of everything counted, or nil when no model has a price.
    var estimatedCostUSD: Double? {
        UsageCalculator.estimatedCost(of: byModel)
    }

    /// The agent's own total when it reported one, plus an estimate of what was used since; otherwise the estimate.
    var costUSD: Double? {
        guard let reported else { return estimatedCostUSD }
        return reported.usd + estimatedSinceReport
    }

    /// False only while the cost is exactly what the agent reported.
    var isCostEstimated: Bool {
        reported == nil || estimatedSinceReport > 0
    }

    private var estimatedSinceReport: Double {
        guard let reported else { return 0 }
        return max((estimatedCostUSD ?? 0) - reported.estimateThen, 0)
    }

    private mutating func remember(_ id: String) {
        messageOrder.append(id)
        guard messageOrder.count > Self.messageMemory else { return }
        let forgotten = messageOrder.prefix(Self.messageMemory / 2)
        forgotten.forEach { messages[$0] = nil }
        messageOrder.removeFirst(forgotten.count)
    }
}
