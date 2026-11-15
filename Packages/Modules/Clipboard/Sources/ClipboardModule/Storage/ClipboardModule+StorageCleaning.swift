import Foundation
import MyNotchCore

/// Clipboard's part of the Storage page: what its history keeps on disk, the two cleans the page offers, and the daily rule. All of it
/// works whether or not the module runs. Running, the history changes through `update`, like any deletion of the user's, so the store,
/// the saved files and the link pictures follow. Stopped, it changes the files, after the disk work queued before it, as clearing the
/// history does. Sizes and scans run off the main thread.
extension ClipboardModule: StorageCleaning {
    static let mediaCategoryID = "clipboard.media"
    static let linkPreviewsCategoryID = "clipboard.linkpreviews"
    /// A file that no item names is left alone for this long, so the pictures a restore has stored and not yet added, or a copy that is
    /// about to be added, are never taken for leftovers.
    static let unreferencedFileGrace: TimeInterval = 60 * 60

    public func storageCategories(storage: ModuleStorage) async -> [StorageCategory] {
        let directory = storage.directory
        // A running module knows more than its files do, which are up to five seconds behind.
        let media = await ClipboardStorageScan.mediaBytes(directory: directory, history: store == nil ? nil : state.history)
        let previews = await StorageFolder.bytes(in: Self.linkPreviewsFolder(in: directory))
        return [
            StorageCategory(id: Self.mediaCategoryID, title: "Ảnh và file", bytes: media, keeps: "Giữ mục đã ghim, các bảng và mục đã khoá", canClean: true),
            StorageCategory(id: Self.linkPreviewsCategoryID, title: "Xem trước link", bytes: previews, keeps: nil, canClean: true),
        ]
    }

    public func clean(categoryID: String, storage: ModuleStorage) async -> Int64 {
        switch categoryID {
        case Self.mediaCategoryID: await cleanMedia(in: storage.directory)
        case Self.linkPreviewsCategoryID: await cleanLinkPreviews(in: storage.directory)
        default: 0
        }
    }

    /// Takes away the files nothing names, then the history's own rule (age, number of items, picture bytes), which is the one Settings
    /// shows. Does nothing while a backup is being written or restored: both read or store pictures that the history does not name yet.
    public func autoClean(now: Date, storage: ModuleStorage) async -> Int64 {
        let directory = storage.directory
        guard backupsInFlight == 0, Self.exists(directory) else { return 0 }
        activeCleaningsInFlight += 1
        defer { activeCleaningsInFlight -= 1 }
        let leftovers = await removeUnreferencedFiles(in: directory, now: now)
        let limits = retentionLimits()
        let retention = await removeItems(in: directory) { history in
            history.prune(limit: limits.limit, retention: limits.retention, imageByteLimit: limits.imageByteLimit, now: now)
        }
        let freed = leftovers.bytes + retention.bytes
        storageReport(
            "storage: auto clean removed \(leftovers.count) unreferenced files (\(leftovers.failed) failed) and \(retention.items) items, freed \(freed) bytes"
        )
        return freed
    }

    public var autoCleanSummary: String? {
        let limits = retentionLimits()
        guard let period = limits.retention.summaryPeriod else { return "Không tự xoá theo thời gian, tối đa \(limits.limit) mục" }
        return "Tự xoá mục chưa ghim sau \(period), tối đa \(limits.limit) mục"
    }

    // MARK: Pictures and files

    private func cleanMedia(in directory: URL) async -> Int64 {
        guard backupsInFlight == 0 else { return 0 }
        activeCleaningsInFlight += 1
        defer { activeCleaningsInFlight -= 1 }
        let removal = await removeItems(in: directory) { history in history.removeReleasableMedia() }
        // The pictures decoded for the cards of what went; the cards still shown decode theirs again.
        thumbnails.removeAll()
        storageReport("storage: picture clean removed \(removal.items) items, freed \(removal.bytes) bytes")
        return removal.bytes
    }

