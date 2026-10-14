import CoreGraphics
import Foundation
import MyNotchCore
import SwiftUI
import Testing
@testable import ClipboardModule

/// Records what the module asks of the floating panel's window, so no test creates a real one.
final class FakePanelWindow: ClipboardPanelWindowing {
    var isOpen = false
    var isKey = true
    /// Where the panel is while open.
    var origin: CGPoint? = CGPoint(x: 120, y: 340)
    private(set) var showCount = 0
    private(set) var focusCount = 0
    private(set) var keyboardReturnCount = 0
    private(set) var keyboardCheckCount = 0
    /// Whether handing the keyboard back leaves the panel without it, which a real window can fail to do.
    var handBackWorks = true
    /// Whether, once the panel has left the screen, the keyboard is with the app in front and not with a window of MyNotch.
    var frontAppHasKeyboardAfterClose = true
    /// Runs when the keyboard is handed back, so a test can look at what had happened by then.
    var onReturnKeyboard: (() -> Void)?
    private(set) var closeCount = 0
    private(set) var model: ClipboardPanelModel?
    private(set) var restoredOrigin: CGPoint?
    private var onClose: (() -> Void)?

    func show(_ content: AnyView, model: ClipboardPanelModel, restoringOrigin: CGPoint?, onClose: @escaping () -> Void) {
        showCount += 1
        isOpen = true
        isKey = true
        self.model = model
        restoredOrigin = restoringOrigin
        self.onClose = onClose
    }

    func focus() {
        focusCount += 1
        isKey = true
    }

    func returnKeyboard() -> Bool {
        keyboardReturnCount += 1
        onReturnKeyboard?()
        if handBackWorks { isKey = false }
        return !isKey
    }

    func keyboardIsWithFrontApp() -> Bool {
        keyboardCheckCount += 1
        return !isKey && frontAppHasKeyboardAfterClose
    }

    /// The window closing, whether the user closed it or the module asked.
    func close() {
        guard isOpen else { return }
        closeCount += 1
        isOpen = false
        isKey = false
        let onClose = onClose
        self.onClose = nil
        onClose?()
    }
}

/// The floating panel as the module drives it, on the same fixture as `ClipboardModuleTests`.
extension ClipboardModuleTests {
    // MARK: Opening

    @Test func thePanelHasAHotkeyWithShiftCommandCAsTheDefault() async throws {
        await start()

        let registration = try #require(harness.hotkeys.registrations.first { $0.id == "clipboard_openPanel" })
        #expect(registration.title == "Mở bảng clipboard nổi")
        #expect(harness.hotkeyBackend.getShortcut(for: registration.name) == KeyboardShortcuts.Shortcut(.c, modifiers: [.command, .shift]))

        #expect(harness.hotkeyBackend.trigger("clipboard_openPanel"))
        #expect(panelWindow.showCount == 1)
        #expect(harness.presenter.openedTabs.isEmpty)
        #expect(libraryWindow.showCount == 0)
    }

    @Test func thePanelDoesNotOpenWhileTheModuleIsStopped() {
        module.togglePanel()
        #expect(panelWindow.showCount == 0)
        #expect(module.panel == nil)
    }

    @Test func thePanelShowsTheHistoryAndFollowsNewCopiesWhileOpen() async throws {
        await start()
        copy("Xin chào")
        module.togglePanel()
        let panel = try #require(module.panel)
        #expect(panel.items.map(\.content) == [.text("Xin chào")])

        copy("Tạm biệt")
        #expect(panel.items.map(\.content) == [.text("Tạm biệt"), .text("Xin chào")])
    }

    // MARK: Toggling

    @Test func theHotkeyClosesAnOpenPanel() async {
        await start()
        module.togglePanel()
        module.togglePanel()

        #expect(panelWindow.closeCount == 1)
        #expect(!panelWindow.isOpen)
        #expect(module.panel == nil)
        #expect(state.historyObserverCount == 0)
    }

    @Test func theHotkeyOnAPinnedPanelThatLostTheKeyboardTakesItBackInsteadOfClosing() async throws {
        let (settings, keys) = try settings()
        settings.set(true, for: keys.panelPinned)
        await start()
        module.togglePanel()
        panelWindow.isKey = false

        module.togglePanel()
        #expect(panelWindow.focusCount == 1)
        #expect(panelWindow.isOpen)

        // Now that it has the keyboard, the same key closes it.
        module.togglePanel()
        #expect(panelWindow.closeCount == 1)
    }

    @Test func closingThePanelAndOpeningAgainBuildsANewOne() async {
        await start()
        module.togglePanel()
        let first = module.panel
        panelWindow.close()
        module.togglePanel()

        #expect(panelWindow.showCount == 2)
        #expect(module.panel != nil)
        #expect(module.panel !== first)
    }

    @Test func stoppingTheModuleClosesThePanel() async {
        await start()
        module.togglePanel()

        await harness.registry.setEnabled(false, for: "clipboard")

        #expect(!panelWindow.isOpen)
        #expect(module.panel == nil)
        #expect(state.historyObserverCount == 0)
    }

