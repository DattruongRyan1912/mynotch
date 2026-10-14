import AppKit

/// Everything on a pasteboard, copied so it can be put back after a temporary write.
struct PasteboardBackup {
    private let items: [[(NSPasteboard.PasteboardType, Data)]]

    init(_ pasteboard: NSPasteboard) {
        items = (pasteboard.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
        }
    }

    /// Replaces the pasteboard's content with the copy, every type of every item. `marker` goes on the first item, so
    /// that clipboard history, which already holds this content, does not record it again.
    func restore(to pasteboard: NSPasteboard, marking marker: NSPasteboard.PasteboardType) {
        let restored = items.map { entries in
            let item = NSPasteboardItem()
            for (type, data) in entries { item.setData(data, forType: type) }
            return item
        }
        restored.first?.setData(Data(), forType: marker)
        pasteboard.clearContents()
        pasteboard.writeObjects(restored)
    }
}
