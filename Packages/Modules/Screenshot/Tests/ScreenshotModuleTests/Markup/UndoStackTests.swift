import CoreGraphics
import Testing
@testable import ScreenshotModule

@Suite struct UndoStackTests {
    let empty = MarkupDocument(imageSize: CGSize(width: 100, height: 80))
    let first = Annotation.redact(CGRect(x: 1, y: 1, width: 10, height: 10))
    let second = Annotation.redact(CGRect(x: 20, y: 20, width: 10, height: 10))
    let third = Annotation.redact(CGRect(x: 40, y: 40, width: 10, height: 10))

    func adding(_ annotation: Annotation, to stack: inout UndoStack) {
        stack.apply { $0.annotations.append(annotation) }
    }

    @Test func startsWithNothingToUndoOrRedo() {
        let stack = UndoStack(empty)
        #expect(stack.document == empty)
        #expect(!stack.canUndo)
        #expect(!stack.canRedo)
    }

    @Test func undoAndRedoStepThroughEdits() {
        var stack = UndoStack(empty)
        adding(first, to: &stack)
        adding(second, to: &stack)
        #expect(stack.document.annotations == [first, second])
        #expect(stack.canUndo && !stack.canRedo)

        stack.undo()
        #expect(stack.document.annotations == [first])
        #expect(stack.canUndo && stack.canRedo)
        stack.undo()
        #expect(stack.document == empty)
        #expect(!stack.canUndo && stack.canRedo)

        stack.redo()
        #expect(stack.document.annotations == [first])
        stack.redo()
        #expect(stack.document.annotations == [first, second])
        #expect(stack.canUndo && !stack.canRedo)
    }

    @Test func newEditClearsRedo() {
        var stack = UndoStack(empty)
        adding(first, to: &stack)
        adding(second, to: &stack)
        stack.undo()
        adding(third, to: &stack)
        #expect(stack.document.annotations == [first, third])
        #expect(!stack.canRedo)
        stack.redo()
        #expect(stack.document.annotations == [first, third])
        stack.undo()
        #expect(stack.document.annotations == [first])
    }

    @Test func undoAndRedoBeyondTheEndsDoNothing() {
        var stack = UndoStack(empty)
        stack.undo()
        stack.redo()
        #expect(stack.document == empty)
        adding(first, to: &stack)
        stack.redo()
        #expect(stack.document.annotations == [first])
        stack.undo()
        stack.undo()
        #expect(stack.document == empty)
        #expect(!stack.canUndo)
    }

    @Test func editThatChangesNothingAddsNoStep() {
        var stack = UndoStack(empty)
        adding(first, to: &stack)
        stack.undo()
        stack.apply { _ in }
        #expect(!stack.canUndo)
        #expect(stack.canRedo)
    }
}
