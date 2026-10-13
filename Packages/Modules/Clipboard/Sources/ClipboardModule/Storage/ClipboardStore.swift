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

    init(directory: URL, scheduler: any Scheduler, logger: Logger) {
        self.directory = directory
        imagesDirectory = directory.appending(path: "images", directoryHint: .isDirectory)
        self.scheduler = scheduler
        self.logger = logger
    }

    /// Reads both files (missing ones are empty) and deletes image files no item references.
    func load() -> ClipboardHistory {
        do {
            try fileManager.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
        } catch {
            logger.error("Could not create clipboard storage: \(String(describing: error), privacy: .public)")
        }
        let history = ClipboardHistory(
            items: read(ClipboardItem.self, from: "history"),
            boards: read(ClipboardBoard.self, from: "boards")
        )
        deleteOrphanImages(referencedBy: history.items)
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
    func saveImage(_ pngData: Data, fileName: String) throws {
        let url = imageURL(fileName: fileName)
        guard !fileExists(url) else { return }
        try pngData.write(to: url, options: .atomic)
    }

    /// Call with the items a history change removed, since only they know their image files.
    func deleteImages(for items: [ClipboardItem]) {
        for fileName in items.compactMap(\.imageFileName) {
            let url = imageURL(fileName: fileName)
            if fileExists(url) { removeFile(url) }
        }
    }

    func imageURL(fileName: String) -> URL {
        imagesDirectory.appending(path: fileName, directoryHint: .notDirectory)
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
    /// A file that cannot be read as a JSON array is moved aside so the next save cannot overwrite it.
    private func read<Element: Decodable>(_ type: Element.Type, from name: String) -> [Element] {
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
            let corrupt = directory.appending(path: "\(name).corrupt-\(Self.corruptTimestamp.string(from: .now)).json")
            do {
                try fileManager.moveItem(at: url, to: corrupt)
            } catch {
                logger.error("Could not move aside \(name, privacy: .public).json: \(String(describing: error), privacy: .public)")
            }
            return []
        }
    }

    /// Images of items dropped without `deleteImages` (an unreadable entry, a crash before saving) would stay forever.
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
