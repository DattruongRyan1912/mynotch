import CoreGraphics
import Testing
@testable import ScreenshotModule

@Suite struct EditorClosingTests {
    let saved = MarkupDocument(imageSize: CGSize(width: 4, height: 3))
    var edited: MarkupDocument {
        var document = saved
        document.annotations.append(.redact(CGRect(x: 0, y: 0, width: 2, height: 2)))
        return document
    }

    @Test func unsavedChangesNeedConfirmation() {
        #expect(EditorClosing.needsConfirmation(current: edited, saved: saved, closesWithoutAsking: false))
    }

    @Test func anUnchangedEditorClosesWithoutAsking() {
        #expect(!EditorClosing.needsConfirmation(current: saved, saved: saved, closesWithoutAsking: false))
    }

    @Test func aSettledCloseNeverAsks() {
        #expect(!EditorClosing.needsConfirmation(current: edited, saved: saved, closesWithoutAsking: true))
    }

    @Test func theWindowClosesAfterASaveOfWhatTheEditorShows() {
        #expect(EditorClosing.shouldCloseAfterSave(saved: edited, current: edited))
    }

    @Test func editsMadeWhileSavingKeepTheWindowOpen() {
        // The save wrote `saved`; closing would lose what was added since.
        #expect(!EditorClosing.shouldCloseAfterSave(saved: saved, current: edited))
    }

    @Test func editsMadeAfterASaveStillNeedConfirmation() {
        // The saved document is what the save wrote, not what the editor shows now.
        #expect(EditorClosing.needsConfirmation(current: edited, saved: saved, closesWithoutAsking: false))
        #expect(!EditorClosing.needsConfirmation(current: edited, saved: edited, closesWithoutAsking: false))
    }
}
