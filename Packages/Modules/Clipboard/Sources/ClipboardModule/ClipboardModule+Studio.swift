import Foundation
import MyNotchCore

public struct ClipboardStudioStatus: Sendable, Equatable {
    public let totalItems: Int
    public let pinnedItems: Int
    public let unpinnedItems: Int
    public let boardsCount: Int
    public let imagesCount: Int
    public let mediaBytes: Int64

    public init(
        totalItems: Int,
        pinnedItems: Int,
        unpinnedItems: Int,
        boardsCount: Int,
        imagesCount: Int = 0,
        mediaBytes: Int64 = 0
    ) {
        self.totalItems = totalItems
        self.pinnedItems = pinnedItems
        self.unpinnedItems = unpinnedItems
        self.boardsCount = boardsCount
        self.imagesCount = imagesCount
        self.mediaBytes = mediaBytes
    }
}

public struct ClipboardPurgeReport: Sendable, Equatable {
    public let removedItems: Int
    public let keptPinnedItems: Int
    public let freedBytes: Int64
    public let removedOrphanImages: Int

    public init(
        removedItems: Int,
        keptPinnedItems: Int,
        freedBytes: Int64,
        removedOrphanImages: Int
    ) {
        self.removedItems = removedItems
        self.keptPinnedItems = keptPinnedItems
        self.freedBytes = freedBytes
        self.removedOrphanImages = removedOrphanImages
    }
}

extension ClipboardModule {
    @MainActor
    public func studioStatus() -> ClipboardStudioStatus {
        if store != nil {
            let history = state.history
            let total = history.items.count
            let pinned = history.items.filter { history.isPinned($0.id) }.count
            let unpinned = max(total - pinned, 0)
            let boards = history.boards.count
            return ClipboardStudioStatus(
                totalItems: total,
                pinnedItems: pinned,
                unpinnedItems: unpinned,
                boardsCount: boards
            )
        } else {
            return ClipboardStudioStatus(
                totalItems: 0,
                pinnedItems: 0,
                unpinnedItems: 0,
                boardsCount: 0
            )
        }
    }

    @discardableResult
    public func purgeUnpinnedAndOrphans(storage: ModuleStorage) async -> ClipboardPurgeReport {
        guard backupsInFlight == 0 else {
            return ClipboardPurgeReport(removedItems: 0, keptPinnedItems: 0, freedBytes: 0, removedOrphanImages: 0)
        }
        activeCleaningsInFlight += 1
        defer { activeCleaningsInFlight -= 1 }

        if store == nil {
            guard await ClipboardStoredHistory.peek(directory: storage.directory) != nil else {
                return ClipboardPurgeReport(removedItems: 0, keptPinnedItems: 0, freedBytes: 0, removedOrphanImages: 0)
            }
        }

        let initialStatus = await MainActor.run { self.studioStatus() }

        // Đảm bảo dữ liệu hiện tại được flush xuống đĩa trước khi đo dung lượng ban đầu
        await store?.flush()
        let dirBytesBefore = await StorageFolder.bytes(in: storage.directory)
        let cacheBytesBefore = await StorageFolder.bytes(in: storage.cachesDirectory)
        let bytesBefore = dirBytesBefore + cacheBytesBefore

        // 1. Dọn dẹp các mục chưa ghim (giữ lại mục đã ghim và trong các bảng)
        await clearHistory(.all, directory: storage.directory).value

        // 2. Dọn các file ảnh / preview mồ côi
        let leftovers = await removeUnreferencedFiles(in: storage.directory, now: now())

        // 3. Làm sạch thư mục caches
        _ = await StorageFolder.removeContents(of: storage.cachesDirectory)

        // 4. Giải phóng cache thumbnails trong bộ nhớ và flush dữ liệu xuống đĩa bền vững
        await MainActor.run {
            self.thumbnails.removeAll()
        }
        await store?.flush()

        let dirBytesAfter = await StorageFolder.bytes(in: storage.directory)
        let cacheBytesAfter = await StorageFolder.bytes(in: storage.cachesDirectory)
        let bytesAfter = dirBytesAfter + cacheBytesAfter
        let actualFreed = max(bytesBefore - bytesAfter, 0)

        let finalStatus = await MainActor.run { self.studioStatus() }
        let removedItemsCount = max(initialStatus.unpinnedItems - finalStatus.unpinnedItems, 0)

        return ClipboardPurgeReport(
            removedItems: removedItemsCount,
            keptPinnedItems: finalStatus.pinnedItems,
            freedBytes: actualFreed,
            removedOrphanImages: leftovers.count
        )
    }
}
