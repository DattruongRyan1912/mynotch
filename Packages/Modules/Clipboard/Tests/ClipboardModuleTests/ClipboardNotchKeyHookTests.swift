import AppKit
import Foundation
import SwiftUI
import Testing
@testable import ClipboardModule

/// The notch tab's key hook: it watches the notch's window while the tab is in it, and offers the preview only the keys typed into the
/// tab's search field. Windows are made and never shown, with a real search field as the first responder, and the key events are built and
/// handed over; no event is posted and no monitor is installed.
@Suite struct ClipboardNotchKeyHookTests {
    typealias Keys = ClipboardPreviewKeys

    final class FakeMonitor {
        private(set) var started = 0
        private(set) var stopped = 0
        private(set) var handler: (@MainActor (NSEvent) -> Bool)?

        var monitor: ClipboardPreviewKeyMonitor {
            ClipboardPreviewKeyMonitor(
                start: { [self] handler in
                    started += 1
                    self.handler = handler
                    return "token"
                },
                stop: { [self] token in
                    #expect(token as? String == "token")
                    stopped += 1
                }
            )
        }
    }

    /// A tab model with a card to show, and a window the hook is in.
    struct Fixture {
        let state = ClipboardState()
        let model: ClipboardTabPreviewModel
        let fake = FakeMonitor()
        let window: NSWindow
        let content = NSView(frame: CGRect(x: 0, y: 0, width: 400, height: 200))
        let hook: ClipboardNotchKeyHook.HookView

        init() {
            var history = ClipboardHistory()
            let item = ClipboardContent.text("Xin chào")
            history.add(item, hash: ClipboardContent.hash(of: item), source: (nil, nil), at: .now)
            state.history = history
            model = ClipboardTabPreviewModel(state: state)
            window = NSWindow(contentRect: content.frame, styleMask: [.borderless], backing: .buffered, defer: true)
            window.contentView = content
            hook = ClipboardNotchKeyHook.HookView(model: model, monitor: fake.monitor)
            hook.windowOfEvent = { [window] _ in window }
        }

        func putHookInWindow() {
            content.addSubview(hook)
        }

        /// A real search field with the keyboard, as the notch's has.
        func focusedSearchField() throws -> WindowReportingSearchField {
            let field = WindowReportingSearchField(frame: CGRect(x: 0, y: 0, width: 200, height: 24))
            content.addSubview(field)
            #expect(window.makeFirstResponder(field))
            return field
        }
    }

