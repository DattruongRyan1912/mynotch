import AppKit
import Foundation
import PDFKit
import Testing
import UniformTypeIdentifiers
@testable import ShelfModule

@Suite struct PDFActionTests {
    let folders = OutputFolders(promisedDirectory: nil)

    func image(_ name: String, _ width: Int, _ height: Int, in folder: URL) throws -> URL {
        try SyntheticFiles.write(SyntheticFiles.image(width: width, height: height), as: .png, named: name, in: folder)
    }

    // MARK: Images to one PDF

    @Test func severalImagesBecomeOnePDFWithAPageEachInTheOrderGiven() throws {
        let folder = try makeTempDirectory()
        let urls = [try image("một.png", 300, 200, in: folder), try image("hai.png", 200, 300, in: folder), try image("ba.png", 100, 100, in: folder)]
        let result = try PDFActions.makePDF(from: urls, quality: 0.85, folders: folders)
        #expect(result.file.lastPathComponent == "một.pdf")
        #expect(result.file.deletingLastPathComponent() == folder)
        #expect(result.skipped.isEmpty)
        let document = try #require(PDFDocument(url: result.file))
        #expect(document.pageCount == 3)
        let sizes = (0..<3).map { document.page(at: $0)!.bounds(for: .mediaBox).size }
        #expect(sizes[0].width > sizes[0].height)
        #expect(sizes[1].height > sizes[1].width)
        #expect(abs(sizes[2].width - sizes[2].height) < 1)
    }

    @Test func aLargePhotoIsFittedToAPageInsteadOfBecomingAHugeOne() throws {
        let folder = try makeTempDirectory()
        let url = try image("lớn.png", 3000, 2000, in: folder)
        let result = try PDFActions.makePDF(from: [url], quality: 0.85, folders: folders)
        let size = try #require(PDFDocument(url: result.file)?.page(at: 0)?.bounds(for: .mediaBox).size)
        #expect(max(size.width, size.height) <= 842.5)
        #expect(abs(size.width / size.height - 1.5) < 0.01)
    }

    @Test func aSmallImageKeepsItsSize() throws {
        let folder = try makeTempDirectory()
        let result = try PDFActions.makePDF(from: [try image("nhỏ.png", 120, 80, in: folder)], quality: 0.85, folders: folders)
        let size = try #require(PDFDocument(url: result.file)?.page(at: 0)?.bounds(for: .mediaBox).size)
        #expect(abs(size.width - 120) < 1 && abs(size.height - 80) < 1)
    }

    @Test func anImageThatCannotBeReadIsSkippedAndTheRestStillMakeThePDF() throws {
        let folder = try makeTempDirectory()
        let good = try image("tốt.png", 50, 50, in: folder)
        let bad = try makeTempFile(named: "hỏng.png", in: folder)
        let gone = folder.appending(path: "mất.png")
        let result = try PDFActions.makePDF(from: [bad, good, gone], quality: 0.85, folders: folders)
        #expect(PDFDocument(url: result.file)?.pageCount == 1)
        #expect(result.skipped.map(\.source) == [bad, gone])
        #expect(result.skipped.map(\.error) == [.notAnImage, .missing])
    }

    @Test func withNoReadableImageNothingIsWritten() throws {
        let folder = try makeTempDirectory()
        let bad = try makeTempFile(named: "hỏng.png", in: folder)
        #expect(throws: FileActionError.noImages) { try PDFActions.makePDF(from: [bad], quality: 0.85, folders: folders) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["hỏng.png"])
    }

    @Test func neverReplacesAPDFThatIsThere() throws {
        let folder = try makeTempDirectory()
        let url = try image("a.png", 20, 20, in: folder)
        let first = try PDFActions.makePDF(from: [url], quality: 0.85, folders: folders).file
        let second = try PDFActions.makePDF(from: [url], quality: 0.85, folders: folders).file
        #expect(first.lastPathComponent == "a.pdf" && second.lastPathComponent == "a 2.pdf")
    }

    // MARK: A PDF to images

