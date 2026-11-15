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
    // Update these when a vendor changes its prices; a model missing from the tables gets no estimate at all.
    static let claudeFable51 = Price(input: 10, output: 50, cacheRead: 0.25, cacheWrite: 12.5)
    static let claudeFable5 = Price(input: 10, output: 50, cacheRead: 1, cacheWrite: 12.5)
    static let claudeOpus55 = Price(input: 4, output: 20, cacheRead: 0.2, cacheWrite: 5)
    static let claudeOpus5 = Price(input: 5, output: 25, cacheRead: 0.5, cacheWrite: 6.25)
    static let claudeOpus4 = Price(input: 15, output: 75, cacheRead: 1.5, cacheWrite: 18.75)
    static let claudeSonnet5 = Price(input: 2, output: 10, cacheRead: 0.2, cacheWrite: 2.5)
    static let claudeSonnet4 = Price(input: 3, output: 15, cacheRead: 0.3, cacheWrite: 3.75)
    /// Haiku 5.5 bills a prompt over 100K tokens at 0.50 input and 2.50 output. The transcripts do not say how
    /// long each prompt was, so every token is priced at the standard rate and a long-context session is understated.
    static let claudeHaiku55 = Price(input: 0.1, output: 0.5, cacheRead: 0.01, cacheWrite: 0.125)
    static let claudeHaiku45 = Price(input: 1, output: 5, cacheRead: 0.1, cacheWrite: 1.25)
    /// OpenAI has no separate cache-write charge. These prices are NOT verified against OpenAI's list: they are
    /// kept from the first version of this table, unlike the Claude rows above.
    static let gpt5 = Price(input: 1.25, output: 10, cacheRead: 0.125, cacheWrite: 0)

    /// Claude models match by prefix, which covers dated ids (`claude-opus-4-1-20250805`) and suffixes such as
    /// `[1m]`; see `matches`. Each row names one release, so a newer generation is never billed at an older
    /// generation's price.
    private static let prefixPrices: [(prefix: String, price: Price)] = [
        ("claude-fable-5-1", claudeFable51),
        ("claude-fable-5", claudeFable5),
        ("claude-opus-5-5", claudeOpus55),
        ("claude-opus-5", claudeOpus5),
        ("claude-opus-4-8", claudeOpus5),
        ("claude-opus-4-7", claudeOpus5),
        ("claude-opus-4-6", claudeOpus5),
        ("claude-opus-4-5", claudeOpus5),
        ("claude-opus-4-1", claudeOpus4),
        ("claude-opus-4", claudeOpus4),
        ("claude-sonnet-5-5", claudeSonnet5),
        ("claude-sonnet-5", claudeSonnet5),
        ("claude-sonnet-4-6", claudeSonnet4),
        ("claude-sonnet-4-5", claudeSonnet4),
        ("claude-sonnet-4", claudeSonnet4),
        ("claude-3-7-sonnet", claudeSonnet4),
        ("claude-haiku-5-5", claudeHaiku55),
        ("claude-haiku-4-5", claudeHaiku45),
    ]

    /// Codex models match exactly: `gpt-5-mini` and the like cost far less than `gpt-5`.
    private static let exactPrices: [String: Price] = [
        "gpt-5": gpt5, "gpt-5-codex": gpt5, "gpt-5.1": gpt5, "gpt-5.1-codex": gpt5,
    ]

    static func price(for model: String?) -> Price? {
        guard let model = model?.lowercased() else { return nil }
        return exactPrices[model] ?? prefixPrices.first { matches(model, prefix: $0.prefix) }?.price
    }

    /// `prefix` names the model, optionally followed by a suffix (`[1m]`) or a date (`-20260101`). Any other number
    /// after it (`claude-opus-5` against `claude-opus-5-9`, or `claude-opus-4-1` against `claude-opus-4-11`) is
    /// another release with a price of its own.
    private static func matches(_ model: String, prefix: String) -> Bool {
        guard model.hasPrefix(prefix) else { return false }
        let rest = model.dropFirst(prefix.count)
        guard let next = rest.first else { return true }
        guard !next.isNumber else { return false }
        guard next == "-" else { return true }
        let digits = rest.dropFirst().prefix(while: \.isNumber).count
        return digits == 0 || digits == 8
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
