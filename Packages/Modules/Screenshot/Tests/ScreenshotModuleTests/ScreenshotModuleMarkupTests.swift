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

/// Annotations past the capture's edge grow the saved and copied image, and the padding follows the setting.
extension ScreenshotModuleTests {
    /// A badge that sticks 15 pixels out of the 40-pixel-wide capture on the right.
    static let overflowing = MarkupDocument(
        imageSize: CGSize(width: 40, height: 50),
        annotations: [.step(number: 1, at: CGPoint(x: 45, y: 10), radius: 10, color: .red)],
        canvasFill: .white
    )

    @Test func canvasPaddingDefaultsToTheCapturesEdgeColourAndFollowsTheSetting() async throws {
        let record = try await capturedRecord()
        let (settings, keys) = try settings()
        #expect(settings.value(keys.canvasFill) == .edgeColor)
        #expect(try #require(await module.editorSource(for: record)).canvasFill == .edgeColor)

        settings.set(.black, for: keys.canvasFill)

        #expect(try #require(await module.editorSource(for: record)).canvasFill == .black)
    }

    @Test func savingAGrownCanvasReplacesTheImageWithTheBiggerOneAndKeepsTheOriginal() async throws {
        let record = try await capturedRecord()
        let before = try pngData(of: record)
        let source = try #require(await module.editorSource(for: record))

        #expect(await module.saveMarkup(Self.overflowing, of: source, for: record))

        let updated = try #require(module.state.records.first)
        #expect((updated.pixelWidth, updated.pixelHeight) == (55, 50))
        #expect(updated.hasMarkup)
        let visible = try visibleBitmap(of: record)
        #expect((visible.width, visible.height) == (55, 50))
        #expect(visible.pixel(54, 49) == .white)
        #expect(visible.pixel(0, 0) == Bitmap.Pixel(r: 20, g: 30, b: 0, a: 255))
        let store = try #require(module.store)
        #expect(try Data(contentsOf: store.originalURL(for: record.id)) == before)
        #expect(try dpi(of: #require(store.url(for: record.id))) == 144)
    }

    @Test func reopeningAGrownCaptureStartsFromTheOriginalSizeWithItsCanvasRebuilt() async throws {
        let record = try await capturedRecord()
        let first = try #require(await module.editorSource(for: record))
        #expect(await module.saveMarkup(Self.overflowing, of: first, for: record))
        let updated = try #require(module.state.records.first)

        let reopened = try #require(await module.editorSource(for: updated))

        let bitmap = try Bitmap(reopened.image)
        #expect((bitmap.width, bitmap.height) == (40, 50))
        let model = MarkupEditorModel(image: reopened.image, document: reopened.document, pointScale: reopened.scale, canvasFill: reopened.canvasFill)
        #expect(model.canvas == CanvasInsets(left: 0, top: 0, right: 15, bottom: 0))
        #expect((model.preview.width, model.preview.height) == (55, 50))
        // What was saved is the starting point: undo only goes back through this session's edits.
        #expect(!model.canUndo)
    }

    @Test func copyingAGrownCanvasPutsTheBiggerImageOnThePasteboard() async throws {
        let record = try await capturedRecord()
        let source = try #require(await module.editorSource(for: record))

        #expect(await module.copyMarkup(Self.overflowing, of: source))

        let copied = try #require(pasteboard.images.last)
        #expect((copied.image.width, copied.image.height) == (55, 50))
        #expect(copied.scale == 2)
        #expect(module.state.records.first?.pixelWidth == 40)
    }
}

/// Everything that leaves the editor (the stored image, Chép, dragging out, saving a copy) is the same render, so a
/// lens drawn before a redaction cannot show what the redaction hides.
extension ScreenshotModuleTests {
    /// A lens at the middle of the 40×50 capture at 4×, then a redaction over the area the lens magnifies.
    static let lensThenRedaction = MarkupDocument(
        imageSize: CGSize(width: 40, height: 50),
        annotations: [
            .magnifier(center: CGPoint(x: 20, y: 25), radius: 18, zoom: 4, style: .init(color: .blue, width: 2)),
            .redact(CGRect(x: 14, y: 19, width: 12, height: 12)),
        ]
    )

    /// (34, 25) is inside the lens and outside the redacted rectangle, and shows source (23.6, 25), which is inside it.
    static let probe = (x: 34, y: 25)

    /// What the lens should show there: the redacted capture's flat block, not the capture's own gradient.
    func hiddenColour(of source: MarkupEditorSource) throws -> Bitmap.Pixel {
        let redacted = try #require(MarkupRenderer.flatten(source.image, MarkupDocument(imageSize: Self.lensThenRedaction.imageSize, annotations: [Self.lensThenRedaction.annotations[1]])))
        return try Bitmap(redacted).pixel(23, 25)
    }

