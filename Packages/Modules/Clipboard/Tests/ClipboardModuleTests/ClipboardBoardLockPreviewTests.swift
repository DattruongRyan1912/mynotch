import AppKit
import Foundation
import Testing
@testable import ClipboardModule

/// The large preview and a board that locks: an item of a locked board is never shown large, and a preview of one that is open is
/// gone, with what it showed, the moment the board locks.
extension ClipboardBoardLockModuleTests {
    func spaceKey() -> ClipboardPreviewKeys.Key {
        ClipboardPreviewKeys.Key(keyCode: 49, characters: " ", modifiers: [])
    }

    @Test func lockingTheBoardWhileItsItemIsShownLargeInThePanelClosesThePreview() async throws {
        await start()
        let board = try await makeLockedBoard()
        try await module.unlockBoard(board, credential: .password(Self.password))
        module.togglePanel()
        let panel = try #require(module.panel)
        panel.searchText = Self.secretText
        panel.togglePreview()
        #expect(panel.previewedItem?.content.plainText == Self.secretText)
        #expect(panelPreview.isOpen)

        #expect(module.relockBoard(board))

        #expect(!panel.isPreviewOpen)
        #expect(panel.previewedItem == nil)
        #expect(!panelPreview.isOpen)
        #expect(panel.items.isEmpty)
    }

    @Test func lockingTheBoardWhileItsCardIsShownLargeInTheLibraryClosesThePreview() async throws {
        await start()
        let board = try await makeLockedBoard()
        try await module.unlockBoard(board, credential: .password(Self.password))
        module.openLibrary()
        let library = try #require(module.library)
        library.select(try item(Self.secretText).id, mode: .replace)
        library.togglePreview()
        #expect(libraryPreview.isOpen)

        #expect(module.relockBoard(board))

        #expect(!library.isPreviewOpen)
        #expect(library.previewedItem == nil)
        #expect(!libraryPreview.isOpen)
    }

    @Test func aLockedBoardsItemsAreNeverOfferedToThePreviewOnceItIsClosed() async throws {
        await start()
        _ = try await makeLockedBoard()
        copy("một mục thường")
        module.togglePanel()
        let panel = try #require(module.panel)

        panel.searchText = Self.secretText
        #expect(panel.items.isEmpty)
        #expect(!panel.handlePreviewKey(spaceKey(), target: .searchField, hasMarkedText: false))
        #expect(!panelPreview.isOpen)

        // Anything else still previews.
        panel.searchText = ""
        #expect(panel.handlePreviewKey(spaceKey(), target: .searchField, hasMarkedText: false))
        #expect(panelPreview.isOpen)
    }

    @Test func thePicturesOfAnOpenBoardAreReadFromMemoryAndAreGoneOnceItLocks() async throws {
        await start()
        let picture = try addImage("preview")
        let board = try makeBoard(holding: ["văn bản"])
        module.pin(picture.item, to: board)
        try await module.lockBoard(board, setup: .password(Self.password))
        try await module.unlockBoard(board, credential: .password(Self.password))
        let shown = try #require(history.items.first { $0.id == picture.item.id })

        // Bytes, not a file: nothing for the preview to read from the disk, or to write there.
        #expect(module.previewImageSource(of: shown) == .memory(picture.bytes))
        #expect(!exists(picture.file))

        #expect(module.relockBoard(board))
        #expect(module.openImages.data(forFileName: picture.item.content.imageFileName ?? "") == nil)
    }
}

private extension ClipboardContent {
    var imageFileName: String? {
        if case .image(let image) = self { image.fileName } else { nil }
    }
}
