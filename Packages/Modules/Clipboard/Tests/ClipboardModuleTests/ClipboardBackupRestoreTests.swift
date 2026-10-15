import Foundation
import Testing
@testable import ClipboardModule

/// Export, then import, then merge: what comes back, what is not added twice, and how boards meet the ones already there.
@Suite final class ClipboardBackupRestoreTests {
    let world: BackupWorld

    init() throws {
        world = try BackupWorld()
    }

    struct BoardEssence: Equatable {
        let name: String
        let icon: String
        let color: ClipboardBoardColor
        let hashes: [String]
    }

    func boards(_ history: ClipboardHistory) -> [BoardEssence] {
        history.boards.map { board in
            let hashes = board.itemIDs.compactMap { id in history.items.first(where: { $0.id == id })?.contentHash }
            return BoardEssence(name: board.name, icon: board.systemImage, color: board.color, hashes: hashes)
        }
    }

    func hash(_ label: String) -> String {
        world.item(label).contentHash
    }

    // MARK: The round trip

    @Test func everyKindComesBackWithItsDateSourceAndFlags() async throws {
        let (restored, plan, result) = try await world.roundTrip()

        #expect(world.essences(restored) == world.essences(world.history))
        #expect(restored.items.count == 10 && result.addedIDs.count == 10)
        #expect(plan.duplicates == 0 && plan.unreadable == 0)
        // The code answer and the secret flag are part of the essence; check the two that matter by name.
        #expect(restored.items.first { $0.contentHash == hash("code") }?.codeDetection == .code(.swift))
        #expect(restored.items.first { $0.contentHash == hash("secret") }?.isSensitive == true)
        #expect(restored.items.first { $0.contentHash == hash("text") }?.isSensitive == false)
    }

    @Test func theImportMakesNewIdsAndTheOriginalOnesAreNotReused() async throws {
        let (restored, _, result) = try await world.roundTrip()
        #expect(Set(restored.items.map(\.id)).isDisjoint(with: Set(world.history.items.map(\.id))))
        #expect(Set(result.addedIDs) == Set(restored.items.map(\.id)))
    }

