import AppKit

/// The image under the pointer while a card is dragged out.
nonisolated enum ShelfDragPreview {
    /// `source` drawn into a square of `side` points. AppKit calls the drawing handler of such an image on whatever thread the
    /// image is drawn on, so it is made here, where the handler is not main-actor isolated: an isolated one traps off the main thread.
    static func image(of source: NSImage, side: CGFloat = 40) -> NSImage {
        NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            source.draw(in: rect)
            return true
        }
    }
}
