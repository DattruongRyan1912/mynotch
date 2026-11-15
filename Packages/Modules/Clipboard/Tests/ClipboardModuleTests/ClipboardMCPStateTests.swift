import Foundation
import Testing
@testable import ClipboardModule

/// The access log: what a row says, how a flood of refusals is kept from pushing the real calls out, and that nothing in it can
/// hold a question.
@Suite struct ClipboardMCPStateTests {
    let start = Date(timeIntervalSince1970: 1_800_000_000)

    func answered(_ state: ClipboardMCPState, count: Int = 1, at seconds: Double) {
        state.record(tool: "search_clipboard", outcome: .answered(count: count, hidden: 0), at: start.addingTimeInterval(seconds))
    }

    func refused(_ state: ClipboardMCPState, at seconds: Double) {
        state.record(tool: "search_clipboard", outcome: .rateLimited(count: 1), at: start.addingTimeInterval(seconds))
    }

    @Test func aRowSaysHowManyItemsWereGivenAndHowManyWereHeldBack() {
        func summary(_ outcome: ClipboardMCPAccess.Outcome) -> String {
            ClipboardMCPAccess(date: start, tool: "search_clipboard", outcome: outcome).summary
        }
        #expect(summary(.answered(count: 3, hidden: 0)) == "3 kết quả")
        #expect(summary(.answered(count: 0, hidden: 0)) == "Không có kết quả")
        #expect(summary(.answered(count: 3, hidden: 2)) == "3 kết quả · 2 mục bị ẩn vì có thể chứa bí mật")
        #expect(summary(.answered(count: 0, hidden: 1)) == "Không có kết quả · 1 mục bị ẩn vì có thể chứa bí mật")
        #expect(summary(.rateLimited(count: 1)) == "Bị chặn: quá 10 lệnh gọi mỗi giây")
        #expect(summary(.rateLimited(count: 143)) == "Bị chặn: quá 10 lệnh gọi mỗi giây (× 143)")
    }

    @Test func refusalsInTheSameSecondAreOneRowWithACount() {
        let state = ClipboardMCPState()
        answered(state, at: 0)
        for step in 0..<40 { refused(state, at: 5 + Double(step) * 0.02) }
        #expect(state.entries.count == 2)
        #expect(state.entries.first?.outcome == .rateLimited(count: 40))
        #expect(state.entries.last?.outcome == .answered(count: 1, hidden: 0))
    }

    @Test func aRefusalInALaterSecondIsANewRow() {
        let state = ClipboardMCPState()
        refused(state, at: 5)
        refused(state, at: 5.5)
        refused(state, at: 6.1)
        #expect(state.entries.map(\.outcome) == [.rateLimited(count: 1), .rateLimited(count: 2)])
    }

    @Test func anAnsweredCallBetweenTwoRefusalsKeepsThemApart() {
        let state = ClipboardMCPState()
        refused(state, at: 5)
        answered(state, at: 5.1)
        refused(state, at: 5.2)
        #expect(state.entries.count == 3)
    }

    @Test func aFloodOfRefusalsCannotPushTheRealCallsOutOfTheLog() {
        let state = ClipboardMCPState()
        for second in 0..<ClipboardMCPState.maxEntries { answered(state, count: second, at: Double(second)) }
        for second in 100..<160 { refused(state, at: Double(second)) }
        #expect(state.entries.count == ClipboardMCPState.maxEntries)
        #expect(state.entries.count { if case .answered = $0.outcome { true } else { false } } == ClipboardMCPState.maxEntries - 1)
        #expect(state.entries.first?.outcome == .rateLimited(count: 1))
        // The newest row of the real calls is still there.
        #expect(state.entries.contains { $0.outcome == .answered(count: ClipboardMCPState.maxEntries - 1, hidden: 0) })
    }

    @Test func theLogHoldsFiftyRowsNewestFirstAndCanBeCleared() {
        let state = ClipboardMCPState()
        for second in 0..<80 { answered(state, count: second, at: Double(second)) }
        #expect(state.entries.count == 50)
        #expect(state.entries.first?.outcome == .answered(count: 79, hidden: 0))
        state.clearLog()
        #expect(state.entries.isEmpty)
    }
}
