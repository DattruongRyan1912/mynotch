import AppKit
import SwiftUI

/// The header's empty space, which drags the panel while it is pinned. A drag is the window's own, so it follows the
/// pointer exactly; the view reports where the panel ended up.
struct ClipboardPanelDragArea: NSViewRepresentable {
    let isEnabled: Bool
    let onEnd: (CGPoint) -> Void

    func makeNSView(context: Context) -> DragView {
        DragView()
    }

    func updateNSView(_ view: DragView, context: Context) {
        view.isEnabled = isEnabled
        view.onEnd = onEnd
    }

    final class DragView: NSView {
        var isEnabled = false
        var onEnd: ((CGPoint) -> Void)?

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            guard isEnabled, let window else {
                super.mouseDown(with: event)
                return
            }
            // Returns when the button is released.
            window.performDrag(with: event)
            onEnd?(window.frame.origin)
        }
    }
}
