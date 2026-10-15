import AppKit
import NotchUI
import SwiftUI
import Testing
@testable import ClipboardModule

/// The editor's own window: out of recordings the way the user asked, hosted with the notch's accent, asking before it closes over
/// unsaved words, and taking Esc and ⌘W before its text view. Windows are made but never put on a screen, and the key events are built
/// and handed over directly: nothing is posted.
@Suite struct ClipboardEditorWindowTests {
    func eventually(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<400 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return condition()
    }

    /// What the controller did to the app around its windows, instead of doing it to the test process.
    final class Recorder {
        var broughtForward = 0
        var closedWindows = 0
    }

    func model(text: String = "Xin chào", close: @escaping () -> Void = {}) -> ClipboardEditorModel {
        let item = ClipboardItem(id: UUID(), content: .text(text), contentHash: "h", copiedAt: .now)
        return ClipboardEditorModel(item: item, text: text, save: { _, _ in .saved(item.id) }, close: close)
    }

    func keyEvent(_ characters: String, code: UInt16, modifiers: NSEvent.ModifierFlags = [], isRepeat: Bool = false) throws -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: 0, context: nil,
            characters: characters, charactersIgnoringModifiers: characters, isARepeat: isRepeat, keyCode: code
        ))
    }

    func makeController(interface: NotchInterface = NotchInterface(), activation: ClipboardEditorWindowController.Activation = .recorded(Recorder())) -> ClipboardEditorWindowController {
        ClipboardEditorWindowController(interface: interface, activation: activation)
    }

    // MARK: Hiding from recordings

    @Test func aNewEditorWindowIsHiddenFromCaptureWhenTheSettingSaysSo() {
        for (hiding, expected) in [
            (CaptureHiding.never, NSWindow.SharingType.readOnly), (.always, SharingNone.value),
            // Opened by the user like an open notch, so "only while collapsed" shows it.
            (.whenCollapsed, .readOnly),
        ] {
            let controller = makeController(interface: NotchInterface(captureHiding: hiding))
            #expect(controller.makeWindow(AnyView(EmptyView()), model: model()).sharingType == expected, "\(hiding)")
        }
    }

    @Test func theEditorWindowFollowsTheSettingWhileItIsOpen() async {
        let interface = NotchInterface()
        let controller = makeController(interface: interface)
        let window = controller.makeWindow(AnyView(EmptyView()), model: model())
        #expect(window.sharingType == .readOnly)

        interface.captureHiding = .always
        #expect(await eventually { window.sharingType == SharingNone.value })
        interface.captureHiding = .never
        #expect(await eventually { window.sharingType == .readOnly })
    }

    @Test func aClosedEditorWindowStopsFollowing() async {
        let interface = NotchInterface()
        let controller = makeController(interface: interface)
        let window = controller.makeWindow(AnyView(EmptyView()), model: model())
        controller.stopFollowingSetting(of: window)

        interface.captureHiding = .always
        try? await Task.sleep(for: .milliseconds(50))
        #expect(window.sharingType == .readOnly)
    }

    @Test func theEditorWindowIsHostedWithTheAccentOfTheNotch() {
        let window = makeController().makeWindow(AnyView(EmptyView()), model: model())
        #expect(window.contentViewController is NSHostingController<ClipboardAccentHost<AnyView>>)
    }

    @Test func theWindowIsAnOrdinaryTitledOneThatCanTakeTyping() {
        let window = makeController().makeWindow(AnyView(EmptyView()), model: model())
        #expect(window.styleMask.isSuperset(of: [.titled, .closable, .resizable, .miniaturizable]))
        #expect(window.canBecomeKey)
        #expect(!window.isReleasedWhenClosed)
        #expect(window.title == "Sửa mục clipboard")
    }

    // MARK: Closing

    @Test func theCloseButtonAsksBeforeLosingWordsAndLetsAnUntouchedWindowGo() {
        let controller = makeController()
        let editor = model()
        let window = controller.makeWindow(AnyView(EmptyView()), model: editor)
        controller.register(window, model: editor, onClose: {})

        #expect(controller.windowShouldClose(window))
        editor.text = "Xin chào bạn"
        #expect(!controller.windowShouldClose(window))
        #expect(editor.isConfirmingDiscard)
    }

    @Test func closingAWindowTellsTheModuleOnceAndGivesTheAppBackItsPolicy() {
        let recorder = Recorder()
        let controller = makeController(activation: .recorded(recorder))
        let editor = model()
        let window = controller.makeWindow(AnyView(EmptyView()), model: editor)
        var closed = 0
        controller.register(window, model: editor) { closed += 1 }
        #expect(controller.openCount == 1)

        controller.close(itemID: editor.itemID)

        #expect(closed == 1)
        #expect(controller.openCount == 0)
        #expect(recorder.closedWindows == 1)
        // The words went with the views.
        #expect(window.contentViewController == nil)
        // Closing what is not open does nothing.
        controller.close(itemID: editor.itemID)
        #expect(closed == 1)
    }

    @Test func aWindowTheControllerDoesNotKnowMayClose() {
        let stranger = ClipboardEditorWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: true)
        #expect(makeController().windowShouldClose(stranger))
    }

    @Test func showingTheSameItemAgainOnlyBringsItForward() {
        let recorder = Recorder()
        let controller = makeController(activation: .recorded(recorder))
        let editor = model()
        controller.register(controller.makeWindow(AnyView(EmptyView()), model: editor), model: editor, onClose: {})
        controller.show(AnyView(EmptyView()), model: editor, onClose: {})
        #expect(controller.openCount == 1)
        #expect(recorder.broughtForward == 1)
        controller.close(itemID: editor.itemID)
    }

    // MARK: Keys

    @Test func escapeAsksTheModelToCancelBeforeTheTextViewSeesIt() throws {
        var closed = 0
        let editor = model { closed += 1 }
        let window = makeController().makeWindow(AnyView(EmptyView()), model: editor)

        #expect(window.handleKey(try keyEvent("\u{1B}", code: 53)))
        #expect(closed == 1)
    }

    @Test func escapeWithUnsavedWordsAsksInsteadOfClosing() throws {
        var closed = 0
        let editor = model { closed += 1 }
        let window = makeController().makeWindow(AnyView(EmptyView()), model: editor)
        editor.text = "Xin chào bạn"

        #expect(window.handleKey(try keyEvent("\u{1B}", code: 53)))
        #expect(closed == 0)
        #expect(editor.isConfirmingDiscard)
    }

    @Test func commandWCancelsToo() throws {
        var closed = 0
        let editor = model { closed += 1 }
        let window = makeController().makeWindow(AnyView(EmptyView()), model: editor)
        #expect(window.handleKey(try keyEvent("w", code: 13, modifiers: .command)))
        #expect(closed == 1)
    }

    @Test func otherKeysAndAHeldEscapeAreLeftOrSwallowedWithoutAskingTwice() throws {
        var closed = 0
        let editor = model { closed += 1 }
        let window = makeController().makeWindow(AnyView(EmptyView()), model: editor)
        #expect(!window.handleKey(try keyEvent("a", code: 0)))
        #expect(!window.handleKey(try keyEvent(" ", code: 49)))
        #expect(!window.handleKey(try keyEvent("\r", code: 36)))
        #expect(closed == 0)
        // A repeat of Esc is eaten and does nothing more.
        #expect(window.handleKey(try keyEvent("\u{1B}", code: 53, isRepeat: true)))
        #expect(closed == 0)
    }

    @Test func aWindowWithNoModelLeavesEveryKeyAlone() throws {
        let window = ClipboardEditorWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: true)
        #expect(!window.handleKey(try keyEvent("\u{1B}", code: 53)))
    }
}

extension ClipboardEditorWindowController.Activation {
    static func recorded(_ recorder: ClipboardEditorWindowTests.Recorder) -> Self {
        Self(bringForward: { _ in recorder.broughtForward += 1 }, windowClosed: { _ in recorder.closedWindows += 1 })
    }
}

/// `NSWindow.SharingType.none`, named so a comparison reads as the case and not as `Optional.none`.
enum SharingNone {
    static let value = NSWindow.SharingType.none
}
