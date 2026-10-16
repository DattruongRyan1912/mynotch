import AppKit
import ClipboardMCPKit
import CryptoKit
import Foundation
import MyNotchCore
import MyNotchTestSupport
import Testing
@testable import ClipboardModule

/// Locking a board in the running module: what is hidden while it is locked and where, what reaches the disk, how it opens and
/// closes again, and what closes it. The Keychain, Touch ID and the system's notifications are all fakes; passwords are made up
/// and never printed.
@Suite final class ClipboardBoardLockModuleTests {
    static let password = "mật khẩu của tôi"
    static let fast = ClipboardVaultCrypto.Derivation(iterations: 1_000, minimumIterations: 1_000)
    static let secretText = "BÍ-MẬT-NGÂN-HÀNG-4821"
    static let screenLocked = Notification.Name("com.apple.screenIsLocked")

    let pasteboard = FakePasteboard()
    let keystrokes = FakeKeystrokeSender()
    let libraryWindow = FakeLibraryWindow()
    let panelWindow = FakePanelWindow()
    let libraryPreview = FakePreviewWindow()
    let panelPreview = FakePreviewWindow()
    let tabPreview = FakePreviewWindow()
    let system = FakeSystem()
    let modifiers = FakeModifierState()
    let keychain = FakeBoardKeychain()
    let authenticator = FakeAuthenticator()
    /// Stand in for the workspace's and the distributed notification centers.
    let workspaceCenter = NotificationCenter()
    let distributedCenter = NotificationCenter()
    let module: ClipboardModule
    let harness: RegistryHarness
    let temporaryRoot: URL
    let socketFolder = "/tmp/mn-\(UUID().uuidString.prefix(8))"

    init() {
        let system = system
        let folder = socketFolder
        module = ClipboardModule(
            pasteboard: pasteboard, keystrokes: keystrokes,
            frontmostApp: { system.frontmost }, isTrusted: { system.trusted },
            pasteboardAccessBehavior: { system.accessBehavior }, modifiers: modifiers, now: { system.now },
            libraryWindow: libraryWindow, panelWindow: panelWindow, libraryPreview: libraryPreview, panelPreview: panelPreview, tabPreview: tabPreview,
            mcpSocketPath: { _ in folder + "/mcp.sock" }, installMCPHelper: { _ in },
            keychain: keychain, authenticator: authenticator, keyDerivation: Self.fast,
            lockTriggers: ClipboardLockTriggers(sources: [
                .init(center: workspaceCenter, names: [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification, NSWorkspace.sessionDidResignActiveNotification]),
                .init(center: distributedCenter, names: [Self.screenLocked]),
            ])
        )
        harness = RegistryHarness([module])
        temporaryRoot = harness.storageRoot.applicationSupport.deletingLastPathComponent()
    }

    deinit {
        try? FileManager.default.removeItem(atPath: socketFolder)
        try? FileManager.default.removeItem(at: temporaryRoot)
    }

    var directory: URL { harness.storageRoot.storage(for: "clipboard").directory }
    var vaultDirectory: URL { directory.appending(path: "vault", directoryHint: .isDirectory) }
    var state: ClipboardState { module.state }
    var history: ClipboardHistory { module.state.history }

    func vaultFile(_ board: UUID) -> URL { vaultDirectory.appending(path: "\(board.uuidString).vault") }

    func settings() throws -> (ModuleSettings, ClipboardSettingKeys) {
        let settings = try #require(harness.settingsEnvironment(for: "clipboard")).settings
        return (settings, ClipboardSettingKeys(settings))
    }

    func start() async {
        await harness.registry.bootstrap()
        #expect(harness.registry.state(of: "clipboard") == .running)
    }

    func restart() async {
        await harness.registry.setEnabled(false, for: "clipboard")
        await harness.registry.setEnabled(true, for: "clipboard")
    }

    func copy(_ text: String, extraTypes: [String] = []) {
        pasteboard.copy(PasteboardSnapshot(types: ["public.utf8-plain-text"] + extraTypes, string: text))
        harness.scheduler.advance(by: ClipboardModuleTests.pollInterval)
    }

    func item(_ text: String) throws -> ClipboardItem {
        try #require(history.items.first { $0.content.plainText == text })
    }

