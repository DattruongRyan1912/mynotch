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

    /// Loads the shelf, leaving out entries that cannot be read and files that no longer exist.
    init(directory: URL, limit: Int, logger: Logger = Log.logger(category: "shelf")) {
        fileURL = directory.appending(path: "shelf.json")
        promisedDirectory = directory.appending(path: "promised", directoryHint: .isDirectory)
        self.logger = logger
        items = []
        let saved = (try? JSONDecoder().decode([Lossy].self, from: Data(contentsOf: fileURL)))?.compactMap(\.item) ?? []
        items = Array(saved.compactMap(refreshed).prefix(limit))
        if items != saved { save() }
    }

    func add(_ kind: ShelfItem.Kind, limit: Int) {
        items.insert(ShelfItem(kind: kind), at: 0)
        let overflow = items.dropFirst(limit)
        overflow.forEach(deleteStoredCopy)
        items.removeLast(overflow.count)
        save()
    }

    func remove(id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        deleteStoredCopy(of: items.remove(at: index))
        save()
    }

    func removeAll() {
        items.forEach(deleteStoredCopy)
        items = []
        save()
    }

    /// Where a file item is now; nil for other items and for files that are gone.
    func url(of item: ShelfItem) -> URL? {
        guard case .file(let bookmark, _, _) = item.kind else { return nil }
        return resolve(bookmark)?.url
    }

    private func resolve(_ bookmark: Data) -> (url: URL, isStale: Bool)? {
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, options: .withoutUI, bookmarkDataIsStale: &isStale),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        return (url, isStale)
    }

    /// The item with a fresh bookmark when its file moved, or nil when the file is gone.
    private func refreshed(_ item: ShelfItem) -> ShelfItem? {
        guard case .file(let bookmark, let name, let type) = item.kind else { return item }
        guard let (url, isStale) = resolve(bookmark) else { return nil }
        guard isStale, let fresh = try? url.bookmarkData() else { return item }
        return ShelfItem(id: item.id, kind: .file(bookmark: fresh, name: name, utType: type), addedAt: item.addedAt)
    }

    private func deleteStoredCopy(of item: ShelfItem) {
        // Bookmarks resolve to the real path, so compare real paths (/var is /private/var).
        guard let url = url(of: item),
              url.resolvingSymlinksInPath().path.hasPrefix(promisedDirectory.resolvingSymlinksInPath().path + "/") else { return }
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
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
