import Foundation

/// A file of the history's folders that a clean may delete, found off the main thread and deleted by whoever has decided that nothing
/// names it.
nonisolated struct ClipboardBlob: Sendable, Equatable {
    let url: URL
    let name: String
    let bytes: Int64
}

/// The history files read as they are, without `ClipboardStore.load()`, which creates folders, moves an unreadable file aside and deletes
/// the pictures that nothing names: things a measuring must not do, and a clean must do only on purpose.
nonisolated enum ClipboardStoredHistory {
    /// A missing file is an empty list. nil when either file cannot be read in full, down to its last entry: a board that cannot be read
    /// leaves its items looking unpinned, and an item that cannot be read leaves its picture looking unclaimed, so nothing may be
    /// decided from what is left.
    @concurrent static func peek(directory: URL) async -> ClipboardHistory? {
        guard let items = read(ClipboardItem.self, from: "history.json", in: directory),
              let boards = read(ClipboardBoard.self, from: "boards.json", in: directory) else { return nil }
        return ClipboardHistory(items: items, boards: boards)
    }

    private static func read<Element: Decodable>(_ type: Element.Type, from fileName: String, in directory: URL) -> [Element]? {
        let url = directory.appending(path: fileName, directoryHint: .notDirectory)
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return [] }
        return try? JSONDecoder().decode([Element].self, from: Data(contentsOf: url))
    }
}

/// Looking at the history's files, off the main thread.
nonisolated enum ClipboardStorageScan {
    /// The bytes of what an unpinned picture or file of the history takes on disk; 0 for a history that cannot be read.
    @concurrent static func mediaBytes(directory: URL, history: ClipboardHistory?) async -> Int64 {
        let known: ClipboardHistory?
        if let history {
            known = history
        } else {
            known = await ClipboardStoredHistory.peek(directory: directory)
        }
        guard let known else { return 0 }
        let names = Set(known.releasableMediaItems.compactMap(\.storedImageFileName))
        return await sizes(of: Array(names), in: directory.appending(path: "images", directoryHint: .isDirectory)).values.reduce(0, +)
    }

    /// The size of each picture file called one of `names` in `folder`. A name that is no file there is left out, and so is one that is
    /// not the stored form (`history.json` may have been edited, and a name must never reach outside the folder).
    @concurrent static func sizes(of names: [String], in folder: URL) async -> [String: Int64] {
        var sizes: [String: Int64] = [:]
        for name in names where ClipboardStore.isImageFileName(name) {
            let path = folder.appending(path: name, directoryHint: .notDirectory).path(percentEncoded: false)
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
                  attributes[.type] as? FileAttributeType == .typeRegular else { continue }
            sizes[name] = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        }
        return sizes
    }

    /// The files directly in `folder` that `isStored` says are of the module's own making by their names and that were last changed at or
    /// before `cutoff`. Anything else a person put there is not listed, and a file whose date cannot be read counts as new.
    @concurrent static func blobs(in folder: URL, matching isStored: @Sendable (String) -> Bool, changedBefore cutoff: Date) async -> [ClipboardBlob] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys) else { return [] }
        return urls.compactMap { url in
            let name = url.lastPathComponent
            guard isStored(name), let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true,
                  let changed = values.contentModificationDate, changed <= cutoff else { return nil }
            return ClipboardBlob(url: url, name: name, bytes: Int64(values.fileSize ?? 0))
        }
    }

    /// Deletes the blobs whose name is not in `referenced`. Called on the main actor in the same turn that worked `referenced` out, so a
    /// copy that names a file (an old one, found there already) cannot slip in between.
    static func delete(_ blobs: [ClipboardBlob], keeping referenced: Set<String>) -> (count: Int, bytes: Int64, failed: Int) {
        var result = (count: 0, bytes: Int64(0), failed: 0)
        for blob in blobs where !referenced.contains(blob.name) {
            do {
                try FileManager.default.removeItem(at: blob.url)
                result.count += 1
                result.bytes += blob.bytes
            } catch {
                result.failed += 1
            }
        }
        return result
    }
}

nonisolated extension ClipboardItem {
    /// The name of the file in `images/` that holds the picture of an image item.
    var storedImageFileName: String? {
        if case .image(let image) = content { image.fileName } else { nil }
    }
}

nonisolated extension ClipboardHistory {
    /// What "Ảnh và file" may remove: pictures and copied files that are in no board (so neither pinned nor in a board that has a lock,
    /// whether it is open or not) and that the app which copied them did not mark as a secret.
    var releasableMediaItems: [ClipboardItem] {
        let inBoards = Set(boards.flatMap(\.itemIDs))
        return items.filter { item in
            (item.content.kind == .image || item.content.kind == .file) && !inBoards.contains(item.id) && !item.isSensitive
        }
    }

    /// Removes them as any deletion does, and returns them for the caller to delete their files.
    mutating func removeReleasableMedia() -> [ClipboardItem] {
        remove(ids: Set(releasableMediaItems.map(\.id)))
    }

    /// Forgets what was read of the pages of links that have a picture. They are read again when a card shows them, if link previews are on.
    mutating func forgetLinkPictures() {
        for index in items.indices where items[index].linkPreview?.hasImage == true { items[index].linkPreview = nil }
    }
}