    func pixel(of image: CGImage) throws -> Bitmap.Pixel {
        try Bitmap(image).pixel(Self.probe.x, Self.probe.y)
    }

    func pixel(ofFileAt url: URL) throws -> Bitmap.Pixel {
        try pixel(of: #require(CGImageSource.image(at: url)))
    }

    @Test func copyingFromTheEditorHidesTheRedactedAreaInsideAnEarlierLens() async throws {
        let record = try await capturedRecord()
        let source = try #require(await module.editorSource(for: record))
        let hidden = try hiddenColour(of: source)
        let leaky = try #require(MarkupRenderer.flatten(source.image, MarkupDocument(imageSize: Self.lensThenRedaction.imageSize, annotations: [Self.lensThenRedaction.annotations[0]])))
        #expect(try pixel(of: leaky) != hidden)

        #expect(await module.copyMarkup(Self.lensThenRedaction, of: source))

        #expect(try pixel(of: #require(pasteboard.images.last).image) == hidden)
    }

    @Test func theStoredImageAndEverythingMadeFromItHideTheRedactedAreaToo() async throws {
        let record = try await capturedRecord()
        let source = try #require(await module.editorSource(for: record))
        let hidden = try hiddenColour(of: source)
        #expect(await module.saveMarkup(Self.lensThenRedaction, of: source, for: record))
        let saved = try #require(module.state.records.first)

        // The stored PNG, which the tray shows and thumbnails.
        let store = try #require(module.store)
        #expect(try pixel(ofFileAt: #require(store.url(for: record.id))) == hidden)

        // The tray's Chép, OCR's input and Lưu vào: all read the stored PNG.
        let copies = pasteboard.images.count
        await module.copy(saved)
        #expect(pasteboard.images.count == copies + 1)
        #expect(try pixel(of: #require(pasteboard.images.last).image) == hidden)

        // Dragging a card out hands over a link to that same file.
        let dragged = try #require(module.dragFileURL(for: saved))
        #expect(try pixel(ofFileAt: dragged) == hidden)

        // Lưu thành… and Lưu vào.
        let folder = temporaryRoot.appending(path: "Exports", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = folder.appending(path: "chosen.png")
        await module.export(saved, to: destination)
        #expect(try pixel(ofFileAt: destination) == hidden)
        system.saveDirectory = folder
        await module.save(saved)
        let copiedFiles = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).filter { $0.lastPathComponent != destination.lastPathComponent }
        #expect(copiedFiles.count == 1)
        #expect(try pixel(ofFileAt: #require(copiedFiles.first)) == hidden)

        // The unredacted capture stays next to it for editing again, and is never what leaves the module.
        #expect(try pixel(ofFileAt: store.originalURL(for: record.id)) != hidden)
    }

    @Test func openEditorForImageOpensMatchingExistingRecord() async throws {
        let record = try await capturedRecord()
        let store = try #require(module.store)
        let fileURL = try #require(store.url(for: record.id))

        await module.openEditorForImage(url: fileURL)

        #expect(editors.opened.count == 1)
        #expect(editors.opened.last?.record.id == record.id)
    }

    @Test func openEditorForImageImportsAndOpensExternalImage() async throws {
        _ = try await capturedRecord()
        let externalURL = temporaryRoot.appending(path: "external.png")
        let gradient = try Self.gradient(width: 60, height: 80)
        let destination = CGImageDestinationCreateWithURL(externalURL as CFURL, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, gradient, nil)
        CGImageDestinationFinalize(destination)

        await module.openEditorForImage(url: externalURL)

        #expect(editors.opened.count == 1)
        #expect(module.state.records.count == 2)
    }

    @Test func openEditorForImageDataImportsAndOpensImage() async throws {
        _ = try await capturedRecord()
        let gradient = try Self.gradient(width: 50, height: 50)
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data as CFMutableData, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, gradient, nil)
        CGImageDestinationFinalize(destination)

        await module.openEditorForImageData(data as Data)

        #expect(editors.opened.count == 1)
        #expect(module.state.records.count == 2)
    }

    @Test func autoOpenEditorSettingOpensEditorImmediatelyOnCapture() async throws {
        let (settings, keys) = try self.settings()
        settings.set(true, for: keys.autoOpenEditor)
        let record = try await capturedRecord()

        #expect(editors.opened.count == 1)
        #expect(editors.opened.first?.record.id == record.id)
    }
}

extension CGImageSource {
    static func image(at url: URL) -> CGImage? {
        CGImageSourceCreateWithURL(url as CFURL, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }
    }
}
