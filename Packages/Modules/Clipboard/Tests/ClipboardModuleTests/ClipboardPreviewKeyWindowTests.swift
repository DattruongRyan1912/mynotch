import AppKit
import NotchUI
import SwiftUI
import Testing
@testable import ClipboardModule

/// The part of each window that reads keys for the preview before any field or view does: Space never reaches a search field as a
/// command (it is typed text), so the windows look at every key press first. Windows are made but never shown; the key events are
/// built and handed over directly, and nothing is posted.
@Suite struct ClipboardPreviewKeyWindowTests {
    typealias Keys = ClipboardPreviewKeys

    func keyEvent(
        _ characters: String, code: UInt16, modifiers: NSEvent.ModifierFlags = [], type: NSEvent.EventType = .keyDown, isRepeat: Bool = false
    ) throws -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: type, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: 0, context: nil,
            characters: characters, charactersIgnoringModifiers: characters, isARepeat: isRepeat, keyCode: code
        ))
    }

    func space(isRepeat: Bool = false) throws -> NSEvent {
        try keyEvent(" ", code: 49, isRepeat: isRepeat)
    }

    struct Seen {
        var key: Keys.Key
        var target: Keys.Target
        var hasMarkedText: Bool
    }

    final class Recorder {
        var seen: [Seen] = []
        var answer = true

        func handle(_ key: Keys.Key, _ target: Keys.Target, _ hasMarkedText: Bool) -> Bool {
            seen.append(Seen(key: key, target: target, hasMarkedText: hasMarkedText))
            return answer
        }
    }

    func makePanel(_ recorder: Recorder) -> ClipboardFloatingPanel {
        let panel = ClipboardPanelController(interface: NotchInterface()).makePanel()
        panel.onPreviewKey = { recorder.handle($0, $1, $2) }
        return panel
    }

    func makeLibraryWindow(_ recorder: Recorder) -> ClipboardLibraryWindow {
        let window = ClipboardLibraryWindowController(interface: NotchInterface()).makeWindow(AnyView(EmptyView())) as! ClipboardLibraryWindow
        window.onPreviewKey = { recorder.handle($0, $1, $2) }
        return window
    }

    // MARK: What a key press is

    @Test func aKeyEventBecomesTheKeyTheTableReads() throws {
        let key = Keys.Key(try keyEvent("y", code: 16, modifiers: [.command, .capsLock], isRepeat: true))
        #expect(key == Keys.Key(keyCode: 16, characters: "y", modifiers: [.command, .capsLock], isRepeat: true))
    }

    // MARK: The floating panel

    @Test func theFloatingPanelOffersEveryKeyPressToThePreviewBeforeAnythingElse() throws {
        let recorder = Recorder()
        let panel = makePanel(recorder)

        panel.sendEvent(try space())

        #expect(recorder.seen.count == 1)
        #expect(recorder.seen.first?.key == Keys.Key(keyCode: 49, characters: " ", modifiers: []))
    }

    @Test func aKeyThePreviewDoesNotTakeIsLeftForTheFieldAndTheRestOfTheWindow() throws {
        let recorder = Recorder()
        recorder.answer = false
        let panel = makePanel(recorder)

        #expect(!panel.handlePreviewKey(try keyEvent("a", code: 0)))
        #expect(recorder.seen.count == 1)
    }

    @Test func aKeyThePreviewTakesIsNotPassedOn() throws {
        let recorder = Recorder()
        let panel = makePanel(recorder)
        #expect(panel.handlePreviewKey(try space()))
    }

    @Test func releasingAKeyIsNotOffered() throws {
        let recorder = Recorder()
        let panel = makePanel(recorder)
        // `sendEvent` only offers key-downs; a key-up never reaches the table.
        #expect(!panel.offersToPreview(try keyEvent(" ", code: 49, type: .keyUp)))
        #expect(panel.offersToPreview(try space()))
    }

    @Test func aPanelWithNoModelOffersNothing() throws {
        let panel = ClipboardPanelController(interface: NotchInterface()).makePanel()
        #expect(!panel.handlePreviewKey(try space()))
    }

    @Test func inThePanelAnythingButAnotherTextFieldCountsAsHavingNowhereToType() throws {
        let recorder = Recorder()
        let panel = makePanel(recorder)
        _ = panel.handlePreviewKey(try space())
        #expect(recorder.seen.first?.target == .cards)
    }

    @Test func aSearchFieldsEditorIsWhereTypingGoes() throws {
        let field = NSSearchField()
        let editor = NSTextView()
        // A field editor's delegate is the field it edits for.
        editor.setValue(field, forKey: "delegate")
        #expect(Keys.Target(responder: editor, isCards: { _ in true }) == .searchField)
        #expect(Keys.Target(responder: NSView(), isCards: { _ in true }) == .cards)
        // Another text field's editor (a password) is never the preview's.
        let other = NSTextView()
        other.setValue(NSTextField(), forKey: "delegate")
        #expect(Keys.Target(responder: other, isCards: { _ in true }) == nil)
        #expect(Keys.Target(responder: NSTextView(), isCards: { _ in true }) == nil)
        #expect(Keys.Target(responder: NSView(), isCards: { _ in false }) == nil)
        #expect(Keys.Target(responder: nil, isCards: { _ in true }) == .cards)
    }

    @Test func aTextViewThatHoldsMarkedTextIsSeenAsComposing() throws {
        let textView = NSTextView()
        #expect(!Keys.hasMarkedText(textView))
        textView.setMarkedText("ă", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(Keys.hasMarkedText(textView))
        #expect(!Keys.hasMarkedText(NSView()))
        #expect(!Keys.hasMarkedText(nil))
    }

    // MARK: The library window

    @Test func theLibraryWindowOffersKeysToThePreviewToo() throws {
        let recorder = Recorder()
        let window = makeLibraryWindow(recorder)
        let content = NSView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        window.contentView = content
        let cards = ClipboardLibraryKeyboard.KeyView()
        content.addSubview(cards)
        #expect(window.makeFirstResponder(cards))

        window.sendEvent(try space())
        #expect(recorder.seen.count == 1)
        #expect(recorder.seen.first?.key == Keys.Key(keyCode: 49, characters: " ", modifiers: []))
    }

    @Test func inTheLibraryOnlyTheCardsViewCountsAsCards() throws {
        let recorder = Recorder()
        let window = makeLibraryWindow(recorder)
        let content = NSView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        window.contentView = content
        let cards = ClipboardLibraryKeyboard.KeyView()
        content.addSubview(cards)

        #expect(window.makeFirstResponder(cards))
        _ = window.handlePreviewKey(try space())
        #expect(recorder.seen.last?.target == .cards)

        // Something else with the keyboard (a sidebar row, a button): the preview does not take keys there.
        let other = FocusableView()
        content.addSubview(other)
        #expect(window.makeFirstResponder(other))
        #expect(!window.handlePreviewKey(try space()))
        #expect(recorder.seen.count == 1)
    }

    @Test func aLibraryWindowWithNoModelOffersNothing() throws {
        let window = ClipboardLibraryWindowController(interface: NotchInterface()).makeWindow(AnyView(EmptyView()))
        #expect(window is ClipboardLibraryWindow)
        #expect(!(window as! ClipboardLibraryWindow).handlePreviewKey(try space()))
    }
}

/// A view that takes the keyboard, standing in for any control that is not the cards.
private final class FocusableView: NSView {
    override var acceptsFirstResponder: Bool { true }
}
