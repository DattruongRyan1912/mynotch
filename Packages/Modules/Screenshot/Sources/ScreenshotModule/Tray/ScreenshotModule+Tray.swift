import AppKit
import ImageIO
import UniformTypeIdentifiers

/// What the tray's cards can do with a capture. Results show as toasts, since the notch is open.
extension ScreenshotModule {
    static let defaultDragCopiesDirectory = FileManager.default.temporaryDirectory
        .appending(path: "MyNotch Screenshot Drags", directoryHint: .isDirectory)

    /// Where "Lưu vào" puts captures now, for the menu's title.
    var saveLocation: SaveLocation {
        guard let context, let keys else { return .desktop }
        return context.settings.value(keys.saveLocation)
    }

    func thumbnail(for record: CaptureRecord, maxPixel: Int) async -> CGImage? {
        await store?.thumbnail(for: record.id, maxPixel: maxPixel)
    }

    func copy(_ record: CaptureRecord) async {
        guard let loaded = await storedImage(of: record), await pasteboard.write(loaded.image, scale: loaded.scale) else {
            showToast("Không chép được ảnh", systemImage: "exclamationmark.triangle.fill")
            return
        }
        showToast("Đã chép ảnh", systemImage: "doc.on.clipboard.fill")
    }

    /// "Lưu vào <folder>": a copy in the folder chosen in Settings.
    func save(_ record: CaptureRecord) async {
        guard let store, let context, let keys else { return }
        let location = context.settings.value(keys.saveLocation)
        guard let directory = saveDirectory(location) else {
            showToast("Không tìm thấy thư mục \(location.title)", systemImage: "exclamationmark.triangle.fill")
            return
        }
        do {
            _ = try await store.export(id: record.id, to: directory)
            showToast("Đã lưu vào \(location.title)", systemImage: "checkmark.circle.fill")
        } catch {
            context.logger.error("Could not save a capture to \(location.rawValue, privacy: .public): \(error, privacy: .public)")
            showToast("Không lưu được vào \(location.title)", systemImage: "exclamationmark.triangle.fill")
        }
    }

    /// "Lưu thành…": asks where, in a panel that blocks until it is answered, so the caller pins the notch around it.
    func saveAs(_ record: CaptureRecord) async {
        guard let context, let keys else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "\(CaptureStore.exportBaseName(of: record)).png"
        panel.directoryURL = saveDirectory(context.settings.value(keys.saveLocation))
        // MyNotch is never the active app, and a panel of an inactive app cannot take typing.
        let previous = NSWorkspace.shared.frontmostApplication
        NSApp.activate()
        defer { previous?.activate() }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        await export(record, to: url)
    }

    /// Copies the capture to `destination`, replacing a file the save panel already asked about.
    func export(_ record: CaptureRecord, to destination: URL) async {
        guard let source = store?.url(for: record.id) else { return }
        do {
            try await Self.copyReplacing(source, to: destination)
            showToast("Đã lưu \(destination.lastPathComponent)", systemImage: "checkmark.circle.fill")
        } catch {
            context?.logger.error("Could not save a capture: \(error, privacy: .public)")
            showToast("Không lưu được ảnh", systemImage: "exclamationmark.triangle.fill")
        }
    }

    @concurrent
    private nonisolated static func copyReplacing(_ source: URL, to destination: URL) async throws {
        if FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: source, to: destination)
    }

    func delete(_ record: CaptureRecord) {
        store?.delete(id: record.id)
        refreshRecords()
    }

    /// "OCR": reads the stored image and copies its text.
    func recognizeText(in record: CaptureRecord) async {
        guard let loaded = await storedImage(of: record) else {
            showToast("Không đọc được ảnh", systemImage: "exclamationmark.triangle.fill")
            return
        }
        startOCR(loaded.image, feedback: .toast)
    }

    /// A hard link to the capture under a readable name, for dragging out (a copy when linking is not possible):
    /// the stored file is named by its ID, and a drop must never move or rename it. Linking costs no pixel copy on
    /// the main actor, and the store replaces files rather than rewriting them, so the link keeps the dragged
    /// version. nil when neither works.
    func dragFileURL(for record: CaptureRecord) -> URL? {
        guard let source = store?.url(for: record.id) else { return nil }
        let folder = dragCopiesDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let copy = folder.appending(path: "\(CaptureStore.exportBaseName(of: record)).png", directoryHint: .notDirectory)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            do {
                try FileManager.default.linkItem(at: source, to: copy)
            } catch {
                try FileManager.default.copyItem(at: source, to: copy)
            }
            return copy
        } catch {
            context?.logger.error("Could not prepare a dragged capture: \(error, privacy: .public)")
            return nil
        }
    }

    /// Shows the store's records again, after the store changed them (a deletion, or the editor saving markup).
    func refreshRecords() {
        state.records = store?.records ?? []
    }

    private func storedImage(of record: CaptureRecord) async -> (image: CGImage, scale: CGFloat)? {
        guard let url = store?.url(for: record.id) else { return nil }
        return await Self.loadImage(at: url)
    }

    /// The PNG decoded off the main actor, with its scale (pixels per point) from the DPI the store wrote into it.
    @concurrent
    nonisolated static func loadImage(at url: URL) async -> (image: CGImage, scale: CGFloat)? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else { return nil }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let dpi = properties?[kCGImagePropertyDPIWidth] as? Double ?? 72
        return (image, max(CGFloat(dpi) / 72, 1))
    }
}
