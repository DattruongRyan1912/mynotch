import AppKit

/// What a card carries when dragged out of the notch.
enum ClipboardDragProvider {
    /// `fileURLs` are the item's stored image or copied files. A SwiftUI drag carries one item provider, which holds
    /// one file URL, so an item of several files drags its first one.
    static func make(for content: ClipboardContent, fileURLs: [URL]) -> NSItemProvider {
        switch content {
        case .text(let text), .richText(let text, _), .color(let text):
            NSItemProvider(object: text as NSString)
        case .link(let url):
            NSItemProvider(object: url as NSURL)
        case .image, .files:
            fileURLs.first.map { NSItemProvider(object: $0 as NSURL) } ?? NSItemProvider()
        }
    }
}