    func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }

    /// Adds a stored image the way a capture does: the file first, then the item.
    @discardableResult
    func addImage(_ seed: String) throws -> (item: ClipboardItem, bytes: Data, file: URL) {
        let bytes = Data("PNG-\(seed)-\(Self.secretText)".utf8)
        let content = ClipboardContent.image(ClipboardImage(fileName: bytes.sha256Hex + ".png", pixelWidth: 4, pixelHeight: 4, byteCount: bytes.count))
        let store = try #require(module.store)
        try store.saveImage(bytes, fileName: bytes.sha256Hex + ".png")
        var added: UUID?
        module.update { history in
            added = history.add(content, hash: ClipboardContent.hash(of: content), source: ("com.apple.Preview", "Preview"), at: system.now).id
            return []
        }
        let item = try #require(history.items.first { $0.id == added })
        return (item, bytes, directory.appending(components: "images", bytes.sha256Hex + ".png"))
    }

    /// A board "Két" holding the given texts, not yet locked.
    func makeBoard(holding texts: [String]) throws -> UUID {
        for text in texts { copy(text) }
        let board = try #require(module.createBoard(named: "Két"))
        for text in texts { module.pin(try item(text), to: board) }
        return board
    }

    /// A password-locked board "Két" holding the given texts.
    func makeLockedBoard(holding texts: [String] = [secretText, "mã số 99"]) async throws -> UUID {
        let board = try makeBoard(holding: texts)
        try await module.lockBoard(board, setup: .password(Self.password))
        return board
    }

    func board(_ id: UUID) throws -> ClipboardBoard {
        try #require(history.boards.first { $0.id == id })
    }

    /// Every file under the module's folder whose bytes hold `needle`.
    func filesHolding(_ needle: String) -> [String] {
        guard let walker = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey]) else { return [] }
        var found: [String] = []
        for case let url as URL in walker {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true, let data = try? Data(contentsOf: url) else { continue }
            if data.range(of: Data(needle.utf8)) != nil { found.append(url.path(percentEncoded: false).replacingOccurrences(of: directory.path(percentEncoded: false), with: "")) }
        }
        return found
    }

    func flush() async {
        await module.store?.flush()
    }

    // MARK: Locking

    @Test func lockingHidesTheItemsAndKeepsNameIconAndCount() async throws {
        await start()
        let board = try await makeLockedBoard()

        let locked = try self.board(board)
        #expect(locked.isLocked && locked.name == "Két" && locked.systemImage == "tray.full")
        #expect(locked.lock == ClipboardBoardLock(method: .password, itemCount: 2, isUnlocked: false))
        #expect(locked.itemIDs.isEmpty)
        #expect(history.items.isEmpty)
        #expect(module.protectedBoardIDs == [board])
    }

    @Test func nothingOfALockedBoardReachesTheDisk() async throws {
        await start()
        let picture = try addImage("a")
        let board = try makeBoard(holding: [Self.secretText])
        module.pin(picture.item, to: board)
        #expect(filesHolding("PNG-a").count == 1)

        try await module.lockBoard(board, setup: .password(Self.password))
        await flush()

        #expect(filesHolding(Self.secretText).isEmpty, "a file still holds the text of a locked board")
        #expect(filesHolding("PNG-a").isEmpty, "a file still holds the image of a locked board")
        #expect(!exists(picture.file))
        // Not the source app and not the date either: only the vault holds them, sealed.
        #expect(exists(vaultFile(board)))
        let header = try ClipboardVaultFile.readHeader(at: vaultFile(board))
        #expect(header.itemCount == 2 && header.method == .password && header.boardID == board)
    }

    @Test func theVaultFileIsPrivateInAPrivateFolder() async throws {
        await start()
        let board = try await makeLockedBoard()
        let file = try FileManager.default.attributesOfItem(atPath: vaultFile(board).path(percentEncoded: false))[.posixPermissions] as? Int
        let folder = try FileManager.default.attributesOfItem(atPath: vaultDirectory.path(percentEncoded: false))[.posixPermissions] as? Int
        #expect(file == 0o600)
        #expect(folder == 0o700)
    }

    @Test func aLockedBoardsItemsAreHiddenFromSearchTheLibraryAndThePanel() async throws {
        await start()
        copy("công khai bình thường")
        let board = try await makeLockedBoard()
        module.openLibrary()
        module.togglePanel()
        let library = try #require(module.library)
        let panel = try #require(panelWindow.model)

        state.query.text = "BÍ-MẬT"
        library.searchText = "BÍ-MẬT"
        panel.searchText = "BÍ-MẬT"
        #expect(state.visibleItems.isEmpty && library.items.isEmpty && panel.items.isEmpty)
        state.query.text = ""
        library.searchText = ""
        panel.searchText = ""
        #expect(state.visibleItems.map { $0.content.plainText } == ["công khai bình thường"])
        #expect(library.items.count == 1 && panel.items.count == 1)
        // Selecting the board shows nothing of it, and the library still counts what it holds.
        state.query.boardID = board
        #expect(state.visibleItems.isEmpty)
        library.selection = .board(board)
        #expect(library.items.isEmpty)
        #expect(library.counts.boards[board] == 2)
        #expect(library.counts.all == 1)
    }

    @Test func aLockedBoardsItemsAreNotOfferedToAgents() async throws {
        await start()
        copy("công khai bình thường")
        let board = try await makeLockedBoard()
        let answer = ClipboardMCPAnswerer.answer(
            .search(ClipboardMCPSearch(query: "")), history: history, index: state.searchIndex, secrets: .init(),
            lockedBoardIDs: module.protectedBoardIDs, now: system.now
        )
        guard case .success(let result) = answer.reply else {
            Issue.record("no answer")
            return
        }
        #expect(result["count"]?.int == 1)
        #expect(module.protectedBoardIDs == [board])
    }

    @Test func aLockedBoardsItemsStayHiddenFromAgentsEvenWhileTheUserHasItOpen() async throws {
        await start()
        _ = try await makeLockedBoard(holding: ["mã chỉ riêng tôi"])
        copy("công khai bình thường")
        try await module.unlockBoard(try #require(history.boards.first?.id), credential: .password(Self.password))
        let (settings, keys) = try settings()
        settings.set(true, for: keys.mcpEnabled)
        for _ in 0..<500 where !module.mcpListening { try await Task.sleep(for: .milliseconds(10)) }
        #expect(module.mcpListening)

        let path = socketFolder + "/mcp.sock"
        func count(_ query: String) async -> Int? {
            let outcome = await Task.detached { ClipboardMCPClient.send(.search(ClipboardMCPSearch(query: query)), socketPath: path, timeout: 600) }.value
            guard case .reply(.success(let result)) = outcome else { return nil }
            return result["count"]?.int
        }
        // It is in the history while open, and the agents still do not get it.
        #expect(history.items.contains { $0.content.plainText == "mã chỉ riêng tôi" })
        #expect(await count("riêng") == 0)
        #expect(await count("công khai") == 1)
    }

    @Test func anItemOfALockedBoardNeverGoesOnTheCopyStack() async throws {
        await start()
        let board = try await makeLockedBoard()
        try await module.unlockBoard(board, credential: .password(Self.password))
        module.startStack()
        // Copying the same words again moves the item to the top of the history; it is the board's, so it is not stacked.
        copy(Self.secretText)
        #expect(history.items.first?.content.plainText == Self.secretText)
        #expect(state.stack.entries.isEmpty)
        copy("một mục thường")
        #expect(state.stack.entries.map { $0.item.content.plainText } == ["một mục thường"])
        #expect(module.relockBoard(board))
        #expect(state.stack.entries.map { $0.item.content.plainText } == ["một mục thường"])
    }

    @Test func lockingTakesTheBoardsItemsOffTheStack() async throws {
        await start()
        let board = try makeBoard(holding: ["trước"])
        module.startStack()
        copy("sau khi bật ngăn xếp")
        let stacked = try item("sau khi bật ngăn xếp")
        module.pin(stacked, to: board)
        #expect(state.stack.entries.map(\.item.id) == [stacked.id])

        try await module.lockBoard(board, setup: .password(Self.password))

        #expect(state.stack.entries.isEmpty)
    }

    @Test func clearingTheHistoryLeavesALockedBoardAlone() async throws {
        await start()
        copy("ngoài")
        let board = try await makeLockedBoard()
        module.clearHistory(.all)
        #expect(history.items.isEmpty)
        try await module.unlockBoard(board, credential: .password(Self.password))
        #expect(history.items.count == 2)
    }

    @Test func imagesGoIntoTheVaultAndComeBack() async throws {
        await start()
        let picture = try addImage("b")
        let board = try makeBoard(holding: ["văn bản"])
        module.pin(picture.item, to: board)
        try await module.lockBoard(board, setup: .password(Self.password))
        #expect(!exists(picture.file))

        try await module.unlockBoard(board, credential: .password(Self.password))

        // In memory, not on the disk.
        #expect(module.openImages.data(forFileName: picture.item.imageName!) == picture.bytes)
        #expect(!exists(picture.file))
        #expect(history.items.contains { $0.id == picture.item.id })
        #expect(try self.board(board).itemIDs.count == 2)
    }

    // MARK: Refusals

    @Test func aShortPasswordIsRefusedAndNothingChanges() async throws {
        await start()
        let board = try makeBoard(holding: [Self.secretText])
        await #expect(throws: ClipboardVaultError.passwordTooShort) { try await module.lockBoard(board, setup: .password("ngắn")) }
        #expect(!(try self.board(board).isProtected))
        #expect(history.items.count == 1)
        #expect(!exists(vaultFile(board)))
    }

    @Test func aBoardCannotBeLockedTwiceOrWhenUnknown() async throws {
        await start()
        let board = try await makeLockedBoard()
        await #expect(throws: ClipboardVaultError.alreadyLocked) { try await module.lockBoard(board, setup: .password(Self.password)) }
        await #expect(throws: ClipboardVaultError.boardNotFound) { try await module.lockBoard(UUID(), setup: .password(Self.password)) }
    }

    @Test func lockingWhileTheModuleIsStoppedIsRefused() async {
        await #expect(throws: ClipboardVaultError.moduleStopped) { try await module.lockBoard(UUID(), setup: .password(Self.password)) }
        await #expect(throws: ClipboardVaultError.moduleStopped) { try await module.unlockBoard(UUID(), credential: .password(Self.password)) }
    }

    @Test func aSecondLockOfTheSameBoardWhileOneIsUnderWayIsBusy() async throws {
        await start()
        let board = try makeBoard(holding: [Self.secretText])
        authenticator.holdAnswer = { try? await Task.sleep(for: .milliseconds(300)) }
        let first = Task { try await module.lockBoard(board, setup: .touchID) }
        try await Task.sleep(for: .milliseconds(50))
        await #expect(throws: ClipboardVaultError.busy) { try await module.lockBoard(board, setup: .password(Self.password)) }
        try await first.value
        #expect(try self.board(board).lock?.method == .touchID)
    }

    // MARK: Unlocking

    @Test func theRightPasswordOpensTheBoardAndTheItemsAreBackInOrder() async throws {
        await start()
        let board = try await makeLockedBoard(holding: ["một", "hai", "ba"])
        try await module.unlockBoard(board, credential: .password(Self.password))

        let open = try self.board(board)
        #expect(open.lock == ClipboardBoardLock(method: .password, itemCount: 3, isUnlocked: true))
        #expect(history.items(of: board).map { $0.content.plainText } == ["ba", "hai", "một"])
        state.query.boardID = board
        #expect(state.visibleItems.map { $0.content.plainText } == ["ba", "hai", "một"])
    }

    @Test func aWrongPasswordLeavesItLockedAndWritesNothing() async throws {
        await start()
        let board = try await makeLockedBoard()
        let before = try Data(contentsOf: vaultFile(board))
        await #expect(throws: ClipboardVaultError.wrongPassword) { try await module.unlockBoard(board, credential: .password("sai mật khẩu")) }
        #expect(try self.board(board).isLocked)
        #expect(history.items.isEmpty)
        #expect(try Data(contentsOf: vaultFile(board)) == before)
        #expect(filesHolding(Self.secretText).isEmpty)
    }

    @Test func aTamperedVaultDoesNotOpenAndStaysLocked() async throws {
        await start()
        let board = try await makeLockedBoard()
        var data = try Data(contentsOf: vaultFile(board))
        data[data.count - 20] ^= 0x01
        try data.write(to: vaultFile(board))

        await #expect(throws: ClipboardVaultError.damaged) { try await module.unlockBoard(board, credential: .password(Self.password)) }
        #expect(try self.board(board).isLocked)
        #expect(history.items.isEmpty)
    }

    @Test func aVaultWhoseCountWasEditedDoesNotOpen() async throws {
        await start()
        let board = try await makeLockedBoard()
        var file = try ClipboardVaultFile.read(at: vaultFile(board))
        file.envelope.itemCount = 7
        try file.write(to: vaultFile(board))
        await #expect(throws: ClipboardVaultError.damaged) { try await module.unlockBoard(board, credential: .password(Self.password)) }
    }

    @Test func unlockingABoardThatIsNotLockedIsAnErrorAndAnOpenOneIsLeftAlone() async throws {
        await start()
        let plain = try #require(module.createBoard(named: "Thường"))
        await #expect(throws: ClipboardVaultError.notLocked) { try await module.unlockBoard(plain, credential: .password(Self.password)) }
        let board = try await makeLockedBoard()
        try await module.unlockBoard(board, credential: .password(Self.password))
        try await module.unlockBoard(board, credential: .password("không cần đúng nữa"))
        #expect(try !self.board(board).isLocked)
    }

    @Test func aBoardStaysLockedAcrossARestartAndStillOpens() async throws {
        await start()
        let board = try await makeLockedBoard()
        await restart()

        let locked = try self.board(board)
        #expect(locked.lock == ClipboardBoardLock(method: .password, itemCount: 2, isUnlocked: false))
        #expect(history.items.isEmpty)
        #expect(filesHolding(Self.secretText).isEmpty)

        try await module.unlockBoard(board, credential: .password(Self.password))
        #expect(history.items.count == 2)
    }

    @Test func aBoardLockedButNotYetSavedAsLockedIsLockedOnTheNextStart() async throws {
        await start()
        let board = try makeBoard(holding: [Self.secretText])
        await flush()
        #expect(!filesHolding(Self.secretText).isEmpty)
        // The vault is written first and the history after it, so a crash between the two leaves both: the items in the clear
        // in `history.json`, and the vault. The vault wins.
        try await module.lockBoard(board, setup: .password(Self.password))
        await harness.registry.setEnabled(false, for: "clipboard")
        var leftover = ClipboardHistory()
        let content = ClipboardContent.text(Self.secretText)
        leftover.add(content, hash: ClipboardContent.hash(of: content), source: (nil, nil), at: system.now)
        let id = try #require(leftover.items.first?.id)
        leftover.boards = [ClipboardBoard(id: board, name: "Két", systemImage: "tray.full", itemIDs: [id])]
        let store = ClipboardStore(directory: directory, scheduler: ManualScheduler(), logger: Log.logger(category: "ClipboardBoardLockModuleTests"))
        _ = store.load()
        store.scheduleSave(leftover)
        await store.flush()
        #expect(!filesHolding(Self.secretText).isEmpty)

        await harness.registry.setEnabled(true, for: "clipboard")
        await flush()

        #expect(history.items.isEmpty)
        #expect(try self.board(board).isLocked)
        #expect(filesHolding(Self.secretText).isEmpty)
    }

    @Test func aVaultWhoseBoardIsGoneIsLeftAlone() async throws {
        await start()
        let board = try await makeLockedBoard()
        await harness.registry.setEnabled(false, for: "clipboard")
        try FileManager.default.removeItem(at: directory.appending(path: "boards.json"))
        await harness.registry.setEnabled(true, for: "clipboard")
        #expect(history.boards.isEmpty)
        #expect(exists(vaultFile(board)))
    }

    // MARK: Closing again

    @Test func closingTheBoardTakesTheItemsAndTheirImagesOutOfMemoryAndOffTheDisk() async throws {
        await start()
        let picture = try addImage("c")
        let board = try makeBoard(holding: [Self.secretText])
        module.pin(picture.item, to: board)
        try await module.lockBoard(board, setup: .password(Self.password))
        try await module.unlockBoard(board, credential: .password(Self.password))
        #expect(!exists(picture.file))
        #expect(module.openImages.contains(picture.item.imageName!))

        #expect(module.relockBoard(board))
        #expect(!module.openImages.contains(picture.item.imageName!))

        #expect(try self.board(board).isLocked)
        #expect(history.items.isEmpty)
        #expect(!exists(picture.file))
        await flush()
        #expect(filesHolding(Self.secretText).isEmpty)
        #expect(filesHolding("PNG-c").isEmpty)
    }

    @Test func whatWasChangedWhileOpenIsKeptWhenItCloses() async throws {
        await start()
        let board = try await makeLockedBoard(holding: ["cũ"])
        try await module.unlockBoard(board, credential: .password(Self.password))
        copy("mới thêm")
        module.pin(try item("mới thêm"), to: board)
        module.unpin(try item("cũ"), from: board)

        #expect(module.relockBoard(board))
        #expect(try self.board(board).lock?.itemCount == 1)
        try await module.unlockBoard(board, credential: .password(Self.password))

        #expect(history.items(of: board).map { $0.content.plainText } == ["mới thêm"])
    }

    @Test func changesAreSealedASecondAfterTheyAreMadeWithoutWaitingForTheBoardToClose() async throws {
        await start()
        let board = try await makeLockedBoard(holding: ["cũ"])
        try await module.unlockBoard(board, credential: .password(Self.password))
        // Opening it schedules a seal of its own, which finds nothing changed.
        harness.scheduler.advance(by: .seconds(2))
        copy("mới thêm")
        module.pin(try item("mới thêm"), to: board)
        #expect(try ClipboardVaultFile.readHeader(at: vaultFile(board)).itemCount == 1)

        // The copy was seen by the next poll, somewhere in the 300 ms `copy` ran for, and the seal is a second after that.
        harness.scheduler.advance(by: .milliseconds(500))
        #expect(try ClipboardVaultFile.readHeader(at: vaultFile(board)).itemCount == 1)
        harness.scheduler.advance(by: .milliseconds(600))
        #expect(try ClipboardVaultFile.readHeader(at: vaultFile(board)).itemCount == 2)
        // Still open, and nothing of it in the clear on disk.
        #expect(try !self.board(board).isLocked)
        await flush()
        #expect(filesHolding("mới thêm").isEmpty)
    }

    @Test func stoppingTheModuleClosesEveryBoardAndKeepsWhatWasChanged() async throws {
        await start()
        let board = try await makeLockedBoard(holding: ["cũ"])
        try await module.unlockBoard(board, credential: .password(Self.password))
        copy("thêm lúc đang mở")
        module.pin(try item("thêm lúc đang mở"), to: board)

        await harness.registry.setEnabled(false, for: "clipboard")
        #expect(filesHolding("thêm lúc đang mở").isEmpty)
        #expect(filesHolding("cũ").isEmpty)
        await harness.registry.setEnabled(true, for: "clipboard")
        try await module.unlockBoard(board, credential: .password(Self.password))

        #expect(Set(history.items(of: board).compactMap { $0.content.plainText }) == ["cũ", "thêm lúc đang mở"])
    }

    // MARK: What closes it by itself

    @Test func aBoardClosesAfterFiveIdleMinutes() async throws {
        await start()
        let board = try await makeLockedBoard()
        try await module.unlockBoard(board, credential: .password(Self.password))

        harness.scheduler.advance(by: .seconds(299))
        #expect(try !self.board(board).isLocked)
        harness.scheduler.advance(by: .seconds(2))
        #expect(try self.board(board).isLocked)
        #expect(history.items.isEmpty)
    }

    @Test func usingTheBoardRestartsTheIdleTime() async throws {
        await start()
        let board = try await makeLockedBoard()
        try await module.unlockBoard(board, credential: .password(Self.password))

        harness.scheduler.advance(by: .seconds(240))
        module.activate(try #require(history.items(of: board).first))
        harness.scheduler.advance(by: .seconds(240))
        #expect(try !self.board(board).isLocked)
        harness.scheduler.advance(by: .seconds(61))
        #expect(try self.board(board).isLocked)
    }

    @Test func anotherCopyDoesNotKeepABoardOpen() async throws {
        await start()
        let board = try await makeLockedBoard()
        try await module.unlockBoard(board, credential: .password(Self.password))
        harness.scheduler.advance(by: .seconds(200))
        copy("một mục thường")
        harness.scheduler.advance(by: .seconds(101))
        #expect(try self.board(board).isLocked)
    }

    @Test func theIdleTimeIsASetting() async throws {
        let (settings, keys) = try settings()
        #expect(settings.value(keys.boardLockIdleMinutes) == 5)
        await start()
        settings.set(1, for: keys.boardLockIdleMinutes)
        let board = try await makeLockedBoard()
        try await module.unlockBoard(board, credential: .password(Self.password))
        harness.scheduler.advance(by: .seconds(59))
        #expect(try !self.board(board).isLocked)
        harness.scheduler.advance(by: .seconds(2))
        #expect(try self.board(board).isLocked)
    }

    @Test(arguments: [0, 1, 2, 3])
    func sleepAndTheLockedScreenCloseEveryBoard(trigger: Int) async throws {
        await start()
        let board = try await makeLockedBoard()
        try await module.unlockBoard(board, credential: .password(Self.password))

        switch trigger {
        case 0: workspaceCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
        case 1: workspaceCenter.post(name: NSWorkspace.screensDidSleepNotification, object: nil)
        case 2: workspaceCenter.post(name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        default: distributedCenter.post(name: Self.screenLocked, object: nil)
        }

        #expect(try self.board(board).isLocked)
        #expect(history.items.isEmpty)
    }

    @Test func anUnrelatedNotificationDoesNotCloseABoard() async throws {
        await start()
        let board = try await makeLockedBoard()
        try await module.unlockBoard(board, credential: .password(Self.password))
        workspaceCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
        workspaceCenter.post(name: Notification.Name("com.example.other"), object: nil)
        distributedCenter.post(name: Notification.Name("com.apple.screenIsUnlocked"), object: nil)
        #expect(try !self.board(board).isLocked)
    }

    @Test func theNotificationsAreHeardAgainAfterARestartAndWhileStoppedNothingHappens() async throws {
        await start()
        let board = try await makeLockedBoard()
        await harness.registry.setEnabled(false, for: "clipboard")
        // Nothing is listening: posting must not do anything or crash.
        workspaceCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
        distributedCenter.post(name: Self.screenLocked, object: nil)
        await harness.registry.setEnabled(true, for: "clipboard")
        try await module.unlockBoard(board, credential: .password(Self.password))
        workspaceCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
        #expect(try self.board(board).isLocked)
    }

    @Test func closingTheNotchClosesTheBoardsOnlyWhenTheSettingIsOn() async throws {
        let (settings, keys) = try settings()
        #expect(settings.value(keys.boardLockOnNotchClose) == false)
        await start()
        let board = try await makeLockedBoard()
        try await module.unlockBoard(board, credential: .password(Self.password))

        module.notchDidClose()
        #expect(try !self.board(board).isLocked)

        settings.set(true, for: keys.boardLockOnNotchClose)
        module.notchDidClose()
        #expect(try self.board(board).isLocked)
    }

    @Test func noTimerIsLeftWhenNoBoardIsOpen() async throws {
        await start()
        let board = try await makeLockedBoard()
        let before = harness.scheduler.pendingCount
        try await module.unlockBoard(board, credential: .password(Self.password))
        #expect(harness.scheduler.pendingCount > before)
        #expect(module.relockBoard(board))
        harness.scheduler.advance(by: .seconds(30))
        let after = harness.scheduler.pendingCount
        #expect(after <= before)
    }

    // MARK: Pins

    @Test func nothingCanBePinnedToALockedBoardButToAnOpenOne() async throws {
        await start()
        let board = try await makeLockedBoard(holding: ["trong két"])
        copy("ngoài két")
        module.pin(try item("ngoài két"), to: board)
        #expect(history.boards.first { $0.id == board }?.itemIDs.isEmpty == true)

        try await module.unlockBoard(board, credential: .password(Self.password))
        module.pin(try item("ngoài két"), to: board)
        #expect(try self.board(board).itemIDs.count == 2)
    }

    @Test func aCopyMadeWhileClosedIsNotDuplicatedWhenItOpens() async throws {
        await start()
        let board = try await makeLockedBoard(holding: ["lặp lại"])
        copy("lặp lại")
        #expect(history.items.count == 1)

        try await module.unlockBoard(board, credential: .password(Self.password))

        #expect(history.items.count == 1)
        #expect(try self.board(board).itemIDs == [history.items[0].id])
    }

    // MARK: Migration

    @Test func anExistingBoardIsLockedAndTakenBackToOrdinary() async throws {
        await start()
        let board = try makeBoard(holding: ["một", "hai"])
        try await module.lockBoard(board, setup: .password(Self.password))
        try await module.unlockBoard(board, credential: .password(Self.password))

        try await module.removeLock(from: board)

        #expect(try !self.board(board).isProtected)
        #expect(!exists(vaultFile(board)))
        #expect(history.items(of: board).map { $0.content.plainText } == ["hai", "một"])
        // The items were written before the vault went, with no flush asked for here: a crash after the vault is gone loses nothing.
        #expect(!filesHolding("hai").isEmpty)
        await restart()
        #expect(try !self.board(board).isProtected)
        #expect(history.items(of: board).count == 2)
    }

    @Test func theLockCannotBeRemovedWhileClosed() async throws {
        await start()
        let board = try await makeLockedBoard()
        await #expect(throws: ClipboardVaultError.stillLocked) { try await module.removeLock(from: board) }
        let plain = try #require(module.createBoard(named: "Thường"))
        await #expect(throws: ClipboardVaultError.notLocked) { try await module.removeLock(from: plain) }
        #expect(exists(vaultFile(board)))
    }

    // MARK: Forgot the password

    @Test func aLockedBoardCanBeDeletedWithItsEncryptedData() async throws {
        await start()
        let board = try await makeLockedBoard()
        #expect(exists(vaultFile(board)))

        module.deleteBoard(board)

        #expect(history.boards.isEmpty)
        #expect(!exists(vaultFile(board)))
        await flush()
        #expect(try String(contentsOf: directory.appending(path: "boards.json"), encoding: .utf8) == "[]")
    }

    @Test func deletingAnOpenBoardDeletesItsItemsToo() async throws {
        await start()
        let picture = try addImage("d")
        let board = try makeBoard(holding: [Self.secretText])
        module.pin(picture.item, to: board)
        try await module.lockBoard(board, setup: .password(Self.password))
        try await module.unlockBoard(board, credential: .password(Self.password))

        module.deleteBoard(board)

        #expect(history.items.isEmpty)
        #expect(!exists(vaultFile(board)))
        #expect(!exists(picture.file))
        await flush()
        #expect(filesHolding(Self.secretText).isEmpty)
    }

    // MARK: Touch ID

    @Test func aBoardCanBeLockedByTouchIDAndTheKeyIsOnlyInTheKeychain() async throws {
        await start()
        let board = try makeBoard(holding: [Self.secretText])
        try await module.lockBoard(board, setup: .touchID)

        #expect(try self.board(board).lock == ClipboardBoardLock(method: .touchID, itemCount: 1, isUnlocked: false))
        #expect(keychain.entries[board]?.count == 32)
        let header = try ClipboardVaultFile.readHeader(at: vaultFile(board))
        #expect(header.method == .touchID && header.derivation == nil && header.wrappedKey == nil)
        // The key is not in any file.
        let key = try #require(keychain.entries[board])
        #expect(try Data(contentsOf: vaultFile(board)).range(of: key) == nil)
        #expect(authenticator.reasons.count == 1, "locking proves the key can be read back")
    }

    @Test func touchIDOpensItAndAskedWithAReasonThatNamesTheBoard() async throws {
        await start()
        let board = try makeBoard(holding: [Self.secretText])
        try await module.lockBoard(board, setup: .touchID)
        authenticator.reasons = []

        try await module.unlockBoard(board, credential: .touchID)

        #expect(history.items.count == 1)
        #expect(authenticator.reasons.count == 1 && authenticator.reasons[0].contains("Két"))
    }

    @Test func dismissingTouchIDLeavesTheBoardLocked() async throws {
        await start()
        let board = try makeBoard(holding: [Self.secretText])
        try await module.lockBoard(board, setup: .touchID)
        authenticator.outcome = .cancelled
        await #expect(throws: ClipboardVaultError.cancelled) { try await module.unlockBoard(board, credential: .touchID) }
        #expect(try self.board(board).isLocked)
        authenticator.outcome = .authenticationFailed
        await #expect(throws: ClipboardVaultError.authenticationFailed) { try await module.unlockBoard(board, credential: .touchID) }
        #expect(history.items.isEmpty)
    }

    @Test func aBoardLockedByTouchIDCannotBeOpenedWithAPassword() async throws {
        await start()
        let board = try makeBoard(holding: [Self.secretText])
        try await module.lockBoard(board, setup: .touchID)
        await #expect(throws: ClipboardVaultError.wrongMethod) { try await module.unlockBoard(board, credential: .password(Self.password)) }
        #expect(try self.board(board).isLocked)
    }

    @Test func aPasswordBoardCannotBeOpenedWithTouchID() async throws {
        await start()
        let board = try await makeLockedBoard()
        await #expect(throws: ClipboardVaultError.wrongMethod) { try await module.unlockBoard(board, credential: .touchID) }
    }

    @Test func aKeychainThatRefusesLeavesTheBoardUntouched() async throws {
        await start()
        let board = try makeBoard(holding: [Self.secretText])
        keychain.storeError = .keychain(-34018)
        await #expect(throws: ClipboardVaultError.keychain(-34018)) { try await module.lockBoard(board, setup: .touchID) }
        #expect(try !self.board(board).isProtected)
        #expect(history.items.count == 1)
        #expect(!exists(vaultFile(board)))
        #expect(keychain.entries.isEmpty)
    }

    @Test func aKeyThatCannotBeReadBackIsNotTrustedWithTheData() async throws {
        await start()
        let board = try makeBoard(holding: [Self.secretText])
        keychain.loadError = .authenticationFailed
        await #expect(throws: ClipboardVaultError.authenticationFailed) { try await module.lockBoard(board, setup: .touchID) }
        #expect(try !self.board(board).isProtected)
        #expect(!exists(vaultFile(board)))
        #expect(keychain.entries.isEmpty, "the key that could not be proved is removed again")
    }

    @Test func aKeyThatIsGoneFromTheKeychainIsSaidSo() async throws {
        await start()
        let board = try makeBoard(holding: [Self.secretText])
        try await module.lockBoard(board, setup: .touchID)
        try keychain.remove(for: board)
        await #expect(throws: ClipboardVaultError.keyMissing) { try await module.unlockBoard(board, credential: .touchID) }
        #expect(try self.board(board).isLocked)
    }

    @Test func deletingATouchIDBoardRemovesItsKeychainEntry() async throws {
        await start()
        let board = try makeBoard(holding: [Self.secretText])
        try await module.lockBoard(board, setup: .touchID)
        module.deleteBoard(board)
        #expect(keychain.entries.isEmpty)
    }

    @Test func removingTheLockOfATouchIDBoardRemovesItsKeychainEntry() async throws {
        await start()
        let board = try makeBoard(holding: [Self.secretText])
        try await module.lockBoard(board, setup: .touchID)
        try await module.unlockBoard(board, credential: .touchID)
        try await module.removeLock(from: board)
        #expect(keychain.entries.isEmpty)
        #expect(!exists(vaultFile(board)))
    }

    @Test func pinningAnItemToAnOpenLockedBoardTakesItOffTheStack() async throws {
        await start()
        let board = try await makeLockedBoard()
        try await module.unlockBoard(board, credential: .password(Self.password))
        module.startStack()
        copy("đang ở trên ngăn xếp")
        #expect(state.stack.entries.count == 1)

        module.pin(try item("đang ở trên ngăn xếp"), to: board)

        #expect(state.stack.entries.isEmpty)
    }

    @Test func aBoardLeftOpenByACrashLeavesNoPictureAfterTheNextStart() async throws {
        await start()
        let picture = try addImage("f")
        let board = try makeBoard(holding: ["văn bản"])
        module.pin(picture.item, to: board)
        try await module.lockBoard(board, setup: .password(Self.password))
        try await module.unlockBoard(board, credential: .password(Self.password))
        await harness.registry.setEnabled(false, for: "clipboard")
        #expect(!exists(picture.file))
        // As if the app had been killed with the board open: the picture is on disk and no history file knows it.
        try picture.bytes.write(to: picture.file)

        await harness.registry.setEnabled(true, for: "clipboard")

        #expect(!exists(picture.file))
        #expect(try self.board(board).isLocked)
    }

    @Test func theThumbnailOfALockedItemIsForgotten() async throws {
        await start()
        let png = try #require(ClipboardClassifierTests.bitmap(pixelsWide: 6, pixelsHigh: 4).representation(using: .png, properties: [:]))
        let name = png.sha256Hex + ".png"
        let file = directory.appending(components: "images", name)
        try #require(module.store).saveImage(png, fileName: name)
        let content = ClipboardContent.image(ClipboardImage(fileName: name, pixelWidth: 6, pixelHeight: 4, byteCount: png.count))
        var added: UUID?
        module.update { history in
            added = history.add(content, hash: ClipboardContent.hash(of: content), source: (nil, nil), at: system.now).id
            return []
        }
        let board = try #require(module.createBoard(named: "Két"))
        module.pin(try #require(history.items.first { $0.id == added }), to: board)
        #expect(await module.thumbnails.thumbnail(for: file) != nil)
        #expect(module.thumbnails.cachedThumbnail(for: file) != nil)

        try await module.lockBoard(board, setup: .password(Self.password))

        #expect(module.thumbnails.cachedThumbnail(for: file) == nil)
    }

    @Test func aDroppedItemOnALockedBoardOfTheLibraryIsRefusedWithAWord() async throws {
        await start()
        let board = try await makeLockedBoard()
        copy("ngoài két")
        module.openLibrary()
        let library = try #require(module.library)
        library.select(try item("ngoài két").id, mode: .replace)

        library.addSelection(toBoard: board)

        #expect(history.boards.first { $0.id == board }?.itemIDs.isEmpty == true)
        #expect(library.notice?.text.contains("mở khoá") == true)
    }

    @Test func theLibraryShowsTheLockPromptInsteadOfCardsForALockedBoard() async throws {
        await start()
        let board = try await makeLockedBoard()
        module.openLibrary()
        let library = try #require(module.library)
        #expect(library.lockedSelectedBoard == nil)
        library.selection = .board(board)
        #expect(library.lockedSelectedBoard?.id == board)
        try await module.unlockBoard(board, credential: .password(Self.password))
        #expect(library.lockedSelectedBoard == nil)
    }

    @Test func theResultOfChangingASecretOfAnOpenBoardStaysInThatBoardAndNeverReachesTheDisk() async throws {
        await start()
        let board = try await makeLockedBoard(holding: ["mật khẩu thường thôi"])
        try await module.unlockBoard(board, credential: .password(Self.password))

        let source = try item("mật khẩu thường thôi")
        #expect(module.apply(.uppercase, to: source))

        #expect(history.items(of: board).compactMap { $0.content.plainText }.contains("MẬT KHẨU THƯỜNG THÔI"))
        await flush()
        #expect(filesHolding("MẬT KHẨU THƯỜNG THÔI").isEmpty)
        #expect(module.relockBoard(board))
        #expect(history.items.isEmpty)
        try await module.unlockBoard(board, credential: .password(Self.password))
        #expect(history.items(of: board).count == 2)
    }

    @Test func aModuleBuiltWithTheDefaultsUsesTheStandardDerivation() {
        let plain = ClipboardModule(
            pasteboard: FakePasteboard(), keystrokes: FakeKeystrokeSender(), frontmostApp: { (nil, nil) }, isTrusted: { true },
            pasteboardAccessBehavior: { .alwaysAllow }, modifiers: FakeModifierState()
        )
        #expect(plain.keyDerivation == .standard)
        #expect(plain.keychain is SystemBoardKeyKeychain && plain.authenticator is SystemUserAuthenticator)
    }

    @Test func noTestEverNeededTheRealKeychain() {
        // The module in these tests was built with fakes; the default one is the only code that talks to the real Keychain.
        #expect(module.keychain is FakeBoardKeychain)
        #expect(module.authenticator is FakeAuthenticator)
    }
}
