#if DEBUG
import Foundation
import MyNotchCore
import MyNotchTestSupport
import SwiftUI
import Testing
@testable import DebugTools

@Suite struct DebugActivityCommandTests {
    @Test func addTakesOneToFive() {
        for count in 1...5 { #expect(DebugActivityCommand("add \(count)") == .add(count)) }
    }

    @Test func caseAndSpacingDoNotMatter() {
        #expect(DebugActivityCommand("  ADD   3 ") == .add(3))
        #expect(DebugActivityCommand("High") == .high)
        #expect(DebugActivityCommand("\tclear\n") == .clear)
    }

    @Test func otherCountsAreNotCommands() {
        for text in ["add 0", "add 6", "add -1", "add x", "add", "add 1 2", "add 1.5", "add 99999999999999999999"] {
            #expect(DebugActivityCommand(text) == nil, "\(text)")
        }
    }

    @Test func nothingElseIsACommand() {
        for text in ["", " ", "highx", "high 1", "clear all", "reset", "addd 1", "add1"] {
            #expect(DebugActivityCommand(text) == nil, "\(text)")
        }
        #expect(DebugActivityCommand(nil) == nil)
    }
}

@Suite struct DebugActivitySpecTests {
    @Test func fiveActivitiesHaveDistinctSymbolsAndTheBriefsSummaries() {
        let specs = DebugActivitySpec.added(count: 5)
        #expect(specs.map(\.id) == ["debug-1", "debug-2", "debug-3", "debug-4", "debug-5"])
        #expect(Set(specs.map(\.symbol)).count == 5)
        #expect(specs.map(\.summary) == (1...5).map { "Thử nghiệm \($0)" })
        #expect(specs.allSatisfy { $0.lifetime == nil })
    }

    @Test func prioritiesCycleLowNormalHigh() {
        #expect(DebugActivitySpec.added(count: 5).map(\.priority) == [.low, .normal, .high, .low, .normal])
        #expect(DebugActivitySpec.added(count: 5).map(\.trailingText) == ["L1", "N2", "H3", "L4", "N5"])
    }

    @Test func theCountIsClamped() {
        #expect(DebugActivitySpec.added(count: 0).isEmpty)
        #expect(DebugActivitySpec.added(count: -3).isEmpty)
        #expect(DebugActivitySpec.added(count: 2).count == 2)
        #expect(DebugActivitySpec.added(count: 9).count == 5)
        #expect(DebugActivitySpec.addIDs == ["debug-1", "debug-2", "debug-3", "debug-4", "debug-5"])
    }

    @Test func theHighOneIsHighAndLastsEightSeconds() {
        #expect(DebugActivitySpec.high.priority == .high)
        #expect(DebugActivitySpec.high.lifetime == .seconds(8))
        #expect(!DebugActivitySpec.addIDs.contains(DebugActivitySpec.high.id))
    }
}

@Suite struct DebugCommandLimiterTests {
    let start = ContinuousClock.now

    func accept(_ limiter: inout DebugCommandLimiter, after offset: Duration) -> Bool {
        limiter.accept(at: start.advanced(by: offset))
    }

    @Test func theFirstCommandAlwaysGoesThrough() {
        var limiter = DebugCommandLimiter()
        #expect(accept(&limiter, after: .zero))
    }

    @Test func aSecondOneWithinASecondIsDropped() {
        var limiter = DebugCommandLimiter()
        #expect(accept(&limiter, after: .zero))
        #expect(!accept(&limiter, after: .zero))
        #expect(!accept(&limiter, after: .milliseconds(999)))
        #expect(accept(&limiter, after: .seconds(1)))
    }

    @Test func aDroppedCommandDoesNotPushTheNextBack() {
        var limiter = DebugCommandLimiter()
        #expect(accept(&limiter, after: .zero))
        #expect(!accept(&limiter, after: .milliseconds(900)))
        #expect(accept(&limiter, after: .milliseconds(1000)))
        #expect(!accept(&limiter, after: .milliseconds(1500)))
        #expect(accept(&limiter, after: .milliseconds(2000)))
    }

    @Test func aClockThatWentBackDoesNotBlock() {
        var limiter = DebugCommandLimiter()
        #expect(accept(&limiter, after: .seconds(10)))
        #expect(accept(&limiter, after: .zero))
    }
}
#endif