    // MARK: Using an item

    @Test func aPasteFromTheUnpinnedPanelClosesItBeforeCommandVAndWaitsOnlyTheShortDelay() async throws {
        let (settings, keys) = try settings()
        settings.set(.paste, for: keys.clickAction)
        await start()
        copy("Xin chào")
        let item = try #require(items.first)
        module.togglePanel()
        let panel = try #require(module.panel)

        panel.activate(item.id)

        // The panel is gone before ⌘V can be sent, so the keyboard is back in the app in front.
        #expect(panelWindow.closeCount == 1)
        #expect(keystrokes.pasteCount == 0)
        harness.scheduler.advance(by: .milliseconds(80))
        #expect(keystrokes.pasteCount == 1)
        #expect(libraryWindow.yieldCount == 0)
        #expect(pasteboard.writes.last?.content == .text("Xin chào"))
    }

    @Test func aPasteFromAPinnedPanelHandsTheKeyboardBackAndKeepsItOpen() async throws {
        let (settings, keys) = try settings()
        settings.set(.paste, for: keys.clickAction)
        settings.set(true, for: keys.panelPinned)
        await start()
        copy("Xin chào")
        let item = try #require(items.first)
        module.togglePanel()

        try #require(module.panel).activate(item.id)

        #expect(panelWindow.closeCount == 0)
        #expect(panelWindow.keyboardReturnCount == 1)
        #expect(keystrokes.pasteCount == 0)
        harness.scheduler.advance(by: .milliseconds(80))
        #expect(keystrokes.pasteCount == 1)
        #expect(panelWindow.isOpen)
    }

    @Test func withTheCopyClickActionThePanelOnlyCopies() async throws {
        let (settings, keys) = try settings()
        settings.set(.copy, for: keys.clickAction)
        await start()
        copy("Xin chào")
        let item = try #require(items.first)
        module.togglePanel()

        try #require(module.panel).activate(item.id)
        harness.scheduler.advance(by: .milliseconds(300))

        #expect(pasteboard.writes.last?.content == .text("Xin chào"))
        #expect(keystrokes.pasteCount == 0)
        #expect(panelWindow.closeCount == 1)
    }

    @Test func withoutAccessibilityThePanelCopiesAndTheNotchHintSaysToPressCommandV() async throws {
        let (settings, keys) = try settings()
        settings.set(.paste, for: keys.clickAction)
        system.trusted = false
        await start()
        copy("Xin chào")
        let item = try #require(items.first)
        module.togglePanel()

        try #require(module.panel).activate(item.id)
        harness.scheduler.advance(by: .milliseconds(300))

        #expect(pasteboard.writes.last?.content == .text("Xin chào"))
        #expect(keystrokes.pasteCount == 0)
        #expect(panelWindow.closeCount == 1)
        #expect(harness.activities.entries.contains { $0.id == "clipboard/pasteHint" })
    }

    @Test func aPickedItemMovesToTheTopOfTheHistory() async throws {
        await start()
        copy("một")
        system.now.addTimeInterval(60)
        copy("hai")
        let older = try #require(items.last)
        module.togglePanel()

        module.panel?.activate(older.id)

        #expect(items.first?.id == older.id)
    }

    // MARK: The keyboard first, then ⌘V

    @Test func theKeyboardIsHandedBackAfterTheWriteAndBeforeCommandVIsScheduled() async throws {
        let (settings, keys) = try settings()
        settings.set(.paste, for: keys.clickAction)
        settings.set(true, for: keys.panelPinned)
        await start()
        copy("Xin chào")
        let item = try #require(items.first)
        module.togglePanel()
        let pendingBefore = harness.scheduler.pendingCount
        var seen: (writes: Int, pending: Int)?
        panelWindow.onReturnKeyboard = { [self] in seen = (pasteboard.writes.count, harness.scheduler.pendingCount) }

        try #require(module.panel).activate(item.id)

        #expect(seen?.writes == 1)
        #expect(seen?.pending == pendingBefore)
        // ⌘V is scheduled only now.
        #expect(harness.scheduler.pendingCount == pendingBefore + 1)
        harness.scheduler.advance(by: .milliseconds(80))
        #expect(keystrokes.pasteCount == 1)
    }

    /// The panel is still key, so ⌘V would land in its own search field: the item stays on the pasteboard instead.
    @Test func aPinnedPanelThatCannotHandTheKeyboardBackOnlyCopies() async throws {
        let (settings, keys) = try settings()
        settings.set(.paste, for: keys.clickAction)
        settings.set(true, for: keys.panelPinned)
        await start()
        copy("Xin chào")
        let item = try #require(items.first)
        module.togglePanel()
        panelWindow.handBackWorks = false

        let panel = try #require(module.panel)
        panel.activate(item.id)
        harness.scheduler.advance(by: .seconds(1))

        #expect(pasteboard.writes.last?.content == .text("Xin chào"))
        #expect(keystrokes.pasteCount == 0)
        #expect(panelWindow.keyboardReturnCount == 1)
        #expect(panelWindow.isOpen)
        #expect(panel.notice?.text == "Đã chép — nhấn ⌘V để dán")
        // The same hint as for a paste without Accessibility, beside the notch.
        #expect(harness.activities.entries.contains { $0.id == "clipboard/pasteHint" })
    }

