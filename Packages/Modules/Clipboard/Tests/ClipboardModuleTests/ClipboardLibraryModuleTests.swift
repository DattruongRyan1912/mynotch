import Foundation
import MyNotchCore
import SwiftUI
import Testing
@testable import ClipboardModule

/// Records what the module asks of the library window, so no test creates a real one.
final class FakeLibraryWindow: ClipboardLibraryWindowing {
    var isOpen = false
    var isFrontmost = false
    private(set) var showCount = 0
    private(set) var frontCount = 0
    private(set) var yieldCount = 0
    private var onClose: (() -> Void)?

    func show(_ content: AnyView, onClose: @escaping () -> Void) {
        showCount += 1
        isOpen = true
        self.onClose = onClose
    }

    func bringToFront() {
        frontCount += 1
    }

    func yieldKeyboardFocus() {
        yieldCount += 1
    }

    /// The window closing, whether the user closed it or the module asked.
    func close() {
        guard isOpen else { return }
        isOpen = false
        isFrontmost = false
        let onClose = onClose
        self.onClose = nil
        onClose?()
    }
}

/// The library as the module drives it, on the same fixture as `ClipboardModuleTests`.
extension ClipboardModuleTests {
    // MARK: Opening

    @Test func theLibraryHasItsOwnHotkeyWithTheShiftedDefault() async throws {
        await start()

        let registration = try #require(harness.hotkeys.registrations.first { $0.id == "clipboard_openLibrary" })
        #expect(registration.title == "Mở thư viện clipboard")
        #expect(harness.hotkeyBackend.getShortcut(for: registration.name) == KeyboardShortcuts.Shortcut(.v, modifiers: [.control, .option, .shift]))

        #expect(harness.hotkeyBackend.trigger("clipboard_openLibrary"))
        #expect(libraryWindow.showCount == 1)
        #expect(harness.presenter.openedTabs.isEmpty)
    }

    @Test func theStatusMenuOffersTheLibraryOnlyWhileTheModuleRuns() async throws {
        #expect(harness.registry.menuItems.isEmpty)

        await start()
        let item = try #require(harness.registry.menuItems.first)
        #expect(harness.registry.menuItems.count == 1)
        #expect(item.title == "Thư viện Clipboard…")
        item.action()
        #expect(libraryWindow.showCount == 1)

        await harness.registry.setEnabled(false, for: "clipboard")
        #expect(harness.registry.menuItems.isEmpty)
    }

    @Test func openingTheLibraryAgainBringsTheSameWindowForward() async {
        await start()
        module.openLibrary()
        let model = module.library
        module.openLibrary()

        #expect(libraryWindow.showCount == 1)
        #expect(libraryWindow.frontCount == 1)
        #expect(module.library === model)
    }

    @Test func theLibraryDoesNotOpenWhileTheModuleIsStopped() {
        module.openLibrary()
        #expect(libraryWindow.showCount == 0)
        #expect(module.library == nil)
    }

    @Test func theLibraryShowsTheHistoryAndFollowsNewCopiesWhileOpen() async throws {
        await start()
        copy("Xin chào")
        module.openLibrary()
        let library = try #require(module.library)
        #expect(library.items.map(\.content) == [.text("Xin chào")])

        copy("Tạm biệt")
        #expect(library.counts.all == 2)
        #expect(library.items.map(\.content) == [.text("Tạm biệt"), .text("Xin chào")])
    }

    // MARK: Closing

    @Test func closingTheWindowEndsTheLibraryAndItsWorkOnTheStore() async {
        await start()
        module.openLibrary()
        #expect(state.historyObserverCount == 1)

        libraryWindow.close()

        #expect(module.library == nil)
        #expect(state.historyObserverCount == 0)
        // Opening again builds a new one.
        module.openLibrary()
        #expect(libraryWindow.showCount == 2)
        #expect(module.library != nil)
    }

    @Test func stoppingTheModuleClosesTheLibrary() async {
        await start()
        module.openLibrary()

        await harness.registry.setEnabled(false, for: "clipboard")

        #expect(!libraryWindow.isOpen)
        #expect(module.library == nil)
        #expect(state.historyObserverCount == 0)
    }

    // MARK: Actions

    @Test func aPasteFromTheLibraryHandsTheKeyboardBackAndWaitsLongerForIt() async throws {
        let (settings, keys) = try settings()
        settings.set(.paste, for: keys.clickAction)
        await start()
        copy("Xin chào")
        let item = try #require(items.first)
        module.openLibrary()
        libraryWindow.isFrontmost = true

        #expect(module.activate(item) == .pasted)

        #expect(libraryWindow.yieldCount == 1)
        harness.scheduler.advance(by: .milliseconds(80))
        #expect(keystrokes.pasteCount == 0)
        harness.scheduler.advance(by: .milliseconds(170))
        #expect(keystrokes.pasteCount == 1)
    }

    @Test func aPasteWithoutAccessibilityFromTheLibraryAlsoHandsTheKeyboardBack() async throws {
        system.trusted = false
        await start()
        copy("Xin chào")
        module.openLibrary()
        libraryWindow.isFrontmost = true

        #expect(module.paste(try #require(items.first)) == .copiedNeedsPermission)

        #expect(libraryWindow.yieldCount == 1)
        #expect(harness.activities.entries.contains { $0.id == "clipboard/pasteHint" })
    }

