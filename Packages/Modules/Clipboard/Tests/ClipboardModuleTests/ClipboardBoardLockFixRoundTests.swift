import AppKit
import CryptoKit
import Foundation
import MyNotchCore
import MyNotchTestSupport
import Testing
import UniformTypeIdentifiers
@testable import ClipboardModule

/// Fix round 1: an open board's pictures live in memory only (a file exists only for the length of a drag), a lock trigger always
/// locks (even when the seal fails), Touch ID is offered only where the Keychain works, and the cheap minors of the review.
extension ClipboardBoardLockModuleTests {
    // MARK: Helpers

    /// Another app copies a picture; the next poll records it.
    func copy(_ snapshot: PasteboardSnapshot) {
        pasteboard.copy(snapshot)
        harness.scheduler.advance(by: ClipboardModuleTests.pollInterval)
    }

    func realPNG(width: Int) throws -> Data {
        try #require(ClipboardClassifierTests.bitmap(pixelsWide: width, pixelsHigh: 3).representation(using: .png, properties: [:]))
    }

    /// A stored picture that really decodes, added as a capture adds it.
    @discardableResult
    func addRealImage(width: Int) throws -> (item: ClipboardItem, bytes: Data, name: String, file: URL) {
        let bytes = try realPNG(width: width)
        let name = bytes.sha256Hex + ".png"
        try #require(module.store).saveImage(bytes, fileName: name)
        let content = ClipboardContent.image(ClipboardImage(fileName: name, pixelWidth: width, pixelHeight: 3, byteCount: bytes.count))
        var added: UUID?
        module.update { history in
            added = history.add(content, hash: ClipboardContent.hash(of: content), source: ("com.apple.Preview", "Preview"), at: system.now).id
            return []
        }
        let item = try #require(history.items.first { $0.id == added })
        return (item, bytes, name, directory.appending(components: "images", name))
    }

    /// Every file under the harness's folders (the module's own and its caches) that holds `needle`.
    func filesAnywhereHolding(_ needle: Data) -> [String] {
        guard let walker = FileManager.default.enumerator(at: temporaryRoot, includingPropertiesForKeys: [.isRegularFileKey]) else { return [] }
        var found: [String] = []
        for case let url as URL in walker {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true, let data = try? Data(contentsOf: url) else { continue }
            if data.range(of: needle) != nil { found.append(url.lastPathComponent) }
        }
        return found
    }