    /// Removes what `choose` takes from the history, and returns how many items went and the bytes of the picture files that are no more.
    /// Which files could go is worked out first, so their sizes are known before they are deleted; what goes is chosen again when the
    /// removal runs, so an item pinned meanwhile stays.
    private func removeItems(
        in directory: URL, choose: @escaping @MainActor (inout ClipboardHistory) -> [ClipboardItem]
    ) async -> (items: Int, bytes: Int64) {
        guard Self.exists(directory) else { return (0, 0) }
        let known: ClipboardHistory?
        if store != nil {
            known = state.history
        } else {
            known = await ClipboardStoredHistory.peek(directory: directory)
        }
        guard var preview = known else { return (0, 0) }
        let planned = choose(&preview)
        guard !planned.isEmpty else { return (0, 0) }
        let folder = Self.imagesFolder(in: directory)
        let thumbStore = ClipboardDiskThumbnailStore(directory: Self.thumbnailsFolder(in: directory))
        let plannedNames = planned.compactMap(\.storedImageFileName)
        let sizes = await ClipboardStorageScan.sizes(of: plannedNames, in: folder)
        let thumbBefore = thumbStore.bytes(for: Set(plannedNames))
        guard backupsInFlight == 0 else { return (0, 0) }
        let removed = await changeStoredHistory(in: directory, choose)
        let names = removed.compactMap(\.storedImageFileName)
        let remaining = await ClipboardStorageScan.sizes(of: names, in: folder)
        let thumbAfter = thumbStore.bytes(for: Set(names))
        let freed = names.reduce(into: Int64(0)) { total, name in
            if remaining[name] == nil { total += sizes[name] ?? 0 }
        } + max(0, thumbBefore - thumbAfter)
        return (removed.count, freed)
    }

    // MARK: Link previews

    /// Empties the pictures of link previews. The history forgets what it read of those links first, so no card draws a picture that is
    /// gone, and they are read again when shown. Items are never removed.
    private func cleanLinkPreviews(in directory: URL) async -> Int64 {
        guard backupsInFlight == 0 else { return 0 }
        activeCleaningsInFlight += 1
        defer { activeCleaningsInFlight -= 1 }
        let folder = Self.linkPreviewsFolder(in: directory)
        let before = await StorageFolder.bytes(in: folder)
        _ = await changeStoredHistory(in: directory) { history in
            history.forgetLinkPictures()
            return []
        }
        _ = await StorageFolder.removeContents(of: folder)
        let freed = max(before - (await StorageFolder.bytes(in: folder)), 0)
        storageReport("storage: link pictures clean freed \(freed) bytes")
        return freed
    }

    // MARK: Files nothing names

    /// Deletes the pictures of `images/`, `thumbnails/`, and `linkpreviews/` that no item names and that are old enough (`unreferencedFileGrace`).
    func removeUnreferencedFiles(in directory: URL, now: Date) async -> (count: Int, bytes: Int64, failed: Int) {
        let cutoff = now.addingTimeInterval(-Self.unreferencedFileGrace)
        let images = await ClipboardStorageScan.blobs(
            in: Self.imagesFolder(in: directory), matching: { ClipboardStore.isImageFileName($0) }, changedBefore: cutoff
        )
        let thumbs = await ClipboardStorageScan.blobs(
            in: Self.thumbnailsFolder(in: directory), matching: { ClipboardDiskThumbnailStore.isThumbnailFileName($0) }, changedBefore: cutoff
        )
        let previews = await ClipboardStorageScan.blobs(
            in: Self.linkPreviewsFolder(in: directory), matching: { ClipboardLinkPreview.isImageFileName($0) }, changedBefore: cutoff
        )
        guard !images.isEmpty || !thumbs.isEmpty || !previews.isEmpty else { return (0, 0, 0) }
        return await whenStopped(
            stopped: { [self] in
                guard let history = await ClipboardStoredHistory.peek(directory: directory) else { return (0, 0, 0) }
                return deleteUnreferenced(images: images, thumbnails: thumbs, previews: previews, history: history)
            },
            running: { [self] in deleteUnreferenced(images: images, thumbnails: thumbs, previews: previews, history: state.history) }
        )
    }

    private func deleteUnreferenced(
        images: [ClipboardBlob], thumbnails: [ClipboardBlob], previews: [ClipboardBlob], history: ClipboardHistory
    ) -> (count: Int, bytes: Int64, failed: Int) {
        guard backupsInFlight == 0 else { return (0, 0, 0) }
        let referencedImages = Set(history.items.compactMap(\.storedImageFileName))
        let validSizes = ClipboardThumbnailCache.supportedPixelSizes
        let keptThumbs = Set(thumbnails.compactMap { (blob) -> String? in
            guard let source = ClipboardDiskThumbnailStore.sourceName(fromThumbnailFileName: blob.name),
                  let size = ClipboardDiskThumbnailStore.thumbnailSize(fromThumbnailFileName: blob.name),
                  referencedImages.contains(source),
                  validSizes.contains(size)
            else { return nil }
            return blob.name
        })
        let pictures = ClipboardStorageScan.delete(images, keeping: referencedImages)
        let thumbPictures = ClipboardStorageScan.delete(thumbnails, keeping: keptThumbs)
        let linkPictures = ClipboardStorageScan.delete(previews, keeping: history.linkPreviewFileNames)
        return (
            pictures.count + thumbPictures.count + linkPictures.count,
            pictures.bytes + thumbPictures.bytes + linkPictures.bytes,
            pictures.failed + thumbPictures.failed + linkPictures.failed
        )
    }

