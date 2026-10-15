import AppKit
import Foundation
import PDFKit

/// PDF with PDFKit: several images into one document, and a document back into one image per page.
nonisolated enum PDFActions {
    /// An image that is bigger than this is fitted to an A4 page (in points) instead of making a huge page.
    static let maxPagePoints: Double = 842
    /// Pages are drawn at twice their size in points, which reads well on a Retina screen, up to this many pixels.
    static let maxPagePixels = 4096

    struct Merged {
        let file: URL
        /// The images left out, with why; the document holds all the others.
        let skipped: [SkippedFile]
    }

    /// One PDF of `sources`, a page each in the order given, next to the first. Images that cannot be read are
    /// skipped, and with none left nothing is written. `quality` is the JPEG quality the pages are stored at.
    static func makePDF(from sources: [URL], quality: Double, folders: OutputFolders) throws -> Merged {
        let document = PDFDocument()
        var skipped: [SkippedFile] = []
        for source in sources {
            try Task.checkCancellation()
            do {
                let loaded = try ImageCodec.load(source, longestSide: nil)
                let width = Double(loaded.image.width), height = Double(loaded.image.height)
                let scale = min(1, maxPagePoints / max(width, height))
                let size = NSSize(width: max(1, (width * scale).rounded()), height: max(1, (height * scale).rounded()))
                // The image's size in points does not set the page's; the media box does.
                let options: [PDFPage.ImageInitializationOption: Any] = [
                    .compressionQuality: quality, .mediaBox: NSValue(rect: CGRect(origin: .zero, size: size)),
                ]
                guard let page = PDFPage(image: NSImage(cgImage: loaded.image, size: size), options: options) else { throw FileActionError.notAnImage }
                document.insert(page, at: document.pageCount)
            } catch let error as FileActionError {
                skipped.append(SkippedFile(source: source, error: error))
            }
        }
        guard document.pageCount > 0, let first = sources.first, let data = document.dataRepresentation() else { throw FileActionError.noImages }
        try Task.checkCancellation()
        let file = try OutputNaming.place(
            stem: first.deletingPathExtension().lastPathComponent, suffix: nil, ext: "pdf", in: folders.folder(for: first)
        ) { try data.write(to: $0, options: .withoutOverwriting) }
        return Merged(file: file, skipped: skipped)
    }

    /// One PNG per page, next to the PDF (`tài-liệu-trang-1.png`; `-01` when there are ten pages or more). All or
    /// nothing: a cancelled or failed split removes the pages it had written. `didWritePage` hears the number of
    /// pages written so far.
    static func renderPages(of pdf: URL, folders: OutputFolders, didWritePage: (Int) -> Void = { _ in }) throws -> [URL] {
        guard FileManager.default.fileExists(atPath: pdf.path) else { throw FileActionError.missing }
        guard FileManager.default.isReadableFile(atPath: pdf.path) else { throw FileActionError.unreadable }
        guard let document = PDFDocument(url: pdf) else { throw FileActionError.notPDF }
        guard !document.isLocked else { throw FileActionError.pdfLocked }
        guard document.pageCount > 0 else { throw FileActionError.pdfEmpty }

        let stem = pdf.deletingPathExtension().lastPathComponent
        let digits = String(document.pageCount).count
        var written: [URL] = []
        do {
            for index in 0..<document.pageCount {
                try Task.checkCancellation()
                guard let page = document.page(at: index), let image = render(page) else { throw FileActionError.notPDF }
                let data = try ImageCodec.encode(image, as: .png, quality: 1, properties: [:], stripLocation: true)
                let number = String(format: "%0\(digits)d", index + 1)
                written.append(try OutputNaming.place(stem: stem, suffix: "trang-\(number)", ext: "png", in: folders.folder(for: pdf)) {
                    try data.write(to: $0, options: .withoutOverwriting)
                })
                didWritePage(written.count)
            }
        } catch {
            for url in written { try? FileManager.default.removeItem(at: url) }
            throw error
        }
        return written
    }

    /// The page on white paper, as it is shown: turned when the page says so.
    private static func render(_ page: PDFPage) -> CGImage? {
        let box = page.bounds(for: .mediaBox)
        let isTurned = page.rotation % 180 != 0
        let points = isTurned ? CGSize(width: box.height, height: box.width) : box.size
        let scale = min(2, Double(maxPagePixels) / max(points.width, points.height))
        let size = CGSize(width: max(1, (points.width * scale).rounded()), height: max(1, (points.height * scale).rounded()))
        return page.thumbnail(of: size, for: .mediaBox).cgImage(forProposedRect: nil, context: nil, hints: nil)
    }
}
