import AppKit

/// The pasteboard the monitor polls and the paster writes, behind a protocol so both are testable without `NSPasteboard`.
protocol PasteboardAccess: AnyObject {
    /// Changes on every write by any app; cheap to poll, unlike reading the content.
    var changeCount: Int { get }
    /// The first item's types and data plus the file URLs of every item; nil when the pasteboard is empty.
    func snapshot() -> PasteboardSnapshot?
    /// Replaces the content and always adds `ClipboardClassifier.ownWriteType`, so the monitor skips the write.
    /// `plainTextOnly` drops the RTF of rich text.
    func write(_ content: ClipboardContent, imageURL: URL?, plainTextOnly: Bool)
}

/// `PasteboardAccess` on an `NSPasteboard`; tests pass a private named pasteboard instead of `.general`.
final class SystemPasteboard: PasteboardAccess {
    private static let marker = NSPasteboard.PasteboardType(ClipboardClassifier.ownWriteType)

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

    func write(_ content: ClipboardContent, imageURL: URL?, plainTextOnly: Bool) {
        pasteboard.clearContents()
        if case .files(let urls) = content {
            // NSURL writes the types Finder and other apps expect for every file; the marker goes on the first item.
            pasteboard.writeObjects(urls.map { $0 as NSURL })
            pasteboard.pasteboardItems?.first?.setData(Data(), forType: Self.marker)
            return
        }
        let item = NSPasteboardItem()
        item.setData(Data(), forType: Self.marker)
        switch content {
        case .text(let text):
            item.setString(text, forType: .string)
        case .richText(let plain, let rtf):
            item.setString(plain, forType: .string)
            if !plainTextOnly { item.setData(rtf, forType: .rtf) }
        case .link(let url):
            item.setString(url.absoluteString, forType: .URL)
            item.setString(url.absoluteString, forType: .string)
        case .color(let hex):
            item.setString(hex, forType: .string)
        case .image:
            if let png = imageURL.flatMap({ try? Data(contentsOf: $0) }) { item.setData(png, forType: .png) }
        case .files:
            break
        }
        pasteboard.writeObjects([item])
    }
}