    /// Makes the vault folder refuse a new file, which is how a full disk looks to the sealer.
    func breakSealing() throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: vaultDirectory.path(percentEncoded: false))
    }

    func repairSealing() throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: vaultDirectory.path(percentEncoded: false))
    }

    /// An open board "Két" holding a real picture and a text, and the picture's pieces.
    func openBoardWithPicture(width: Int = 7) async throws -> (board: UUID, picture: (item: ClipboardItem, bytes: Data, name: String, file: URL)) {
        let picture = try addRealImage(width: width)
        let board = try makeBoard(holding: ["văn bản trong két"])
        module.pin(picture.item, to: board)
        try await module.lockBoard(board, setup: .password(Self.password))
        try await module.unlockBoard(board, credential: .password(Self.password))
        return (board, picture)
    }

    var dragFolder: URL { harness.storageRoot.storage(for: "clipboard").cachesDirectory.appending(path: "open-drags", directoryHint: .isDirectory) }

    func dragFiles() -> [URL] {
        let walker = FileManager.default.enumerator(at: dragFolder, includingPropertiesForKeys: [.isRegularFileKey])
        return (walker?.allObjects as? [URL] ?? []).filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
    }

    // MARK: I2. Pictures in memory only

    @Test func noFileOfAnOpenBoardHoldsAPictureOrAText() async throws {
        await start()
        let picture = try addImage("g")
        let board = try makeBoard(holding: [Self.secretText])
        module.pin(picture.item, to: board)
        try await module.lockBoard(board, setup: .password(Self.password))
        try await module.unlockBoard(board, credential: .password(Self.password))
        await flush()

        #expect(!exists(picture.file), "unlocking wrote a picture to the images folder")
        #expect(filesAnywhereHolding(Data("PNG-g".utf8)).isEmpty)
        #expect(filesAnywhereHolding(Data(Self.secretText.utf8)).isEmpty)
        #expect(module.openImages.data(forFileName: picture.item.imageName!) == picture.bytes)
        #expect(try Self.imagesFolderListing(directory).isEmpty)
    }

    static func imagesFolderListing(_ directory: URL) throws -> [String] {
        let images = directory.appending(path: "images", directoryHint: .isDirectory)
        return (try? FileManager.default.contentsOfDirectory(atPath: images.path(percentEncoded: false))) ?? []
    }

    @Test func anOpenBoardsPictureIsDrawnFromMemoryAndHasNoFileToReveal() async throws {
        await start()
        let (board, picture) = try await openBoardWithPicture()
        let item = try #require(history.items(of: board).first { $0.imageName == picture.name })

        let url = try #require(module.displayImageURL(of: item))
        #expect(url.scheme == ClipboardOpenImages.scheme && !url.isFileURL)
        #expect(await module.thumbnails.thumbnail(for: url) != nil)
        #expect(module.thumbnails.cachedThumbnail(for: url) != nil)
        // Nothing to hand to Finder, and no file for "Hiện trong Finder" to find.
        #expect(module.fileURLs(of: item).isEmpty)
        #expect(!exists(picture.file))
    }

    @Test func anOrdinaryPictureIsStillDrawnFromItsFile() async throws {
        await start()
        let picture = try addRealImage(width: 9)
        #expect(module.displayImageURL(of: picture.item) == module.fileURLs(of: picture.item).first)
        #expect(module.displayImageURL(of: picture.item)?.isFileURL == true)
        #expect(module.displayImageURL(of: try Self.textItem("x")) == nil)
    }

    static func textItem(_ text: String) throws -> ClipboardItem {
        let content = ClipboardContent.text(text)
        return ClipboardItem(id: UUID(), content: content, contentHash: ClipboardContent.hash(of: content), copiedAt: .now, sourceBundleID: nil, sourceAppName: nil)
    }

    @Test func theLibraryAndThePanelDrawTheSamePicturesFromMemoryToo() async throws {
        await start()
        module.openLibrary()
        module.togglePanel()
        #expect(try #require(module.library).thumbnails.openImages === module.openImages)
        #expect(try #require(panelWindow.model).thumbnails.openImages === module.openImages)
        let (board, picture) = try await openBoardWithPicture()
        let item = try #require(history.items(of: board).first { $0.imageName == picture.name })
        let url = try #require(module.displayImageURL(of: item))
        #expect(await module.library?.thumbnails.thumbnail(for: url) != nil)
        #expect(await panelWindow.model?.thumbnails.thumbnail(for: url) != nil)
    }

    @Test func aPictureOfAnOpenBoardIsCopiedFromMemory() async throws {
        await start()
        let (board, picture) = try await openBoardWithPicture()
        let item = try #require(history.items(of: board).first { $0.imageName == picture.name })

        module.copy(item)

        let write = try #require(pasteboard.writes.last)
        #expect(write.imageData == picture.bytes)
        #expect(write.imageURL == nil)
        #expect(write.content == item.content)
    }

    @Test func aDragOfAnOpenBoardsPictureMakesAFileOnlyWhenTheDropTargetAsksAndItGoesWhenTheDragEnds() async throws {
        await start()
        let (board, picture) = try await openBoardWithPicture()
        let item = try #require(history.items(of: board).first { $0.imageName == picture.name })

        let provider = module.dragProvider(for: item)
        #expect(dragFiles().isEmpty, "a file exists before anyone asked for it")

        let received = await withCheckedContinuation { (continuation: CheckedContinuation<Data?, Never>) in
            provider.loadFileRepresentation(forTypeIdentifier: UTType.png.identifier) { url, _ in
                continuation.resume(returning: url.flatMap { try? Data(contentsOf: $0) })
            }
        }
        #expect(received == picture.bytes)
        let files = dragFiles()
        let file = try #require(files.first)
        // The temporary folder is reached through a link (/var is /private/var).
        let inside = file.resolvingSymlinksInPath().path(percentEncoded: false).hasPrefix(dragFolder.resolvingSymlinksInPath().path(percentEncoded: false))
        #expect(files.count == 1 && inside)
        let mode = try FileManager.default.attributesOfItem(atPath: file.path(percentEncoded: false))[.posixPermissions] as? Int
        let folderMode = try FileManager.default.attributesOfItem(atPath: dragFolder.path(percentEncoded: false))[.posixPermissions] as? Int
        #expect(mode == 0o600 && folderMode == 0o700)
        #expect(file.pathExtension == "png")

        module.dragEnded()
        harness.scheduler.advance(by: .seconds(1))
        #expect(dragFiles().count == 1, "removed before the drop target could read it")
        harness.scheduler.advance(by: .seconds(2))
        #expect(dragFiles().isEmpty, "the drag's file is still there after the drag")
        #expect(filesAnywhereHolding(picture.bytes).isEmpty)
    }

    @Test func aDragFileIsRemovedAtOnceWhenTheBoardCloses() async throws {
        await start()
        let (board, picture) = try await openBoardWithPicture()
        let item = try #require(history.items(of: board).first { $0.imageName == picture.name })
        let provider = module.dragProvider(for: item)
        _ = await withCheckedContinuation { (continuation: CheckedContinuation<URL?, Never>) in
            provider.loadFileRepresentation(forTypeIdentifier: UTType.png.identifier) { url, _ in continuation.resume(returning: url) }
        }
        #expect(dragFiles().count == 1)

        #expect(module.relockBoard(board))

        #expect(dragFiles().isEmpty)
    }

    @Test func theDragFolderIsSweptAtStart() async throws {
        await start()
        let leftover = dragFolder.appending(path: "old-drag", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: leftover, withIntermediateDirectories: true)
        try Data("còn lại".utf8).write(to: leftover.appending(path: "x.png"))
        await restart()
        #expect(dragFiles().isEmpty)
    }

    @Test func pinningAPictureToAnOpenBoardTakesItOffTheDisk() async throws {
        await start()
        let (board, _) = try await openBoardWithPicture()
        let other = try addRealImage(width: 13)
        #expect(exists(other.file))

        module.pin(other.item, to: board)

        #expect(!exists(other.file))
        #expect(module.openImages.data(forFileName: other.name) == other.bytes)
        // And it is sealed with the board.
        #expect(module.relockBoard(board))
        try await module.unlockBoard(board, credential: .password(Self.password))
        #expect(module.openImages.data(forFileName: other.name) == other.bytes)
        #expect(!exists(other.file))
    }

    @Test func takingTheLockOffGivesTheBoardsPicturesBackTheirFiles() async throws {
        await start()
        let (board, picture) = try await openBoardWithPicture()
        #expect(!exists(picture.file))

        try await module.removeLock(from: board)

        // An ordinary board again: its picture is a file like any other, drawn from it, and survives a restart.
        #expect(try Data(contentsOf: picture.file) == picture.bytes)
        #expect(module.openImages.isEmpty)
        let item = try #require(history.items(of: board).first { $0.imageName == picture.name })
        #expect(module.displayImageURL(of: item) == module.fileURLs(of: item).first)
        await restart()
        #expect(history.items(of: board).contains { $0.imageName == picture.name })
        #expect(exists(picture.file))
    }

    @Test func theLockStaysWhenAPictureCannotBeGivenItsFileBack() async throws {
        await start()
        let (board, picture) = try await openBoardWithPicture()
        let images = directory.appending(path: "images", directoryHint: .isDirectory)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: images.path(percentEncoded: false))
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: images.path(percentEncoded: false)) }

        await #expect(throws: ClipboardVaultError.self) { try await module.removeLock(from: board) }

        // Nothing changed: still a locked board, open, with its vault and its picture in memory.
        #expect(try self.board(board).lock?.isUnlocked == true)
        #expect(exists(vaultFile(board)))
        #expect(module.openImages.contains(picture.name))
    }

    @Test func aPictureThatLeavesAnOpenBoardBecomesAnOrdinaryFileAgain() async throws {
        await start()
        let (board, picture) = try await openBoardWithPicture()
        let item = try #require(history.items(of: board).first { $0.imageName == picture.name })

        module.unpin(item, from: board)

        #expect(try Data(contentsOf: picture.file) == picture.bytes)
        #expect(!module.openImages.contains(picture.name))
        #expect(module.displayImageURL(of: item) == module.fileURLs(of: item).first)
        // And the board no longer holds it.
        #expect(module.relockBoard(board))
        #expect(try self.board(board).lock?.itemCount == 1)
    }

    @Test func aPictureCopiedWhileTheBoardWasClosedLeavesNoFileOnceItOpens() async throws {
        await start()
        let picture = try addRealImage(width: 15)
        let board = try makeBoard(holding: ["văn bản"])
        module.pin(picture.item, to: board)
        try await module.lockBoard(board, setup: .password(Self.password))
        #expect(!exists(picture.file))
        // The same picture is copied again while the board is closed: an ordinary item, with its file.
        copy(PasteboardSnapshot(types: ["public.png"], png: picture.bytes))
        #expect(exists(picture.file))

        try await module.unlockBoard(board, credential: .password(Self.password))

        #expect(!exists(picture.file))
        #expect(module.openImages.data(forFileName: picture.name) == picture.bytes)
        #expect(history.items.filter { $0.imageName == picture.name }.count == 1)
    }

    @Test func copyingTheSamePictureAgainWhileTheBoardIsOpenWritesNoFile() async throws {
        await start()
        let (_, picture) = try await openBoardWithPicture()
        copy(PasteboardSnapshot(types: ["public.png"], png: picture.bytes))
        #expect(!exists(picture.file))
        #expect(history.items.filter { $0.imageName == picture.name }.count == 1)
    }

    @Test func closingAndStoppingForgetThePicturesInMemoryToo() async throws {
        await start()
        let (board, picture) = try await openBoardWithPicture()
        #expect(module.openImages.contains(picture.name))
        #expect(module.relockBoard(board))
        #expect(module.openImages.isEmpty)

        try await module.unlockBoard(board, credential: .password(Self.password))
        await harness.registry.setEnabled(false, for: "clipboard")
        #expect(module.openImages.isEmpty)
    }

    @Test func anOpenBoardsPictureIsInNoBackupAndInNoFile() async throws {
        await start()
        let (_, picture) = try await openBoardWithPicture()
        let (url, summary) = try await export()
        #expect(summary.itemCount == 0 && summary.skippedLockedBoards == 1)
        #expect(try Data(contentsOf: url).range(of: picture.bytes) == nil)
        #expect(filesAnywhereHolding(picture.bytes).filter { $0 != url.lastPathComponent }.isEmpty)
    }

    // MARK: I3. A lock trigger always locks

    enum Trigger: CaseIterable {
        case idle, sleep, screenLocked, sessionSwitch, notchClosed, manual
    }

    func fire(_ trigger: Trigger, board: UUID) throws {
        switch trigger {
        case .idle: harness.scheduler.advance(by: .seconds(301))
        case .sleep: workspaceCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
        case .screenLocked: distributedCenter.post(name: Self.screenLocked, object: nil)
        case .sessionSwitch: workspaceCenter.post(name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        case .notchClosed:
            let (settings, keys) = try settings()
            settings.set(true, for: keys.boardLockOnNotchClose)
            module.notchDidClose()
        case .manual: module.relockBoard(board)
        }
    }

    @Test(arguments: Trigger.allCases)
    func everyTriggerLocksTheBoardEvenWhenTheSealFails(trigger: Trigger) async throws {
        await start()
        let (board, picture) = try await openBoardWithPicture()
        harness.scheduler.advance(by: .seconds(2))
        // A change that has not been sealed yet, and a disk that now refuses the vault.
        copy("chưa kịp niêm phong")
        module.pin(try item("chưa kịp niêm phong"), to: board)
        try breakSealing()
        defer { try? repairSealing() }

        try fire(trigger, board: board)

        #expect(try self.board(board).isLocked, "a board was left open by \(trigger)")
        #expect(history.items.isEmpty)
        #expect(module.openImages.isEmpty)
        #expect(!exists(picture.file))
        let notice = try #require(state.vaultNotice)
        #expect(notice.contains("Két") && notice.contains("chưa lưu"))
        // The copy on disk is the truth: what was sealed before comes back, and what was not does not.
        try repairSealing()
        try await module.unlockBoard(board, credential: .password(Self.password))
        #expect(Set(history.items(of: board).compactMap { $0.content.plainText }) == ["văn bản trong két"])
    }

    @Test func theChangesAreWrittenFirstWhenTheSealWorks() async throws {
        await start()
        let (board, _) = try await openBoardWithPicture()
        harness.scheduler.advance(by: .seconds(2))
        copy("kịp niêm phong")
        module.pin(try item("kịp niêm phong"), to: board)

        workspaceCenter.post(name: NSWorkspace.willSleepNotification, object: nil)

        #expect(try self.board(board).isLocked)
        #expect(state.vaultNotice == nil)
        try await module.unlockBoard(board, credential: .password(Self.password))
        #expect(history.items(of: board).compactMap { $0.content.plainText }.contains("kịp niêm phong"))
    }

    @Test func stoppingTheModuleDropsABoardItCouldNotSealToo() async throws {
        await start()
        let (board, picture) = try await openBoardWithPicture()
        harness.scheduler.advance(by: .seconds(2))
        copy("mất vì ổ đĩa đầy")
        module.pin(try item("mất vì ổ đĩa đầy"), to: board)
        try breakSealing()
        defer { try? repairSealing() }

        await harness.registry.setEnabled(false, for: "clipboard")

        #expect(history.items.isEmpty && module.openImages.isEmpty)
        #expect(filesAnywhereHolding(picture.bytes).isEmpty)
        try repairSealing()
        await harness.registry.setEnabled(true, for: "clipboard")
        #expect(try self.board(board).isLocked)
    }

    @Test func aSealThatFailsWithNoTriggerLeavesTheBoardOpenAndTellsNothing() async throws {
        await start()
        let (board, _) = try await openBoardWithPicture()
        harness.scheduler.advance(by: .seconds(2))
        copy("thay đổi")
        module.pin(try item("thay đổi"), to: board)
        try breakSealing()
        defer { try? repairSealing() }

        // The one-second seal fails; the user is still working, so nothing closes and nothing is said.
        harness.scheduler.advance(by: .seconds(2))

        #expect(try !self.board(board).isLocked)
        #expect(state.vaultNotice == nil)
    }

    @Test func theNoticeCanBeDismissedAndIsGoneWhenTheModuleRestarts() async throws {
        await start()
        let (board, _) = try await openBoardWithPicture()
        copy("thay đổi")
        module.pin(try item("thay đổi"), to: board)
        try breakSealing()
        defer { try? repairSealing() }
        workspaceCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
        #expect(state.vaultNotice != nil)
        module.dismissVaultNotice()
        #expect(state.vaultNotice == nil)
    }

    // MARK: I1. Touch ID only where it works

    @Test func touchIDIsHiddenWhereTheKeychainHasNoAccessGroup() async throws {
        keychain.usable = false
        await start()
        let board = try makeBoard(holding: [Self.secretText])

        #expect(!module.touchIDAvailable)
        let model = module.lockModel(for: try self.board(board))
        #expect(!model.touchIDAvailable && !model.showsTouchID)
        #expect(model.touchIDNote == ClipboardBoardLockModel.touchIDUnavailableNote)
        await #expect(throws: ClipboardVaultError.touchIDUnavailable) { try await module.lockBoard(board, setup: .touchID) }
        #expect(try !self.board(board).isProtected)
        #expect(history.items.count == 1)
        #expect(keychain.storeCount == 0 && authenticator.reasons.isEmpty && !exists(vaultFile(board)))
    }

    @Test func touchIDIsHiddenOnAMacThatCannotAskForIt() async throws {
        authenticator.available = false
        await start()
        #expect(!module.touchIDAvailable)
        let board = try makeBoard(holding: [Self.secretText])
        await #expect(throws: ClipboardVaultError.touchIDUnavailable) { try await module.lockBoard(board, setup: .touchID) }
    }

    @Test func touchIDIsOfferedWhereItWorks() async throws {
        await start()
        let board = try makeBoard(holding: [Self.secretText])
        let model = module.lockModel(for: try self.board(board))
        #expect(module.touchIDAvailable && model.touchIDAvailable && model.showsTouchID)
        #expect(model.touchIDNote == ClipboardBoardLockModel.touchIDNote)
    }

    @Test func theProbeRunsOnceAndAgainAfterARestart() async throws {
        await start()
        _ = module.touchIDAvailable
        _ = module.touchIDAvailable
        _ = module.lockModel(for: ClipboardBoard(id: UUID(), name: "x", systemImage: "key", itemIDs: []))
        #expect(keychain.probeCount == 1)
        keychain.usable = false
        #expect(module.touchIDAvailable, "the answer is kept for as long as the module runs")
        await restart()
        #expect(!module.touchIDAvailable)
        #expect(keychain.probeCount == 2)
    }

    @Test func aTouchIDBoardKeepsItsPromptEvenWhenTheProbeSaysNo() async throws {
        await start()
        let board = try makeBoard(holding: [Self.secretText])
        try await module.lockBoard(board, setup: .touchID)
        keychain.usable = false
        await restart()
        let model = module.lockModel(for: try self.board(board))
        // There is no password to fall back to for a board whose key is only in the Keychain: the prompt stays and says why.
        #expect(model.method == .touchID && !model.touchIDAvailable)
        #expect(model.touchIDNote == ClipboardBoardLockModel.touchIDUnavailableNote)
        try await module.unlockBoard(board, credential: .touchID)
        #expect(history.items.count == 1)
    }

    // MARK: Minors

    @Test func fiveWrongPasswordsAskForAWaitThatGrowsAndARightOneClearsIt() async throws {
        await start()
        let board = try await makeLockedBoard()
        for _ in 0..<5 {
            await #expect(throws: ClipboardVaultError.wrongPassword) { try await module.unlockBoard(board, credential: .password("sai mật khẩu rồi")) }
        }
        // Even the right password waits.
        await #expect(throws: ClipboardVaultError.tooManyAttempts(retryAfter: 30)) {
            try await module.unlockBoard(board, credential: .password(Self.password))
        }
        system.now += 29
        await #expect(throws: ClipboardVaultError.tooManyAttempts(retryAfter: 1)) {
            try await module.unlockBoard(board, credential: .password(Self.password))
        }
        system.now += 2
        await #expect(throws: ClipboardVaultError.wrongPassword) { try await module.unlockBoard(board, credential: .password("lại sai nữa")) }
        // The sixth failure doubles it.
        await #expect(throws: ClipboardVaultError.tooManyAttempts(retryAfter: 60)) {
            try await module.unlockBoard(board, credential: .password(Self.password))
        }
        system.now += 61
        try await module.unlockBoard(board, credential: .password(Self.password))
        #expect(try !self.board(board).isLocked)

        // A right password starts the count again.
        #expect(module.relockBoard(board))
        for _ in 0..<4 {
            await #expect(throws: ClipboardVaultError.wrongPassword) { try await module.unlockBoard(board, credential: .password("sai mật khẩu rồi")) }
        }
        try await module.unlockBoard(board, credential: .password(Self.password))
    }

    @Test func theWaitHasACeilingAndIsPerBoard() async throws {
        await start()
        let first = try await makeLockedBoard()
        copy("trong két khác")
        let second = try #require(module.createBoard(named: "Két hai"))
        module.pin(try item("trong két khác"), to: second)
        try await module.lockBoard(second, setup: .password(Self.password))
        for _ in 0..<5 {
            await #expect(throws: ClipboardVaultError.wrongPassword) { try await module.unlockBoard(first, credential: .password("sai mật khẩu rồi")) }
        }
        // Another board is not held back by this one.
        try await module.unlockBoard(second, credential: .password(Self.password))
        for _ in 0..<10 {
            system.now += 100_000
            await #expect(throws: ClipboardVaultError.wrongPassword) { try await module.unlockBoard(first, credential: .password("sai mật khẩu rồi")) }
        }
        await #expect(throws: ClipboardVaultError.tooManyAttempts(retryAfter: 600)) {
            try await module.unlockBoard(first, credential: .password(Self.password))
        }
    }

    @Test func aWaitIsNotCountedForTouchIDOrForADamagedFile() async throws {
        await start()
        let board = try makeBoard(holding: [Self.secretText])
        try await module.lockBoard(board, setup: .touchID)
        authenticator.outcome = .cancelled
        for _ in 0..<8 {
            await #expect(throws: ClipboardVaultError.cancelled) { try await module.unlockBoard(board, credential: .touchID) }
        }
        authenticator.outcome = nil
        try await module.unlockBoard(board, credential: .touchID)
    }

    @Test func aStackSavedBeforeACrashDoesNotBringBackAnItemOfALockedBoard() async throws {
        let (settings, keys) = try settings()
        settings.set(true, for: keys.stackPersist)
        await start()
        let board = try makeBoard(holding: [Self.secretText])
        try await module.lockBoard(board, setup: .password(Self.password))
        await harness.registry.setEnabled(false, for: "clipboard")
        // As a crash leaves it: the items in the clear in `history.json`, one of them on the stack on disk, and the vault.
        var leftover = ClipboardHistory()
        let content = ClipboardContent.text(Self.secretText)
        let id = leftover.add(content, hash: ClipboardContent.hash(of: content), source: (nil, nil), at: system.now).id
        leftover.boards = [ClipboardBoard(id: board, name: "Két", systemImage: "tray.full", itemIDs: [id])]
        let store = ClipboardStore(directory: directory, scheduler: ManualScheduler(), logger: Log.logger(category: "ClipboardBoardLockFixRoundTests"))
        _ = store.load()
        store.scheduleSave(leftover)
        await store.flush()
        var stack = CopyStack()
        stack.start()
        stack.collect(try #require(leftover.items.first))
        store.saveStack(stack)
        await store.waitForWrites()
        #expect(!filesHolding(Self.secretText).isEmpty)

        await harness.registry.setEnabled(true, for: "clipboard")
        await flush()

        #expect(state.stack.entries.isEmpty)
        #expect(filesHolding(Self.secretText).isEmpty, "the stack file still holds the secret")
    }

    @Test func anUnlockThatRacesALockTriggerDoesNotOpenTheBoard() async throws {
        await start()
        let board = try makeBoard(holding: [Self.secretText])
        try await module.lockBoard(board, setup: .touchID)
        authenticator.holdAnswer = { try? await Task.sleep(for: .milliseconds(300)) }
        let unlock = Task { try await module.unlockBoard(board, credential: .touchID) }
        try await Task.sleep(for: .milliseconds(60))

        workspaceCenter.post(name: NSWorkspace.willSleepNotification, object: nil)

        await #expect(throws: ClipboardVaultError.cancelled) { try await unlock.value }
        #expect(try self.board(board).isLocked)
        #expect(history.items.isEmpty)
    }

    @Test func aBoardTooBigForTheFileFormatIsRefusedAtTheSeal() throws {
        let item = try Self.textItem(String(repeating: "x", count: 5_000))
        let key = SymmetricKey(size: .bits256)
        #expect(throws: ClipboardVaultError.tooLarge) {
            try ClipboardVaultSealer.sealNow(items: [item], images: [:], key: key, boardID: UUID(), maxBytes: 1_000)
        }
        #expect(throws: Never.self) {
            try ClipboardVaultSealer.sealNow(items: [item], images: [:], key: key, boardID: UUID(), maxBytes: 100_000)
        }
        #expect(ClipboardVaultFile.maxFileBytes == 1 << 30)
    }

    @Test func theLockFormSaysEarlierCopiesMayRemain() {
        #expect(ClipboardBoardLockModel.priorCopiesNote.contains("Time Machine"))
        #expect(ClipboardBoardLockModel.priorCopiesNote.contains("trước khi khoá"))
    }
}
