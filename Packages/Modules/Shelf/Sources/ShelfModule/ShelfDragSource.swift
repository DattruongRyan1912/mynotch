import AppKit
import NotchUI
import SwiftUI

/// What to do with a card once its drag session has ended.
nonisolated enum ShelfDragOutcome {
    /// Only a drag that a destination accepted (its operation is not empty) takes the card off the shelf. Esc, or a
    /// drop on something that refuses it, ends with no operation, and the card may be the only copy of a text or of
    /// a promised file.
    static func removesCard(operation: NSDragOperation, removeAfterDragOut: Bool) -> Bool {
        removeAfterDragOut && !operation.isEmpty
    }
}

/// The source side of one card drag. It keeps itself alive until the session reports its end, so the notch hears
/// about it even when the card has gone from the shelf meanwhile.
final class ShelfDragSession: NSObject, NSDraggingSource {
    /// A copy or a link: the destination never gets to move or delete what the shelf keeps.
    static let allowedOperations: NSDragOperation = [.copy, .link, .generic]

    private let onEnd: (NSDragOperation) -> Void
    private var keepAlive: ShelfDragSession?

    init(onEnd: @escaping (NSDragOperation) -> Void) {
        self.onEnd = onEnd
        super.init()
        keepAlive = self
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        Self.allowedOperations
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        finish(operation: operation)
    }

    /// Reports the end once; `operation` is empty when the drag was cancelled or refused.
    func finish(operation: NSDragOperation) {
        guard keepAlive != nil else { return }
        keepAlive = nil
        onEnd(operation)
    }
}

/// A transparent layer over a card that starts a real AppKit drag session. SwiftUI's `onDrag` cannot say how a drag
/// ended, and the shelf must not remove a card the user cancelled.
final class ShelfDragSourceView: NSView {
    var writer: () -> (any NSPasteboardWriting)? = { nil }
    var image: () -> NSImage = { NSImage() }
    var onOpen: () -> Void = {}
    var onBegin: () -> Void = {}
    var onEnd: (NSDragOperation) -> Void = { _ in }

    private var pressedAt: NSPoint?

    /// Only a plain left press belongs to this layer; right and control clicks (the context menu) and scrolling go to
    /// the SwiftUI view underneath.
    static func takes(_ event: NSEvent?) -> Bool {
        guard let event, event.type == .leftMouseDown else { return false }
        return !event.modifierFlags.contains(.control)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        Self.takes(NSApp.currentEvent) ? super.hitTest(point) : nil
    }

    /// The notch is never the active window, and a card must still be draggable at the first press.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override var mouseDownCanMoveWindow: Bool { false }

    override func mouseDown(with event: NSEvent) {
        pressedAt = event.locationInWindow
        if event.clickCount == 2 { onOpen() }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = pressedAt, hypot(event.locationInWindow.x - start.x, event.locationInWindow.y - start.y) >= 4,
              let writer = writer() else { return }
        pressedAt = nil
        let preview = image()
        let center = convert(event.locationInWindow, from: nil)
        let item = NSDraggingItem(pasteboardWriter: writer)
        item.setDraggingFrame(
            NSRect(x: center.x - preview.size.width / 2, y: center.y - preview.size.height / 2, width: preview.size.width, height: preview.size.height),
            contents: preview
        )
        onBegin()
        beginDraggingSession(with: [item], event: event, source: ShelfDragSession(onEnd: onEnd))
    }
}

/// Puts `ShelfDragSourceView` over a card and wires it to the shelf and to the notch's drag mode.
struct ShelfCardDragSource: NSViewRepresentable {
    let item: ShelfItem
    let module: ShelfModule
    let image: () -> NSImage

    func makeNSView(context: Context) -> ShelfDragSourceView { ShelfDragSourceView() }

    /// The closures are replaced on every update; the one a drag was started with is the one that ends it.
    func updateNSView(_ view: ShelfDragSourceView, context: Context) {
        let notch = context.environment.notch, module = module, item = item
        view.writer = { module.dragWriter(for: item) }
        view.image = image
        view.onOpen = { module.open(item) }
        view.onBegin = { notch.setDragging(true) }
        view.onEnd = { operation in
            notch.setDragging(false)
            module.didDragEnd(item, operation: operation)
        }
    }
}
