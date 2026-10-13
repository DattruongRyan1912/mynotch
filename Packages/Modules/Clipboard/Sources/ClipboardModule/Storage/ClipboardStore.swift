import Foundation
import MyNotchCore
import os

/// Keeps the history on disk as `history.json`, `boards.json` and PNG files in `images/`.
/// Saves wait one second after the last change so a burst of copies costs one write,
/// and a damaged file costs at most that file, never a crash.
final class ClipboardStore {
    private static let saveDelay: Duration = .seconds(1)
    private static let corruptTimestamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()

    private let directory: URL
    private let imagesDirectory: URL
    private let scheduler: any Scheduler
    private let logger: Logger
    /// Dates the names of moved-aside files; injected so tests can put two failures in the same second.
    private let now: () -> Date
    private let fileManager = FileManager.default
    /// Sorted keys keep the files stable. Both directions use the default date strategy,
    /// which keeps sub-second precision so a saved history loads back equal.
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return encoder
    }()
    /// The latest history not yet on disk; kept after a failed write so the next save retries.
    private var pending: ClipboardHistory?
    private var saveTimer: ScheduledAction?
    /// Successful writes, so tests can tell coalesced saves apart.
    private(set) var writeCount = 0

    init(directory: URL, scheduler: any Scheduler, logger: Logger, now: @escaping () -> Date = { .now }) {
        self.directory = directory
        imagesDirectory = directory.appending(path: "images", directoryHint: .isDirectory)
        self.scheduler = scheduler
        self.logger = logger
        self.now = now
    }

    /// Reads both files (missing ones are empty) and deletes image files no item references,
    /// unless the history file was moved aside: its images stay so it can still be recovered.
    func load() -> ClipboardHistory {
        do {
            try fileManager.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
        } catch {
            logger.error("Could not create clipboard storage: \(String(describing: error), privacy: .public)")
        }
        let items = read(ClipboardItem.self, from: "history")
        let history = ClipboardHistory(items: items ?? [], boards: read(ClipboardBoard.self, from: "boards") ?? [])
        if items != nil { deleteOrphanImages(referencedBy: history.items) }
        return history
    }

    /// Restarts the delay on every call, so changes within a second are written once with the latest value.
    func scheduleSave(_ history: ClipboardHistory) {
        pending = history
        saveTimer?.cancel()
        saveTimer = scheduler.schedule(after: Self.saveDelay) { [weak self] in self?.writePending() }
    }

    /// Writes a pending save now; called when the module stops.
    func flush() {
        saveTimer?.cancel()
        writePending()
    }

    /// File names are content hashes, so an existing file already holds these bytes.
    /// Throws `CocoaError(.fileWriteInvalidFileName)` for a name `imageURL` rejects.
    func saveImage(_ pngData: Data, fileName: String) throws {
        guard let url = imageURL(fileName: fileName) else { throw CocoaError(.fileWriteInvalidFileName) }
        guard !fileExists(url) else { return }
        try pngData.write(to: url, options: .atomic)
    }

    /// Call with the items a history change removed, since only they know their image files.
    /// Names `imageURL` rejects are skipped.
    func deleteImages(for items: [ClipboardItem]) {
        for url in items.compactMap(\.imageFileName).compactMap(imageURL(fileName:)) where fileExists(url) {
            removeFile(url)
        }
    }

    /// nil unless `fileName` is a plain file name: names come from `history.json`, which may have been edited,
    /// and must never reach outside `images/` or name the folder itself.
    func imageURL(fileName: String) -> URL? {
        guard !fileName.isEmpty, !fileName.contains("/"), !fileName.hasPrefix(".") else { return nil }
        return imagesDirectory.appending(path: fileName, directoryHint: .notDirectory)
    }

    private func writePending() {
        saveTimer = nil
        guard let history = pending else { return }
        do {
            try encoder.encode(history.items).write(to: fileURL("history"), options: .atomic)
            try encoder.encode(history.boards).write(to: fileURL("boards"), options: .atomic)
            pending = nil
            writeCount += 1
        } catch {
            logger.error("Could not save clipboard history, retrying on the next save: \(String(describing: error), privacy: .public)")
        }
    }

    /// Decodes one element at a time, so an entry from a newer version or a damaged edit loses only itself.
    /// Returns nil for a file that cannot be read as a JSON array, after moving it aside.
    private func read<Element: Decodable>(_ type: Element.Type, from name: String) -> [Element]? {
        let url = fileURL(name)
        guard fileExists(url) else { return [] }
        do {
            let entries = try JSONDecoder().decode([Lossy<Element>].self, from: Data(contentsOf: url))
            let elements = entries.compactMap(\.value)
            if elements.count < entries.count {
                logger.error("Dropped \(entries.count - elements.count) unreadable entries from \(name, privacy: .public).json")
            }
            return elements
        } catch {
            // The error may quote file content, so it stays private.
            logger.error("\(name, privacy: .public).json is unreadable, starting it empty: \(String(describing: error))")
            moveAside(url, name: name)
            return nil
        }
    }

    /// Renames to `<name>.corrupt-<time>.json`, numbered `-1`, `-2`, … if that exists, so the next save
    /// cannot overwrite the broken file and two failures within a second keep both.
    private func moveAside(_ url: URL, name: String) {
        let stem = "\(name).corrupt-\(Self.corruptTimestamp.string(from: now()))"
        var target = directory.appending(path: "\(stem).json")
        var number = 0
        while fileExists(target) {
            number += 1
            target = directory.appending(path: "\(stem)-\(number).json")
        }
        do {
            try fileManager.moveItem(at: url, to: target)
        } catch {
            logger.error("Could not move aside \(name, privacy: .public).json: \(String(describing: error), privacy: .public)")
        }
    }

    /// Images of items dropped without `deleteImages` (an undecodable entry, a crash before saving) would stay forever.
    private func deleteOrphanImages(referencedBy items: [ClipboardItem]) {
        let referenced = Set(items.compactMap(\.imageFileName))
        do {
            for file in try fileManager.contentsOfDirectory(at: imagesDirectory, includingPropertiesForKeys: nil)
            where !referenced.contains(file.lastPathComponent) {
                removeFile(file)
            }
        } catch {
            logger.error("Could not list clipboard images: \(String(describing: error), privacy: .public)")
        }
    }

    private func removeFile(_ url: URL) {
        do {
            try fileManager.removeItem(at: url)
        } catch {
            logger.error("Could not delete clipboard image: \(String(describing: error), privacy: .public)")
        }
    }

    private func fileURL(_ name: String) -> URL {
        directory.appending(path: "\(name).json", directoryHint: .notDirectory)
    }

    private func fileExists(_ url: URL) -> Bool {
        fileManager.fileExists(atPath: url.path(percentEncoded: false))
    }
}

/// Decodes to nil instead of throwing, so one bad array element does not fail the whole array.
private nonisolated struct Lossy<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: any Decoder) throws {
        value = try? decoder.singleValueContainer().decode(Value.self)
    }
}

private nonisolated extension ClipboardItem {
    var imageFileName: String? {
        if case .image(let image) = content { image.fileName } else { nil }
    }
}
