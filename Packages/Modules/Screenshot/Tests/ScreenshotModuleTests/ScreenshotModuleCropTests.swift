import CoreGraphics
import Foundation
import Testing
@testable import ScreenshotModule

/// Saving, reopening and copying a crop, and the copy that "Xong" makes, without any window or the real pasteboard.
extension ScreenshotModuleTests {
    /// The 40×50 capture (red x + 20, green y + 30) cropped to its bottom-right 20×30 corner.
    static let corner: MarkupDocument = {
        var document = MarkupDocument(imageSize: CGSize(width: 40, height: 50))
        document.crop = CGRect(x: 20, y: 20, width: 20, height: 30)
        return document
    }()

    // MARK: Crop

    @Test func savingACropAloneStoresTheSmallerPictureAndKeepsTheOriginal() async throws {
        let record = try await capturedRecord()
        let before = try pngData(of: record)
        let source = try #require(await module.editorSource(for: record))

        #expect(await module.saveMarkup(Self.corner, of: source, for: record))

        let store = try #require(module.store)
        #expect(try Data(contentsOf: store.originalURL(for: record.id)) == before)
        #expect(try JSONDecoder().decode(MarkupDocument.self, from: Data(contentsOf: store.markupURL(for: record.id))) == Self.corner)
        let updated = try #require(module.state.records.first)
        #expect((updated.pixelWidth, updated.pixelHeight) == (20, 30))
        #expect(updated.hasMarkup)
        #expect(updated.editedAt != nil)
        let visible = try visibleBitmap(of: record)
        #expect((visible.width, visible.height) == (20, 30))
        #expect(visible.pixel(0, 0) == Bitmap.Pixel(r: 40, g: 50, b: 0, a: 255))
        #expect(visible.pixel(19, 29) == Bitmap.Pixel(r: 59, g: 79, b: 0, a: 255))
        #expect(try dpi(of: #require(store.url(for: record.id))) == 144)
    }

    @Test func reopeningACroppedCaptureStartsFromTheFullOriginalWithTheCropApplied() async throws {
        let record = try await capturedRecord()
        let source = try #require(await module.editorSource(for: record))
        #expect(await module.saveMarkup(Self.corner, of: source, for: record))
        let updated = try #require(module.state.records.first)

        let reopened = try #require(await module.editorSource(for: updated))

        #expect(reopened.document == Self.corner)
        let original = try Bitmap(reopened.image)
        #expect((original.width, original.height) == (40, 50))
        let model = MarkupEditorModel(image: reopened.image, document: reopened.document, pointScale: reopened.scale, canvasFill: reopened.canvasFill)
        #expect((model.preview.width, model.preview.height) == (20, 30))
        #expect(model.document.crop == Self.corner.crop)
        #expect(!model.canUndo)
    }

    @Test func theCropCanBeWidenedBackToTheWholeCapture() async throws {
        let record = try await capturedRecord()
        let before = try pngData(of: record)
        let first = try #require(await module.editorSource(for: record))
        #expect(await module.saveMarkup(Self.corner, of: first, for: record))
        let second = try #require(await module.editorSource(for: record))

        #expect(await module.saveMarkup(MarkupDocument(imageSize: Self.corner.imageSize), of: second, for: record))

        let updated = try #require(module.state.records.first)
        #expect((updated.pixelWidth, updated.pixelHeight) == (40, 50))
        #expect(!updated.hasMarkup)
        let visible = try visibleBitmap(of: record)
        #expect(visible.pixel(0, 0) == Bitmap.Pixel(r: 20, g: 30, b: 0, a: 255))
        #expect(try Data(contentsOf: #require(module.store).originalURL(for: record.id)) == before)
    }

    @Test func copyingACroppedEditPutsTheCroppedPictureOnThePasteboard() async throws {
        let record = try await capturedRecord()
        let source = try #require(await module.editorSource(for: record))

        #expect(await module.copyMarkup(Self.corner, of: source))

        let copied = try #require(pasteboard.images.last)
        #expect((copied.image.width, copied.image.height) == (20, 30))
        #expect(copied.scale == 2)
        #expect(!copied.markedAsOwn)
    }

