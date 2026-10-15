import Foundation
import MyNotchCore
import os

/// Keeps the history on disk as `history.json`, `boards.json` and PNG files in `images/`, and, when the user wants the copy
/// stack kept between launches, the stack as `stack.json`.
/// Saves wait one second after the last change (at most five after the first) so a burst of copies costs
/// one write, encoding and writing run off the main thread, and a damaged file costs at most that file, never a crash.
final class ClipboardStore {
    private static let saveDelay: Duration = .seconds(1)
    private static let maxSaveDelay: Duration = .seconds(5)
    private static let corruptTimestamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()

    private let directory: URL
    /// Where the PNG files are.
    let imagesDirectory: URL
    private let scheduler: any Scheduler
    private let logger: Logger
    /// Dates the names of moved-aside files; injected so tests can put two failures in the same second.
    private let now: () -> Date
    private let fileManager = FileManager.default
    /// Serial, so writes reach the disk in the order they were started.
    private let writer = DispatchQueue(label: "io.lucasvu.mynotch.clipboard.store")
    /// The newest history not yet confirmed on disk, numbered so a late failure can tell whether it is still the newest.
    private var unsaved: (history: ClipboardHistory, version: Int)?
    /// Whether `unsaved` still has to be handed to the writer: set by every change and again after its write failed.
    private var needsWrite = false
    private var version = 0
    /// Restarted by every change.
    private var saveTimer: ScheduledAction?
    /// Armed by the first change of a batch and never restarted, so steady changes still get saved.
    private var maxWaitTimer: ScheduledAction?
    /// Successful writes, so tests can tell coalesced saves apart.
    private(set) var writeCount = 0

    init(directory: URL, scheduler: any Scheduler, logger: Logger, now: @escaping () -> Date = { .now }) {
        self.directory = directory
        imagesDirectory = directory.appending(path: "images", directoryHint: .isDirectory)
        self.scheduler = scheduler
        self.logger = logger
        self.now = now
    }

    /// Reads both files (missing ones are empty) and deletes image files that neither the loaded nor the unsaved
    /// history references. An unreadable history file is moved aside together with `images/`, so no later
    /// orphan cleanup can delete the images it still references.
    func load() -> ClipboardHistory {
        let items = read(ClipboardItem.self, from: "history.json")
        if items == nil { moveAside(["history.json", "images"]) }
        let boards = read(ClipboardBoard.self, from: "boards.json")
        if boards == nil { moveAside(["boards.json"]) }
        do {
            try fileManager.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
        } catch {
            logFailure("Creating the clipboard folders", error)
        }
        let history = ClipboardHistory(items: items ?? [], boards: boards ?? [])
        if items != nil { deleteOrphanImages(referencedBy: history.items + (unsaved?.history.items ?? [])) }
        return history
    }

    /// Restarts the one-second delay on every call, so changes in a burst are written once with the latest value. What is written
    /// never holds the items of a board that has a lock, whoever asks (they live sealed in the board's vault file).
    func scheduleSave(_ history: ClipboardHistory) {
        version += 1
        unsaved = (history.persistable, version)
        needsWrite = true
        saveTimer?.cancel()
        saveTimer = scheduler.schedule(after: Self.saveDelay) { [weak self] in self?.startWrite() }
        if maxWaitTimer == nil {
            maxWaitTimer = scheduler.schedule(after: Self.maxSaveDelay) { [weak self] in self?.startWrite() }
        }
    }

    /// Writes any unsaved change now and waits for every write so far; awaited when the module stops.
    func flush() async {
        startWrite()
        await waitForWrites()
    }

    /// Waits until every write already handed to the writer has finished and reported back.
    func waitForWrites() async {
        await withCheckedContinuation { continuation in
            writer.async { DispatchQueue.main.async { continuation.resume() } }
        }
    }

    /// The stack kept by an earlier run; nil when there is none or the file cannot be read (it is replaced by the next
    /// `saveStack`, since a stack is too short-lived to be worth moving aside).
    func loadStack() -> CopyStack? {
        let url = fileURL("stack.json")
        guard fileExists(url) else { return nil }
        do {
            return try JSONDecoder().decode(CopyStack.self, from: Data(contentsOf: url))
        } catch {
            logFailure("Reading stack.json (starting without a stack)", error)
            return nil
        }
    }

    /// Writes the stack now, on the writer queue after every write before it, so the newest call is the one left on disk.
    /// A stack changes only when the user copies or pastes, so there is nothing to wait for and batch. nil deletes the
    /// file, which is how a stack the user no longer wants kept leaves the disk.
    func saveStack(_ stack: CopyStack?) {
        let url = fileURL("stack.json")
        writer.async { [weak self] in
            do {
                try Self.write(stack, to: url)
            } catch {
                DispatchQueue.main.async { self?.logFailure("Saving the copy stack", error) }
            }
        }
    }

    /// File names are content hashes, so an existing file already holds these bytes.
    /// Throws `CocoaError(.fileWriteInvalidFileName)` for a name `imageURL` rejects.
    func saveImage(_ pngData: Data, fileName: String) throws {
        try Self.writeImage(pngData, named: fileName, in: imagesDirectory)
    }

