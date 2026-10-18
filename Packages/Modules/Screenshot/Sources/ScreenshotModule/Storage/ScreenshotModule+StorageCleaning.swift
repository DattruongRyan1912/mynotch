import Foundation
import MyNotchCore

/// The module's part of the Storage page: its captures, the recordings that were exported and the ones that were not, the two cleans the
/// page offers, and the daily rule. A recording that was never exported is the only copy of what was recorded, so the page only shows it
/// (`canClean` is false): "Dọn tất cả" cannot reach it, and only the recordings list's own "Xoá", which asks first, removes it. All of it
/// works whether or not the module runs, from `ModuleStorage` and the files; when it runs, the captures change through its own store
/// and the tray follows. Recordings live in `ModuleStorage.directory`, never in the caches, because the generic cache clean may take
/// anything from `cachesDirectory`, a recording being made included.
extension ScreenshotModule: StorageCleaning {
    static let capturesCategoryID = "screenshot.captures"
    static let exportedRecordingsCategoryID = "screenshot.recordings.exported"
    static let unexportedRecordingsCategoryID = "screenshot.recordings.unexported"
    static let exportedRecordingsKeepNote = "File đã xuất ở ~/Movies/MyNotch không bị xoá"
    static let unexportedRecordingsKeepNote = "Xoá từng bản trong tab Chụp màn hình (chưa có bản xuất nào)"

    static func recordingsFolder(in directory: URL) -> URL {
        directory.appending(path: "Recordings", directoryHint: .isDirectory)
    }

    public func storageCategories(storage: ModuleStorage) async -> [StorageCategory] {
        let captures = await StorageFolder.bytes(in: CaptureStore.capturesFolder(in: storage.directory))
        let sizes = await Self.recordingSizes(in: Self.recordingsFolder(in: storage.directory))
        return [
            StorageCategory(id: Self.capturesCategoryID, title: "Ảnh chụp", bytes: captures, keeps: nil, canClean: true),
            StorageCategory(
                id: Self.exportedRecordingsCategoryID, title: "Bản quay đã xuất", bytes: sizes.exported,
                keeps: Self.exportedRecordingsKeepNote, canClean: true
            ),
            StorageCategory(
                id: Self.unexportedRecordingsCategoryID, title: "Bản quay chưa xuất", bytes: sizes.unexported,
                keeps: Self.unexportedRecordingsKeepNote, canClean: false
            ),
        ]
    }

    /// What `Recordings/` holds, split in two: the recordings that were exported, and everything else. A recording whose project cannot
    /// be read, one still marked as being recorded, and a stray file all count as not exported, so nothing but a recording that says
    /// it was exported is ever offered to a clean. Read as it is: nothing is rescued or written.
    @concurrent private nonisolated static func recordingSizes(in folder: URL) async -> (exported: Int64, unexported: Int64) {
        let store = RecordingStore(root: folder)
        var exported: Int64 = 0
        for id in await store.exported(before: .distantFuture) { exported += await StorageFolder.bytes(in: store.folder(for: id)) }
        let total = await StorageFolder.bytes(in: folder)
        return (exported, max(total - exported, 0))
    }

    public func clean(categoryID: String, storage: ModuleStorage) async -> Int64 {
        switch categoryID {
        case Self.capturesCategoryID: await cleanCaptures(storage: storage)
        case Self.exportedRecordingsCategoryID: await cleanExportedRecordings(storage: storage)
        // Not cleanable by the page, whatever calls: only the list's own "Xoá" removes a recording that was never exported.
        default: 0
        }
    }

    /// The keep count on the captures and, if the person turned it on, the originals of the recordings that were exported long enough
    /// ago. Does nothing at all while a recording is being made or an export runs: only the module knows.
    public func autoClean(now: Date, storage: ModuleStorage) async -> Int64 {
        if let recording, recording.phase.isBusy || recording.isExporting { return 0 }
        let rules = retentionRules()
        let captures = await trimCaptures(keepCount: rules.keepCount, storage: storage)
        var recordings = (count: 0, bytes: Int64(0))
        if let days = rules.exportedDays {
            let store = RecordingStore(root: Self.recordingsFolder(in: storage.directory))
            let ids = await store.exported(before: now.addingTimeInterval(-Double(days) * 24 * 60 * 60))
            recordings = await removeRecordings(ids, from: store)
        }
        storageReport(
            "storage: auto clean freed \(captures) bytes of captures and removed \(recordings.count) exported recordings, freed \(recordings.bytes) bytes"
        )
        return captures + recordings.bytes
    }