    // MARK: Changing the history

    /// Applies `change` to the history and returns the items it removed: through `update` when the module runs, to the files when it is
    /// stopped.
    private func changeStoredHistory(
        in directory: URL, _ change: @escaping @MainActor (inout ClipboardHistory) -> [ClipboardItem]
    ) async -> [ClipboardItem] {
        await whenStopped(
            stopped: { [self] in await changeFiles(in: directory, change) },
            running: { [self] in changeRunningHistory(change) }
        )
    }

    private func changeRunningHistory(_ change: (inout ClipboardHistory) -> [ClipboardItem]) -> [ClipboardItem] {
        var removed: [ClipboardItem] = []
        update { history in
            removed = change(&history)
            return removed
        }
        return removed
    }

    /// Edits a stopped module's files. Nothing is done for a folder that was never made or a history that cannot be read in full, and
    /// nothing is written when `change` leaves the history as it is. Pictures are deleted only once the history that no longer lists them
    /// is written, so a failed write loses nothing. Returns what was removed, or nothing if it was not written.
    private func changeFiles(in directory: URL, _ change: (inout ClipboardHistory) -> [ClipboardItem]) async -> [ClipboardItem] {
        guard Self.exists(directory), let original = await ClipboardStoredHistory.peek(directory: directory) else { return [] }
        var history = original
        let removed = change(&history)
        guard history != original else { return [] }
        let store = ClipboardStore(directory: directory, scheduler: TaskScheduler(), logger: Log.logger(category: descriptor.id.rawValue), now: now)
        store.scheduleSave(history)
        await store.flush()
        guard store.writeCount > 0 else { return [] }
        store.deleteImages(for: removed)
        store.deleteLinkPreviewImages(named: removed.compactMap(\.linkPreviewFileName))
        return removed
    }

    /// Runs `running` when the module runs; otherwise `stopped`, after the disk work queued before it, so it never meets the files of a
    /// start, which waits for it in turn. A start that got in first while it waited is a module that runs.
    private func whenStopped<Result: Sendable>(
        stopped: @escaping @MainActor () async -> Result, running: @escaping @MainActor () -> Result
    ) async -> Result {
        if store != nil { return running() }
        let previous = diskWork
        let work = Task<Result, Never> {
            await previous?.value
            return self.store != nil ? running() : await stopped()
        }
        diskWork = Task { _ = await work.value }
        return await work.value
    }

    // MARK: Rule and folders

    /// The rule of Settings as it is now: from the settings the module has been given, or, when none has reached it, from the app's own.
    private func retentionLimits() -> ClipboardRestoreImpact.Limits {
        let limit: Int, retention: Retention, imageMB: Int
        if let storageSettings {
            let keys = ClipboardSettingKeys(storageSettings)
            limit = storageSettings.value(keys.historyLimit)
            retention = storageSettings.value(keys.retention)
            imageMB = storageSettings.value(keys.imageStorageLimitMB)
        } else {
            limit = storageFallbackSettings.value(ClipboardRetentionKeys.historyLimit)
            retention = storageFallbackSettings.value(ClipboardRetentionKeys.retention)
            imageMB = storageFallbackSettings.value(ClipboardRetentionKeys.imageStorageLimitMB)
        }
        return ClipboardRestoreImpact.Limits(limit: limit, retention: retention, imageByteLimit: imageMB * ClipboardStorageUsage.bytesPerMB)
    }

    private static func imagesFolder(in directory: URL) -> URL {
        directory.appending(path: "images", directoryHint: .isDirectory)
    }

    private static func thumbnailsFolder(in directory: URL) -> URL {
        directory.appending(path: "thumbnails", directoryHint: .isDirectory)
    }

    private static func linkPreviewsFolder(in directory: URL) -> URL {
        directory.appending(path: "linkpreviews", directoryHint: .isDirectory)
    }

    private static func exists(_ directory: URL) -> Bool {
        FileManager.default.fileExists(atPath: directory.path(percentEncoded: false))
    }
}

private extension Retention {
    /// "1 tháng", as in "sau 1 tháng"; nil when nothing is removed for its age.
    var summaryPeriod: String? {
        switch self {
        case .day: "1 ngày"
        case .week: "1 tuần"
        case .month: "1 tháng"
        case .year: "1 năm"
        case .forever: nil
        }
    }
}