    @Test func eachPageBecomesAPNGWithAWhitePageAndItsContent() throws {
        let folder = try makeTempDirectory()
        let pdf = try SyntheticFiles.pdf(pages: 3, size: CGSize(width: 200, height: 300), in: folder)
        let files = try PDFActions.renderPages(of: pdf, folders: folders)
        #expect(files.map(\.lastPathComponent) == ["tài liệu-trang-1.png", "tài liệu-trang-2.png", "tài liệu-trang-3.png"])
        let page = try SyntheticFiles.decoded(files[0])
        #expect(page.width == 400 && page.height == 600)
        #expect(try SyntheticFiles.type(of: files[0]) == .png)
        // The black square is 20 to 80 points from the bottom left; the rest of the page is white.
        let square = SyntheticFiles.pixel(of: page, x: 100, y: 600 - 100)
        #expect(square.r < 30 && square.a == 255)
        let paper = SyntheticFiles.pixel(of: page, x: 350, y: 50)
        #expect(paper.r > 240 && paper.g > 240 && paper.b > 240 && paper.a == 255)
    }

    @Test func pageNumbersAreAlignedWhenThereAreTenOrMore() throws {
        let folder = try makeTempDirectory()
        let pdf = try SyntheticFiles.pdf(pages: 10, size: CGSize(width: 20, height: 20), named: "d.pdf", in: folder)
        let files = try PDFActions.renderPages(of: pdf, folders: folders)
        #expect(files.map(\.lastPathComponent).first == "d-trang-01.png")
        #expect(files.map(\.lastPathComponent).last == "d-trang-10.png")
    }

    @Test func aPageIsNeverRenderedBeyondTheSizeLimit() throws {
        let folder = try makeTempDirectory()
        let pdf = try SyntheticFiles.pdf(pages: 1, size: CGSize(width: 5000, height: 100), named: "rộng.pdf", in: folder)
        let page = try SyntheticFiles.decoded(try #require(PDFActions.renderPages(of: pdf, folders: folders).first))
        #expect(max(page.width, page.height) <= PDFActions.maxPagePixels)
    }

    @Test func aFileThatIsNotAPDFIsRefused() throws {
        let folder = try makeTempDirectory()
        let text = try makeTempFile(named: "a.pdf", in: folder)
        #expect(throws: FileActionError.notPDF) { try PDFActions.renderPages(of: text, folders: folders) }
        #expect(throws: FileActionError.missing) { try PDFActions.renderPages(of: folder.appending(path: "gone.pdf"), folders: folders) }
    }

    @Test func aPDFWithAPasswordIsRefused() throws {
        let folder = try makeTempDirectory()
        let plain = try SyntheticFiles.pdf(pages: 1, named: "plain.pdf", in: folder)
        let locked = folder.appending(path: "locked.pdf")
        let document = try #require(PDFDocument(url: plain))
        #expect(document.write(to: locked, withOptions: [.userPasswordOption: "secret", .ownerPasswordOption: "secret"]))
        #expect(throws: FileActionError.pdfLocked) { try PDFActions.renderPages(of: locked, folders: folders) }
    }

    @Test func aCancelledSplitLeavesNoPagesBehind() async throws {
        let folder = try makeTempDirectory()
        let pdf = try SyntheticFiles.pdf(pages: 4, size: CGSize(width: 20, height: 20), named: "d.pdf", in: folder)
        let task = Task.detached { [folders] in
            Result {
                try PDFActions.renderPages(of: pdf, folders: folders) { written in
                    // The user cancels once the second page is written.
                    if written == 2 { withUnsafeCurrentTask { $0?.cancel() } }
                }
            }
        }
        let result = await task.value
        #expect(throws: CancellationError.self) { try result.get() }
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["d.pdf"])
    }

    @Test func aSplitOfAPromisedCopyPutsEachPageInAFolderOfItsOwn() throws {
        let promised = try makeTempDirectory().appending(path: "promised", directoryHint: .isDirectory)
        let own = promised.appending(path: "X", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: own, withIntermediateDirectories: true)
        let pdf = try SyntheticFiles.pdf(pages: 2, size: CGSize(width: 20, height: 20), named: "d.pdf", in: own)
        let files = try PDFActions.renderPages(of: pdf, folders: OutputFolders(promisedDirectory: promised))
        #expect(files.count == 2)
        #expect(Set(files.map { $0.deletingLastPathComponent().path }).count == 2)
        #expect(files.allSatisfy { $0.deletingLastPathComponent() != own })
    }
}