    public var autoCleanSummary: String? {
        let rules = retentionRules()
        let recordings = rules.exportedDays.map { "tự xoá bản quay gốc đã xuất sau \($0) ngày" } ?? "không tự xoá bản quay"
        return "Giữ \(rules.keepCount) ảnh chụp gần nhất, \(recordings)"
    }

    // MARK: Captures

    private func cleanCaptures(storage: ModuleStorage) async -> Int64 {
        let folder = CaptureStore.capturesFolder(in: storage.directory)
        let before = await StorageFolder.bytes(in: folder)
        if let store {
            await store.deleteAll()
            refreshRecords()
        } else {
            _ = await StorageFolder.removeContents(of: folder)
        }
        let freed = max(before - (await StorageFolder.bytes(in: folder)), 0)
        storageReport("storage: captures clean freed \(freed) bytes")
        return freed
    }

    /// The keep count applied now. A running module does it through its own store; a stopped one through a store that reads the
    /// folder and is dropped again, as the module's `start` would read it.
    private func trimCaptures(keepCount: Int, storage: ModuleStorage) async -> Int64 {
        if let store {
            let freed = store.trim(keepCount: keepCount)
            refreshRecords()
            return freed
        }
        guard FileManager.default.fileExists(atPath: CaptureStore.capturesFolder(in: storage.directory).path(percentEncoded: false)) else { return 0 }
        let stopped = CaptureStore(directory: storage.directory, cachesDirectory: storage.cachesDirectory, logger: Log.logger(category: "screenshot"))
        stopped.load()
        return stopped.trim(keepCount: keepCount)
    }

    // MARK: Recordings

    /// Removes the originals of the recordings that were exported, except the ones an editor has open; what was exported is the
    /// person's own file, somewhere else, and stays. A recording that was never exported is not among them, however old. Not while
    /// the stream starts or the files close, when the folder in the making has no ID to go by.
    private func cleanExportedRecordings(storage: ModuleStorage) async -> Int64 {
        guard recording?.canRemoveRecordings ?? true else { return 0 }
        let store = RecordingStore(root: Self.recordingsFolder(in: storage.directory))
        let removed = await removeRecordings(await store.exported(before: .distantFuture), from: store)
        storageReport("storage: exported recordings clean removed \(removed.count) recordings, freed \(removed.bytes) bytes")
        return removed.bytes
    }

    /// Removes the folders of `ids`, one by one, asking again for each whether it may go: an editor opened since the list was made
    /// keeps its recording. Returns how many went and the bytes they held.
    private func removeRecordings(_ ids: [UUID], from store: RecordingStore) async -> (count: Int, bytes: Int64) {
        var removed = (count: 0, bytes: Int64(0))
        for id in ids {
            guard recording?.canRemoveRecordings ?? true, recording?.mayRemove(id) ?? true else { continue }
            let bytes = await Self.remove(id, from: store)
            if let bytes {
                removed.count += 1
                removed.bytes += bytes
            }
        }
        await recording?.refreshList()
        return removed
    }

    /// The bytes of the recording's folder if it was removed; nil if it was not.
    @concurrent private nonisolated static func remove(_ id: UUID, from store: RecordingStore) async -> Int64? {
        let bytes = await StorageFolder.bytes(in: store.folder(for: id))
        return store.remove(id: id) ? bytes : nil
    }

    // MARK: Rules

    /// The rules from the module's settings when it has any, else from the app's own store.
    private func retentionRules() -> (keepCount: Int, exportedDays: Int?) {
        if let storageSettings {
            let keys = ScreenshotSettingKeys(storageSettings)
            return (
                storageSettings.value(keys.keepCount),
                storageSettings.value(keys.cleanExportedRecordings) ? storageSettings.value(keys.exportedRecordingDays) : nil
            )
        }
        let settings = storageFallbackSettings
        return (
            settings.value(ScreenshotRetentionKeys.keepCount),
            settings.value(ScreenshotRetentionKeys.cleanExportedRecordings) ? settings.value(ScreenshotRetentionKeys.exportedRecordingDays) : nil
        )
    }
}
