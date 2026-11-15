import Foundation
import Testing
@testable import ClipboardModule

/// A locked board and a backup: left out by default, and when the user includes it, in the file still sealed, and restored
/// as a locked board that only its password opens.
extension ClipboardBoardLockModuleTests {
    var backupDestination: URL { temporaryRoot.appending(path: "out-\(UUID().uuidString.prefix(6)).mynotchclip") }

    func export(_ options: ClipboardBackupOptions = ClipboardBackupOptions()) async throws -> (url: URL, summary: ClipboardBackupExportSummary) {
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
        let url = backupDestination
        return (url, try await module.exportBackup(options, to: url))
    }

    func manifest(of url: URL) throws -> ClipboardBackupManifest {
        let archive = try ZipReader(url: url, limits: ClipboardBackupFormat.limits)
        let data = try archive.data(named: "manifest.json")
        return try ClipboardBackupFormat.makeDecoder().decode(ClipboardBackupManifest.self, from: #require(data))
    }

    func entryNames(of url: URL) throws -> [String] {
        try ZipReader(url: url, limits: ClipboardBackupFormat.limits).entries.map(\.name)
    }

    func restore(_ url: URL, policy: ClipboardRestorePolicy = .applyLimits) async throws -> (ClipboardRestorePlanSummary, ClipboardBackupRestoreSummary) {
        let offer = try await module.planRestore(from: url)
        let result = try await offer.commit(policy) { _ in }
        return (offer.summary, result)
    }

    // MARK: Left out

    @Test func aLockedBoardIsLeftOutOfTheBackupByDefaultWithItsNameToo() async throws {
        await start()
        copy("công khai bình thường")
        _ = try await makeLockedBoard()

        let (url, summary) = try await export()

        #expect(summary.itemCount == 1 && summary.boardCount == 0)
        #expect(summary.skippedLockedBoards == 1 && summary.lockedBoardCount == 0)
        #expect(try Data(contentsOf: url).range(of: Data(Self.secretText.utf8)) == nil)
        let manifest = try manifest(of: url)
        #expect(manifest.boards.isEmpty && manifest.lockedBoards == nil)
        #expect(!String(decoding: try JSONEncoder().encode(manifest), as: UTF8.self).contains("Két"))
        #expect(try entryNames(of: url).allSatisfy { !$0.hasPrefix("vaults/") })
    }

    @Test func anOpenBoardIsLeftOutTooItsItemsIncluded() async throws {
        await start()
        copy("công khai bình thường")
        let board = try await makeLockedBoard()
        try await module.unlockBoard(board, credential: .password(Self.password))
        #expect(history.items.count == 3)

        let (url, summary) = try await export()

        #expect(summary.itemCount == 1 && summary.skippedLockedBoards == 1)
        #expect(try Data(contentsOf: url).range(of: Data(Self.secretText.utf8)) == nil)
        #expect(try manifest(of: url).boards.isEmpty)
    }

    @Test func theLegacyWarningDoesNotCountTheItemsOfALockedBoard() async throws {
        await start()
        _ = try await makeLockedBoard()
        // The sheet's count reads the module's history as a backup sees it.
        #expect(module.backupHistory.items.isEmpty && module.backupHistory.boards.isEmpty)
    }

    // MARK: Included, still sealed

    @Test func anIncludedBoardIsInTheFileSealedWithItsVaultAndNoPlaintext() async throws {
        await start()
        copy("công khai bình thường")
        let board = try await makeLockedBoard()

        let (url, summary) = try await export(ClipboardBackupOptions(includeLockedBoards: true))

        #expect(summary.lockedBoardCount == 1 && summary.skippedLockedBoards == 0 && summary.itemCount == 1)
        let data = try Data(contentsOf: url)
        #expect(data.range(of: Data(Self.secretText.utf8)) == nil)
        let entry = "vaults/\(board.uuidString).vault"
        #expect(try entryNames(of: url).contains(entry))
        let archive = try ZipReader(url: url, limits: ClipboardBackupFormat.limits)
        #expect(try archive.data(named: entry) == Data(contentsOf: vaultFile(board)))
        let locked = try #require(try manifest(of: url).lockedBoards?.first)
        #expect(locked.id == board && locked.name == "Két" && locked.icon == "tray.full" && locked.itemCount == 2)
        #expect(try manifest(of: url).boards.isEmpty)
    }

    @Test func whatWasChangedInAnOpenBoardIsInTheIncludedFile() async throws {
        await start()
        let board = try await makeLockedBoard(holding: ["cũ"])
        try await module.unlockBoard(board, credential: .password(Self.password))
        copy("mới thêm")
        module.pin(try item("mới thêm"), to: board)

        // No second has passed, so the vault has not been sealed since; the export seals it first.
        let (url, _) = try await export(ClipboardBackupOptions(includeLockedBoards: true))

        let archive = try ZipReader(url: url, limits: ClipboardBackupFormat.limits)
        let file = try ClipboardVaultFile.decode(#require(try archive.data(named: "vaults/\(board.uuidString).vault")))
        #expect(file.envelope.itemCount == 2)
        #expect(try Data(contentsOf: url).range(of: Data("mới thêm".utf8)) == nil)
    }

    @Test func aTouchIDBoardCannotLeaveThisMacSoItIsNotIncluded() async throws {
        await start()
        let board = try makeBoard(holding: [Self.secretText])
        try await module.lockBoard(board, setup: .touchID)

        let (url, summary) = try await export(ClipboardBackupOptions(includeLockedBoards: true))

        #expect(summary.lockedBoardCount == 0 && summary.skippedLockedBoards == 1)
        #expect(try manifest(of: url).lockedBoards == nil)
        #expect(summary.text.contains("Touch ID"))
    }

    @Test func theSummaryTellsWhatWasLeftOutAndThatThePasswordIsNeeded() async throws {
        await start()
        let board = try await makeLockedBoard()
        let (_, left) = try await export()
        #expect(left.text.contains("1 board đã khoá"))
        let (_, included) = try await export(ClipboardBackupOptions(includeLockedBoards: true))
        #expect(included.text.contains("1 board đã khoá") && included.text.contains("mật khẩu"))
        _ = board
    }

    // MARK: Restored

    @Test func anIncludedBoardIsRestoredLockedAndOnlyItsPasswordOpensIt() async throws {
        await start()
        let board = try await makeLockedBoard(holding: ["một", "hai"])
        let (url, _) = try await export(ClipboardBackupOptions(includeLockedBoards: true))
        module.deleteBoard(board)
        #expect(history.boards.isEmpty && !exists(vaultFile(board)))

        let (plan, result) = try await restore(url)

        #expect(plan.lockedBoards == 1 && result.lockedBoardsRestored == 1)
        let restored = try self.board(board)
        #expect(restored.lock == ClipboardBoardLock(method: .password, itemCount: 2, isUnlocked: false))
        #expect(restored.name == "Két" && restored.systemImage == "tray.full")
        #expect(history.items.isEmpty)
        let permissions = try FileManager.default.attributesOfItem(atPath: vaultFile(board).path(percentEncoded: false))[.posixPermissions] as? Int
        #expect(permissions == 0o600)
        await #expect(throws: ClipboardVaultError.wrongPassword) { try await module.unlockBoard(board, credential: .password("sai mật khẩu")) }
        try await module.unlockBoard(board, credential: .password(Self.password))
        #expect(history.items(of: board).map { $0.content.plainText } == ["hai", "một"])
    }

    @Test func aBoardTheHistoryAlreadyHasIsNotRestoredOverIt() async throws {
        await start()
        let board = try await makeLockedBoard()
        let (url, _) = try await export(ClipboardBackupOptions(includeLockedBoards: true))
        let before = try Data(contentsOf: vaultFile(board))

        let (_, result) = try await restore(url)

        #expect(result.lockedBoardsRestored == 0)
        #expect(history.boards.count == 1)
        #expect(try Data(contentsOf: vaultFile(board)) == before)
    }

    @Test func aRestoreNeverPutsPinsIntoALockedBoardThatHasTheSameName() async throws {
        await start()
        copy("công khai")
        let ordinary = try #require(module.createBoard(named: "Két"))
        module.pin(try item("công khai"), to: ordinary)
        let (url, _) = try await export()
        module.deleteBoard(ordinary)
        _ = try await makeLockedBoard(holding: ["trong két"])

        let (_, result) = try await restore(url)

        #expect(result.boardsCreated == 1)
        let boards = history.boards
        #expect(boards.count == 2)
        let locked = try #require(boards.first { $0.isProtected })
        #expect(locked.itemIDs.isEmpty)
        let created = try #require(boards.first { !$0.isProtected })
        #expect(created.name == "Két" && created.itemIDs.count == 1)
    }

    @Test func restoringTwiceDoesNotMakeASecondLockedBoard() async throws {
        await start()
        let board = try await makeLockedBoard()
        let (url, _) = try await export(ClipboardBackupOptions(includeLockedBoards: true))
        module.deleteBoard(board)
        _ = try await restore(url)
        let (_, second) = try await restore(url)
        #expect(second.lockedBoardsRestored == 0)
        #expect(history.boards.count == 1)
    }

    @Test func aRestoreThatTheUserDoesNotChooseWritesNoVault() async throws {
        await start()
        let board = try await makeLockedBoard()
        let (url, _) = try await export(ClipboardBackupOptions(includeLockedBoards: true))
        module.deleteBoard(board)

        _ = try await module.planRestore(from: url)

        #expect(!exists(vaultFile(board)))
        #expect(history.boards.isEmpty)
    }

    // MARK: A hostile file

    func zip(manifest: ClipboardBackupManifest, entries: [String: Data] = [:]) throws -> URL {
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
        let url = backupDestination
        let archive = try ZipWriter(url: url)
        for (name, data) in entries.sorted(by: { $0.key < $1.key }) { try archive.add(name: name, data: data, compress: false) }
        try archive.add(name: "manifest.json", data: ClipboardBackupFormat.makeEncoder().encode(manifest))
        try archive.finish()
        return url
    }

    func manifest(locked: [ClipboardBackupManifest.LockedBoard]) -> ClipboardBackupManifest {
        ClipboardBackupManifest(
            format: ClipboardBackupFormat.formatName, version: 1, createdAt: system.now, scope: "all", includesSensitive: false,
            items: [], boards: [], lockedBoards: locked
        )
    }

    @Test func lockedBoardsOfAFileThatCannotBeTrustedAreNotRestored() async throws {
        await start()
        let good = try await makeLockedBoard()
        let goodFile = try Data(contentsOf: vaultFile(good))
        module.deleteBoard(good)
        let other = UUID()
        func entry(_ id: UUID, name: String = "Két") -> ClipboardBackupManifest.LockedBoard {
            ClipboardBackupManifest.LockedBoard(id: id, name: name, icon: nil, color: nil, itemCount: 2)
        }
        var wrongBoard = try ClipboardVaultFile.decode(goodFile)
        // A file whose header names another board than the entry it is in.
        wrongBoard.envelope.boardID = UUID()
        let url = try zip(
            manifest: manifest(locked: [
                entry(good, name: "Tốt"),
                entry(UUID()),
                entry(other),
                entry(UUID(), name: "   "),
            ]),
            entries: [
                "vaults/\(good.uuidString).vault": goodFile,
                "vaults/\(other.uuidString).vault": wrongBoard.encoded() + Data([0]),
            ]
        )

        let (plan, result) = try await restore(url)

        // Only the board whose file is a vault of its own id is restored; the missing one and the blank name are not. Already at the
        // plan, before anything is written: the second look when the files are stored is not what keeps the others out.
        #expect(plan.lockedBoards == 1)
        #expect(plan.unreadable == 3)
        #expect(result.lockedBoardsRestored == 1)
        #expect(result.unreadable == 3)
        #expect(history.boards.map(\.name) == ["Tốt"])
    }

    @Test func aTouchIDVaultInAFileIsRefused() async throws {
        await start()
        let id = UUID()
        let file = ClipboardVaultFile(envelope: ClipboardVaultEnvelope(boardID: id, method: .touchID, itemCount: 0), sealed: Data([1, 2, 3]))
        let url = try zip(
            manifest: manifest(locked: [.init(id: id, name: "Két", icon: nil, color: nil, itemCount: 0)]),
            entries: ["vaults/\(id.uuidString).vault": file.encoded()]
        )
        let (plan, result) = try await restore(url)
        // Refused at the plan: a Touch ID board's key is in the Keychain of the Mac that made it.
        #expect(plan.lockedBoards == 0 && plan.unreadable == 1)
        #expect(result.lockedBoardsRestored == 0 && result.unreadable == 1)
        #expect(history.boards.isEmpty)
    }

    @Test func aFileWithMoreBoardsThanTheLimitIsRefusedBeforeAnythingIsRead() async throws {
        await start()
        let locked = (0...ClipboardBackupFormat.maxBoards).map { ClipboardBackupManifest.LockedBoard(id: UUID(), name: "B\($0)", icon: nil, color: nil, itemCount: 0) }
        let url = try zip(manifest: manifest(locked: locked))
        await #expect(throws: ClipboardBackupError.tooManyBoards) { _ = try await module.planRestore(from: url) }
    }

    @Test func aBoardNameThatIsTooLongIsRefused() async throws {
        await start()
        let long = String(repeating: "x", count: ClipboardBackupFormat.maxNameLength + 1)
        let url = try zip(manifest: manifest(locked: [.init(id: UUID(), name: long, icon: nil, color: nil, itemCount: 0)]))
        await #expect(throws: ClipboardBackupError.tooLongText) { _ = try await module.planRestore(from: url) }
    }
}
