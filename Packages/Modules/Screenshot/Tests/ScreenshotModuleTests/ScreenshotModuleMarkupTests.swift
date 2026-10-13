import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import ScreenshotModule

/// The markup editor's saving and reopening, without any window.
extension ScreenshotModuleTests {
    static let redaction = MarkupDocument(
        imageSize: CGSize(width: 40, height: 50), annotations: [.redact(CGRect(x: 0, y: 0, width: 40, height: 50))]
    )

    func pngData(of record: CaptureRecord) throws -> Data {
        try Data(contentsOf: #require(module.store?.url(for: record.id)))
    }

    /// The stored PNG as the tray shows it.
    func visibleBitmap(of record: CaptureRecord) throws -> Bitmap {
        let url = try #require(module.store?.url(for: record.id))
        let image = try #require(CGImageSource.image(at: url))
        return try Bitmap(image)
    }

    @Test func aCaptureNeverEditedOpensFromItsPNGWithoutAnnotations() async throws {
        let record = try await capturedRecord()

        let source = try #require(await module.editorSource(for: record))

        #expect(source.document == nil)
        #expect(source.scale == 2)
        let bitmap = try Bitmap(source.image)
        #expect((bitmap.width, bitmap.height) == (40, 50))
        #expect(bitmap.pixel(0, 0) == Bitmap.Pixel(r: 20, g: 30, b: 0, a: 255))
    }

    @Test func savingKeepsTheOriginalAndTheAnnotationsAndReplacesTheVisibleImage() async throws {
        let record = try await capturedRecord()
        let before = try pngData(of: record)
        let source = try #require(await module.editorSource(for: record))

        #expect(await module.saveMarkup(Self.redaction, of: source, for: record))

        let store = try #require(module.store)
        #expect(try Data(contentsOf: store.originalURL(for: record.id)) == before)
        #expect(try JSONDecoder().decode(MarkupDocument.self, from: Data(contentsOf: store.markupURL(for: record.id))) == Self.redaction)
        #expect(try pngData(of: record) != before)
        let visible = try visibleBitmap(of: record)
        #expect(visible.pixel(0, 0) != Bitmap.Pixel(r: 20, g: 30, b: 0, a: 255))
        #expect(try dpi(of: #require(store.url(for: record.id))) == 144)
        #expect(module.state.records.first?.hasMarkup == true)
        #expect(module.state.records == store.records)
    }

    @Test func reopeningStartsFromTheOriginalWithItsAnnotations() async throws {
        let record = try await capturedRecord()
        let source = try #require(await module.editorSource(for: record))
        #expect(await module.saveMarkup(Self.redaction, of: source, for: record))
        let updated = try #require(module.state.records.first)

        let reopened = try #require(await module.editorSource(for: updated))

        #expect(reopened.document == Self.redaction)
        #expect(reopened.scale == 2)
        #expect(try Bitmap(reopened.image).pixel(0, 0) == Bitmap.Pixel(r: 20, g: 30, b: 0, a: 255))
    }

    @Test func savingAgainFlattensTheOriginalAndNeverReplacesIt() async throws {
        let record = try await capturedRecord()
        let before = try pngData(of: record)
        let first = try #require(await module.editorSource(for: record))
        #expect(await module.saveMarkup(Self.redaction, of: first, for: record))
        let second = try #require(await module.editorSource(for: record))

        #expect(await module.saveMarkup(MarkupDocument(imageSize: Self.redaction.imageSize), of: second, for: record))

        let store = try #require(module.store)
        #expect(try Data(contentsOf: store.originalURL(for: record.id)) == before)
        // With every annotation removed the visible image is the original's pixels again.
        let visible = try visibleBitmap(of: record)
        #expect(visible.pixel(0, 0) == Bitmap.Pixel(r: 20, g: 30, b: 0, a: 255))
        #expect(visible.pixel(39, 49) == Bitmap.Pixel(r: 59, g: 79, b: 0, a: 255))
    }

    @Test func everySaveChangesTheRecordTheTrayShows() async throws {
        let record = try await capturedRecord()
        let another = MarkupDocument(
            imageSize: Self.redaction.imageSize, annotations: [.redact(CGRect(x: 0, y: 0, width: 10, height: 10))]
        )
        var shown = [record]

        // The tab reloads a card's thumbnail when its record changes, also after the second and third save.
        for document in [Self.redaction, another, Self.redaction] {
            let source = try #require(await module.editorSource(for: shown.last ?? record))
            #expect(await module.saveMarkup(document, of: source, for: record))
            shown.append(try #require(module.state.records.first))
        }

        #expect(zip(shown, shown.dropFirst()).allSatisfy { $0 != $1 })
    }

    @Test func removingEveryAnnotationClearsTheMarkupBadge() async throws {
        let record = try await capturedRecord()
        let first = try #require(await module.editorSource(for: record))
        #expect(await module.saveMarkup(Self.redaction, of: first, for: record))
        #expect(module.state.records.first?.hasMarkup == true)
        let second = try #require(await module.editorSource(for: record))

        #expect(await module.saveMarkup(MarkupDocument(imageSize: Self.redaction.imageSize), of: second, for: record))

        #expect(module.state.records.first?.hasMarkup == false)
        // The original and the (empty) annotations stay, so the next edit still starts from the original.
        let store = try #require(module.store)
        #expect(FileManager.default.fileExists(atPath: store.originalURL(for: record.id).path(percentEncoded: false)))
    }

    @Test func savingWithoutAnnotationsOfACaptureNeverEditedChangesNothing() async throws {
        let record = try await capturedRecord()
        let before = try pngData(of: record)
        let source = try #require(await module.editorSource(for: record))

        #expect(await module.saveMarkup(MarkupDocument(imageSize: Self.redaction.imageSize), of: source, for: record))

        let store = try #require(module.store)
        #expect(try pngData(of: record) == before)
        #expect(!FileManager.default.fileExists(atPath: store.originalURL(for: record.id).path(percentEncoded: false)))
        #expect(!FileManager.default.fileExists(atPath: store.markupURL(for: record.id).path(percentEncoded: false)))
        #expect(module.state.records.first?.hasMarkup == false)
    }

    @Test func savingACaptureThatWasDeletedFailsWithAToast() async throws {
        let record = try await capturedRecord()
        let source = try #require(await module.editorSource(for: record))
        module.delete(record)
        let toasts = harness.presenter.toastCount

        #expect(await !module.saveMarkup(Self.redaction, of: source, for: record))

        #expect(harness.presenter.toastCount == toasts + 1)
        #expect(module.state.records.isEmpty)
    }

    @Test func copyingPutsTheFlattenedImageOnThePasteboardAtTheCapturesScale() async throws {
        let record = try await capturedRecord()
        let source = try #require(await module.editorSource(for: record))
        let copies = pasteboard.images.count

        #expect(await module.copyMarkup(Self.redaction, of: source))

        #expect(pasteboard.images.count == copies + 1)
        let copied = try #require(pasteboard.images.last)
        #expect(copied.scale == 2)
        #expect(try Bitmap(copied.image).pixel(0, 0) != Bitmap.Pixel(r: 20, g: 30, b: 0, a: 255))
        // The stored capture is untouched.
        #expect(module.state.records.first?.hasMarkup == false)
    }

    @Test func aFailedCopyShowsAToast() async throws {
        let record = try await capturedRecord()
        let source = try #require(await module.editorSource(for: record))
        pasteboard.succeeds = false
        let toasts = harness.presenter.toastCount

        #expect(await !module.copyMarkup(Self.redaction, of: source))

        #expect(harness.presenter.toastCount == toasts + 1)
    }
}

extension CGImageSource {
    static func image(at url: URL) -> CGImage? {
        CGImageSourceCreateWithURL(url as CFURL, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }
    }
}
