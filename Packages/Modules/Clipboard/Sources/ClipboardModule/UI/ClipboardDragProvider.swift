import AppKit

/// What a card carries when dragged out of the notch. SwiftUI's drag source offers only the copy operation, so a drop
/// never moves the copied files a card names; stored images are dragged as a copy under a readable name all the same.
nonisolated enum ClipboardDragProvider {
    /// Each image drag gets its own folder here. The system's cleanup of temporary files removes them later: a drop
    /// target may read the file after the drop, and on APFS a copy shares the stored file's blocks.
    static let imageCopiesDirectory = FileManager.default.temporaryDirectory
        .appending(path: "MyNotch Clipboard Drags", directoryHint: .isDirectory)

    /// `fileURLs` are the image's drag copy or the copied files. A SwiftUI drag carries one item provider, which holds
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
