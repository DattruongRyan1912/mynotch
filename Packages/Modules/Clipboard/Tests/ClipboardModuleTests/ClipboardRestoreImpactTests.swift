import Foundation
import Testing
@testable import ClipboardModule

/// What a restore would do to the history under the limits, worked out on a copy so the user can be told first.
@Suite struct ClipboardRestoreImpactTests {
    static let now = Date(timeIntervalSince1970: 1_800_000_000)
    static let day: TimeInterval = 86_400
    static let limits = ClipboardRestoreImpact.Limits(limit: 50, retention: .month, imageByteLimit: 1_000_000)

    func item(_ name: String, daysOld: Double, imageBytes: Int? = nil) -> ClipboardItem {
        let content: ClipboardContent = imageBytes.map {
            .image(ClipboardImage(fileName: "\(name).png", pixelWidth: 1, pixelHeight: 1, byteCount: $0))
        } ?? .text(name)
        return ClipboardItem(
            id: UUID(), content: content, contentHash: "h-\(name)", copiedAt: Self.now.addingTimeInterval(-daysOld * Self.day),
            sourceBundleID: nil, sourceAppName: nil
        )
    }

    func plan(_ items: [ClipboardItem], boards: [ClipboardRestorePlan.Board] = [], duplicates: Int = 0, unreadable: Int = 0) -> ClipboardRestorePlan {
        ClipboardRestorePlan(items: items, boards: boards, duplicates: duplicates, unreadable: unreadable)
    }

    func summary(_ plan: ClipboardRestorePlan, on history: ClipboardHistory, limits: ClipboardRestoreImpact.Limits = limits) async -> ClipboardRestorePlanSummary {
        await ClipboardRestoreImpact.summary(of: plan, on: history, limits: limits, now: Self.now)
    }

    @Test func aRestoreInsideTheLimitsChangesNothingElse() async {
        let history = ClipboardHistory(items: (0..<10).map { item("old\($0)", daysOld: Double($0)) })
        let result = await summary(plan((0..<5).map { item("new\($0)", daysOld: Double($0) + 0.5) }, duplicates: 2, unreadable: 1), on: history)

        #expect(result == ClipboardRestorePlanSummary(added: 5, duplicates: 2, unreadable: 1))
        #expect(!result.affectsHistory)
    }

    @Test func importedItemsOlderThanTheRetentionAreCountedAsOutsideTheLimits() async {
        let result = await summary(plan([item("a", daysOld: 40), item("b", daysOld: 100), item("c", daysOld: 1)]), on: ClipboardHistory())
        #expect(result.added == 3 && result.outsideLimits == 2 && result.evictedExisting == 0)
        #expect(result.affectsHistory)
    }

    @Test func importedItemsBeyondTheCountLimitAreOutsideTheLimits() async {
        let old = ClipboardHistory(items: (0..<50).map { item("old\($0)", daysOld: 1 + Double($0) / 100) })
        // Older than every existing item, so they are the ones the limit takes.
        let result = await summary(plan((0..<7).map { item("new\($0)", daysOld: 20 + Double($0)) }), on: old)
        #expect(result.outsideLimits == 7 && result.evictedExisting == 0)
    }

    @Test func existingItemsAreEvictedWhenTheImportIsNewerAndTheHistoryIsAtItsLimit() async {
        let history = ClipboardHistory(items: (0..<50).map { item("old\($0)", daysOld: 10 + Double($0) / 100) })
        let result = await summary(plan((0..<6).map { item("new\($0)", daysOld: Double($0) / 100) }), on: history)

        #expect(result.added == 6 && result.outsideLimits == 0 && result.evictedExisting == 6 && result.evictedExistingImages == 0)
        #expect(result.affectsHistory)
    }

    @Test func theImagesAmongTheEvictedItemsAreCounted() async {
        // The oldest three existing items are images.
        var items = (0..<47).map { item("old\($0)", daysOld: 10 + Double($0) / 100) }
        items += (0..<3).map { item("img\($0)", daysOld: 12 + Double($0) / 100, imageBytes: 100) }
        let result = await summary(plan((0..<3).map { item("new\($0)", daysOld: Double($0) / 100) }), on: ClipboardHistory(items: items))
        #expect(result.evictedExisting == 3 && result.evictedExistingImages == 3)
    }

    @Test func anItemThatWouldBeRemovedAnywayIsNotBlamedOnTheImport() async {
        // Already older than the retention: the next change to the history takes it whatever is restored.
        var items = (0..<10).map { item("old\($0)", daysOld: Double($0)) }
        items += [item("expired1", daysOld: 45), item("expired2", daysOld: 60)]
        let result = await summary(plan([item("new", daysOld: 0)]), on: ClipboardHistory(items: items))
        #expect(result.evictedExisting == 0 && result.outsideLimits == 0)
    }

    @Test func pinnedItemsAreNeverEvicted() async {
        var history = ClipboardHistory(items: (0..<50).map { item("old\($0)", daysOld: 10 + Double($0) / 100) })
        let board = history.createBoard(name: "Giữ")
        for index in 40..<50 { history.pin(itemID: history.items[index].id, to: board) }
        let result = await summary(plan((0..<4).map { item("new\($0)", daysOld: Double($0) / 100) }), on: history)
        // Ten of the fifty are pinned, so forty count against the limit: four newer ones fit with nothing evicted.
        #expect(result.evictedExisting == 0 && result.outsideLimits == 0)
    }

    @Test func theImageByteLimitEvictsExistingImagesToo() async {
        let tight = ClipboardRestoreImpact.Limits(limit: 500, retention: .forever, imageByteLimit: 250)
        let history = ClipboardHistory(items: [item("a", daysOld: 3, imageBytes: 100), item("b", daysOld: 4, imageBytes: 100)])
        let result = await summary(plan([item("c", daysOld: 0, imageBytes: 100)]), on: history, limits: tight)
        #expect(result.evictedExisting == 1 && result.evictedExistingImages == 1 && result.outsideLimits == 0)
    }

    @Test func boardsThatWouldBeMadeAreCountedByNameIgnoringCase() async {
        var history = ClipboardHistory()
        history.createBoard(name: "Công việc")
        let boards = [
            ClipboardRestorePlan.Board(name: "công việc", systemImage: "star", color: .accent, itemHashes: []),
            ClipboardRestorePlan.Board(name: "Mới", systemImage: "star", color: .accent, itemHashes: []),
            ClipboardRestorePlan.Board(name: "Khác", systemImage: "star", color: .accent, itemHashes: []),
        ]
        let result = await summary(plan([], boards: boards), on: history)
        #expect(result.boardsToCreate == 2)
    }

    @Test func theHistoryItselfIsLeftAsItWas() async {
        let history = ClipboardHistory(items: (0..<50).map { item("old\($0)", daysOld: 10 + Double($0) / 100) })
        let before = history
        _ = await summary(plan((0..<6).map { item("new\($0)", daysOld: Double($0) / 100) }), on: history)
        #expect(history == before)
    }
}