    func keyEvent(_ characters: String, code: UInt16, modifiers: NSEvent.ModifierFlags = [], type: NSEvent.EventType = .keyDown) throws -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: type, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: 0, context: nil,
            characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code
        ))
    }

    func space() throws -> NSEvent { try keyEvent(" ", code: 49) }

    // MARK: Watching

    @Test func itWatchesTheNotchsWindowOnlyWhileItIsInThatWindow() {
        let fixture = Fixture()
        #expect(fixture.fake.started == 0)
        #expect(!fixture.hook.isWatching)

        fixture.putHookInWindow()
        #expect(fixture.fake.started == 1)
        #expect(fixture.hook.isWatching)

        fixture.hook.removeFromSuperview()
        #expect(fixture.fake.stopped == 1)
        #expect(!fixture.hook.isWatching)
    }

    @Test func goingToAnotherWindowWatchesAgainAndStopsTheOldMonitorOnce() {
        let fixture = Fixture()
        fixture.putHookInWindow()
        let other = NSWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: true)
        other.contentView = NSView()
        other.contentView?.addSubview(fixture.hook)

        #expect(fixture.fake.started == 2)
        #expect(fixture.fake.stopped == 1)
        fixture.hook.stop()
        fixture.hook.stop()
        #expect(fixture.fake.stopped == 2)
    }

    @Test func aMonitorThatCouldNotBeInstalledIsNotRemoved() {
        var stopped = 0
        let model = ClipboardTabPreviewModel(state: ClipboardState())
        let hook = ClipboardNotchKeyHook.HookView(model: model, monitor: ClipboardPreviewKeyMonitor(start: { _ in nil }, stop: { _ in stopped += 1 }))
        let window = NSWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: true)
        window.contentView = NSView()
        window.contentView?.addSubview(hook)
        hook.stop()
        #expect(stopped == 0)
    }

    @Test func theModelIsToldWhichWindowIsTheNotchsWhileItIsThere() {
        let fixture = Fixture()
        #expect(fixture.model.hostWindow().id == nil)
        fixture.putHookInWindow()
        #expect(fixture.model.hostWindow().id == ObjectIdentifier(fixture.window))
        #expect(fixture.model.hostWindow().frame == fixture.window.frame)

        fixture.hook.removeFromSuperview()
        #expect(fixture.model.hostWindow().id == nil)
    }

    @Test func theHookTakesNoClicks() {
        let fixture = Fixture()
        fixture.putHookInWindow()
        #expect(fixture.hook.hitTest(NSPoint(x: 1, y: 1)) == nil)
    }

    // MARK: What is offered

    @Test func aSpaceTypedInTheSearchFieldOpensThePreviewAndNeverReachesTheField() throws {
        let fixture = Fixture()
        fixture.putHookInWindow()
        _ = try fixture.focusedSearchField()

        // The field editor is the first responder, and its delegate is the field: the notch's search.
        #expect(fixture.hook.offer(try space()))
        #expect(fixture.model.isPreviewOpen)
        #expect(fixture.hook.offer(try space()))
        #expect(!fixture.model.isPreviewOpen)
    }

    @Test func commandYAndEscapeAndTabAndReturnAreOfferedToo() throws {
        let fixture = Fixture()
        fixture.putHookInWindow()
        _ = try fixture.focusedSearchField()

        #expect(fixture.hook.offer(try keyEvent("y", code: 16, modifiers: .command)))
        #expect(fixture.model.isPreviewOpen)
        // Esc closes only the preview; with it closed Esc is not taken (the tab closes the notch with it).
        #expect(fixture.hook.offer(try keyEvent("\u{1B}", code: 53)))
        #expect(!fixture.model.isPreviewOpen)
        #expect(!fixture.hook.offer(try keyEvent("\u{1B}", code: 53)))
        #expect(!fixture.hook.offer(try keyEvent("\t", code: 48)))
    }

    @Test func aKeyThatIsNotThePreviewsIsLeftToTheField() throws {
        let fixture = Fixture()
        fixture.putHookInWindow()
        _ = try fixture.focusedSearchField()
        #expect(!fixture.hook.offer(try keyEvent("a", code: 0)))
        #expect(!fixture.hook.offer(try keyEvent(" ", code: 49, modifiers: .command)))
        #expect(!fixture.model.isPreviewOpen)
    }

    @Test func aSpaceWhileAnInputMethodIsComposingIsTheInputMethods() throws {
        let fixture = Fixture()
        fixture.putHookInWindow()
        let field = try fixture.focusedSearchField()
        let editor = try #require(field.currentEditor() as? NSTextView)
        editor.setMarkedText("ă", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(editor.hasMarkedText())

        #expect(!fixture.hook.offer(try space()))
        #expect(!fixture.model.isPreviewOpen)
    }

    /// The board's name, and the password of a locked board, are text fields of their own.
    @Test func aBoardNameOrAPasswordBeingTypedIsNeverTheSearch() throws {
        let fixture = Fixture()
        fixture.putHookInWindow()
        let name = NSTextField(frame: CGRect(x: 0, y: 40, width: 200, height: 24))
        fixture.content.addSubview(name)
        #expect(fixture.window.makeFirstResponder(name))
        #expect(name.currentEditor() != nil)

        #expect(!fixture.hook.offer(try space()))
        #expect(!fixture.hook.offer(try keyEvent("y", code: 16, modifiers: .command)))
        #expect(!fixture.model.isPreviewOpen)

        let password = NSSecureTextField(frame: CGRect(x: 0, y: 80, width: 200, height: 24))
        fixture.content.addSubview(password)
        #expect(fixture.window.makeFirstResponder(password))
        #expect(!fixture.hook.offer(try space()))
        #expect(!fixture.model.isPreviewOpen)
    }

    @Test func theBoardAndStackButtonsHavingTheKeyboardKeepTheirSpace() throws {
        let fixture = Fixture()
        fixture.putHookInWindow()
        let button = FocusableControl(frame: CGRect(x: 0, y: 120, width: 60, height: 22))
        fixture.content.addSubview(button)
        #expect(fixture.window.makeFirstResponder(button))

        // With nothing to type in, the notch's cards are not a key view either: a Space on a button presses the button.
        #expect(!fixture.hook.offer(try space()))
        #expect(!fixture.model.isPreviewOpen)
    }

    @Test func aKeyForAnotherWindowIsNotOffered() throws {
        let fixture = Fixture()
        fixture.putHookInWindow()
        _ = try fixture.focusedSearchField()
        let other = NSWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: true)
        fixture.hook.windowOfEvent = { _ in other }

        #expect(!fixture.hook.offer(try space()))
        #expect(!fixture.model.isPreviewOpen)
    }

    @Test func aKeyReleasedOrOfferedBeforeTheHookIsInAWindowIsNotTaken() throws {
        let fixture = Fixture()
        #expect(!fixture.hook.offer(try space()))
        fixture.putHookInWindow()
        _ = try fixture.focusedSearchField()
        #expect(!fixture.hook.offer(try keyEvent(" ", code: 49, type: .keyUp)))
        #expect(!fixture.model.isPreviewOpen)
    }

    @Test func theMonitorsHandlerIsTheHooksOffer() throws {
        let fixture = Fixture()
        fixture.putHookInWindow()
        _ = try fixture.focusedSearchField()
        #expect(try fixture.fake.handler?(space()) == true)
        #expect(fixture.model.isPreviewOpen)
    }
}

/// A control that takes the keyboard, standing in for the board and stack buttons.
private final class FocusableControl: NSView {
    override var acceptsFirstResponder: Bool { true }
}
