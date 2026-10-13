import AppKit
import Testing
@testable import ClipboardModule

@Suite struct ClipboardKeyCommandTests {
    @Test func upAndDownAlwaysMoveTheSelection() {
        for searchIsEmpty in [true, false] {
            #expect(ClipboardKeyCommand(#selector(NSResponder.moveDown(_:)), searchIsEmpty: searchIsEmpty) == .next)
            #expect(ClipboardKeyCommand(#selector(NSResponder.moveUp(_:)), searchIsEmpty: searchIsEmpty) == .previous)
        }
    }

    @Test func leftAndRightMoveTheSelectionOnlyWhileTheSearchIsEmpty() {
        #expect(ClipboardKeyCommand(#selector(NSResponder.moveRight(_:)), searchIsEmpty: true) == .next)
        #expect(ClipboardKeyCommand(#selector(NSResponder.moveLeft(_:)), searchIsEmpty: true) == .previous)
        #expect(ClipboardKeyCommand(#selector(NSResponder.moveRight(_:)), searchIsEmpty: false) == nil)
        #expect(ClipboardKeyCommand(#selector(NSResponder.moveLeft(_:)), searchIsEmpty: false) == nil)
    }

    @Test func returnActivatesAndEscClearsTheSearchBeforeClosing() {
        #expect(ClipboardKeyCommand(#selector(NSResponder.insertNewline(_:)), searchIsEmpty: true) == .activate)
        #expect(ClipboardKeyCommand(#selector(NSResponder.cancelOperation(_:)), searchIsEmpty: false) == .clearSearch)
        #expect(ClipboardKeyCommand(#selector(NSResponder.cancelOperation(_:)), searchIsEmpty: true) == .close)
    }

    @Test func otherKeysStayWithTheField() {
        #expect(ClipboardKeyCommand(#selector(NSResponder.deleteBackward(_:)), searchIsEmpty: false) == nil)
        #expect(ClipboardKeyCommand(#selector(NSResponder.insertTab(_:)), searchIsEmpty: true) == nil)
        #expect(ClipboardKeyCommand(#selector(NSResponder.moveToBeginningOfLine(_:)), searchIsEmpty: false) == nil)
    }
}
