import Foundation

/// The whole clipboard history as a value, so every rule is testable without disk or pasteboard.
/// Methods that drop items return them, because only the caller knows how to delete their image files.
nonisolated struct ClipboardHistory: Codable, Equatable, Sendable {
    /// Newest first.
    var items: [ClipboardItem] = []
    var boards: [ClipboardBoard] = []

    enum AddResult: Equatable, Sendable {
        case inserted(UUID)
        /// An item with the same hash was moved to the top instead of adding a duplicate.
        case moved(UUID)

        var id: UUID {
            switch self {
            case .inserted(let id), .moved(let id): id
            }
        }
    }

    /// A repeated copy keeps its id (so pins survive) but takes the newest content, date and source:
    /// rich text and plain text share a hash, so the latest formatting wins.
    @discardableResult
    mutating func add(_ content: ClipboardContent, hash: String, source: (bundleID: String?, name: String?), at date: Date) -> AddResult {
        if let index = items.firstIndex(where: { $0.contentHash == hash }) {
            var item = items.remove(at: index)
            item.content = content
            item.copiedAt = date
            item.sourceBundleID = source.bundleID
            item.sourceAppName = source.name
            // The same hash is the same text, so the answer stays; only an item from before detection has none yet.
            item.codeDetection = item.codeDetection ?? ClipboardCodeDetector.detect(content)
            items.insert(item, at: 0)
            return .moved(item.id)
        }
        let item = ClipboardItem(
            id: UUID(), content: content, contentHash: hash, copiedAt: date,
            sourceBundleID: source.bundleID, sourceAppName: source.name, codeDetection: ClipboardCodeDetector.detect(content)
        )
        items.insert(item, at: 0)
        return .inserted(item.id)
    }

    /// The next texts saved before code detection existed, newest first, which still have no answer. The list stops when
    /// the items together have given `maxBytes` of what detection reads of them (at most 4 KB each, so one long text is
    /// never worth more than that) or at `maxItems`, and always holds one if there is one.
    func unclassifiedTexts(maxBytes: Int, maxItems: Int) -> [(id: UUID, text: String)] {
        var found: [(id: UUID, text: String)] = []
        var bytes = 0
        for item in items where item.codeDetection == nil {
            guard let text = item.content.plainText, item.content.kind == .text else { continue }
            found.append((item.id, text))
            bytes += min(text.utf8.count, ClipboardCodeDetector.sampleBytes)
            if bytes >= maxBytes || found.count >= maxItems { break }
        }
        return found
    }

    /// Records answers found elsewhere, such as in the background. An item that has one already (a copy made meanwhile) keeps
    /// it, and an item that is gone is skipped.
    mutating func applyDetections(_ detections: [(UUID, CodeDetection)]) {
        let byID = Dictionary(detections, uniquingKeysWith: { first, _ in first })
        for index in items.indices where items[index].codeDetection == nil {
            if let detection = byID[items[index].id] { items[index].codeDetection = detection }
        }
    }

    /// Called when MyNotch reuses an item, so the most recently used one is first.
    mutating func touch(id: UUID, at date: Date) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        var item = items.remove(at: index)
        item.copiedAt = date
        items.insert(item, at: 0)
    }

    /// Explicit deletion, so pinned items go too and leave their boards.
    mutating func remove(ids: Set<UUID>) -> [ClipboardItem] {
        for index in boards.indices { boards[index].itemIDs.removeAll(where: ids.contains) }
        return removeItems { ids.contains($0.id) }
    }

    /// Clears items copied after `cutoff` (nil clears all), keeping pinned ones.
    mutating func clear(newerThan cutoff: Date?) -> [ClipboardItem] {
        let pinned = pinnedIDs
        return removeItems { item in !pinned.contains(item.id) && (cutoff.map { item.copiedAt > $0 } ?? true) }
    }

    /// Enforces the limits in order: item count, age, then image bytes, each removing the oldest unpinned items first.
    /// The limits apply only to unpinned items: pinned ones are exempt and never removed, so pinning many items
    /// never pushes new copies out of history. Returns the removed items in removal order.
    mutating func prune(limit: Int, retention: Retention, imageByteLimit: Int, now: Date) -> [ClipboardItem] {
        let pinned = pinnedIDs
        var removed: [ClipboardItem] = []
        /// Walks from the oldest item and removes every unpinned one that `shouldRemove` accepts at that moment.
        func removeOldestUnpinned(where shouldRemove: (ClipboardItem) -> Bool) {
            for index in items.indices.reversed() where !pinned.contains(items[index].id) && shouldRemove(items[index]) {
                removed.append(items.remove(at: index))
            }
        }

        var unpinnedCount = items.count { !pinned.contains($0.id) }
        removeOldestUnpinned { _ in
            guard unpinnedCount > limit else { return false }
            unpinnedCount -= 1
            return true
        }
        if let interval = retention.interval {
            let cutoff = now.addingTimeInterval(-interval)
            removeOldestUnpinned { $0.copiedAt < cutoff }
        }
        var imageBytes = items.reduce(0) { pinned.contains($1.id) ? $0 : $0 + ($1.imageByteCount ?? 0) }
        removeOldestUnpinned { item in
            guard imageBytes > imageByteLimit, let bytes = item.imageByteCount else { return false }
            imageBytes -= bytes
            return true
        }
        return removed
    }

    @discardableResult
    mutating func createBoard(name: String, systemImage: String = "tray.full") -> UUID {
        let board = ClipboardBoard(id: UUID(), name: name, systemImage: systemImage, itemIDs: [])
        boards.append(board)
        return board.id
    }

    mutating func renameBoard(id: UUID, name: String) {
        guard let index = boardIndex(id) else { return }
        boards[index].name = name
    }

    /// The board's items stay in history, unpinned unless another board holds them.
    mutating func deleteBoard(id: UUID) {
        boards.removeAll { $0.id == id }
    }

    /// Ignores unknown items and boards, and items already in the board.
    mutating func pin(itemID: UUID, to boardID: UUID) {
        guard items.contains(where: { $0.id == itemID }), let index = boardIndex(boardID),
              !boards[index].itemIDs.contains(itemID) else { return }
        boards[index].itemIDs.insert(itemID, at: 0)
    }

    mutating func unpin(itemID: UUID, from boardID: UUID) {
        guard let index = boardIndex(boardID) else { return }
        boards[index].itemIDs.removeAll { $0 == itemID }
    }

    func isPinned(_ id: UUID) -> Bool {
        boards.contains { $0.itemIDs.contains(id) }
    }

    func boards(containing itemID: UUID) -> [ClipboardBoard] {
        boards.filter { $0.itemIDs.contains(itemID) }
    }

    /// Drops board entries whose item is gone, e.g. after items failed to load; boards themselves stay.
    mutating func removeDanglingPins() {
        let ids = Set(items.map(\.id))
        for index in boards.indices { boards[index].itemIDs.removeAll { !ids.contains($0) } }
    }

    private var pinnedIDs: Set<UUID> {
        Set(boards.flatMap(\.itemIDs))
    }

    private func boardIndex(_ id: UUID) -> Int? {
        boards.firstIndex { $0.id == id }
    }

    /// Removes matching items and returns them in history order.
    private mutating func removeItems(where matches: (ClipboardItem) -> Bool) -> [ClipboardItem] {
        let removed = items.filter(matches)
        items.removeAll(where: matches)
        return removed
    }
}

/// In an extension so the memberwise initializer stays available.
nonisolated extension ClipboardHistory {
    /// A missing array means empty, so history saved without boards (or the reverse) still loads.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        items = try container.decodeIfPresent([ClipboardItem].self, forKey: .items) ?? []
        boards = try container.decodeIfPresent([ClipboardBoard].self, forKey: .boards) ?? []
    }
}

private nonisolated extension ClipboardItem {
    var imageByteCount: Int? {
        if case .image(let image) = content { image.byteCount } else { nil }
    }
}
