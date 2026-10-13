import Foundation

/// Estimates what a session cost from its token counts. Claude Code only sometimes writes the real total
/// (`cost-state`), so most costs are list-price estimates and must be shown as such, with `estimateLabel`.
nonisolated enum UsageCalculator {
    /// Shown next to every cost that comes from the price table instead of from the agent.
    static let estimateLabel = "ước tính"

    /// USD per million tokens.
    nonisolated struct Price: Equatable, Sendable {
        var input: Double
        var output: Double
        var cacheRead: Double
        var cacheWrite: Double
    }

    // List prices (USD per million tokens). Cache writes are billed at the five-minute rate, 1.25 times input.
    // Update these when a vendor changes its prices; a model missing from `table` gets no estimate at all.
    static let claudeOpus4 = Price(input: 15, output: 75, cacheRead: 1.5, cacheWrite: 18.75)
    static let claudeOpus45 = Price(input: 5, output: 25, cacheRead: 0.5, cacheWrite: 6.25)
    static let claudeSonnet = Price(input: 3, output: 15, cacheRead: 0.3, cacheWrite: 3.75)
    static let claudeHaiku45 = Price(input: 1, output: 5, cacheRead: 0.1, cacheWrite: 1.25)
    /// OpenAI has no separate cache-write charge.
    static let gpt5 = Price(input: 1.25, output: 10, cacheRead: 0.125, cacheWrite: 0)

    /// Claude models match by prefix, which covers the dated ids (`claude-opus-4-1-20250805`). Prefixes are
    /// spelled out so that a newer generation is never billed at an older generation's price.
    private static let prefixPrices: [(prefix: String, price: Price)] = [
        ("claude-opus-4-5", claudeOpus45),
        ("claude-opus-4-1", claudeOpus4),
        ("claude-opus-4-2025", claudeOpus4),
        ("claude-sonnet-4-5", claudeSonnet),
        ("claude-sonnet-4-2025", claudeSonnet),
        ("claude-3-7-sonnet", claudeSonnet),
        ("claude-haiku-4-5", claudeHaiku45),
    ]

    /// Codex models match exactly: `gpt-5-mini` and the like cost far less than `gpt-5`.
    private static let exactPrices: [String: Price] = [
        "gpt-5": gpt5, "gpt-5-codex": gpt5, "gpt-5.1": gpt5, "gpt-5.1-codex": gpt5,
    ]

    static func price(for model: String?) -> Price? {
        guard let model = model?.lowercased() else { return nil }
        return exactPrices[model] ?? prefixPrices.first { model.hasPrefix($0.prefix) }?.price
    }

    /// Nil when the model has no price.
    static func estimatedCost(of usage: UsageTotals, model: String?) -> Double? {
        guard let price = price(for: model) else { return nil }
        let perMillion = Double(usage.input) * price.input + Double(usage.output) * price.output
            + Double(usage.cacheRead) * price.cacheRead + Double(usage.cacheWrite) * price.cacheWrite
        return perMillion / 1_000_000
    }

    /// The sum over the models that have a price, or nil when none does: unpriced usage adds nothing rather
    /// than guessing.
    static func estimatedCost(of usageByModel: [String: UsageTotals]) -> Double? {
        let costs = usageByModel.compactMap { estimatedCost(of: $0.value, model: $0.key) }
        return costs.isEmpty ? nil : costs.reduce(0, +)
    }
}