    /// MyNotch's own window (the library, Settings) is the one that gets the keyboard once the panel is gone.
    @Test func anUnpinnedPanelThatLeavesTheKeyboardWithAWindowOfMyNotchOnlyCopies() async throws {
        let (settings, keys) = try settings()
        settings.set(.paste, for: keys.clickAction)
        await start()
        copy("Xin chào")
        let item = try #require(items.first)
        module.togglePanel()
        panelWindow.frontAppHasKeyboardAfterClose = false

        try #require(module.panel).activate(item.id)
        harness.scheduler.advance(by: .seconds(1))

        #expect(panelWindow.closeCount == 1)
        #expect(panelWindow.keyboardCheckCount == 1)
        #expect(pasteboard.writes.last?.content == .text("Xin chào"))
        #expect(keystrokes.pasteCount == 0)
        #expect(harness.activities.entries.contains { $0.id == "clipboard/pasteHint" })
    }

    @Test func aPasteThatWorksShowsNoHintAndAskedForTheKeyboardOnce() async throws {
        let (settings, keys) = try settings()
        settings.set(.paste, for: keys.clickAction)
        await start()
        copy("Xin chào")
        let item = try #require(items.first)
        module.togglePanel()

        try #require(module.panel).activate(item.id)
        harness.scheduler.advance(by: .seconds(1))

        #expect(keystrokes.pasteCount == 1)
        #expect(panelWindow.keyboardCheckCount == 1)
        #expect(!harness.activities.entries.contains { $0.id == "clipboard/pasteHint" })
    }

    @Test func aWriteThatFailsKeepsThePanelOpenWithTheKeyboardAndPastesNothing() async throws {
        let (settings, keys) = try settings()
        settings.set(.paste, for: keys.clickAction)
        settings.set(true, for: keys.panelPinned)
        await start()
        copy("Xin chào")
        let item = try #require(items.first)
        module.togglePanel()
        pasteboard.writesSucceed = false

        let panel = try #require(module.panel)
        panel.activate(item.id)
        harness.scheduler.advance(by: .seconds(1))

        #expect(panelWindow.isOpen)
        #expect(panelWindow.keyboardReturnCount == 0)
        #expect(keystrokes.pasteCount == 0)
        #expect(panel.notice?.text == "Không chép được mục này")
    }

    // MARK: Remembering

    @Test func thePinnedStateAndThePositionWhilePinnedAreRemembered() async throws {
        let (settings, keys) = try settings()
        await start()
        module.togglePanel()
        #expect(panelWindow.restoredOrigin == nil)
        #expect(settings.value(keys.panelPinned) == false)

        // Pinning remembers where the panel is now.
        try #require(module.panel).togglePin()
        #expect(settings.value(keys.panelPinned))
        #expect(settings.value(keys.panelPosition) == ClipboardPanelPosition(CGPoint(x: 120, y: 340)))

        // Dragging it while pinned moves the remembered position.
        try #require(module.panel).moved(to: CGPoint(x: 30, y: 40))
        #expect(settings.value(keys.panelPosition) == ClipboardPanelPosition(CGPoint(x: 30, y: 40)))

        // The next time it opens, it is pinned and where it was left.
        panelWindow.close()
        module.togglePanel()
        #expect(try #require(module.panel).isPinned)
        #expect(panelWindow.restoredOrigin == CGPoint(x: 30, y: 40))
    }

    @Test func anUnpinnedPanelOpensAtThePointerEvenWithASavedPosition() async throws {
        let (settings, keys) = try settings()
        settings.set(true, for: keys.panelPinned)
        settings.set(ClipboardPanelPosition(CGPoint(x: 30, y: 40)), for: keys.panelPosition)
        await start()
        module.togglePanel()
        try #require(module.panel).togglePin()
        #expect(settings.value(keys.panelPinned) == false)

        panelWindow.close()
        module.togglePanel()
        #expect(panelWindow.restoredOrigin == nil)
        #expect(try #require(module.panel).isPinned == false)
    }

    @Test func aMoveWhileUnpinnedIsNotRemembered() async throws {
        let (settings, keys) = try settings()
        await start()
        module.togglePanel()

        try #require(module.panel).moved(to: CGPoint(x: 5, y: 6))
        #expect(settings.value(keys.panelPosition) == nil)
    }

    @Test func thePanelSettingsStartUnpinnedWithNoPosition() throws {
        let (settings, keys) = try settings()
        #expect(settings.value(keys.panelPinned) == false)
        #expect(settings.value(keys.panelPosition) == nil)
    }
}
