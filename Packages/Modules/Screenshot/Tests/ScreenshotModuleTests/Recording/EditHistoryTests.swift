import Testing
@testable import ScreenshotModule

@Suite struct EditHistoryTests {
    @Test func aChangeCanBeUndoneAndRedone() {
        var history = EditHistory(1)
        #expect(history.apply { $0 = 2 })
        #expect(history.apply { $0 = 3 })
        #expect(history.value == 3 && history.canUndo && !history.canRedo)
        #expect(history.undo() && history.value == 2)
        #expect(history.undo() && history.value == 1)
        #expect(!history.undo() && history.value == 1 && !history.canUndo)
        #expect(history.redo() && history.value == 2)
        #expect(history.redo() && history.value == 3)
        #expect(!history.redo() && !history.canRedo)
    }

    @Test func aNewChangeForgetsWhatCouldHaveBeenRedone() {
        var history = EditHistory(1)
        history.apply { $0 = 2 }
        history.undo()
        #expect(history.canRedo)
        history.apply { $0 = 5 }
        #expect(!history.canRedo)
        #expect(history.undo() && history.value == 1)
    }

    @Test func aChangeThatLeavesTheValueAsItWasIsNoStep() {
        var history = EditHistory(["a"])
        #expect(!history.apply { $0 = ["a"] })
        #expect(!history.canUndo)
        history.apply { $0.append("b") }
        #expect(!history.apply { _ in })
        #expect(history.undo() && history.value == ["a"])
    }

    @Test func optionalsComeBackAsNilNotAsEmpty() {
        var history = EditHistory<[Int]?>(nil)
        history.apply { $0 = [] }
        history.apply { $0 = [1] }
        history.undo()
        #expect(history.value == [])
        history.undo()
        #expect(history.value == nil)
    }
}
