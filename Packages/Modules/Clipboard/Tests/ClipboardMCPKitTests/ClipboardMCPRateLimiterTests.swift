import Testing
@testable import ClipboardMCPKit

@Suite struct ClipboardMCPRateLimiterTests {
    /// What the limiter answers to a call at each time, in order. (`#expect` cannot call a mutating method itself.)
    private func answers(_ limiter: inout ClipboardMCPRateLimiter, at times: [Double]) -> [Bool] {
        times.map { limiter.allow(at: $0) }
    }

    @Test func tenCallsInASecondPassAndTheEleventhDoesNot() {
        var limiter = ClipboardMCPRateLimiter()
        let result = answers(&limiter, at: (0..<10).map { 100 + Double($0) * 0.05 } + [100.6])
        #expect(result == Array(repeating: true, count: 10) + [false])
    }

    @Test func aCallFreesItsPlaceAfterTheWindow() {
        var limiter = ClipboardMCPRateLimiter()
        let result = answers(&limiter, at: Array(repeating: 50, count: 10) + [50.999, 51])
        #expect(result == Array(repeating: true, count: 10) + [false, true])
    }

    @Test func refusedCallsDoNotUseUpPlaces() {
        var limiter = ClipboardMCPRateLimiter()
        _ = answers(&limiter, at: Array(repeating: 0, count: 10))
        let flood = answers(&limiter, at: (1..<100).map { Double($0) * 0.005 })
        #expect(!flood.contains(true))
        #expect(answers(&limiter, at: [1]) == [true])
    }

    @Test func aSteadyTenPerSecondIsAllowedForever() {
        var limiter = ClipboardMCPRateLimiter()
        let result = answers(&limiter, at: (0..<1_000).map { Double($0) * 0.101 })
        #expect(!result.contains(false))
    }

    @Test func aClockThatGoesBackwardsDoesNotOpenTheGate() {
        var limiter = ClipboardMCPRateLimiter()
        _ = answers(&limiter, at: Array(repeating: 500, count: 10))
        #expect(answers(&limiter, at: [400]) == [false])
    }

    @Test func theLimitsCanBeChosen() {
        var limiter = ClipboardMCPRateLimiter(maxCalls: 2, window: 10)
        #expect(answers(&limiter, at: [0, 1, 9.9, 10]) == [true, true, false, true])
    }
}
