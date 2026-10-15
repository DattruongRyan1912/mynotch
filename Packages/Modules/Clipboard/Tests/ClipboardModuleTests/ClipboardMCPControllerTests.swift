import ClipboardMCPKit
import Foundation
import Testing
@testable import ClipboardModule

/// The rules around an answer: off means nothing, calls are limited, and every call that reached the history is logged
/// without what was asked.
@Suite struct ClipboardMCPControllerTests {
    final class Env {
        var enabled = true
        var uptime = 5_000.0
        var history = ClipboardHistory()
        var historyReads = 0
        var locked: Set<UUID> = []
        let now = Date(timeIntervalSince1970: 1_800_000_000)
    }

    let env = Env()
    let state = ClipboardMCPState()
    let controller: ClipboardMCPController

    init() {
        let env = env
        env.history = ClipboardHistory(items: [
            ClipboardItem(
                id: UUID(), content: .text("find me please"), contentHash: "h1", copiedAt: env.now, sourceBundleID: "com.apple.Safari",
                sourceAppName: "Safari", codeDetection: .notCode, sensitive: false
            ),
        ])
        controller = ClipboardMCPController(
            state: state, history: { env.historyReads += 1; return env.history }, index: ClipboardSearchIndex(),
            lockedBoardIDs: { env.locked }, isEnabled: { env.enabled }, now: { env.now }, uptime: { env.uptime }
        )
    }

    func line(_ request: ClipboardMCPRequest) -> Data {
        let full = ClipboardMCPWire.requestLine(request) ?? Data()
        return full.dropLast()
    }

    let searchRequest = ClipboardMCPRequest.search(ClipboardMCPSearch(query: "find"))

    @Test func aSearchIsAnsweredFromTheHistory() {
        guard case .success(let result) = controller.answer(line(searchRequest)) else {
            Issue.record("not answered")
            return
        }
        #expect(result["count"] == .int(1))
    }

    @Test func nothingIsAnsweredWhileTheFeatureIsOffAndTheHistoryIsNotEvenLooked() {
        env.enabled = false
        let reply = controller.answer(line(searchRequest))
        guard case .failure(let reason, _) = reply else {
            Issue.record("answered while off")
            return
        }
        #expect(reason == .disabled)
        #expect(env.historyReads == 0)
        #expect(state.entries.isEmpty)
    }

    @Test func turningItOffBetweenTwoCallsStopsTheSecond() {
        #expect(controller.answer(line(searchRequest)) != .failure(.disabled, ""))
        env.enabled = false
        guard case .failure(let reason, _) = controller.answer(line(searchRequest)) else {
            Issue.record("answered while off")
            return
        }
        #expect(reason == .disabled)
    }

    @Test func aRequestThatIsNotReadableOrBreaksTheRulesIsRefusedWithoutTouchingTheHistory() {
        let garbage = controller.answer(Data("garbage".utf8))
        guard case .failure(let reason, _) = garbage else {
            Issue.record("answered garbage")
            return
        }
        #expect(reason == .invalidArguments)
        let bad = Data(#"{"arguments":{"query":"x","limit":500},"tool":"search_clipboard","version":1}"#.utf8)
        #expect(controller.answer(bad) == .failure(.invalidArguments, "limit must be a whole number from 1 to 50"))
        let other = Data(#"{"arguments":{"query":"x"},"tool":"search_clipboard","version":9}"#.utf8)
        guard case .failure(.versionMismatch, _) = controller.answer(other) else {
            Issue.record("version not refused")
            return
        }
        #expect(env.historyReads == 0)
        #expect(state.entries.isEmpty)
    }

    @Test func theLockedBoardsOfTheMomentAreHonoured() {
        let id = env.history.items[0].id
        let board = ClipboardBoard(id: UUID(), name: "L", systemImage: "lock", itemIDs: [id])
        env.history.boards = [board]
        env.locked = [board.id]
        guard case .success(let result) = controller.answer(line(searchRequest)) else {
            Issue.record("not answered")
            return
        }
        #expect(result["count"] == .int(0))
    }

    // MARK: Rate

    @Test func theEleventhCallInASecondIsRefusedAndALaterOneIsAnswered() {
        for _ in 0..<10 {
            if case .failure = controller.answer(line(searchRequest)) { Issue.record("refused too early") }
        }
        guard case .failure(let reason, let message) = controller.answer(line(searchRequest)) else {
            Issue.record("not limited")
            return
        }
        #expect(reason == .rateLimited)
        #expect(message.contains("10"))
        env.uptime += 1
        if case .failure = controller.answer(line(searchRequest)) { Issue.record("still limited a second later") }
    }

    @Test func aFloodOfRequestsThatAreNotReadableUsesUpTheLimitToo() {
        for _ in 0..<10 { _ = controller.answer(Data("garbage".utf8)) }
        guard case .failure(let reason, _) = controller.answer(line(searchRequest)) else {
            Issue.record("answered during a flood")
            return
        }
        #expect(reason == .rateLimited)
    }

    // MARK: The log

    @Test func eachAnsweredCallIsLoggedWithItsToolAndHowManyItemsItGave() {
        _ = controller.answer(line(searchRequest))
        _ = controller.answer(line(.search(ClipboardMCPSearch(query: "nothing like it"))))
        _ = controller.answer(line(.item(UUID())))
        #expect(state.entries.map(\.tool) == ["get_clipboard_item", "search_clipboard", "search_clipboard"])
        #expect(state.entries.map(\.outcome) == [.answered(count: 0), .answered(count: 0), .answered(count: 1)])
    }

    @Test func aRefusedCallForGoingTooFastIsLoggedToo() {
        for _ in 0..<11 { _ = controller.answer(line(searchRequest)) }
        #expect(state.entries.count == 11)
        #expect(state.entries.first?.outcome == .rateLimited)
    }

    @Test func theLogNeverHoldsWhatWasAsked() {
        _ = controller.answer(line(.search(ClipboardMCPSearch(query: "very-secret-words", app: "very-secret-app"))))
        let text = String(describing: state.entries)
        #expect(!text.contains("very-secret"))
        #expect(!state.entries.map(\.summary).joined().contains("very-secret"))
    }

    @Test func theLogKeepsTheLastFiftyNewestFirstAndCanBeClearedAndSaysItInVietnamese() {
        for index in 0..<60 {
            env.uptime += 1
            _ = controller.answer(line(.search(ClipboardMCPSearch(query: "q\(index)", limit: 1 + index % 5))))
        }
        #expect(state.entries.count == 50)
        #expect(state.entries.map(\.date) == state.entries.map(\.date).sorted(by: >))
        #expect(ClipboardMCPAccess(date: env.now, tool: "search_clipboard", outcome: .answered(count: 3)).summary == "3 kết quả")
        #expect(ClipboardMCPAccess(date: env.now, tool: "search_clipboard", outcome: .answered(count: 0)).summary == "Không có kết quả")
        #expect(ClipboardMCPAccess(date: env.now, tool: "search_clipboard", outcome: .rateLimited).summary == "Bị chặn: quá 10 lệnh gọi mỗi giây")
        state.clearLog()
        #expect(state.entries.isEmpty)
    }
}
