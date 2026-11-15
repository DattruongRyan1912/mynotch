import AppKit
import QuickLookUI
import SwiftUI

/// Quick Look's own view of one file already on disk, inside the preview's panel. The panel never becomes key, and this view
/// does not ask it to: Quick Look draws in a service of its own and only reads the file. `close()` runs when the view goes,
/// as Quick Look asks, so nothing of the file stays held.
struct ClipboardQuickLookView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .normal) ?? QLPreviewView()
        view.autostarts = true
        view.shouldCloseWithWindow = true
        view.previewItem = url as NSURL
        return view
    }

    func updateNSView(_ view: QLPreviewView, context: Context) {
        if (view.previewItem as? NSURL) as URL? != url { view.previewItem = url as NSURL }
    }

    static func dismantleNSView(_ view: QLPreviewView, coordinator: ()) {
        view.close()
    }
}
