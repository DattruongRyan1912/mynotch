import AppKit
import Dispatch
import Testing
@testable import ShelfModule

/// AppKit draws the preview of a drag on whatever thread it likes, so drawing it must work off the main thread.
@Suite struct ShelfDragPreviewTests {
    @Test func thePreviewIsDrawnToASquareOfTheGivenSide() {
        let source = NSImage(systemSymbolName: "link", accessibilityDescription: nil) ?? NSImage()
        let preview = ShelfDragPreview.image(of: source, side: 24)
        #expect(preview.size == NSSize(width: 24, height: 24))
        #expect(preview.tiffRepresentation?.isEmpty == false)
    }

    @Test func thePreviewCanBeDrawnOnAnotherThread() async {
        let preview = ShelfDragPreview.image(
            of: NSImage(systemSymbolName: "text.alignleft", accessibilityDescription: nil) ?? NSImage())
        let bytes = await withCheckedContinuation { (done: CheckedContinuation<Int, Never>) in
            DispatchQueue.global().async {
                done.resume(returning: preview.tiffRepresentation?.count ?? 0)
            }
        }
        #expect(bytes > 0)
    }
}
