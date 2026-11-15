import AppKit
import UniformTypeIdentifiers

/// What a card or a row carries when dragged out of the notch, the library or the floating panel, which all use this one. SwiftUI's
/// drag source offers only the copy operation, so a drop never moves the copied files a card names; stored images are dragged as a
/// copy under a readable name all the same. Each kind carries the forms a drop target may want, in the order it should prefer them:
/// - text and a colour: the string (a colour as the text it was copied as);
/// - rich text: RTF, then the plain text, so a target that takes only text still gets it;
/// - a link: the URL, then the address as a string, for a text box that does not take URLs;
/// - a file: its file URL;
/// - an image: the file URL of its copy, then the PNG data (read only when a target asks for it), for targets that take a file and
///   for those that take a picture. A picture of an open locked board is a file made only if a target asks (`openImageDragProvider`).
nonisolated enum ClipboardDragProvider {
    /// Each image drag gets its own folder here. The system's cleanup of temporary files removes them later: a drop
    /// target may read the file after the drop, and on APFS a copy shares the stored file's blocks.
    static let imageCopiesDirectory = FileManager.default.temporaryDirectory
        .appending(path: "MyNotch Clipboard Drags", directoryHint: .isDirectory)

    /// `fileURLs` are the image's drag copy or the copied files. A SwiftUI drag carries one item provider, which holds
    /// one file URL, so an item of several files drags its first one.
    static func make(for content: ClipboardContent, fileURLs: [URL]) -> NSItemProvider {
        switch content {
        case .text, .color:
            return NSItemProvider(object: (content.plainText ?? "") as NSString)
        case .richText(let plain, let rtf):
            let provider = NSItemProvider()
            // An empty RTF is no RTF: a target would paste nothing at all from it.
            if !rtf.isEmpty {
                provider.registerDataRepresentation(forTypeIdentifier: UTType.rtf.identifier, visibility: .all) { completion in
                    completion(rtf, nil)
                    return nil
                }
            }
            provider.registerObject(plain as NSString, visibility: .all)
            return provider
        case .link(let url):
            let provider = NSItemProvider(object: url as NSURL)
            provider.registerObject(url.absoluteString as NSString, visibility: .all)
            return provider
        case .image:
            guard let url = fileURLs.first else { return NSItemProvider() }
            let provider = NSItemProvider(object: url as NSURL)
            // Read when a target asks, not now: a drag that starts and is dropped on a file target never holds the picture in memory.
            provider.registerDataRepresentation(forTypeIdentifier: UTType.png.identifier, visibility: .all) { completion in
                do {
                    completion(try Data(contentsOf: url), nil)
                } catch {
                    completion(nil, error)
                }
                return nil
            }
            return provider
        case .files:
            return fileURLs.first.map { NSItemProvider(object: $0 as NSURL) } ?? NSItemProvider()
        }
    }

    /// "Ảnh clipboard 2026-10-14 00.37.10.png", from when the image was copied.
    static func imageFileName(copiedAt: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return "Ảnh clipboard \(formatter.string(from: copiedAt)).png"
    }

    /// Copies a stored image into a new folder of `directory`, so the drop target never sees the stored file (named by
    /// its hash) and two drags of images copied in the same second never collide.
    static func copyImage(at url: URL, copiedAt: Date, into directory: URL = imageCopiesDirectory) throws -> URL {
        let folder = directory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let copy = folder.appending(path: imageFileName(copiedAt: copiedAt), directoryHint: .notDirectory)
        try FileManager.default.copyItem(at: url, to: copy)
        return copy
    }
}
