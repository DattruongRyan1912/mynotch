import Foundation
import Testing
@testable import AIAgentsModule

@Suite struct UsageCalculatorTests {
    func close(_ value: Double?, to expected: Double) -> Bool {
        value.map { abs($0 - expected) < 1e-9 } ?? false
    }

    @Test func claudeOpusIsPricedPerMillionTokensOfEachKind() {
        let million = 1_000_000
        #expect(close(UsageCalculator.estimatedCost(of: UsageTotals(input: million), model: "claude-opus-4-1"), to: 15))
        #expect(close(UsageCalculator.estimatedCost(of: UsageTotals(output: million), model: "claude-opus-4-1"), to: 75))
        #expect(close(UsageCalculator.estimatedCost(of: UsageTotals(cacheRead: million), model: "claude-opus-4-1"), to: 1.5))
        #expect(close(UsageCalculator.estimatedCost(of: UsageTotals(cacheWrite: million), model: "claude-opus-4-1"), to: 18.75))
    }

    @Test func aMixOfTokenKindsAddsUp() {
        let usage = UsageTotals(input: 2_000, output: 500, cacheRead: 100_000, cacheWrite: 10_000)
        // 0.03 + 0.0375 + 0.15 + 0.1875
        #expect(close(UsageCalculator.estimatedCost(of: usage, model: "claude-opus-4-1"), to: 0.405))
    }

    @Test func codexReasoningTokensAreAlreadyPartOfOutput() {
        // Normalised Codex usage: 5 000 uncached input, 15 000 cached, 800 output of which 300 reasoning.
        let usage = UsageTotals(input: 5_000, output: 800, cacheRead: 15_000, reasoning: 300)
        // 0.00625 + 0.008 + 0.001875; reasoning is not charged twice.
        #expect(close(UsageCalculator.estimatedCost(of: usage, model: "gpt-5-codex"), to: 0.016125))
    }

    @Test func datedModelIDsUseTheirFamilyPrice() {
        let usage = UsageTotals(input: 1_000_000)
        #expect(close(UsageCalculator.estimatedCost(of: usage, model: "claude-opus-4-1-20250805"), to: 15))
        #expect(close(UsageCalculator.estimatedCost(of: usage, model: "claude-opus-4-20250514"), to: 15))
        #expect(close(UsageCalculator.estimatedCost(of: usage, model: "claude-sonnet-4-5-20250929"), to: 3))
        #expect(close(UsageCalculator.estimatedCost(of: usage, model: "claude-haiku-4-5-20251001"), to: 1))
    }

    @Test func laterOpusGenerationsHaveTheirOwnPrice() {
        #expect(close(UsageCalculator.estimatedCost(of: UsageTotals(output: 1_000_000), model: "claude-opus-4-5-20251101"), to: 25))
    }

    @Test func modelsWithoutAPriceHaveNoEstimate() {
        let usage = UsageTotals(input: 1_000_000)
        #expect(UsageCalculator.estimatedCost(of: usage, model: "mystery-model") == nil)
        #expect(UsageCalculator.estimatedCost(of: usage, model: nil) == nil)
        // A smaller sibling must not be billed at the flagship rate.
        #expect(UsageCalculator.estimatedCost(of: usage, model: "gpt-5-mini") == nil)
        #expect(UsageCalculator.estimatedCost(of: usage, model: "") == nil)
    }

    @Test func perModelTotalsAreSummedAndUnpricedModelsSkipped() {
        let byModel = [
            "claude-opus-4-1": UsageTotals(input: 1_000_000),
            "gpt-5-codex": UsageTotals(output: 1_000_000),
            "mystery-model": UsageTotals(input: 9_000_000),
            "": UsageTotals(input: 9_000_000),
        ]
        #expect(close(UsageCalculator.estimatedCost(of: byModel), to: 25))
    }

    @Test func noPricedUsageMeansNoEstimate() {
        #expect(UsageCalculator.estimatedCost(of: [:]) == nil)
        #expect(UsageCalculator.estimatedCost(of: ["mystery-model": UsageTotals(input: 5)]) == nil)
    }

    @Test func resultsAreLabelledAsEstimates() {
        #expect(UsageCalculator.estimateLabel == "ước tính")
    }
}

@Suite struct UsageTotalsTests {
    @Test func startsFromAnAgentUsageWithoutItsMetadata() {
        let usage = AgentUsage(input: 1, output: 2, cacheRead: 3, cacheWrite: 4, reasoning: 5, model: "m", messageID: "id", isCumulative: true)
        #expect(UsageTotals(usage) == UsageTotals(input: 1, output: 2, cacheRead: 3, cacheWrite: 4, reasoning: 5))
    }

    @Test func addsAndSubtractsFieldByField() {
        let a = UsageTotals(input: 10, output: 20, cacheRead: 30, cacheWrite: 40, reasoning: 5)
        let b = UsageTotals(input: 1, output: 2, cacheRead: 3, cacheWrite: 4, reasoning: 1)
        #expect(a + b == UsageTotals(input: 11, output: 22, cacheRead: 33, cacheWrite: 44, reasoning: 6))
        #expect(a - b == UsageTotals(input: 9, output: 18, cacheRead: 27, cacheWrite: 36, reasoning: 4))
        var sum = UsageTotals()
        sum += a
        sum += b
        #expect(sum == a + b)
    }

    @Test func allTokensCountsEachKindOnceAndReasoningInsideOutput() {
        #expect(UsageTotals(input: 1, output: 2, cacheRead: 3, cacheWrite: 4, reasoning: 2).allTokens == 10)
        #expect(UsageTotals().isEmpty)
        #expect(!UsageTotals(reasoning: 1).isEmpty)
    }

    @Test func reportsWhetherEveryKindIsAtLeastAnotherTotal() {
        let small = UsageTotals(input: 1, output: 2)
        #expect(UsageTotals(input: 1, output: 3).isAtLeast(small))
        #expect(small.isAtLeast(small))
        #expect(!UsageTotals(input: 0, output: 9).isAtLeast(small))
    }
}
