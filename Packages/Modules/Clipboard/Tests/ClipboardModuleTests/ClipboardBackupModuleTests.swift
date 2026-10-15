import Foundation
import MyNotchCore
import Testing
@testable import ClipboardModule

/// Backing up and restoring as the module does it, on the same fixture as `ClipboardModuleTests`.
extension ClipboardModuleTests {
    func backupFile(_ name: String = "backup.mynotchclip") -> URL {
        temporaryRoot.appending(path: name)
    }

    func essences() -> [BackupWorld.Essence] {
        items.map(BackupWorld.Essence.init)
    }

    /// A few copies as the user makes them, a minute apart, with a pinned board that has an icon and a colour.
    func makeHistory() async throws {
        system.now = Date(timeIntervalSince1970: 1_800_000_000)
        copy("một")
        system.now += 60
        copy(PasteboardSnapshot(types: ["public.png"], png: ClipboardClassifierTests.png))
        system.now += 60
        copy("hai")
        let board = try #require(module.createBoard(named: "Việc"))
        module.setBoardIcon(board, to: "star")
        module.setBoardColor(board, to: .teal)
        module.pin(try #require(items.last), to: board)
    }

    @Test func aBackupRestoresAHistoryThatWasCleared() async throws {
        await start()
        try await makeHistory()
        let before = essences()
        let file = backupFile()

        let exported = try await module.exportBackup(ClipboardBackupOptions(), to: file)
        module.delete(ids: Set(items.map(\.id)))
        module.deleteBoard(try #require(state.history.boards.first?.id))
        #expect(items.isEmpty && state.history.boards.isEmpty)
        let restored = try await module.restoreBackup(from: file)

        #expect(exported.itemCount == 3 && exported.boardCount == 1)
        #expect(restored == ClipboardBackupRestoreSummary(added: 3, boardsCreated: 1))
        #expect(restored.text == "Đã thêm 3 mục, tạo 1 board mới")
        #expect(essences() == before)
        let image = try #require(items.first { $0.content.kind == .image })
        #expect(exists(try #require(module.fileURLs(of: image).first)))
        let board = try #require(state.history.boards.first)
        #expect(board.name == "Việc" && board.systemImage == "star" && board.color == .teal)
        #expect(board.itemIDs.count == 1 && state.history.items.first { $0.id == board.itemIDs[0] }?.content == .text("một"))
    }

    @Test func restoringOverAHistoryThatHasTheItemsAddsNothing() async throws {
        await start()
        try await makeHistory()
        let file = backupFile()
        _ = try await module.exportBackup(ClipboardBackupOptions(), to: file)
        let before = items

        let restored = try await module.restoreBackup(from: file)

        #expect(restored == ClipboardBackupRestoreSummary(added: 0, duplicates: 3))
        #expect(restored.text == "Đã thêm 0 mục, bỏ qua 3 trùng lặp")
        #expect(items == before)
        #expect(state.history.boards.count == 1)
    }

    @Test func aSecretTheUserKeepsStaysOutOfTheBackupUnlessAskedFor() async throws {
        let (settings, keys) = try settings()
        settings.set(false, for: keys.ignoreSensitive)
        await start()
        copy(PasteboardSnapshot(types: Self.concealed, string: "mật khẩu"))
        copy("công khai")

        let plain = try await module.exportBackup(ClipboardBackupOptions(), to: backupFile("plain.mynotchclip"))
        let all = try await module.exportBackup(ClipboardBackupOptions(skipSensitive: false), to: backupFile("all.mynotchclip"))

        #expect(plain.itemCount == 1 && plain.skippedSensitive == 1)
        #expect(all.itemCount == 2 && all.skippedSensitive == 0)
        let reader = try ZipReader(url: backupFile("plain.mynotchclip"), limits: .unlimited)
        for entry in reader.entries {
            #expect(!String(decoding: try reader.data(of: entry), as: UTF8.self).contains("mật khẩu"))
        }
        // And it comes back marked, so it can be left out of the next backup too.
        module.delete(ids: Set(items.map(\.id)))
        _ = try await module.restoreBackup(from: backupFile("all.mynotchclip"))
        #expect(items.filter(\.isSensitive).map(\.content) == [.text("mật khẩu")])
    }

    @Test func backingUpAndRestoringNeedTheModuleToRun() async throws {
        await #expect(throws: ClipboardBackupError.moduleStopped) {
            try await module.exportBackup(ClipboardBackupOptions(), to: backupFile())
        }
        await #expect(throws: ClipboardBackupError.moduleStopped) { try await module.restoreBackup(from: backupFile()) }
        #expect(!exists(backupFile()))
    }

    @Test func restoredItemsAndTheirImagesAreSavedAndSurviveARestart() async throws {
        await start()
        try await makeHistory()
        let file = backupFile()
        _ = try await module.exportBackup(ClipboardBackupOptions(), to: file)
        module.delete(ids: Set(items.map(\.id)))
        _ = try await module.restoreBackup(from: file)
        let before = essences()

        await harness.registry.setEnabled(false, for: "clipboard")
        #expect(makeStore().load().items.count == 3)
        await harness.registry.setEnabled(true, for: "clipboard")

        #expect(essences() == before)
        let image = try #require(items.first { $0.content.kind == .image })
        #expect(exists(try #require(module.fileURLs(of: image).first)))
        #expect(state.history.boards.map(\.name) == ["Việc"])
    }

    @Test func theLimitsOfTheHistoryStillApplyAndTheSummaryTellsWhatTheyTookAway() async throws {
        await start()
        system.now = Date(timeIntervalSince1970: 1_800_000_000)
        let world = try BackupWorld()
        // Both are 40 days old, and the default is to keep a month; only the one in a board is kept.
        let old = system.now.timeIntervalSince1970 - 40 * 86_400
        let pinned = UUID(), loose = UUID()
        let manifest = BackupWorld.manifest(
            items: [BackupWorld.manifestItem(pinned, copiedAt: old), BackupWorld.manifestItem(loose, copiedAt: old + 1)],
            boards: [["name": "Giữ", "icon": "star", "items": [pinned.uuidString]]]
        )
        let file = try world.craft(
            manifest: manifest,
            entries: [
                (BackupWorld.payload(pinned, "txt"), Data("đã ghim".utf8), 0o100644), (BackupWorld.payload(loose, "txt"), Data("không ghim".utf8), 0o100644),
            ]
        )

        let restored = try await module.restoreBackup(from: file)

        #expect(restored == ClipboardBackupRestoreSummary(added: 1, boardsCreated: 1, prunedByLimits: 1))
        #expect(restored.text.contains("1 mục vượt giới hạn hoặc thời gian giữ"))
        #expect(items.map(\.content) == [.text("đã ghim")])
        #expect(state.history.boards.first?.itemIDs == [items[0].id])
    }

    @Test func aRestoreOfAnImageThatTheLimitsDropLeavesNoFileBehind() async throws {
        await start()
        system.now = Date(timeIntervalSince1970: 1_800_000_000)
        let world = try BackupWorld()
        let id = UUID()
        let old = system.now.timeIntervalSince1970 - 40 * 86_400
        let file = try world.craft(
            manifest: BackupWorld.manifest(items: [BackupWorld.manifestItem(id, kind: "image", copiedAt: old)]),
            entries: [(BackupWorld.payload(id, "png"), world.firstPNG, 0o100644)]
        )

        let restored = try await module.restoreBackup(from: file)

        #expect(restored.added == 0 && restored.prunedByLimits == 1)
        #expect(!exists(imageFile(world.firstPNG.sha256Hex + ".png")))
    }

    @Test func aFileThatCannotBeUsedChangesNothing() async throws {
        await start()
        try await makeHistory()
        let before = items
        let boards = state.history.boards
        let bad = backupFile("bad.mynotchclip")
        try Data("not a backup".utf8).write(to: bad)

        await #expect(throws: ClipboardBackupError.notABackup) { try await module.restoreBackup(from: bad) }

        #expect(items == before && state.history.boards == boards)
    }

    @Test func aCancelledRestoreChangesNothing() async throws {
        await start()
        try await makeHistory()
        let file = backupFile()
        _ = try await module.exportBackup(ClipboardBackupOptions(), to: file)
        module.delete(ids: Set(items.map(\.id)))
        module.deleteBoard(try #require(state.history.boards.first?.id))

        let module = module
        let task = Task {
            try await module.restoreBackup(from: file, progress: { _ in withUnsafeCurrentTask { $0?.cancel() } })
        }
        await #expect(throws: CancellationError.self) { try await task.value }

        #expect(items.isEmpty && state.history.boards.isEmpty)
    }

    @Test func aCancelledBackupLeavesNoFile() async throws {
        await start()
        try await makeHistory()
        let module = module
        let file = backupFile("cancelled.mynotchclip")

        let task = Task {
            try await module.exportBackup(ClipboardBackupOptions(), to: file, progress: { _ in withUnsafeCurrentTask { $0?.cancel() } })
        }
        await #expect(throws: CancellationError.self) { try await task.value }

        #expect(!exists(file))
    }

    @Test func theCodeAnswerGoesThroughAndATextWithoutOneGetsOne() async throws {
        await start()
        let world = try BackupWorld()
        let none = UUID(), marked = UUID()
        let file = try world.craft(
            manifest: BackupWorld.manifest(items: [
                BackupWorld.manifestItem(none, copiedAt: system.now.timeIntervalSince1970 - 100),
                BackupWorld.manifestItem(marked, copiedAt: system.now.timeIntervalSince1970 - 200, extra: ["code": "python"]),
            ]),
            entries: [
                (BackupWorld.payload(none, "txt"), Data(BackupWorld.swiftCode.utf8), 0o100644),
                (BackupWorld.payload(marked, "txt"), Data("hello".utf8), 0o100644),
            ]
        )

        _ = try await module.restoreBackup(from: file)

        #expect(items.map(\.codeDetection) == [.code(.swift), .code(.python)])
        // Found by the code filter at once, with no wait for the start-up pass.
        state.query.text = "@code"
        #expect(state.visibleItems.count == 2)
    }
}