    /// The same, for a restore that runs off the main actor and so has no store at hand, only the folder.
    nonisolated static func writeImage(_ pngData: Data, named fileName: String, in directory: URL) throws {
        guard isImageFileName(fileName) else { throw CocoaError(.fileWriteInvalidFileName) }
        let url = directory.appending(path: fileName, directoryHint: .notDirectory)
        guard !FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return }
        try pngData.write(to: url, options: .atomic)
        // Pictures a locked board gives back are written here too: they are for the user to read, and nobody else.
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path(percentEncoded: false))
    }

    private nonisolated static func isImageFileName(_ fileName: String) -> Bool {
        fileName.wholeMatch(of: /[0-9a-f]{64}\.png/) != nil
    }

    /// Call with the items a history change removed, since only they know their image files.
    /// Names `imageURL` rejects are skipped.
    func deleteImages(for items: [ClipboardItem]) {
        for url in items.compactMap(\.imageFileName).compactMap(imageURL(fileName:)) where fileExists(url) {
            removeFile(url)
        }
    }

    /// nil unless `fileName` has the stored form "<SHA-256 hex>.png": names come from `history.json`,
    /// which may have been edited, and must never reach outside `images/`.
    func imageURL(fileName: String) -> URL? {
        guard Self.isImageFileName(fileName) else { return nil }
        return imagesDirectory.appending(path: fileName, directoryHint: .notDirectory)
    }

    /// Hands the unsaved history to the writer and ends the batch: the next change arms both timers again.
    private func startWrite() {
        saveTimer?.cancel()
        saveTimer = nil
        maxWaitTimer?.cancel()
        maxWaitTimer = nil
        guard needsWrite, let unsaved else { return }
        needsWrite = false
        let boardsURL = fileURL("boards.json"), itemsURL = fileURL("history.json")
        writer.async { [weak self] in
            let result = Result { try Self.write(unsaved.history, boardsURL: boardsURL, itemsURL: itemsURL) }
            DispatchQueue.main.async { self?.finishWrite(version: unsaved.version, result: result) }
        }
    }

    /// Runs on the writer queue.
    private nonisolated static func write(_ stack: CopyStack?, to url: URL) throws {
        guard let stack else {
            do {
                try FileManager.default.removeItem(at: url)
            } catch CocoaError.fileNoSuchFile {
                // Nothing to delete.
            }
            return
        }
        try JSONEncoder().encode(stack).write(to: url, options: .atomic)
    }

    /// A failure leaves the history unsaved for the next save or flush, unless a newer change replaced it meanwhile.
    private func finishWrite(version: Int, result: Result<Void, any Error>) {
        let isNewest = unsaved?.version == version
        switch result {
        case .success:
            writeCount += 1
            if isNewest { unsaved = nil }
        case .failure(let error):
            logFailure("Saving the clipboard history (retrying on the next save)", error)
            if isNewest { needsWrite = true }
        }
    }

    /// Runs on the writer queue. Sorted keys keep the files stable; the default date strategy (also used to read)
    /// keeps sub-second precision so a saved history loads back equal. Boards go first: if the second write fails,
    /// a pin may point at a missing item, but a pinned item is never saved as unpinned and pruned on the next launch.
    private nonisolated static func write(_ history: ClipboardHistory, boardsURL: URL, itemsURL: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        try encoder.encode(history.boards).write(to: boardsURL, options: .atomic)
        try encoder.encode(history.items).write(to: itemsURL, options: .atomic)
    }

    /// Decodes one element at a time, so an entry from a newer version or a damaged edit loses only itself.
    /// Returns nil for a file that cannot be read as a JSON array.
    private func read<Element: Decodable>(_ type: Element.Type, from fileName: String) -> [Element]? {
        let url = fileURL(fileName)
        guard fileExists(url) else { return [] }
        do {
            let entries = try JSONDecoder().decode([Lossy<Element>].self, from: Data(contentsOf: url))
            let elements = entries.compactMap(\.value)
            if elements.count < entries.count {
                logger.error("Dropped \(entries.count - elements.count) unreadable entries from \(fileName, privacy: .public)")
            }
            return elements
        } catch {
            logFailure("Reading \(fileName) (starting it empty)", error)
            return nil
        }
    }

    /// Renames each existing entry to `<name>.corrupt-<time><ext>` with one stamp free for all of them, numbered
    /// `-1`, `-2`, … when taken, so the next save cannot overwrite them and two failures within a second keep both.
    private func moveAside(_ fileNames: [String]) {
        func target(_ fileName: String, _ stamp: String) -> URL {
            let dot = fileName.firstIndex(of: ".") ?? fileName.endIndex
            return fileURL("\(fileName[..<dot]).corrupt-\(stamp)\(fileName[dot...])")
        }
        let time = Self.corruptTimestamp.string(from: now())
        var stamp = time
        var number = 0
        while fileNames.contains(where: { fileExists(target($0, stamp)) }) {
            number += 1
            stamp = "\(time)-\(number)"
        }
        for fileName in fileNames where fileExists(fileURL(fileName)) {
            do {
                try fileManager.moveItem(at: fileURL(fileName), to: target(fileName, stamp))
            } catch {
                logFailure("Moving aside \(fileName)", error)
            }
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
            logFailure("Listing clipboard images", error)
        }
    }

    private func removeFile(_ url: URL) {
        do {
            try fileManager.removeItem(at: url)
        } catch {
            logFailure("Deleting a clipboard image", error)
        }
    }

    /// Cocoa errors quote full paths and decoding errors may quote file content, so only the domain and code are public.
    private func logFailure(_ action: String, _ error: any Error) {
        let nsError = error as NSError
        logger.error("\(action, privacy: .public) failed (\(nsError.domain, privacy: .public) \(nsError.code, privacy: .public)): \(String(describing: error), privacy: .private)")
    }

    private func fileURL(_ fileName: String) -> URL {
        directory.appending(path: fileName)
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
