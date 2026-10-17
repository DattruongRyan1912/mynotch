import AppKit
import Foundation
import MyNotchCore
import MyNotchTestSupport
import SwiftUI
import Testing
@testable import ClipboardModule

/// Records what the module asks of the editor windows, so no test creates a real one.
final class FakeEditorWindow: ClipboardEditorWindowing {
    private(set) var models: [UUID: ClipboardEditorModel] = [:]
    private(set) var showCount = 0
    private(set) var frontCount = 0
    private var closers: [UUID: () -> Void] = [:]

    func isOpen(_ id: UUID) -> Bool { closers[id] != nil }

    func show(_ content: AnyView, model: ClipboardEditorModel, onClose: @escaping () -> Void) {
        showCount += 1
        models[model.itemID] = model
        closers[model.itemID] = onClose
    }

    func bringToFront(itemID: UUID) {
        frontCount += 1
    }

    /// The window closing, whoever closes it.
    func close(itemID: UUID) {
        closers.removeValue(forKey: itemID)?()
    }
}

/// The editor in the running module: who can open it, what saving does to the history and the disk, and what closes it. The pasteboard,
/// the Keychain and every window are fakes.
@Suite final class ClipboardEditorModuleTests {
    static let password = "mật khẩu của tôi"
    static let secretText = "BÍ-MẬT-NGÂN-HÀNG-4821"

    let pasteboard = FakePasteboard()
    let keystrokes = FakeKeystrokeSender()
    let libraryWindow = FakeLibraryWindow()
    let panelWindow = FakePanelWindow()
    let editorWindow = FakeEditorWindow()
    let keychain = FakeBoardKeychain()
    let authenticator = FakeAuthenticator()
    let system = FakeSystem()
    let modifiers = FakeModifierState()
    let module: ClipboardModule
    let harness: RegistryHarness
    let temporaryRoot: URL
    let socketFolder = SocketFolder.reservedPath()

    init() {
        let system = system
        let folder = socketFolder
        module = ClipboardModule(
            pasteboard: pasteboard, keystrokes: keystrokes,
            frontmostApp: { system.frontmost }, isTrusted: { system.trusted },
            pasteboardAccessBehavior: { system.accessBehavior }, modifiers: modifiers, now: { system.now },
            libraryWindow: libraryWindow, panelWindow: panelWindow,
            mcpSocketPath: { _ in folder + "/mcp.sock" }, installMCPHelper: { _ in },
            keychain: keychain, authenticator: authenticator, keyDerivation: ClipboardVaultCrypto.Derivation(iterations: 1_000, minimumIterations: 1_000),
            lockTriggers: ClipboardLockTriggers(sources: [])
        )
        module.editors.windowing = editorWindow
        harness = RegistryHarness([module])
        temporaryRoot = harness.storageRoot.applicationSupport.deletingLastPathComponent()
    }

    deinit {
        try? FileManager.default.removeItem(atPath: socketFolder)
        try? FileManager.default.removeItem(at: temporaryRoot)
    }

    var directory: URL { harness.storageRoot.storage(for: "clipboard").directory }
    var state: ClipboardState { module.state }
    var history: ClipboardHistory { module.state.history }

    func start() async {
        await harness.registry.bootstrap()
        #expect(harness.registry.state(of: "clipboard") == .running)
    }

    func stop() async {
        await harness.registry.setEnabled(false, for: "clipboard")
    }

    func copy(_ text: String) {
        pasteboard.copy(PasteboardSnapshot(types: ["public.utf8-plain-text"], string: text))
        harness.scheduler.advance(by: ClipboardModuleTests.pollInterval)
    }

    func item(_ text: String) throws -> ClipboardItem {
        try #require(history.items.first { $0.content.plainText == text })
    }

    func settings() throws -> (ModuleSettings, ClipboardSettingKeys) {
        let settings = try #require(harness.settingsEnvironment(for: "clipboard")).settings
        return (settings, ClipboardSettingKeys(settings))
    }

    func reload() -> ClipboardHistory {
        ClipboardStore(directory: directory, scheduler: ManualScheduler(), logger: Log.logger(category: "ClipboardEditorModuleTests")).load()
    }

    /// Opens the editor on a text and returns its model.
    func openEditor(on text: String) throws -> ClipboardEditorModel {
        let item = try item(text)
        #expect(module.edit(item))
        return try #require(editorWindow.models[item.id])
    }

    /// A board "Két" holding `texts`, locked with a password and opened again.
    func openBoard(holding texts: [String]) async throws -> UUID {
        for text in texts { copy(text) }
        let board = try #require(module.createBoard(named: "Két"))
        for text in texts { module.pin(try item(text), to: board) }
        try await module.lockBoard(board, setup: .password(Self.password))
        try await module.unlockBoard(board, credential: .password(Self.password))
        return board
    }

