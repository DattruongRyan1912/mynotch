import Foundation
import Testing
@testable import ClipboardModule
import MyNotchCore
import MyNotchTestSupport

@Suite final class ClipboardStudioCleanerTests {
    private static let pollInterval: Duration = .milliseconds(300)

    let pasteboard = FakePasteboard()
    let keystrokes = FakeKeystrokeSender()
    let libraryWindow = FakeLibraryWindow()
    let panelWindow = FakePanelWindow()
    let libraryPreview = FakePreviewWindow()
    let panelPreview = FakePreviewWindow()
    let tabPreview = FakePreviewWindow()
    let system = FakeSystem()
    let modifiers = FakeModifierState()
    let module: ClipboardModule
    let harness: RegistryHarness
    let temporaryRoot: URL

    init() {
        let system = system
        module = ClipboardModule(
            pasteboard: pasteboard, keystrokes: keystrokes,
            frontmostApp: { system.frontmost }, isTrusted: { system.trusted },
            pasteboardAccessBehavior: { system.accessBehavior }, modifiers: modifiers, now: { system.now },
            libraryWindow: libraryWindow, panelWindow: panelWindow, libraryPreview: libraryPreview, panelPreview: panelPreview,
            tabPreview: tabPreview
        )
        harness = RegistryHarness([module])
        temporaryRoot = harness.storageRoot.applicationSupport.deletingLastPathComponent()
    }

    deinit {
        try? FileManager.default.removeItem(at: temporaryRoot)
    }

    var storage: ModuleStorage { harness.storageRoot.storage(for: "clipboard") }
    var directory: URL { storage.directory }
    var items: [ClipboardItem] { module.state.history.items }

    func start() async {
        await harness.registry.bootstrap()
        #expect(harness.registry.state(of: "clipboard") == .running)
    }

    func copy(_ text: String) {
        pasteboard.copy(PasteboardSnapshot(types: ["public.utf8-plain-text"], string: text))
        harness.scheduler.advance(by: Self.pollInterval)
    }

    @Test func testStudioStatusAndPurgeUnpinnedPreservesPinnedItemsAndSweepsOrphans() async throws {
        await start()

        system.now += 10
        copy("Item 1 - Unpinned")
        system.now += 10
        copy("Item 2 - Will Pin")
        system.now += 10
        copy("Item 3 - Unpinned")

        let itemToPin = try #require(items.first(where: { $0.content == .text("Item 2 - Will Pin") }))
        let boardID = try #require(module.createBoard(named: "Board Quan Trọng"))
        module.pin(itemToPin, to: boardID)

        // Tạo ảnh mồ côi cũ trong images/ có tên sha256 64 ký tự hex và modificationDate > 1 giờ trước
        let imagesFolder = directory.appending(path: "images")
        try FileManager.default.createDirectory(at: imagesFolder, withIntermediateDirectories: true)
        let orphanFileName = String(repeating: "a", count: 64) + ".png"
        let orphanURL = imagesFolder.appending(path: orphanFileName)
        try Data("dummy-orphan".utf8).write(to: orphanURL)
        let twoHoursAgo = system.now.addingTimeInterval(-7200)
        try FileManager.default.setAttributes([.modificationDate: twoHoursAgo], ofItemAtPath: orphanURL.path(percentEncoded: false))

        // Tạo file tạm trong cachesDirectory
        try FileManager.default.createDirectory(at: storage.cachesDirectory, withIntermediateDirectories: true)
        let tempCacheFile = storage.cachesDirectory.appending(path: "temp.cache")
        try Data("cache-data".utf8).write(to: tempCacheFile)

        // Kiểm tra status trước khi purge
        let statusBefore = module.studioStatus()
        #expect(statusBefore.totalItems == 3)
        #expect(statusBefore.pinnedItems == 1)
        #expect(statusBefore.unpinnedItems == 2)
        #expect(statusBefore.boardsCount == 1)

        // Thực thi purge
        let report = await module.purgeUnpinnedAndOrphans(storage: storage)
        #expect(report.removedItems == 2)
        #expect(report.keptPinnedItems == 1)
        #expect(report.freedBytes > 0)

        // Kiểm tra status sau khi purge
        let statusAfter = module.studioStatus()
        #expect(statusAfter.totalItems == 1)
        #expect(statusAfter.pinnedItems == 1)
        #expect(statusAfter.unpinnedItems == 0)
        #expect(items.map(\.id) == [itemToPin.id])

        // Đối soát dữ liệu bền vững trên đĩa qua ClipboardStoredHistory.peek
        let persisted = try #require(await ClipboardStoredHistory.peek(directory: directory))
        #expect(persisted.items.map(\.id) == [itemToPin.id])
        #expect(persisted.boards.count == 1)

        // File mồ côi và file cache đã bị xoá
        #expect(!FileManager.default.fileExists(atPath: orphanURL.path(percentEncoded: false)))
        #expect(!FileManager.default.fileExists(atPath: tempCacheFile.path(percentEncoded: false)))
    }

    @Test func testPurgeUnpinnedAbortsSafelyWhenBackupInFlight() async throws {
        await start()

        system.now += 10
        copy("Item A")
        system.now += 10
        copy("Item B")

        module.backupsInFlight = 1

        let report = await module.purgeUnpinnedAndOrphans(storage: storage)
        #expect(report.removedItems == 0)
        #expect(report.freedBytes == 0)
        #expect(items.count == 2)
    }

    @Test func testClearFilesAbortsWhenBoardsJSONIsCorrupted() async throws {
        // Tạo file history.json hợp lệ và boards.json bị hỏng
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let sampleHistory = [ClipboardItem(id: UUID(), content: .text("Hello World"), contentHash: "hash123", copiedAt: Date())]
        let historyData = try JSONEncoder().encode(sampleHistory)
        try historyData.write(to: directory.appending(path: "history.json"))
        try Data("CORRUPTED_JSON".utf8).write(to: directory.appending(path: "boards.json"))

        // Gọi clearHistory khi module đang stopped
        await module.clearHistory(.all, directory: directory).value

        // Xác nhận dữ liệu không bị xoá sạch vì clearFiles đã abort an toàn
        let recheckHistory = try Data(contentsOf: directory.appending(path: "history.json"))
        #expect(!recheckHistory.isEmpty)
    }

    @Test func testBackupRefusesWhenActiveCleaningInFlight() async throws {
        await start()
        module.activeCleaningsInFlight = 1
        let dummyDest = directory.appending(path: "test.backup")

        await #expect(throws: ClipboardBackupError.busy) {
            try await module.exportBackup(ClipboardBackupOptions(), to: dummyDest)
        }

        await #expect(throws: ClipboardBackupError.busy) {
            _ = try await module.planRestore(from: dummyDest)
        }
    }
}
