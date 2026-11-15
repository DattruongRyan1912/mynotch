import Foundation

/// What the history takes on disk, shown in Settings.
nonisolated struct ClipboardStorageUsage: Equatable, Sendable {
    /// One MB in the image limit setting and in this summary.
    static let bytesPerMB = 1024 * 1024

    var itemCount: Int
    var imageBytes: Int

    init(itemCount: Int, imageBytes: Int) {
        self.itemCount = itemCount
        self.imageBytes = imageBytes
    }

    /// Usage of the running module, whose files may lag behind by the save delay.
    init(history: ClipboardHistory) {
        itemCount = history.items.count
        imageBytes = history.items.reduce(0) { total, item in
            if case .image(let image) = item.content { total + image.byteCount } else { total }
        }
    }

    /// Reads the files of a stopped module without `ClipboardStore.load()`, which would create folders
    /// and move or delete files just because Settings was opened. Missing files count as empty.
    @concurrent static func read(directory: URL) async -> ClipboardStorageUsage {
        let items = (try? Data(contentsOf: directory.appending(path: "history.json")))
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [Any] }
        let images = (try? FileManager.default.contentsOfDirectory(
            at: directory.appending(path: "images", directoryHint: .isDirectory), includingPropertiesForKeys: [.fileSizeKey]
        )) ?? []
        let imageBytes = images.reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
        return ClipboardStorageUsage(itemCount: items?.count ?? 0, imageBytes: imageBytes)
    }

    /// "12 mục · 3,4 MB ảnh"
    func summary(locale: Locale = .current) -> String {
        let megabytes = Double(imageBytes) / Double(Self.bytesPerMB)
        return "\(itemCount) mục · \(megabytes.formatted(.number.precision(.fractionLength(1)).locale(locale))) MB ảnh"
    }
}
