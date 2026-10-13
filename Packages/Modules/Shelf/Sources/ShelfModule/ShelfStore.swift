import Foundation
import MyNotchCore
import Observation
import os

/// The shelf's items, newest first, kept in `shelf.json`. Every change is written at once.
@Observable
final class ShelfStore {
    private(set) var items: [ShelfItem]
    /// Copies of files that were only promised by the drag source (Photos, Mail); removed with their item.
    let promisedDirectory: URL
    private let fileURL: URL
    private let logger: Logger

    /// Loads the shelf, leaving out entries that cannot be read and files that no longer exist, and deleting the
    /// stored copies that no item points at any more.
    init(directory: URL, limit: Int, logger: Logger = Log.logger(category: "shelf")) {
        fileURL = directory.appending(path: "shelf.json")
        promisedDirectory = directory.appending(path: "promised", directoryHint: .isDirectory)
        self.logger = logger
        items = []
        let saved = (try? JSONDecoder().decode([Lossy].self, from: Data(contentsOf: fileURL)))?.compactMap(\.item) ?? []
        items = Array(saved.compactMap(refreshed).prefix(limit))
        removeOrphanedCopies()
        if items != saved { save() }
    }

    /// A file that is already on the shelf moves to the front instead of appearing twice, so a card dropped back
    /// onto the shelf cannot leave two cards sharing one stored copy.
    func add(_ kind: ShelfItem.Kind, limit: Int) {
        if let file = url(of: kind), let index = items.firstIndex(where: { url(of: $0.kind) == file }) {
            let existing = items.remove(at: index)
            items.insert(ShelfItem(id: existing.id, kind: existing.kind, addedAt: .now), at: 0)
            return save()
        }
        items.insert(ShelfItem(kind: kind), at: 0)
        let overflow = items.dropFirst(limit)
        overflow.forEach { deleteStoredCopy(of: $0.kind) }
        items.removeLast(overflow.count)
        save()
    }

    /// `deletingCopy: false` keeps the stored copy of a promised file whose item was dragged out, because the
    /// destination may still be reading it; the next load sweeps it.
    func remove(id: UUID, deletingCopy: Bool = true) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let item = items.remove(at: index)
        if deletingCopy { deleteStoredCopy(of: item.kind) }
        save()
    }

    func removeAll() {
        items.forEach { deleteStoredCopy(of: $0.kind) }
        items = []
        save()
    }

    /// Where a file item is now; nil for other items and for files that are gone.
    func url(of item: ShelfItem) -> URL? { url(of: item.kind) }

    private func url(of kind: ShelfItem.Kind) -> URL? {
        guard case .file(let bookmark, _, _) = kind else { return nil }
        return resolve(bookmark)?.url
    }

    private func resolve(_ bookmark: Data) -> (url: URL, isStale: Bool)? {
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, options: .withoutUI, bookmarkDataIsStale: &isStale),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        return (url, isStale)
    }

    /// The item with a fresh bookmark and the file's current name when the file moved or was renamed, or nil when
    /// the file is gone.
    private func refreshed(_ item: ShelfItem) -> ShelfItem? {
        guard case .file(let bookmark, let name, let type) = item.kind else { return item }
        guard let (url, isStale) = resolve(bookmark) else { return nil }
        guard isStale || url.lastPathComponent != name else { return item }
        let fresh = isStale ? (try? url.bookmarkData()) ?? bookmark : bookmark
        return ShelfItem(id: item.id, kind: .file(bookmark: fresh, name: url.lastPathComponent, utType: type), addedAt: item.addedAt)
    }

    /// Deletes the folder of `promised/` that holds a promised file; files that live anywhere else are never touched.
    func deleteStoredCopy(of kind: ShelfItem.Kind) {
        // Bookmarks resolve to the real path, so compare real paths (/var is /private/var).
        guard let folder = url(of: kind)?.deletingLastPathComponent(),
              folder.deletingLastPathComponent().resolvingSymlinksInPath().path == promisedDirectory.resolvingSymlinksInPath().path
        else { return }
        try? FileManager.default.removeItem(at: folder)
    }

    /// What is left in `promised/` once no item points at it: the copies of items the limit trimmed, of drops that
    /// failed halfway, of items dragged out.
    private func removeOrphanedCopies() {
        let folders = (try? FileManager.default.contentsOfDirectory(at: promisedDirectory, includingPropertiesForKeys: nil)) ?? []
        guard !folders.isEmpty else { return }
        let kept = Set(items.compactMap { url(of: $0)?.deletingLastPathComponent().resolvingSymlinksInPath().path })
        for folder in folders where !kept.contains(folder.resolvingSymlinksInPath().path) {
            try? FileManager.default.removeItem(at: folder)
        }
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(items).write(to: fileURL, options: .atomic)
        } catch {
            logger.error("Could not save the shelf: \(error.localizedDescription)")
        }
    }

    /// Decodes one entry at a time, so a single unreadable entry does not lose the rest.
    private struct Lossy: Decodable {
        let item: ShelfItem?
        init(from decoder: any Decoder) throws {
            item = try? ShelfItem(from: decoder)
        }
    }
}
