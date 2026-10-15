import AppKit
import Testing
@testable import TranslationModule

/// How the system's events become `SelectionInput`. The events are made here and handed straight to the conversion: none is
/// posted, so nothing reaches any app, and no monitor is installed.
@Suite struct SelectionInputTests {
    func mouse(_ type: NSEvent.EventType, clicks: Int = 1) throws -> NSEvent {
        try #require(NSEvent.mouseEvent(
            with: type, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: clicks,
            pressure: 0
        ))
    }

    func key(_ type: NSEvent.EventType, code: UInt16, flags: NSEvent.ModifierFlags = []) throws -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: type, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil, characters: "",
            charactersIgnoringModifiers: "", isARepeat: false, keyCode: code
        ))
    }

    @Test(arguments: [NSEvent.EventType.leftMouseDown, .rightMouseDown, .otherMouseDown])
    func anyButtonGoingDownIsAPress(type: NSEvent.EventType) throws {
        guard case .mouseDown? = SelectionInput(try mouse(type)) else {
            Issue.record("not a press: \(type)")
            return
        }
    }

    @Test func aLeftReleaseCarriesItsClickCount() throws {
        for clicks in [1, 2, 3] {
            guard case .mouseUp(_, let counted)? = SelectionInput(try mouse(.leftMouseUp, clicks: clicks)) else {
                Issue.record("not a release")
                return
            }
            #expect(counted == clicks)
        }
    }

    @Test(arguments: [NSEvent.EventType.rightMouseUp, .otherMouseUp, .leftMouseDragged, .mouseMoved])
    func otherMouseEventsAreNotListenedTo(type: NSEvent.EventType) throws {
        #expect(SelectionInput(try mouse(type)) == nil)
    }

    @Test func aKeyUpKeepsOnlyTheKeyAndTheTwoModifiers() throws {
        guard case .keyUp(let press, _)? = SelectionInput(try key(.keyUp, code: 124, flags: [.shift, .capsLock])) else {
            Issue.record("not a key-up")
            return
        }
        #expect(press == KeyPress(code: 124, shift: true, command: false))
        guard case .keyUp(let other, _)? = SelectionInput(try key(.keyUp, code: 124, flags: [.option, .control])) else {
            Issue.record("not a key-up")
            return
        }
        #expect(other == KeyPress(code: 124, shift: false, command: false))
        guard case .keyUp(let selectAll, _)? = SelectionInput(try key(.keyUp, code: 0, flags: [.command])) else {
            Issue.record("not a key-up")
            return
        }
        #expect(selectAll == KeyPress(code: 0, shift: false, command: true))
        #expect(selectAll.changesSelection)
    }

    @Test func theMonitorListensToPressesAndReleasesAndToKeyUpsOnlyWhenAsked() {
        let withoutKeys = SystemSelectionInput.mask(keys: false)
        #expect(withoutKeys == [.leftMouseDown, .rightMouseDown, .otherMouseDown, .leftMouseUp])
        #expect(SystemSelectionInput.mask(keys: true) == withoutKeys.union(.keyUp))
        // Never moves, drags or key-downs.
        #expect(SystemSelectionInput.mask(keys: true).isDisjoint(with: [.mouseMoved, .leftMouseDragged, .keyDown, .flagsChanged]))
    }

    @Test func aKeyGoingDownIsNotListenedTo() throws {
        #expect(SelectionInput(try key(.keyDown, code: 124, flags: [.shift])) == nil)
    }
}