    // MARK: Who can open it

    @Test func theEditorOpensOnATextWithItsWords() async throws {
        await start()
        copy("Xin chào")
        let model = try openEditor(on: "Xin chào")
        #expect(model.text == "Xin chào")
        #expect(editorWindow.showCount == 1)
        #expect(!model.hasChanges)
    }

    @Test func aLinkOpensWithItsAddress() async throws {
        await start()
        copy("https://example.com/a")
        let link = try #require(history.items.first)
        #expect(link.content.kind == .link)
        #expect(module.edit(link))
        #expect(editorWindow.models[link.id]?.text == "https://example.com/a")
    }

    @Test func aRichTextOpensWithItsPlainWords() async throws {
        await start()
        pasteboard.copy(PasteboardSnapshot(types: ["public.utf8-plain-text", "public.rtf"], string: "Bảng giá", rtf: Data("{\\rtf1 Bảng giá}".utf8)))
        harness.scheduler.advance(by: ClipboardModuleTests.pollInterval)
        let rich = try #require(history.items.first)
        guard case .richText = rich.content else {
            Issue.record("Expected a rich text")
            return
        }
        #expect(module.edit(rich))
        #expect(editorWindow.models[rich.id]?.text == "Bảng giá")
        #expect(editorWindow.models[rich.id]?.losesFormatting == true)
    }

