import AppKit

/// The pasteboard the monitor polls and the paster writes, behind a protocol so both are testable without `NSPasteboard`.
protocol PasteboardAccess: AnyObject {
    /// Changes on every write by any app; cheap to poll, unlike reading the content.
    var changeCount: Int { get }
    /// The first item's types and data plus the file URLs of every item; nil when the pasteboard is empty.
    func snapshot() -> PasteboardSnapshot?
    /// Replaces the content and always adds `ClipboardClassifier.ownWriteType`, so the monitor skips the write.
    /// `plainTextOnly` drops the RTF of rich text; `sourceBundleID` tells other clipboard managers where the item came from.
    /// Returns false and leaves the user's clipboard untouched when the content cannot be written (missing image, no files).
    @discardableResult
    func write(_ content: ClipboardContent, imageURL: URL?, plainTextOnly: Bool, sourceBundleID: String?) -> Bool
}

extension PasteboardAccess {
    @discardableResult
    func write(_ content: ClipboardContent, imageURL: URL?, plainTextOnly: Bool) -> Bool {
        write(content, imageURL: imageURL, plainTextOnly: plainTextOnly, sourceBundleID: nil)
    }
}

/// `PasteboardAccess` on an `NSPasteboard`; tests pass a private named pasteboard instead of `.general`.
final class SystemPasteboard: PasteboardAccess {
    private static let marker = NSPasteboard.PasteboardType(ClipboardClassifier.ownWriteType)
    /// nspasteboard.org convention naming the app the content came from.
    private static let source = NSPasteboard.PasteboardType("org.nspasteboard.source")

    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    var changeCount: Int { pasteboard.changeCount }

    func snapshot() -> PasteboardSnapshot? {
        guard let item = pasteboard.pasteboardItems?.first else { return nil }
        let png = item.data(forType: .png)
        let fileURLs = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
        return PasteboardSnapshot(
            types: item.types.map(\.rawValue),
            string: item.string(forType: .string),
            rtf: item.data(forType: .rtf),
            png: png,
            // Only the classifier's fallback uses TIFF, and screenshots can make it very large.
            tiff: png == nil ? item.data(forType: .tiff) : nil,
            fileURLs: fileURLs ?? [],
            url: item.string(forType: .URL).flatMap(URL.init(string:))
        )
    }

    @discardableResult
    func write(_ content: ClipboardContent, imageURL: URL?, plainTextOnly: Bool, sourceBundleID: String?) -> Bool {
        // Items are complete, markers included, before the clipboard is cleared, so a failure leaves it as it was.
        guard let items = Self.items(for: content, imageURL: imageURL, plainTextOnly: plainTextOnly),
              let first = items.first else { return false }
        first.setData(Data(), forType: Self.marker)
        if let sourceBundleID { first.setString(sourceBundleID, forType: Self.source) }
        pasteboard.clearContents()
        return pasteboard.writeObjects(items)
    }

    /// One item per file so multi-file copies paste whole, one item for everything else; nil for an unreadable image.
    private static func items(for content: ClipboardContent, imageURL: URL?, plainTextOnly: Bool) -> [NSPasteboardItem]? {
        let item = NSPasteboardItem()
        switch content {
        case .text(let text):
            item.setString(text, forType: .string)
        case .richText(let plain, let rtf):
            item.setString(plain, forType: .string)
            if !plainTextOnly { item.setData(rtf, forType: .rtf) }
        case .link(let url):
            item.setString(url.absoluteString, forType: .URL)
            item.setString(url.absoluteString, forType: .string)
        case .color(let hex, let original):
            item.setString(original ?? hex, forType: .string)
        case .image:
            guard let png = imageURL.flatMap({ try? Data(contentsOf: $0) }), !png.isEmpty else { return nil }
            item.setData(png, forType: .png)
        case .files(let urls):
            // The same `public.file-url` items `NSURL` writes, built here so the first can carry the markers.
            return urls.map { url in
                let fileItem = NSPasteboardItem()
                fileItem.setString(url.absoluteString, forType: .fileURL)
                return fileItem
            }
        }
        return [item]
    }
}
