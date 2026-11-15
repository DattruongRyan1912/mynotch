import Foundation
import MyNotchCore
import Observation
import os

/// The shelf's items, newest first, kept in `shelf.json`. Every change is written at once.
///
/// Resolving a bookmark is file system work (it can wait on a volume), so each file is resolved when it is loaded or
/// added, or when `refreshedURL` is asked for it, and views read `url(of:)` from that.
@Observable
final class ShelfStore {
    /// Where a bookmark points now, and whether the system says the bookmark should be made again.
    typealias Resolution = (url: URL, isStale: Bool)

    private(set) var items: [ShelfItem]
    /// Copies of files that were only promised by the drag source (Photos, Mail); removed with their item.
    let promisedDirectory: URL
    /// Where each file item was last found; it has no entry when its file is gone.
    private var locations: [UUID: URL] = [:]
    private let fileURL: URL
    private let logger: Logger
    private let resolve: (Data) -> Resolution?

    /// Loads the shelf, leaving out entries that cannot be read and files that no longer exist, and deleting the
    /// stored copies that no item points at any more. `resolve` is a seam for tests.
    init(directory: URL, limit: Int, logger: Logger = Log.logger(category: "shelf"), resolve: @escaping (Data) -> Resolution? = ShelfStore.resolveBookmark) {
        fileURL = directory.appending(path: "shelf.json")
        promisedDirectory = directory.appending(path: "promised", directoryHint: .isDirectory)
        self.logger = logger
        self.resolve = resolve
        items = []
        let saved = (try? JSONDecoder().decode([Lossy].self, from: Data(contentsOf: fileURL)))?.compactMap(\.item) ?? []
        let loaded = saved.compactMap(locate).prefix(limit)
        items = loaded.map(\.item)
        locations = Dictionary(loaded.compactMap { entry in entry.url.map { (entry.item.id, $0) } }, uniquingKeysWith: { $1 })
        removeOrphanedCopies()
        if items != saved { save() }
    }

    /// Plain bookmark, no UI and no mounting: a file on a volume that is not there is gone, rather than a reason to
    /// wait for the volume.
    nonisolated static func resolveBookmark(_ bookmark: Data) -> Resolution? {
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, options: [.withoutUI, .withoutMounting], bookmarkDataIsStale: &isStale),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        return (url, isStale)
    }

    /// Something that is already on the shelf (the same file, text or link) moves to the front instead of appearing
    /// twice, so a card dropped back onto the shelf cannot leave two cards sharing one stored copy.
    func add(_ kind: ShelfItem.Kind, limit: Int) {
        add(contentsOf: [kind], limit: limit)
    }

    /// `add` for several, one after the other (so the last of them ends up first), written to `shelf.json` once.
    func add(contentsOf kinds: [ShelfItem.Kind], limit: Int) {
        for kind in kinds { insert(kind, limit: limit) }
        save()
    }

    private func insert(_ kind: ShelfItem.Kind, limit: Int) {
        let location = resolvedURL(of: kind)
        if let index = items.firstIndex(where: { isSame($0, as: kind, at: location) }) {
            let existing = items.remove(at: index)
            items.insert(ShelfItem(id: existing.id, kind: existing.kind, addedAt: .now), at: 0)
            return
        }
        let item = ShelfItem(kind: kind)
        items.insert(item, at: 0)
        locations[item.id] = location
        let overflow = Array(items.dropFirst(limit))
        for trimmed in overflow {
            discardCopy(of: trimmed)
            locations[trimmed.id] = nil
        }
        items.removeLast(overflow.count)
    }

    /// `deletingCopy: false` keeps the stored copy of a promised file whose item was dragged out, because the
    /// destination may still be reading it; the next load sweeps it.
    func remove(id: UUID, deletingCopy: Bool = true) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let item = items.remove(at: index)
        if deletingCopy { discardCopy(of: item) }
        locations[id] = nil
        save()
    }

    func removeAll() {
        items.forEach(discardCopy)
        items = []
        locations = [:]
        save()
    }

    /// Where a file item was last found; nil for other items and for files that are gone. Reads a cache, so views
    /// can call it on every render.
    func url(of item: ShelfItem) -> URL? { locations[item.id] }

    /// Resolves the file again, for an action that is about to use it: the file may have moved or been renamed since
    /// the shelf was loaded. A bookmark the system calls stale is made again, and a renamed file shows its new name.
    func refreshedURL(of item: ShelfItem) -> URL? {
        guard let index = items.firstIndex(where: { $0.id == item.id }), case .file = items[index].kind else { return nil }
        guard let located = locate(items[index]) else {
            locations[item.id] = nil
            return nil
        }
        locations[item.id] = located.url
        if located.item != items[index] {
            items[index] = located.item
            save()
        }
        return located.url
    }

    /// `refreshedURL` for every file, for when the shelf comes into view again.
    func refreshLocations() {
        for item in items { _ = refreshedURL(of: item) }
    }

    private func resolvedURL(of kind: ShelfItem.Kind) -> URL? {
        guard case .file(let bookmark, _, _) = kind else { return nil }
        return resolve(bookmark)?.url
    }

    private func isSame(_ item: ShelfItem, as kind: ShelfItem.Kind, at location: URL?) -> Bool {
        switch kind {
        case .file: location != nil && locations[item.id] == location
        case .text, .link: item.kind == kind
        }
    }

    /// The item with a fresh bookmark and the file's current name when the file moved or was renamed, together with
    /// where the file is; nil when the file is gone.
    private func locate(_ item: ShelfItem) -> (item: ShelfItem, url: URL?)? {
        guard case .file(let bookmark, let name, let type) = item.kind else { return (item, nil) }
        guard let (url, isStale) = resolve(bookmark) else { return nil }
        guard isStale || url.lastPathComponent != name else { return (item, url) }
        let fresh = isStale ? (try? url.bookmarkData()) ?? bookmark : bookmark
        return (ShelfItem(id: item.id, kind: .file(bookmark: fresh, name: url.lastPathComponent, utType: type), addedAt: item.addedAt), url)
    }

    /// Deletes the stored copy of something that never made it onto the shelf (a drop that arrived too late).
    func deleteStoredCopy(of kind: ShelfItem.Kind) {
        deleteCopy(at: resolvedURL(of: kind))
    }

    private func discardCopy(of item: ShelfItem) {
        deleteCopy(at: locations[item.id])
    }

    /// Deletes the folder of `promised/` that holds a promised file; files that live anywhere else are never touched.
    private func deleteCopy(at url: URL?) {
        // Bookmarks resolve to the real path, so compare real paths (/var is /private/var).
        guard let folder = url?.deletingLastPathComponent(),
              folder.deletingLastPathComponent().resolvingSymlinksInPath().path == promisedDirectory.resolvingSymlinksInPath().path
        else { return }
        try? FileManager.default.removeItem(at: folder)
    }

    /// What is left in `promised/` once no item points at it: the copies of items the limit trimmed, of drops that
    /// failed halfway, of items dragged out.
    private func removeOrphanedCopies() {
        let folders = (try? FileManager.default.contentsOfDirectory(at: promisedDirectory, includingPropertiesForKeys: nil)) ?? []
        guard !folders.isEmpty else { return }
        let kept = Set(items.compactMap { locations[$0.id]?.deletingLastPathComponent().resolvingSymlinksInPath().path })
        for folder in folders where !kept.contains(folder.resolvingSymlinksInPath().path) {
            try? FileManager.default.removeItem(at: folder)
        }
    }

    /// How many times the shelf was written, for tests of batches.
    private(set) var saveCount = 0

    private func save() {
        saveCount += 1
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
