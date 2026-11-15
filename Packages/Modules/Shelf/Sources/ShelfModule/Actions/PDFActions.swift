import AppKit
import CoreGraphics
import Foundation
import PDFKit

/// PDF: several images into one document (written page by page with Core Graphics), and a document back into one
/// image per page (PDFKit).
nonisolated enum PDFActions {
    /// An image that is bigger than this is fitted to an A4 page (in points) instead of making a huge page.
    static let maxPagePoints: Double = 842
    /// Each image is decoded at no more than twice its page, which is 144 dpi at the largest page and reads well on a
    /// Retina screen. It also keeps a 12-megapixel photo from costing 50 MB of memory for the whole run.
    static let maxImagePixels = Int(maxPagePoints * 2)
    /// Pages are drawn at twice their size in points, up to this many pixels.
    static let maxPagePixels = 4096
    /// A PDF with more pages than this is not split: every page becomes a file and a card, so an accident with a
    /// book would fill the folder and the shelf.
    static let maxSplitPages = 200

    struct Merged {
        let file: URL
        /// The images left out, with why; the document holds all the others.
        let skipped: [SkippedFile]
    }

    /// One PDF of `sources`, a page each in the order given, next to the first image that made a page, and named
    /// after it. Images that cannot be read are skipped, and with none left nothing is written. `quality` is the JPEG
    /// quality the pages are stored at.
    ///
    /// Pages are drawn one at a time: an image is decoded (by `loadImage`, which gets the longest side it may have),
    /// compressed, drawn and let go before the next is opened, so the memory the run needs does not grow with the
    /// number of images.
    static func makePDF(
        from sources: [URL], quality: Double, folders: OutputFolders,
        loadImage: (URL, Int) throws -> CGImage = { try ImageCodec.load($0, longestSide: $1).image }
    ) throws -> Merged {
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data), let pdf = CGContext(consumer: consumer, mediaBox: nil, nil) else {
            throw FileActionError.cannotWrite
        }
        var skipped: [SkippedFile] = []
        var firstUsed: URL?
        for source in sources {
            try Task.checkCancellation()
            do {
                let size = try ImageCodec.uprightSize(of: source)
                guard size.width >= 1, size.height >= 1 else { throw FileActionError.notAnImage }
                let scale = min(1, maxPagePoints / max(size.width, size.height))
                var page = CGRect(x: 0, y: 0, width: max(1, (size.width * scale).rounded()), height: max(1, (size.height * scale).rounded()))
                let image = jpegBacked(try loadImage(source, maxImagePixels), quality: quality)
                let info = [kCGPDFContextMediaBox as String: Data(bytes: &page, count: MemoryLayout<CGRect>.size)] as CFDictionary
                pdf.beginPDFPage(info)
                pdf.draw(image, in: page)
                pdf.endPDFPage()
                firstUsed = firstUsed ?? source
            } catch let error as FileActionError {
                skipped.append(SkippedFile(source: source, error: error))
            }
        }
        pdf.closePDF()
        guard let first = firstUsed else { throw FileActionError.noImages }
        try Task.checkCancellation()
        let file = try OutputNaming.place(
            stem: first.deletingPathExtension().lastPathComponent, suffix: nil, ext: "pdf", in: folders.folder(for: first)
        ) { try (data as Data).write(to: $0, options: .withoutOverwriting) }
        return Merged(file: file, skipped: skipped)
    }

    /// The picture as JPEG at `quality`, as an image that keeps those bytes, which the PDF then stores as they are:
    /// the quality setting decides the size, and the decoded pixels can be freed at once. (A transparent image is
    /// put on white, as JPEG has no transparency.) The picture itself when it cannot be done.
    private static func jpegBacked(_ image: CGImage, quality: Double) -> CGImage {
        guard let jpeg = try? ImageCodec.encode(image, as: .jpeg, quality: quality, properties: [:], stripLocation: true),
              let provider = CGDataProvider(data: jpeg as CFData),
              let backed = CGImage(jpegDataProviderSource: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        else { return image }
        return backed
    }

    /// One PNG per page, next to the PDF (`tài-liệu-trang-1.png`; `-01` when there are ten pages or more). All or
    /// nothing: a cancelled or failed split removes the pages it had written. `didWritePage` hears the number of
    /// pages written so far and how many there are. A PDF with more than `maxSplitPages` pages is refused.
    static func renderPages(of pdf: URL, folders: OutputFolders, didWritePage: (Int, Int) -> Void = { _, _ in }) throws -> [URL] {
        guard FileManager.default.fileExists(atPath: pdf.path) else { throw FileActionError.missing }
        guard FileManager.default.isReadableFile(atPath: pdf.path) else { throw FileActionError.unreadable }
        guard let document = PDFDocument(url: pdf) else { throw FileActionError.notPDF }
        guard !document.isLocked else { throw FileActionError.pdfLocked }
        guard document.pageCount > 0 else { throw FileActionError.pdfEmpty }
        guard document.pageCount <= maxSplitPages else { throw FileActionError.tooManyPages(count: document.pageCount, limit: maxSplitPages) }

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
                didWritePage(written.count, document.pageCount)
            }
        } catch {
            for url in written { try? FileManager.default.removeItem(at: url) }
            throw error
        }
        return written
    }

    /// The page on white paper, as a viewer shows it: within its crop box, and turned when the page says so.
    private static func render(_ page: PDFPage) -> CGImage? {
        let box = page.bounds(for: .cropBox)
        let isTurned = page.rotation % 180 != 0
        let points = isTurned ? CGSize(width: box.height, height: box.width) : box.size
        let scale = min(2, Double(maxPagePixels) / max(points.width, points.height))
        let size = CGSize(width: max(1, (points.width * scale).rounded()), height: max(1, (points.height * scale).rounded()))
        return page.thumbnail(of: size, for: .cropBox).cgImage(forProposedRect: nil, context: nil, hints: nil)
    }
}
