import Foundation

nonisolated extension ClipboardHistory {
    struct RestoreResult: Equatable, Sendable {
        var addedIDs: [UUID] = []
        /// Items of the plan whose content the history had by the time of the merge, though the plan did not know.
        var duplicates = 0
        var boardsCreated = 0
        var pinned = 0
    }

    /// Merges what a backup held. An item the history has (by content hash) is not added again and keeps its own date and
    /// source; a new one keeps the date and source it had and goes where that date puts it, after an item of the same date that
    /// is already here. Boards are matched by name, ignoring case: a board that exists keeps its look and takes the file's pins
    /// after its own, and one that does not is made, last in the row, in the file's order. A pin is made for an item that was
    /// not added too, since it is the same item.
    @discardableResult
    mutating func restore(_ plan: ClipboardRestorePlan) -> RestoreResult {
        var result = RestoreResult()
        var known = Set(items.map(\.contentHash))
        var fresh: [ClipboardItem] = []
        for item in plan.items {
            if known.insert(item.contentHash).inserted {
                fresh.append(item)
            } else {
                result.duplicates += 1
            }
        }
        result.addedIDs = fresh.map(\.id)
        mergeNewestFirst(fresh)

        let idByHash = Dictionary(items.map { ($0.contentHash, $0.id) }, uniquingKeysWith: { first, _ in first })
        for spec in plan.boards {
            let index: Int
            if let existing = boards.firstIndex(where: { $0.name.caseInsensitiveCompare(spec.name) == .orderedSame }) {
                index = existing
            } else {
                boards.append(ClipboardBoard(id: UUID(), name: spec.name, systemImage: spec.systemImage, color: spec.color, itemIDs: []))
                index = boards.count - 1
                result.boardsCreated += 1
            }
            for hash in spec.itemHashes {
                guard let id = idByHash[hash], !boards[index].itemIDs.contains(id) else { continue }
                boards[index].itemIDs.append(id)
                result.pinned += 1
            }
        }
        return result
    }

    /// `incoming` in the order given, placed among `items` by date.
    private mutating func mergeNewestFirst(_ incoming: [ClipboardItem]) {
        guard !incoming.isEmpty else { return }
        let sorted = incoming.enumerated().sorted { first, second in
            first.element.copiedAt != second.element.copiedAt ? first.element.copiedAt > second.element.copiedAt : first.offset < second.offset
        }.map(\.element)
        var merged: [ClipboardItem] = []
        merged.reserveCapacity(items.count + sorted.count)
        var existing = 0, added = 0
        while existing < items.count || added < sorted.count {
            if added == sorted.count || (existing < items.count && items[existing].copiedAt >= sorted[added].copiedAt) {
                merged.append(items[existing])
                existing += 1
            } else {
                merged.append(sorted[added])
                added += 1
            }
        }
        items = merged
    }
}
