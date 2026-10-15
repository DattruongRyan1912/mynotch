import Foundation
import MyNotchCore
import Testing
@testable import ClipboardModule

/// Backing up and restoring as the module does it, on the same fixture as `ClipboardModuleTests`. A restore is two steps: the
/// plan, which reads the file and writes nothing, and the commit, which the user chooses the way of.
extension ClipboardModuleTests {
    func backupFile(_ name: String = "backup.mynotchclip") -> URL {
        temporaryRoot.appending(path: name)
    }

    func essences() -> [BackupWorld.Essence] {
        items.map(BackupWorld.Essence.init)
    }

    func plan(_ file: URL) async throws -> ClipboardRestoreOffer {
        try await module.planRestore(from: file)
    }

    /// Both steps, with the choice made by the caller.
    @discardableResult
    func restore(_ file: URL, _ policy: ClipboardRestorePolicy = .applyLimits) async throws -> ClipboardBackupRestoreSummary {
        try await plan(file).commit(policy, { _ in })
    }

    func imageFiles() throws -> [String] {
        let folder = directory.appending(path: "images", directoryHint: .isDirectory)
        return try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false)).sorted()
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

    /// A backup file of `count` text items `daysOld` days old (plus one second each), written by a world of its own.
    func oldBackup(count: Int, daysOld: Double, as name: String = "old.mynotchclip", boards: [[String: Any]] = []) throws -> URL {
        let world = try BackupWorld()
        let ids = (0..<count).map { _ in UUID() }
        let old = system.now.timeIntervalSince1970 - daysOld * 86_400
        let url = backupFile(name)
        try FileManager.default.copyItem(
            at: try world.craft(
                manifest: BackupWorld.manifest(
                    items: ids.enumerated().map { BackupWorld.manifestItem($1, copiedAt: old + Double($0)) }, boards: boards
                ),
                entries: ids.enumerated().map { (BackupWorld.payload($1, "txt"), Data("cũ \($0) \(name)".utf8), 0o100644) }
            ),
            to: url
        )
        return url
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
        let restored = try await restore(file)

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

        let restored = try await restore(file)

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
        try await restore(backupFile("all.mynotchclip"))
        #expect(items.filter(\.isSensitive).map(\.content) == [.text("mật khẩu")])
    }

    @Test func backingUpAndRestoringNeedTheModuleToRun() async throws {
        await #expect(throws: ClipboardBackupError.moduleStopped) {
            try await module.exportBackup(ClipboardBackupOptions(), to: backupFile())
        }
        await #expect(throws: ClipboardBackupError.moduleStopped) { try await module.planRestore(from: backupFile()) }
        #expect(!exists(backupFile()))
    }

    @Test func restoredItemsAndTheirImagesAreSavedAndSurviveARestart() async throws {
        await start()
        try await makeHistory()
        let file = backupFile()
        _ = try await module.exportBackup(ClipboardBackupOptions(), to: file)
        module.delete(ids: Set(items.map(\.id)))
        try await restore(file)
        let before = essences()

        await harness.registry.setEnabled(false, for: "clipboard")
        #expect(makeStore().load().items.count == 3)
        await harness.registry.setEnabled(true, for: "clipboard")

        #expect(essences() == before)
        let image = try #require(items.first { $0.content.kind == .image })
        #expect(exists(try #require(module.fileURLs(of: image).first)))
        #expect(state.history.boards.map(\.name) == ["Việc"])
    }

    // MARK: Nothing is written before the choice

    @Test func planningReadsTheFileAndChangesNothing() async throws {
        await start()
        try await makeHistory()
        let file = backupFile()
        _ = try await module.exportBackup(ClipboardBackupOptions(), to: file)
        module.delete(ids: Set(items.map(\.id)))
        module.deleteBoard(try #require(state.history.boards.first?.id))
        harness.scheduler.advance(by: .seconds(1))
        await module.store?.waitForWrites()
        let files = try imageFiles()
        let history = state.history
        let onDisk = makeStore().load()

        let offer = try await plan(file)

        #expect(offer.summary == ClipboardRestorePlanSummary(added: 3, boardsToCreate: 1))
        #expect(state.history == history)
        #expect(try imageFiles() == files)
        harness.scheduler.advance(by: .seconds(6))
        await module.store?.waitForWrites()
        #expect(makeStore().load() == onDisk)
    }

    @Test func notChoosingLeavesEverythingAsItWas() async throws {
        await start()
        try await makeHistory()
        let file = backupFile()
        _ = try await module.exportBackup(ClipboardBackupOptions(), to: file)
        module.delete(ids: Set(items.map(\.id)))
        let files = try imageFiles()

        // The offer is made and dropped, as when the user answers "Huỷ".
        _ = try await plan(file)

        let after = try imageFiles()
        #expect(items.isEmpty && after == files)
    }

    @Test func aCancelledPlanLeavesNothing() async throws {
        await start()
        try await makeHistory()
        let file = backupFile()
        _ = try await module.exportBackup(ClipboardBackupOptions(), to: file)
        module.delete(ids: Set(items.map(\.id)))
        let module = module
        let files = try imageFiles()

        let task = Task { try await module.planRestore(from: file, progress: { _ in withUnsafeCurrentTask { $0?.cancel() } }) }
        await #expect(throws: CancellationError.self) { try await task.value }

        let after = try imageFiles()
        #expect(items.isEmpty && after == files)
    }

    @Test func aFileThatCannotBeUsedChangesNothing() async throws {
        await start()
        try await makeHistory()
        let before = items
        let boards = state.history.boards
        let bad = backupFile("bad.mynotchclip")
        try Data("not a backup".utf8).write(to: bad)

        await #expect(throws: ClipboardBackupError.notABackup) { try await module.planRestore(from: bad) }

        #expect(items == before && state.history.boards == boards)
    }

    // MARK: The limits, said before and applied after the choice

    @Test func theLimitsAreToldBeforeAndAppliedOnlyWhenChosen() async throws {
        await start()
        system.now = Date(timeIntervalSince1970: 1_800_000_000)
        // 40 days old, and the default is to keep a month; the pinned one of the two is exempt as any pinned item is.
        let ids = (UUID(), UUID())
        let world = try BackupWorld()
        let old = system.now.timeIntervalSince1970 - 40 * 86_400
        let file = try world.craft(
            manifest: BackupWorld.manifest(
                items: [BackupWorld.manifestItem(ids.0, copiedAt: old), BackupWorld.manifestItem(ids.1, copiedAt: old + 1)],
                boards: [["name": "Giữ", "icon": "star", "items": [ids.0.uuidString]]]
            ),
            entries: [
                (BackupWorld.payload(ids.0, "txt"), Data("đã ghim".utf8), 0o100644), (BackupWorld.payload(ids.1, "txt"), Data("không ghim".utf8), 0o100644),
            ]
        )

        let offer = try await plan(file)
        #expect(offer.summary == ClipboardRestorePlanSummary(added: 2, boardsToCreate: 1, outsideLimits: 1))
        #expect(items.isEmpty)

        let restored = try await offer.commit(.applyLimits, { _ in })

        #expect(restored == ClipboardBackupRestoreSummary(added: 1, boardsCreated: 1, prunedByLimits: 1))
        #expect(restored.text.contains("1 mục vượt giới hạn hoặc thời gian giữ"))
        #expect(items.map(\.content) == [.text("đã ghim")])
        #expect(state.history.boards.first?.itemIDs == [items[0].id])
    }

    @Test func keepingEverythingKeepsWhatTheLimitsWouldDropAndItStaysAfterTheNextCopy() async throws {
        await start()
        system.now = Date(timeIntervalSince1970: 1_800_000_000)
        let file = try oldBackup(count: 5, daysOld: 100)

        let offer = try await plan(file)
        #expect(offer.summary.outsideLimits == 5)
        let restored = try await offer.commit(.keepAll, { _ in })

        #expect(restored == ClipboardBackupRestoreSummary(added: 5))
        #expect(items.count == 5 && items.allSatisfy(\.isExemptFromLimits))
        // The next copy runs the limits again, and they leave the restored items alone.
        copy("mới")
        harness.scheduler.advance(by: .seconds(1))
        #expect(items.count == 6)
        // They are saved as kept: after a restart the limits still leave them alone.
        await harness.registry.setEnabled(false, for: "clipboard")
        await harness.registry.setEnabled(true, for: "clipboard")
        #expect(items.count == 6 && items.filter(\.isExemptFromLimits).count == 5)
    }

    /// 50 items in the history, the lowest history limit, three of the oldest of them images with files; a file of ten newer ones.
    func fullHistoryAndANewerBackup() async throws -> URL {
        let (settings, keys) = try settings()
        settings.set(50, for: keys.historyLimit)
        var history = ClipboardHistory()
        let base = system.now
        for index in 0..<47 {
            let content = ClipboardContent.text("có \(index)")
            history.items.append(Self.item(content, copiedAt: base.addingTimeInterval(-3_600 - Double(index))))
        }
        for index in 0..<3 {
            let content = Self.image("hiện có \(index)")
            history.items.append(Self.item(content, copiedAt: base.addingTimeInterval(-7_200 - Double(index))))
        }
        await persist(history)
        for index in 0..<3 { try Data([1, 2, 3, 4]).write(to: imageFile(Data("hiện có \(index)".utf8).sha256Hex + ".png")) }
        return try oldBackup(count: 10, daysOld: 0.001, as: "newer.mynotchclip")
    }

    @Test func aRestoreSaysWhichOfTheItemsThatAreThereWouldMakeRoomAndHowManyAreImages() async throws {
        let file = try await fullHistoryAndANewerBackup()
        await start()
        #expect(items.count == 50)

        let offer = try await plan(file)

        #expect(offer.summary.added == 10 && offer.summary.outsideLimits == 0)
        #expect(offer.summary.evictedExisting == 10 && offer.summary.evictedExistingImages == 3)
        #expect(offer.summary.affectsHistory)
    }

    @Test func keepingEverythingEvictsNoItemThatWasThere() async throws {
        let file = try await fullHistoryAndANewerBackup()
        await start()
        let before = Set(items.map(\.id))
        let imagesBefore = try imageFiles()

        let restored = try await restore(file, .keepAll)

        #expect(restored == ClipboardBackupRestoreSummary(added: 10))
        #expect(items.count == 60 && before.isSubset(of: Set(items.map(\.id))))
        #expect(try imageFiles() == imagesBefore)
        // A copy made later is an ordinary one and takes its place under the limit as any copy does, which makes room by taking
        // the oldest ordinary item; the restored ones, which do not count, are all still there.
        copy("thêm")
        #expect(items.filter(\.isExemptFromLimits).count == 10)
        #expect(items.count == 60)
    }

    @Test func underTheLimitsTheOldestItemsThatWereThereMakeRoomAndTheirImagesGo() async throws {
        let file = try await fullHistoryAndANewerBackup()
        await start()

        let restored = try await restore(file, .applyLimits)

        #expect(restored == ClipboardBackupRestoreSummary(added: 10, evictedExisting: 10))
        #expect(restored.text.contains("10 mục đã có bị xoá để vừa giới hạn lịch sử"))
        #expect(items.count == 50)
        #expect(items.filter { $0.content.kind == .image }.isEmpty)
        #expect(try imageFiles().isEmpty)
    }

    @Test func anItemThatTheLimitsWouldTakeAnywayIsNotCountedAgainstTheRestore() async throws {
        await start()
        copy("sắp hết hạn")
        let file = try oldBackup(count: 1, daysOld: 0)
        // 40 days later nothing has pruned it yet, but the next change to the history will, restore or not.
        system.now += 40 * 86_400

        let offer = try await plan(file)
        let restored = try await offer.commit(.applyLimits, { _ in })

        #expect(offer.summary.evictedExisting == 0)
        #expect(restored.evictedExisting == 0)
    }

    @Test func theHistoryMayHaveChangedBetweenThePlanAndTheCommit() async throws {
        await start()
        system.now = Date(timeIntervalSince1970: 1_800_000_000)
        let file = try oldBackup(count: 3, daysOld: 0.01)
        let offer = try await plan(file)

        copy("đến sau khi đọc tệp")
        let restored = try await offer.commit(.applyLimits, { _ in })

        #expect(restored.added == 3)
        #expect(items.count == 4)
    }

    // MARK: The second step

    @Test func theCommitMakesTheImagesAndAStoppedModuleLeavesNone() async throws {
        await start()
        try await makeHistory()
        let file = backupFile()
        _ = try await module.exportBackup(ClipboardBackupOptions(), to: file)
        module.delete(ids: Set(items.map(\.id)))
        let offer = try await plan(file)
        let folder = directory.appending(path: "images", directoryHint: .isDirectory)
        #expect(try imageFiles().isEmpty)

        await harness.registry.setEnabled(false, for: "clipboard")
        await #expect(throws: ClipboardBackupError.moduleStopped) { try await offer.commit(.applyLimits, { _ in }) }

        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false)).isEmpty)
    }

    @Test func aCancelledCommitChangesNothingAndLeavesNoImage() async throws {
        await start()
        try await makeHistory()
        let file = backupFile()
        _ = try await module.exportBackup(ClipboardBackupOptions(), to: file)
        module.delete(ids: Set(items.map(\.id)))
        module.deleteBoard(try #require(state.history.boards.first?.id))
        let offer = try await plan(file)

        let task = Task { try await offer.commit(.applyLimits, { _ in withUnsafeCurrentTask { $0?.cancel() } }) }
        await #expect(throws: CancellationError.self) { try await task.value }

        #expect(items.isEmpty && state.history.boards.isEmpty)
        #expect(try imageFiles().isEmpty)
    }

    @Test func aCommitCancelledAfterItsImagesWereStoredRemovesThem() async throws {
        await start()
        try await makeHistory()
        let file = backupFile()
        _ = try await module.exportBackup(ClipboardBackupOptions(), to: file)
        module.delete(ids: Set(items.map(\.id)))
        module.deleteBoard(try #require(state.history.boards.first?.id))
        let offer = try await plan(file)
        #expect(try imageFiles().isEmpty)

        // Cancelled by the last report of the storing, when every image is already on disk and nothing has been merged.
        let task = Task { try await offer.commit(.applyLimits, { value in if value >= 1 { withUnsafeCurrentTask { $0?.cancel() } } }) }
        await #expect(throws: CancellationError.self) { try await task.value }

        #expect(items.isEmpty && state.history.boards.isEmpty)
        #expect(try imageFiles().isEmpty)
    }

    @Test func anImageThatIsNoLongerInTheFileDropsItsItemAndIsCounted() async throws {
        await start()
        try await makeHistory()
        let file = backupFile()
        _ = try await module.exportBackup(ClipboardBackupOptions(), to: file)
        module.delete(ids: Set(items.map(\.id)))
        let offer = try await plan(file)
        // The file is replaced by one without the image between the two steps.
        try FileManager.default.removeItem(at: file)
        let writer = try ZipWriter(url: file)
        try writer.add(name: ClipboardBackupFormat.manifestName, data: BackupWorld.manifest())
        try writer.finish()

        let restored = try await offer.commit(.applyLimits, { _ in })

        #expect(restored.added == 2 && restored.unreadable == 1)
        #expect(items.allSatisfy { $0.content.kind != .image })
    }

    // MARK: Boards

    @Test func aFileThatWouldTakeTheBoardsOverTheLimitIsRefusedBeforeAnythingIsWritten() async throws {
        await start()
        for index in 0..<(ClipboardBackupFormat.maxBoards - 5) { module.createBoard(named: "Của tôi \(index)") }
        let world = try BackupWorld()
        let boards = (0..<10).map { ["name": "Từ tệp \($0)", "icon": "star", "items": []] as [String: Any] }
        let file = try world.craft(manifest: BackupWorld.manifest(boards: boards))

        await #expect(throws: ClipboardBackupError.tooManyBoards) { try await module.planRestore(from: file) }

        #expect(state.history.boards.count == ClipboardBackupFormat.maxBoards - 5)
    }

    @Test func boardsThatAreThereAlreadyDoNotCountAgainstTheLimit() async throws {
        await start()
        for index in 0..<ClipboardBackupFormat.maxBoards { module.createBoard(named: "B\(index)") }
        let world = try BackupWorld()
        let boards = (0..<10).map { ["name": "b\($0)", "icon": "star", "items": []] as [String: Any] }
        let file = try world.craft(manifest: BackupWorld.manifest(boards: boards))

        let offer = try await module.planRestore(from: file)

        #expect(offer.summary.boardsToCreate == 0)
    }

    @Test func anIconThisMacHasNoSymbolForFallsBackToTheDefault() async throws {
        await start()
        let world = try BackupWorld()
        let boards: [[String: Any]] = [
            ["name": "Có", "icon": "star", "items": []], ["name": "Không có", "icon": "no.such.symbol.on.this.mac", "items": []],
        ]
        let file = try world.craft(manifest: BackupWorld.manifest(boards: boards))

        try await restore(file)

        #expect(state.history.boards.map(\.systemImage) == ["star", "tray.full"])
    }

    // MARK: Code, cancel

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

        try await restore(file)

        #expect(items.map(\.codeDetection) == [.code(.swift), .code(.python)])
        // Found by the code filter at once, with no wait for the start-up pass.
        state.query.text = "@code"
        #expect(state.visibleItems.count == 2)
    }
}
