import AppKit

/// What the markup editor starts from: the picture to draw on and the annotations already on it.
struct MarkupEditorSource {
    /// The capture as it was before any markup: the stored original if there is one, else the stored PNG.
    let image: CGImage
    /// nil for a capture that was never edited.
    let document: MarkupDocument?
    /// Pixels per point, for the PNG's DPI and the clipboard.
    let scale: CGFloat
}

/// The tray's "Sửa": opening the editor, and what its Lưu and Copy do with the result. Results show as toasts.
extension ScreenshotModule {
    /// Opens the editor for `record`, or brings its window forward when it is already open.
    func edit(_ record: CaptureRecord) async {
        guard let context else { return }
        guard let source = await editorSource(for: record) else {
            showToast("Không mở được ảnh để sửa", systemImage: "exclamationmark.triangle.fill")
            return
        }
        // The window is a regular app window; the notch has nothing more to show behind it.
        context.presenter.close()
        let editors = editors ?? MarkupEditorWindowController(module: self)
        self.editors = editors
        editors.open(record, source: source)
    }

    /// A capture that was edited reopens from its original with its annotations, so the markup stays editable.
    func editorSource(for record: CaptureRecord) async -> MarkupEditorSource? {
        guard let store else { return nil }
        let original = store.originalURL(for: record.id)
        let isEdited = FileManager.default.fileExists(atPath: original.path(percentEncoded: false))
        guard let url = isEdited ? original : store.url(for: record.id),
              let loaded = await Self.loadImage(at: url) else { return nil }
        var document: MarkupDocument?
        if isEdited {
            do {
                document = try JSONDecoder().decode(MarkupDocument.self, from: Data(contentsOf: store.markupURL(for: record.id)))
            } catch {
                context?.logger.error("Could not read the markup of a capture: \(error, privacy: .public)")
            }
        }
        return MarkupEditorSource(image: loaded.image, document: document, scale: loaded.scale)
    }

    /// Lưu: keeps the untouched PNG and the annotations next to the capture the first time, then replaces the
    /// visible image with the flattened one. A capture without annotations that was never edited stays as it is.
    func saveMarkup(_ document: MarkupDocument, of source: MarkupEditorSource, for record: CaptureRecord) async -> Bool {
        guard let store, let current = store.url(for: record.id) else {
            showToast("Không lưu được ảnh đã sửa", systemImage: "exclamationmark.triangle.fill")
            return false
        }
        let original = store.originalURL(for: record.id)
        let isEdited = FileManager.default.fileExists(atPath: original.path(percentEncoded: false))
        if document.annotations.isEmpty, !isEdited { return true }
        do {
            let flattened = try await Self.keepSidecars(
                of: current, original: original, markup: store.markupURL(for: record.id), document: document, image: source.image
            )
            try await store.replaceImage(id: record.id, with: flattened, scale: source.scale)
            refreshRecords()
            showToast("Đã lưu ảnh đã sửa", systemImage: "checkmark.circle.fill")
            return true
        } catch {
            context?.logger.error("Could not save markup: \(error, privacy: .public)")
            showToast("Không lưu được ảnh đã sửa", systemImage: "exclamationmark.triangle.fill")
            return false
        }
    }

    /// Copy: the flattened image on the pasteboard; the stored capture does not change.
    func copyMarkup(_ document: MarkupDocument, of source: MarkupEditorSource) async -> Bool {
        guard let flattened = await Self.flatten(source.image, document), await pasteboard.write(flattened, scale: source.scale) else {
            showToast("Không chép được ảnh", systemImage: "exclamationmark.triangle.fill")
            return false
        }
        showToast("Đã chép ảnh", systemImage: "doc.on.clipboard.fill")
        return true
    }

    /// Copies the stored PNG to `original` unless that exists (it is only untouched until the first save), writes the
    /// annotations, and returns the flattened image. Off the main actor: it copies a file and renders every pixel.
    @concurrent
    private nonisolated static func keepSidecars(
        of current: URL, original: URL, markup: URL, document: MarkupDocument, image: CGImage
    ) async throws -> CGImage {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: original.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: markup.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !fileManager.fileExists(atPath: original.path(percentEncoded: false)) {
            try fileManager.copyItem(at: current, to: original)
        }
        try JSONEncoder().encode(document).write(to: markup, options: .atomic)
        guard let flattened = MarkupRenderer.flatten(image, document) else { throw CaptureStore.StoreError.encodingFailed }
        return flattened
    }

    @concurrent
    private nonisolated static func flatten(_ image: CGImage, _ document: MarkupDocument) async -> CGImage? {
        MarkupRenderer.flatten(image, document)
    }
}