    @Test func aCopyFromTheLibraryKeepsTheKeyboardAndReportsTheOutcome() async throws {
        await start()
        copy("Xin chào")
        module.openLibrary()
        libraryWindow.isFrontmost = true

        #expect(module.copy(try #require(items.first)) == .copied)

        #expect(libraryWindow.yieldCount == 0)
    }

    @Test func aPasteFromTheNotchWhileTheLibraryIsInTheBackKeepsTheShortDelay() async throws {
        let (settings, keys) = try settings()
        settings.set(.paste, for: keys.clickAction)
        await start()
        copy("Xin chào")
        module.openLibrary()
        libraryWindow.isFrontmost = false

        module.activate(try #require(items.first))

        #expect(libraryWindow.yieldCount == 0)
        harness.scheduler.advance(by: .milliseconds(80))
        #expect(keystrokes.pasteCount == 1)
    }

    /// The whole path from a double click: the library's model, the module, the click action from Settings.
    @Test func theLibraryActivatesWithTheClickActionFromSettings() async throws {
        let (settings, keys) = try settings()
        await start()
        copy("Xin chào")
        module.openLibrary()
        libraryWindow.isFrontmost = true
        let library = try #require(module.library)
        let item = try #require(items.first)

        #expect(library.activate(item.id))
        harness.scheduler.advance(by: .seconds(1))
        #expect(pasteboard.writes.map(\.content) == [.text("Xin chào")])
        #expect(keystrokes.pasteCount == 0)
        #expect(libraryWindow.yieldCount == 0)
        #expect(library.notice?.text == "Đã chép")

        settings.set(.paste, for: keys.clickAction)
        #expect(library.activate(item.id))
        harness.scheduler.advance(by: .seconds(1))
        #expect(pasteboard.writes.count == 2)
        #expect(keystrokes.pasteCount == 1)
        #expect(libraryWindow.yieldCount == 1)
        #expect(library.notice == nil)
    }

    @Test func activateReportsAFailedCopyAndNothingWhileStopped() async throws {
        let item = Self.item(.text("Xin chào"), copiedAt: system.now)
        #expect(module.activate(item) == nil)
        #expect(module.copy(item) == nil)
        #expect(module.paste(item) == nil)
    }

    @Test func deletingSeveralItemsKeepsTheRestAndSaves() async throws {
        await start()
        copy("một")
        copy("hai")
        copy("ba")
        let ids = Set(items.prefix(2).map(\.id))

        module.delete(ids: ids)

        #expect(items.map(\.content) == [.text("một")])
        harness.scheduler.advance(by: .seconds(1))
        await module.store?.waitForWrites()
        #expect(makeStore().load().items.map(\.content) == [.text("một")])
    }

    @Test func deletingItemsRemovesThemFromTheirBoardsAndTheirImages() async throws {
        await start()
        copy(PasteboardSnapshot(types: ["public.png"], png: ClipboardClassifierTests.png))
        let image = try #require(items.first)
        let imageURL = try #require(module.fileURLs(of: image).first)
        let board = try #require(module.createBoard(named: "Board"))
        module.pin(image, to: board)

        module.delete(ids: [image.id])

        #expect(items.isEmpty)
        #expect(state.history.boards.first?.itemIDs == [])
        #expect(!exists(imageURL))
    }

    @Test func pinningSeveralItemsKeepsTheirOrderInTheBoard() async throws {
        await start()
        copy("một")
        copy("hai")
        copy("ba")
        let board = try #require(module.createBoard(named: "Board"))
        let shown = items.map(\.id)

        module.pin(ids: shown, to: board)

        // Newest pin first, so the board lists the items the way the library showed them.
        #expect(state.history.boards.first?.itemIDs == shown)
        module.pin(ids: [UUID()], to: board)
        module.pin(ids: shown, to: UUID())
        #expect(state.history.boards.first?.itemIDs == shown)
    }

    // MARK: Preferences

    @Test func theLibraryRemembersItsViewPreferences() async throws {
        await start()
        module.openLibrary()
        let library = try #require(module.library)
        #expect(library.layout == .grid)
        #expect(library.sort == .newest)
        #expect(library.cardSize == .medium)

        library.layout = .list
        library.sort = .byKind
        library.cardSize = .large
        libraryWindow.close()

        let (settings, keys) = try settings()
        #expect(settings.value(keys.libraryLayout) == .list)
        #expect(settings.value(keys.librarySort) == .byKind)
        #expect(settings.value(keys.libraryCardSize) == .large)

        module.openLibrary()
        let reopened = try #require(module.library)
        #expect(reopened.layout == .list)
        #expect(reopened.sort == .byKind)
        #expect(reopened.cardSize == .large)
    }

    @Test func theViewPreferencesStartAtTheirDefaults() async throws {
        let (settings, keys) = try settings()
        #expect(settings.value(keys.libraryLayout) == .grid)
        #expect(settings.value(keys.librarySort) == .newest)
        #expect(settings.value(keys.libraryCardSize) == .medium)
    }
}