    @Test func boardsComeBackWithTheirNamesIconsColoursAndPinsInOrder() async throws {
        let (restored, _, result) = try await world.roundTrip()

        #expect(boards(restored) == [
            BoardEssence(name: "Công việc", icon: "briefcase", color: .orange, hashes: [hash("code"), hash("text")]),
            BoardEssence(name: "Ảnh", icon: "photo", color: .accent, hashes: [hash("image")]),
            BoardEssence(name: "Trống", icon: "star", color: .pink, hashes: []),
            BoardEssence(name: "Bí mật", icon: "lock", color: .gray, hashes: [hash("secret")]),
        ])
        #expect(result.boardsCreated == 4 && result.pinned == 4)
    }

    @Test func imagesAreWrittenUnderTheirHashNames() async throws {
        _ = try await world.roundTrip()
        let first = world.restoredImages.appending(path: world.firstPNG.sha256Hex + ".png")
        let second = world.restoredImages.appending(path: world.secondPNG.sha256Hex + ".png")
        #expect(try Data(contentsOf: first) == world.firstPNG)
        #expect(try Data(contentsOf: second) == world.secondPNG)
    }

    @Test func withSecretsLeftOutNeitherTheSecretNorItsPinComeBack() async throws {
        let (restored, _, _) = try await world.roundTrip(ClipboardBackupOptions())

        #expect(restored.items.count == 9 && !restored.items.contains { $0.isSensitive })
        #expect(restored.items.allSatisfy { $0.content.plainText != BackupWorld.secretText })
        #expect(boards(restored)[3] == BoardEssence(name: "Bí mật", icon: "lock", color: .gray, hashes: []))
    }

    @Test func theSecretsOfAHistoryThatKeepsThemComeBackMarkedWhenTheUserAskedForThem() async throws {
        let (restored, _, _) = try await world.roundTrip(ClipboardBackupOptions(skipSensitive: false))
        #expect(restored.items.filter(\.isSensitive).map(\.content) == [.text(BackupWorld.secretText)])
    }

    @Test func pinnedOnlyBringsBackTheBoardsAndTheirItems() async throws {
        let (restored, _, _) = try await world.roundTrip(ClipboardBackupOptions(scope: .pinnedOnly, skipSensitive: false))

        #expect(Set(restored.items.map(\.contentHash)) == Set(["text", "code", "image", "secret"].map(hash)))
        #expect(restored.boards.map(\.name) == ["Công việc", "Ảnh", "Trống", "Bí mật"])
    }

    // MARK: Merging with what is there

    @Test func anItemWeAlreadyHaveIsNotAddedAgainAndKeepsItsOwnDateAndSource() async throws {
        var existing = ClipboardHistory()
        let content = world.item("text").content
        let existingID = existing.add(
            content, hash: ClipboardContent.hash(of: content), source: ("com.apple.Notes", "Notes"), at: BackupWorld.base.addingTimeInterval(99_999)
        ).id

        let (merged, plan, result) = try await world.roundTrip(into: existing)

        #expect(plan.duplicates == 1 && merged.items.count == 10 && result.addedIDs.count == 9)
        let kept = try #require(merged.items.first { $0.id == existingID })
        #expect(kept.sourceAppName == "Notes" && kept.copiedAt == BackupWorld.base.addingTimeInterval(99_999))
        #expect(merged.items.filter { $0.contentHash == hash("text") }.count == 1)
    }

    @Test func aBoardOfTheFileHoldsAnItemWeAlreadyHad() async throws {
        var existing = ClipboardHistory()
        let content = world.item("text").content
        existing.add(content, hash: ClipboardContent.hash(of: content), source: (nil, nil), at: BackupWorld.base)

        let (merged, _, _) = try await world.roundTrip(into: existing)

        #expect(boards(merged)[0].hashes == [hash("code"), hash("text")])
    }

    @Test func importingTheSameFileTwiceAddsNothingTheSecondTime() async throws {
        let (url, _) = try await world.export(ClipboardBackupOptions(skipSensitive: false))
        var history = ClipboardHistory()
        let first = try await world.plan(url)
        history.restore(first)

        let second = try await world.plan(url, known: Set(history.items.map(\.contentHash)))
        let result = history.restore(second)

        #expect(second.items.isEmpty && second.duplicates == 10)
        #expect(result.addedIDs.isEmpty && result.boardsCreated == 0 && result.pinned == 0)
        #expect(history.items.count == 10 && history.boards.count == 4)
        #expect(history.boards.map(\.itemIDs).flatMap { $0 }.count == 4)
    }

    @Test func importedItemsTakeTheirPlaceByDateAmongTheOnesThatAreThere() async throws {
        var existing = ClipboardHistory()
        // Between the fixture's third and fourth items, and one newer than all of them.
        let between = existing.add(.text("giữa"), hash: "h-between", source: (nil, nil), at: BackupWorld.base.addingTimeInterval(150)).id
        let newest = existing.add(.text("mới nhất"), hash: "h-newest", source: (nil, nil), at: BackupWorld.base.addingTimeInterval(100_000)).id
        let oldest = existing.add(.text("cũ nhất"), hash: "h-oldest", source: (nil, nil), at: BackupWorld.base.addingTimeInterval(-5)).id
        // Newest first, as the history keeps it.
        existing.items.sort { $0.copiedAt > $1.copiedAt }

        let (merged, _, _) = try await world.roundTrip(into: existing)

        let dates = merged.items.map(\.copiedAt)
        #expect(dates == dates.sorted(by: >))
        #expect(merged.items.first?.id == newest && merged.items.last?.id == oldest)
        let position = try #require(merged.items.firstIndex { $0.id == between })
        #expect(merged.items[position - 1].copiedAt > merged.items[position].copiedAt)
        #expect(merged.items[position].copiedAt > merged.items[position + 1].copiedAt)
    }

    @Test func itemsWithTheSameDateKeepTheOrderOfTheFile() async throws {
        let id1 = UUID(), id2 = UUID(), id3 = UUID()
        let plan = ClipboardRestorePlan(
            items: [id1, id2, id3].enumerated().map { index, id in
                ClipboardItem(
                    id: id, content: .text("t\(index)"), contentHash: "h\(index)", copiedAt: BackupWorld.base, sourceBundleID: nil,
                    sourceAppName: nil
                )
            },
            boards: [], duplicates: 0, unreadable: 0
        )
        var history = ClipboardHistory()
        history.restore(plan)
        #expect(history.items.map(\.contentHash) == ["h0", "h1", "h2"])
    }

    // MARK: Boards meet boards

    @Test func aBoardWithTheNameOfOneThatIsThereTakesItsItemsAndKeepsItsOwnLook() async throws {
        var existing = ClipboardHistory()
        let mine = existing.createBoard(name: "công việc", systemImage: "heart", color: .red)
        let content = ClipboardContent.text("đã có")
        let mineItem = existing.add(content, hash: ClipboardContent.hash(of: content), source: (nil, nil), at: BackupWorld.base.addingTimeInterval(-100)).id
        existing.pin(itemID: mineItem, to: mine)

        let (merged, _, result) = try await world.roundTrip(into: existing)

        #expect(merged.boards.map(\.name) == ["công việc", "Ảnh", "Trống", "Bí mật"])
        #expect(merged.boards[0].id == mine && merged.boards[0].systemImage == "heart" && merged.boards[0].color == .red)
        // Their pins follow the ones already there, once each.
        #expect(boards(merged)[0].hashes == [ClipboardContent.hash(of: content), hash("code"), hash("text")])
        #expect(result.boardsCreated == 3)
    }

    @Test func newBoardsGoAfterTheOnesThatAreThereInTheOrderOfTheFile() async throws {
        var existing = ClipboardHistory()
        existing.createBoard(name: "Của tôi")
        existing.createBoard(name: "Ảnh")

        let (merged, _, _) = try await world.roundTrip(into: existing)

        #expect(merged.boards.map(\.name) == ["Của tôi", "Ảnh", "Công việc", "Trống", "Bí mật"])
    }

    @Test func aPinAlreadyThereIsNotRepeated() async throws {
        let (url, _) = try await world.export(ClipboardBackupOptions(skipSensitive: false))
        var history = ClipboardHistory()
        history.restore(try await world.plan(url))
        let before = history.boards

        // Restoring over it with an empty set of known hashes, as if the history had been cleared meanwhile but not the boards.
        history.restore(try await world.plan(url))

        #expect(history.boards.map(\.itemIDs.count) == before.map(\.itemIDs.count))
        #expect(history.boards.count == 4)
    }

    @Test func anItemThatAppearedWhileTheFileWasBeingReadIsCountedAsADuplicate() async throws {
        let (url, _) = try await world.export(ClipboardBackupOptions(skipSensitive: false))
        // The plan was made with nothing known, then the user copied one of the same items before the merge.
        let plan = try await world.plan(url)
        var history = ClipboardHistory()
        let content = world.item("link").content
        history.add(content, hash: ClipboardContent.hash(of: content), source: (nil, nil), at: BackupWorld.base)

        let result = history.restore(plan)

        #expect(result.duplicates == 1 && result.addedIDs.count == 9 && history.items.count == 10)
    }

    // MARK: Words

    @Test func theSummaryIsTheOneTheBriefAsksFor() {
        let summary = ClipboardBackupRestoreSummary(added: 312, duplicates: 18)
        #expect(summary.text == "Đã thêm 312 mục, bỏ qua 18 trùng lặp")
        #expect(ClipboardBackupRestoreSummary(added: 4).text == "Đã thêm 4 mục")
        #expect(ClipboardBackupRestoreSummary().text == "Đã thêm 0 mục")
    }

    @Test func theSummaryMentionsWhatElseHappened() {
        let summary = ClipboardBackupRestoreSummary(added: 5, duplicates: 2, unreadable: 3, boardsCreated: 1, prunedByLimits: 4)
        #expect(summary.text.hasPrefix("Đã thêm 5 mục, bỏ qua 2 trùng lặp, 3 mục không đọc được, tạo 1 board mới"))
        #expect(summary.text.contains("4 mục vượt giới hạn hoặc thời gian giữ trong Cài đặt nên đã bị dọn"))
    }

    @Test func theErrorsSpeakVietnamese() {
        let errors: [ClipboardBackupError] = [
            .moduleStopped, .notABackup, .newerVersion(3), .malformed, .unsafeEntry("../x"), .tooLarge, .itemTooLarge("a"), .unsupported,
            .damaged, .cannotRead("x"), .cannotWrite("y"),
        ]
        for error in errors { #expect(!(error.errorDescription ?? "").isEmpty, "\(error)") }
        #expect(ClipboardBackupError.newerVersion(3).errorDescription?.contains("3") == true)
        // A path in a message would leak into the log and the window.
        #expect(ClipboardBackupError.unsafeEntry("../secret/x").errorDescription?.contains("secret") == false)
    }
}