    @Test func aCropWithAnnotationsSavesOnlyWhatIsLeftOfThem() async throws {
        let record = try await capturedRecord()
        let source = try #require(await module.editorSource(for: record))
        var document = Self.corner
        document.annotations = [.redact(CGRect(x: 0, y: 0, width: 10, height: 10)), .redact(CGRect(x: 25, y: 25, width: 10, height: 10))]
        // The first redaction is outside the crop; model-level cropping removes it, so the document saved here is the result.
        document.annotations.removeFirst()

        #expect(await module.saveMarkup(document, of: source, for: record))

        let store = try #require(module.store)
        let saved = try JSONDecoder().decode(MarkupDocument.self, from: Data(contentsOf: store.markupURL(for: record.id)))
        #expect(saved.annotations == [.redact(CGRect(x: 25, y: 25, width: 10, height: 10))])
        let visible = try visibleBitmap(of: record)
        #expect((visible.width, visible.height) == (20, 30))
        // Pixel (8, 8) of the crop is (28, 28) of the capture, inside the redaction, so it is no longer the capture's own.
        #expect(visible.pixel(8, 8) != Bitmap.Pixel(r: 48, g: 58, b: 0, a: 255))
        #expect(visible.pixel(0, 0) == Bitmap.Pixel(r: 40, g: 50, b: 0, a: 255))
    }

    // MARK: Copy when done

    @Test func copyingWhenDoneIsOnByDefault() throws {
        let (settings, keys) = try settings()
        #expect(settings.value(keys.copyWhenDone))
    }

    @Test func doneCopiesTheSavedPictureAsMyNotchsOwnWriteAndSaysSo() async throws {
        let record = try await capturedRecord()
        let source = try #require(await module.editorSource(for: record))
        let copies = pasteboard.images.count
        let toasts = harness.presenter.toastCount

        #expect(await module.saveMarkup(Self.corner, of: source, for: record))

        #expect(pasteboard.images.count == copies + 1)
        let copied = try #require(pasteboard.images.last)
        #expect(copied.markedAsOwn)
        #expect(copied.scale == 2)
        #expect((copied.image.width, copied.image.height) == (20, 30))
        #expect(try Bitmap(copied.image).pixel(0, 0) == visibleBitmap(of: record).pixel(0, 0))
        // One message for the whole of "Xong", the confirmation of the copy, not a save toast and then another.
        #expect(harness.presenter.toastCount == toasts + 1)
    }

    @Test func theCopyIsTheEditedPictureNotTheOriginal() async throws {
        let record = try await capturedRecord()
        let source = try #require(await module.editorSource(for: record))

        #expect(await module.saveMarkup(Self.redaction, of: source, for: record))

        let copied = try #require(pasteboard.images.last)
        #expect(try Bitmap(copied.image).pixel(0, 0) != Bitmap.Pixel(r: 20, g: 30, b: 0, a: 255))
        #expect(try Bitmap(copied.image).pixel(0, 0) == visibleBitmap(of: record).pixel(0, 0))
    }

    @Test func withTheSettingOffDoneSavesAndCopiesNothing() async throws {
        let record = try await capturedRecord()
        let (settings, keys) = try settings()
        settings.set(false, for: keys.copyWhenDone)
        let source = try #require(await module.editorSource(for: record))
        let copies = pasteboard.images.count
        let toasts = harness.presenter.toastCount

        #expect(await module.saveMarkup(Self.redaction, of: source, for: record))

        #expect(pasteboard.images.count == copies)
        #expect(module.state.records.first?.hasMarkup == true)
        #expect(harness.presenter.toastCount == toasts + 1)
    }

    @Test func doneWithNothingEditedSavesAndCopiesNothing() async throws {
        let record = try await capturedRecord()
        let source = try #require(await module.editorSource(for: record))
        let copies = pasteboard.images.count
        let toasts = harness.presenter.toastCount

        #expect(await module.saveMarkup(MarkupDocument(imageSize: Self.redaction.imageSize), of: source, for: record))

        #expect(pasteboard.images.count == copies)
        #expect(harness.presenter.toastCount == toasts)
    }

    @Test func aFailedSaveCopiesNothing() async throws {
        let record = try await capturedRecord()
        let source = try #require(await module.editorSource(for: record))
        module.delete(record)
        let copies = pasteboard.images.count

        #expect(await !module.saveMarkup(Self.redaction, of: source, for: record))

        #expect(pasteboard.images.count == copies)
    }

    @Test func aFailedCopyLeavesTheSaveInPlaceAndTellsTheUser() async throws {
        let record = try await capturedRecord()
        let source = try #require(await module.editorSource(for: record))
        pasteboard.succeeds = false
        let toasts = harness.presenter.toastCount

        #expect(await module.saveMarkup(Self.redaction, of: source, for: record))

        #expect(module.state.records.first?.hasMarkup == true)
        #expect(harness.presenter.toastCount == toasts + 1)
    }

    @Test func theEditorsOwnCopyButtonStaysAnOrdinaryCopy() async throws {
        let record = try await capturedRecord()
        let source = try #require(await module.editorSource(for: record))

        #expect(await module.copyMarkup(Self.redaction, of: source))

        #expect(try #require(pasteboard.images.last).markedAsOwn == false)
    }
}
