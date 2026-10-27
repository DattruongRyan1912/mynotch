import AppKit
import ImageIO

/// What the markup editor starts from: the picture to draw on and the annotations already on it.
struct MarkupEditorSource {
    /// The capture as it was before any markup: the stored original if there is one, else the stored PNG.
    let image: CGImage
    /// nil for a capture that was never edited.
    let document: MarkupDocument?
    /// Pixels per point, for the PNG's DPI and the clipboard.
    let scale: CGFloat
    /// What fills the canvas where it grows past the capture, from Settings when the editor opened.
    let canvasFill: CanvasFill
}

/// What the module needs of the editor's windows: to open one and to close them all. A protocol so tests open no window.
protocol MarkupEditorHosting: AnyObject {
    /// Shows the editor of `record`, or brings its window forward if it is already open.
    func open(_ record: CaptureRecord, source: MarkupEditorSource)
    func closeAll()
}

extension MarkupEditorWindowController: MarkupEditorHosting {}

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
        let editors = editors ?? makeEditors(self)
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
        let fill = context.flatMap { context in keys.map { context.settings.value($0.canvasFill) } } ?? .standard
        return MarkupEditorSource(image: loaded.image, document: document, scale: loaded.scale, canvasFill: fill)
    }

    /// What saving an edit did.
    private enum SaveOutcome {
        case failed
        /// Nothing was edited and nothing was kept before, so the capture stays as it is.
        case unchanged
        /// The stored picture was replaced by this one.
        case saved(CGImage)
    }

    /// Lưu, which is also "Xong": keeps the untouched PNG and the edits next to the capture the first time, then
    /// replaces the visible image with the flattened one. When Settings says so, the saved picture is also copied, as an
    /// ordinary copy that Clipboard history records like the capture's own, so it can be pasted at once. One toast tells
    /// how it went. A capture that was never edited and has nothing to save stays as it is, and nothing is copied.
    func saveMarkup(_ document: MarkupDocument, of source: MarkupEditorSource, for record: CaptureRecord) async -> Bool {
        switch await persistMarkup(document, of: source, for: record) {
        case .failed:
            return false
        case .unchanged:
            return true
        case .saved(let flattened):
            let copies = context.flatMap { context in keys.map { context.settings.value($0.copyWhenDone) } } ?? false
            guard copies else {
                showToast("Đã lưu ảnh đã sửa", systemImage: "checkmark.circle.fill")
                return true
            }
            if await pasteboard.write(flattened, scale: source.scale) {
                showToast("Đã chép ảnh", systemImage: "doc.on.clipboard.fill")
            } else {
                showToast("Không chép được ảnh", systemImage: "exclamationmark.triangle.fill")
            }
            return true
        }
    }

    private func persistMarkup(_ document: MarkupDocument, of source: MarkupEditorSource, for record: CaptureRecord) async -> SaveOutcome {
        guard let store, let current = store.url(for: record.id) else {
            showToast("Không lưu được ảnh đã sửa", systemImage: "exclamationmark.triangle.fill")
            return .failed
        }
        let original = store.originalURL(for: record.id)
        let isEdited = FileManager.default.fileExists(atPath: original.path(percentEncoded: false))
        if !document.hasEdits, !isEdited { return .unchanged }
        do {
            let flattened = try await Self.keepSidecars(
                of: current, original: original, markup: store.markupURL(for: record.id), document: document, image: source.image
            )
            try await store.replaceImage(id: record.id, with: flattened, scale: source.scale, hasMarkup: document.hasEdits)
            refreshRecords()
            return .saved(flattened)
        } catch {
            context?.logger.error("Could not save markup: \(error, privacy: .public)")
            showToast("Không lưu được ảnh đã sửa", systemImage: "exclamationmark.triangle.fill")
            return .failed
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


    func openEditorForImage(url: URL) async {
        guard let context, let store else { return }
        // 1. If it's already a capture record, open it directly.
        if let matching = store.records.first(where: { store.url(for: $0.id) == url || store.originalURL(for: $0.id) == url }) {
            await edit(matching)
            return
        }
        // 2. Otherwise load the image and add it as a new capture record to edit.
        guard let loaded = await Self.loadImage(at: url) else {
            showToast("Không mở được ảnh để sửa", systemImage: "exclamationmark.triangle.fill")
            return
        }
        do {
            let keepCount = keys.map { context.settings.value($0.keepCount) } ?? ScreenshotSettingKeys.defaultKeepCount
            let record = try await store.add(loaded.image, scale: loaded.scale, keepCount: keepCount)
            state.records = store.records
            await edit(record)
        } catch {
            showToast("Không mở được ảnh để sửa", systemImage: "exclamationmark.triangle.fill")
        }
    }

    func openEditorForImageData(_ data: Data) async {
        guard let context, let store else { return }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            showToast("Không mở được ảnh để sửa", systemImage: "exclamationmark.triangle.fill")
            return
        }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let dpi = properties?[kCGImagePropertyDPIWidth] as? Double ?? 144
        let scale = max(CGFloat(dpi) / 72, 1)
        do {
            let keepCount = keys.map { context.settings.value($0.keepCount) } ?? ScreenshotSettingKeys.defaultKeepCount
            let record = try await store.add(image, scale: scale, keepCount: keepCount)
            state.records = store.records
            await edit(record)
        } catch {
            showToast("Không mở được ảnh để sửa", systemImage: "exclamationmark.triangle.fill")
        }
    }
}