    @Test func aColourAPictureAndFilesAreNotEdited() async throws {
        await start()
        copy("#FF8800")
        pasteboard.copy(PasteboardSnapshot(types: ["public.file-url"], fileURLs: [URL(fileURLWithPath: "/tmp/a.txt")]))
        harness.scheduler.advance(by: ClipboardModuleTests.pollInterval)
        #expect(history.items.count == 2)
        for item in history.items { #expect(!module.edit(item)) }
        #expect(editorWindow.showCount == 0)
    }

    @Test func aStoppedModuleOpensNothing() {
        let item = ClipboardItem(id: UUID(), content: .text("a"), contentHash: "h", copiedAt: system.now)
        #expect(!module.edit(item))
        #expect(editorWindow.showCount == 0)
    }

    @Test func anItemThatIsNotInTheHistoryAnyMoreOpensNothing() async throws {
        await start()
        copy("Xin chào")
        let gone = try item("Xin chào")
        module.delete(gone)
        #expect(!module.edit(gone))
    }

    @Test func openingTheSameItemAgainBringsItsWindowForward() async throws {
        await start()
        copy("Xin chào")
        _ = try openEditor(on: "Xin chào")
        #expect(module.edit(try item("Xin chào")))
        #expect(editorWindow.showCount == 1)
        #expect(editorWindow.frontCount == 1)
    }

    @Test func twoItemsHaveTwoEditors() async throws {
        await start()
        copy("một")
        copy("hai")
        _ = try openEditor(on: "một")
        _ = try openEditor(on: "hai")
        #expect(editorWindow.showCount == 2)
        #expect(module.editors.open.count == 2)
    }

    @Test func theLibraryOpensItThroughItsActions() async throws {
        await start()
        copy("Xin chào")
        copy("#FF8800")
        module.openLibrary()
        let library = try #require(module.library)
        library.select(try item("Xin chào").id, mode: .replace)
        #expect(library.editFocused())
        #expect(editorWindow.models[try item("Xin chào").id] != nil)
        library.select(try item("#FF8800").id, mode: .replace)
        #expect(!library.editFocused())
    }

    // MARK: Saving as a new item

    @Test func savingAsNewAddsAnItemAndLeavesTheOriginalAndTheClipboardAlone() async throws {
        await start()
        copy("Xin chào")
        copy("tạm biệt")
        let original = try item("Xin chào")
        let model = try openEditor(on: "Xin chào")
        let writes = pasteboard.writes.count

        model.text = "Xin chào các bạn"
        model.save(.saveAsNew)

        #expect(history.items.map(\.content.plainText) == ["Xin chào các bạn", "tạm biệt", "Xin chào"])
        #expect(try item("Xin chào") == original)
        // A save is not a copy: nothing was written for the user to paste.
        #expect(pasteboard.writes.count == writes)
        #expect(pasteboard.writes.isEmpty)
        #expect(!editorWindow.isOpen(original.id))
        #expect(module.editors.open.isEmpty)
        #expect(state.historyObserverCount == 0)
        // The next poll does not record it again either.
        harness.scheduler.advance(by: ClipboardModuleTests.pollInterval)
        #expect(history.items.count == 3)

        await stop()
        #expect(reload().items.map(\.content.plainText) == ["Xin chào các bạn", "tạm biệt", "Xin chào"])
    }

    @Test func theNewItemIsDatedNowFromNoAppAndNotMarkedEdited() async throws {
        await start()
        copy("Xin chào")
        let model = try openEditor(on: "Xin chào")
        system.now = system.now.addingTimeInterval(600)
        model.text = "Xin chào các bạn"
        model.save(.saveAsNew)
        let saved = try item("Xin chào các bạn")
        #expect(saved.copiedAt == system.now)
        #expect(saved.sourceBundleID == nil && saved.sourceAppName == nil)
        #expect(!saved.isEdited && saved.timesCopied == 1)
    }

    // MARK: Replacing

    @Test func replacingChangesTheWordsKeepsTheAppAndDatesTheItemNow() async throws {
        await start()
        copy("một")
        copy("hai")
        copy("ba")
        let original = try item("hai")
        let model = try openEditor(on: "hai")
        system.now = system.now.addingTimeInterval(3_600)

        model.text = "hai mươi"
        model.save(.replace)

        #expect(history.items.map(\.content.plainText) == ["hai mươi", "ba", "một"])
        let replaced = try item("hai mươi")
        #expect(replaced.id == original.id)
        #expect(replaced.copiedAt == system.now && replaced.copiedAt != original.copiedAt)
        #expect(replaced.sourceBundleID == "com.apple.Safari" && replaced.sourceAppName == "Safari")
        #expect(replaced.isEdited)
        #expect(pasteboard.writes.isEmpty)
        #expect(!editorWindow.isOpen(original.id))

        await stop()
        let loaded = try #require(reload().items.first { $0.id == original.id })
        #expect(loaded.content == .text("hai mươi"))
        #expect(loaded.isEdited)
        #expect(loaded.copiedAt == system.now)
    }

    @Test func replacingKeepsAnItemsBoardAndItsCode() async throws {
        await start()
        copy("hai")
        let board = try #require(module.createBoard(named: "Số"))
        let original = try item("hai")
        module.pin(original, to: board)
        let model = try openEditor(on: "hai")

        model.text = "func add(_ a: Int, _ b: Int) -> Int {\n    return a + b\n}\n"
        model.save(.replace)

        #expect(history.boards.first?.itemIDs == [original.id])
        #expect(history.items.first?.codeLanguage == .swift)
    }

    @Test func replacingWithWordsAnotherItemHasKeepsTheEditorOpenAndChangesNothing() async throws {
        await start()
        copy("một")
        copy("hai")
        let model = try openEditor(on: "hai")
        let before = history

        model.text = "một"
        model.save(.replace)

        #expect(history == before)
        #expect(model.notice?.contains("sửa") == true && model.notice?.contains("chép") == true)
        #expect(model.notice?.contains("Lưu thành mục mới") == false)
        #expect(editorWindow.isOpen(model.itemID))
        // Saving as new is the way: it brings the other item to the top.
        model.save(.saveAsNew)
        #expect(history.items.first?.content == .text("một"))
        #expect(history.items.count == 2)
    }

    @Test func afterAReplaceTheNewWordsAreFoundAndTheOldOnesAreNot() async throws {
        await start()
        copy("bản nháp đầu tiên")
        copy("một mục khác")
        module.openLibrary()
        module.togglePanel()
        let library = try #require(module.library)
        let panel = try #require(module.panel)
        // Looked at before, so the search index has folded the old words and would keep them if it only looked at ids.
        state.query.text = "nháp"
        library.searchText = "nháp"
        panel.searchText = "nháp"
        #expect(state.visibleItems.count == 1 && library.items.count == 1 && panel.items.count == 1)

        let model = try openEditor(on: "bản nháp đầu tiên")
        model.text = "bản chính thức cuối cùng"
        model.save(.replace)

        for search in ["nháp", "dau tien"] {
            state.query.text = search
            library.searchText = search
            panel.searchText = search
            #expect(state.visibleItems.isEmpty, "\(search) in the notch's tab")
            #expect(library.items.isEmpty, "\(search) in the library")
            #expect(panel.items.isEmpty, "\(search) in the panel")
        }
        for search in ["chinh thuc", "CUỐI cùng"] {
            state.query.text = search
            library.searchText = search
            panel.searchText = search
            #expect(state.visibleItems.count == 1, "\(search) in the notch's tab")
            #expect(library.items.count == 1, "\(search) in the library")
            #expect(panel.items.count == 1, "\(search) in the panel")
        }
    }

    @Test func theEditedWordsAreClassifiedLikeACopyBySettings() async throws {
        await start()
        copy("hai")
        let (settings, keys) = try settings()
        settings.set(false, for: keys.colorsWithoutHash)
        let model = try openEditor(on: "hai")
        model.text = "ff8800"
        model.save(.replace)
        #expect(history.items.first?.content == .text("ff8800"))

        copy("ba")
        settings.set(true, for: keys.colorsWithoutHash)
        let second = try openEditor(on: "ba")
        second.text = "ff8800"
        second.save(.replace)
        // Typed as a copy of it would be, it is a colour now, which is not the same item as the text "ff8800".
        #expect(history.items.first?.content == .color(hex: "#FF8800"))
        #expect(history.items.count == 2)
    }

    @Test func blankAndHugeWordsAreRefusedAndNothingChanges() async throws {
        await start()
        copy("hai")
        let id = try item("hai").id
        let before = history
        #expect(module.saveEdit(of: id, text: "   ", mode: .saveAsNew) == .blank)
        #expect(module.saveEdit(of: id, text: String(repeating: "a", count: ClipboardClassifier.maxTextBytes + 1), mode: .replace) == .tooLarge)
        #expect(module.saveEdit(of: UUID(), text: "x", mode: .replace) == .missing)
        #expect(history == before)
    }

    @Test func aStoppedModuleSavesNothing() {
        #expect(module.saveEdit(of: UUID(), text: "x", mode: .saveAsNew) == .stopped)
    }

    // MARK: What closes it

    @Test func stoppingTheModuleClosesEveryEditor() async throws {
        await start()
        copy("một")
        copy("hai")
        let first = try openEditor(on: "một")
        let second = try openEditor(on: "hai")
        first.text = "một sửa dở"

        await stop()

        #expect(!editorWindow.isOpen(first.itemID) && !editorWindow.isOpen(second.itemID))
        #expect(module.editors.open.isEmpty)
        #expect(state.historyObserverCount == 0)
    }

    @Test func closingTheWindowForgetsTheEditor() async throws {
        await start()
        copy("Xin chào")
        let model = try openEditor(on: "Xin chào")
        editorWindow.close(itemID: model.itemID)
        #expect(module.editors.open.isEmpty)
        #expect(state.historyObserverCount == 0)
        // It can be opened again, as a new editor.
        #expect(module.edit(try item("Xin chào")))
        #expect(editorWindow.showCount == 2)
    }

    // MARK: Locked boards

    @Test func anItemOfAnOpenBoardCanBeEditedAndStaysInThatBoard() async throws {
        await start()
        let board = try await openBoard(holding: [Self.secretText, "mã số 99"])
        let secret = try item(Self.secretText)
        let model = try openEditor(on: Self.secretText)

        model.text = Self.secretText + "-SỬA"
        model.save(.replace)

        let edited = try item(Self.secretText + "-SỬA")
        #expect(edited.id == secret.id)
        #expect(history.boards.first { $0.id == board }?.itemIDs.contains(edited.id) == true)
        #expect(module.relockBoard(board))
        #expect(history.items.isEmpty)
    }

    @Test func savingAsNewFromAnOpenBoardPutsTheResultInTheSameBoardSoItLocksWithIt() async throws {
        await start()
        let board = try await openBoard(holding: [Self.secretText])
        let model = try openEditor(on: Self.secretText)
        model.text = Self.secretText + "-BẢN-SAO"
        model.save(.saveAsNew)
        #expect(history.items.count == 2)
        #expect(history.boards.first { $0.id == board }?.itemIDs.count == 2)

        #expect(module.relockBoard(board))

        // Nothing of either is left in the history, in memory or in a file the module wrote in the clear.
        #expect(history.items.isEmpty)
        await module.store?.flush()
        #expect(!reload().items.contains { $0.content.plainText?.contains(Self.secretText) == true })
    }

    @Test func lockingTheBoardWipesTheSecretWordsAndTheEditorStaysToSaySo() async throws {
        await start()
        let board = try await openBoard(holding: [Self.secretText])
        let model = try openEditor(on: Self.secretText)
        model.text = Self.secretText + "-đang gõ dở"

        #expect(module.relockBoard(board))

        // The words are gone from the editor and the history; the window stays, empty, with the notice, so the user sees why.
        #expect(model.text.isEmpty && model.originalText.isEmpty)
        #expect(model.isDroppedOnLock)
        #expect(editorWindow.isOpen(model.itemID))
        #expect(!model.isConfirmingDiscard)
        #expect(!model.hasChanges && !model.canSave)
        // Once locked there is no item to edit: it is not in the history at all.
        #expect(history.items.isEmpty)

        // Closing it is plain: nothing is left to lose.
        model.cancel()
        #expect(!editorWindow.isOpen(model.itemID))
        #expect(module.editors.open.isEmpty)
        #expect(state.historyObserverCount == 0)
    }

    @Test func lockingTheBoardClosesAnEditorThatHadNothingUnsaved() async throws {
        await start()
        let board = try await openBoard(holding: [Self.secretText])
        let model = try openEditor(on: Self.secretText)

        #expect(module.relockBoard(board))

        #expect(!editorWindow.isOpen(model.itemID))
        #expect(!model.isDroppedOnLock)
        #expect(model.text.isEmpty && module.editors.open.isEmpty)
    }

    @Test func savingAsNewFromASecretWhoseWordsAnotherItemHasIsRefusedAndTheEditorSaysWhyWithoutPointingAtTheButton() async throws {
        await start()
        copy("một mục thường")
        _ = try await openBoard(holding: [Self.secretText])
        let model = try openEditor(on: Self.secretText)
        model.text = "một mục thường"

        model.save(.saveAsNew)

        #expect(editorWindow.isOpen(model.itemID))
        let notice = try #require(model.notice)
        #expect(!notice.contains("Lưu thành mục mới") && !notice.contains("Thay thế"))
        #expect(!notice.contains("một mục thường") && !notice.contains(Self.secretText))
        // Nothing was pinned or moved: the ordinary item is where it was.
        #expect(history.boards.first { $0.name == "Két" }?.itemIDs.count == 1)
    }

    @Test func aLockedBoardsItemIsRefusedWhereverItIsStillListed() async throws {
        await start()
        copy("hai")
        let board = try #require(module.createBoard(named: "Két"))
        let item = try item("hai")
        module.pin(item, to: board)
        // The state the module never makes: the item listed, the board closed.
        module.update { history in
            history.boards[0].lock = ClipboardBoardLock(method: .password, itemCount: 1, isUnlocked: false)
            return []
        }
        #expect(!module.edit(item))
        #expect(module.saveEdit(of: item.id, text: "x", mode: .replace) == .locked)
        #expect(editorWindow.showCount == 0)
    }

    // MARK: The library's inspector

    @Test func theLibraryOpensWithTheInspectorHiddenAndRemembersTheChoice() async throws {
        await start()
        module.openLibrary()
        let library = try #require(module.library)
        #expect(!library.isInspectorVisible)

        library.toggleInspector()
        let (settings, keys) = try settings()
        #expect(settings.value(keys.libraryInspectorVisible))

        libraryWindow.close()
        module.openLibrary()
        #expect(module.library?.isInspectorVisible == true)
        module.library?.toggleInspector()
        #expect(!settings.value(keys.libraryInspectorVisible))
    }

    @Test func theOtherLibraryChoicesAreStillRememberedWithIt() async throws {
        await start()
        module.openLibrary()
        let library = try #require(module.library)
        library.toggleInspector()
        library.layout = .list
        library.cardSize = .large
        let (settings, keys) = try settings()
        #expect(settings.value(keys.libraryLayout) == .list && settings.value(keys.libraryCardSize) == .large)
        #expect(settings.value(keys.libraryInspectorVisible))
    }

    @Test func pastingFromTheInspectorUsesTheModulesPastePath() async throws {
        await start()
        copy("Xin chào")
        module.openLibrary()
        let library = try #require(module.library)
        library.select(try item("Xin chào").id, mode: .replace)

        #expect(library.pasteFocused())

        // The pasteboard was written by the paste path, whatever the click action is.
        #expect(pasteboard.writes.map(\.content) == [.text("Xin chào")])
    }

    // MARK: How often it was copied

    @Test func copyingTheSameWordsAgainCountsAndTheCountIsKept() async throws {
        await start()
        copy("Xin chào")
        #expect(try item("Xin chào").timesCopied == 1)
        copy("tạm biệt")
        copy("Xin chào")
        copy("Xin chào")
        #expect(try item("Xin chào").timesCopied == 3)
        #expect(try item("tạm biệt").timesCopied == 1)

        await stop()
        #expect(try #require(reload().items.first { $0.content.plainText == "Xin chào" }).timesCopied == 3)
    }

    @Test func pastingAnItemFromMyNotchIsNotACopy() async throws {
        await start()
        copy("Xin chào")
        copy("tạm biệt")
        let first = try item("Xin chào")
        module.activate(first)
        #expect(history.items.first?.id == first.id)
        #expect(try item("Xin chào").timesCopied == 1)
    }
}
