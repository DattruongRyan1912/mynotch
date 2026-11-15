import Foundation
import Testing
@testable import ClipboardModule

/// Items a restore keeps whatever the limits say: `prune` leaves them alone and does not count them, so they cannot push an
/// item that was there before out of the history.
@Suite struct ClipboardLimitExemptionTests {
    static let now = Date(timeIntervalSince1970: 1_800_000_000)
    static let day: TimeInterval = 86_400

    func item(_ name: String, daysOld: Double, exempt: Bool = false, imageBytes: Int? = nil) -> ClipboardItem {
        let content: ClipboardContent = imageBytes.map {
            .image(ClipboardImage(fileName: "\(name).png", pixelWidth: 1, pixelHeight: 1, byteCount: $0))
        } ?? .text(name)
        return ClipboardItem(
            id: UUID(), content: content, contentHash: "h-\(name)", copiedAt: Self.now.addingTimeInterval(-daysOld * Self.day),
            sourceBundleID: nil, sourceAppName: nil, exemptFromLimits: exempt ? true : nil
        )
    }

    func names(_ items: [ClipboardItem]) -> [String] {
        items.map { $0.contentHash.dropFirst(2).description }
    }

    @Test func anExemptItemIsNotRemovedByTheCountLimitAndDoesNotCountToward() {
        var history = ClipboardHistory(items: [
            item("e1", daysOld: 1, exempt: true), item("n1", daysOld: 2), item("e2", daysOld: 3, exempt: true), item("n2", daysOld: 4),
            item("n3", daysOld: 5), item("e3", daysOld: 50, exempt: true), item("n4", daysOld: 60), item("n5", daysOld: 70),
        ])
        let removed = history.prune(limit: 3, retention: .forever, imageByteLimit: .max, now: Self.now)

        // Five ordinary items against a limit of three: the two oldest go. The three exempt ones stay and are not counted.
        #expect(names(removed) == ["n5", "n4"])
        #expect(Set(names(history.items)) == ["e1", "e2", "e3", "n1", "n2", "n3"])
    }

    @Test func manyExemptItemsNeverPushOutAnOrdinaryOne() {
        var history = ClipboardHistory(items: (0..<100).map { item("e\($0)", daysOld: Double($0) / 10, exempt: true) } + [
            item("n1", daysOld: 100), item("n2", daysOld: 101), item("n3", daysOld: 102),
        ])
        #expect(history.prune(limit: 3, retention: .forever, imageByteLimit: .max, now: Self.now).isEmpty)
        #expect(history.items.count == 103)
    }

    @Test func theRetentionDoesNotReachAnExemptItem() {
        var history = ClipboardHistory(items: [item("e", daysOld: 400, exempt: true), item("n", daysOld: 400)])
        let removed = history.prune(limit: 50, retention: .month, imageByteLimit: .max, now: Self.now)
        #expect(names(removed) == ["n"] && names(history.items) == ["e"])
    }

    @Test func theImageBytesOfAnExemptImageAreNotCountedOrRemoved() {
        var history = ClipboardHistory(items: [
            item("big-exempt", daysOld: 1, exempt: true, imageBytes: 1_000), item("small", daysOld: 2, imageBytes: 100),
            item("old", daysOld: 3, imageBytes: 100),
        ])
        // 200 ordinary bytes against a limit of 150: the older ordinary image goes, the exempt 1,000 bytes are not looked at.
        let removed = history.prune(limit: 50, retention: .forever, imageByteLimit: 150, now: Self.now)
        #expect(names(removed) == ["old"])
        #expect(names(history.items) == ["big-exempt", "small"])
    }

    @Test func theFlagIsStoredOnlyWhenItIsSet() throws {
        let plain = item("a", daysOld: 1), exempt = item("b", daysOld: 1, exempt: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let text = String(decoding: try encoder.encode([plain, exempt]), as: UTF8.self)

        #expect(text.components(separatedBy: "exemptFromLimits").count == 2)
        let decoded = try JSONDecoder().decode([ClipboardItem].self, from: Data(text.utf8))
        #expect(decoded == [plain, exempt])
        #expect(decoded[0].isExemptFromLimits == false && decoded[1].isExemptFromLimits)
    }

    @Test func copyingAnExemptItemAgainMakesItAnOrdinaryOneAgain() {
        var history = ClipboardHistory(items: [item("same", daysOld: 100, exempt: true)])
        history.add(.text("same"), hash: "h-same", source: (nil, nil), at: Self.now)
        #expect(!history.items[0].isExemptFromLimits)
    }

    @Test func usingAnExemptItemThroughMyNotchMakesItAnOrdinaryOneAgain() {
        let exempt = item("same", daysOld: 100, exempt: true)
        var history = ClipboardHistory(items: [exempt])
        history.touch(id: exempt.id, at: Self.now)
        #expect(!history.items[0].isExemptFromLimits)
    }

    @Test func clearingTheHistoryStillRemovesExemptItems() {
        var history = ClipboardHistory(items: [item("e", daysOld: 1, exempt: true), item("n", daysOld: 1)])
        let removed = history.clear(olderThan: nil)
        #expect(removed.count == 2 && history.items.isEmpty)
    }

    // MARK: A restore with and without the exemption

    func existingAtTheLimit() -> ClipboardHistory {
        ClipboardHistory(items: (0..<50).map { item("old\($0)", daysOld: 40 + Double($0) / 100) })
    }

    func newerPlan() -> ClipboardRestorePlan {
        ClipboardRestorePlan(
            items: (0..<10).map { item("new\($0)", daysOld: Double($0) / 100) }, boards: [], duplicates: 0, unreadable: 0
        )
    }

    @Test func keepingEverythingEvictsNoExistingItem() {
        var history = existingAtTheLimit()
        let result = history.restore(newerPlan(), exempt: true)
        let removed = history.prune(limit: 50, retention: .forever, imageByteLimit: .max, now: Self.now)

        #expect(removed.isEmpty && history.items.count == 60)
        #expect(result.addedIDs.count == 10)
        #expect(history.items.filter(\.isExemptFromLimits).count == 10)
        #expect(history.items.filter { $0.contentHash.hasPrefix("h-old") }.count == 50)
    }

    @Test func keepingEverythingDoesNotFlagWhatWasThereOrWhatWasAlreadyThere() {
        var history = existingAtTheLimit()
        var plan = newerPlan()
        // One of the plan's items is in the history already: not added, not flagged.
        plan.items[0] = ClipboardItem(
            id: UUID(), content: .text("old0"), contentHash: "h-old0", copiedAt: Self.now, sourceBundleID: nil, sourceAppName: nil
        )
        let result = history.restore(plan, exempt: true)
        #expect(result.duplicates == 1 && result.addedIDs.count == 9)
        #expect(history.items.filter(\.isExemptFromLimits).count == 9)
        #expect(!(history.items.first { $0.contentHash == "h-old0" }?.isExemptFromLimits ?? true))
    }

    @Test func underTheLimitsTheNewerImportEvictsTheOldestExistingItems() {
        var history = existingAtTheLimit()
        history.restore(newerPlan(), exempt: false)
        let removed = history.prune(limit: 50, retention: .forever, imageByteLimit: .max, now: Self.now)

        #expect(removed.count == 10 && removed.allSatisfy { $0.contentHash.hasPrefix("h-old") })
        #expect(history.items.count == 50)
    }
}
