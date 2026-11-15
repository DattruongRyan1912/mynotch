import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Persistent on-disk cache for already-scaled clipboard thumbnails (`<sha256>_<size>.png`).
///
/// Storing downscaled PNGs avoids re-decompressing multi-megabyte original screenshots when entries
/// leave the 24 MB / 48-card in-memory cache or when the library reopens.
/// Privacy invariant: callers must never pass or read locked-vault (`ClipboardOpenImages`) items here.
nonisolated final class ClipboardDiskThumbnailStore: Sendable {
    let directory: URL

    private let writer = DispatchQueue(label: "io.lucasvu.mynotch.clipboard.thumbnail.store", qos: .utility)

    init(directory: URL) {
        self.directory = directory
    }

    static func thumbnailFileName(forSourceName name: String, size: Int) -> String? {
        guard size > 0, ClipboardStore.isImageFileName(name) else { return nil }
        let stem = name.dropLast(4)
        return "\(stem)_\(size).png"
    }

    static func isThumbnailFileName(_ fileName: String) -> Bool {
        fileName.wholeMatch(of: /[0-9a-f]{64}_[1-9][0-9]*\.png/) != nil
    }

    static func sourceName(fromThumbnailFileName fileName: String) -> String? {
        guard isThumbnailFileName(fileName), let underscore = fileName.firstIndex(of: "_") else { return nil }
        return String(fileName[..<underscore]) + ".png"
    }

    static func thumbnailSize(fromThumbnailFileName fileName: String) -> Int? {
        guard isThumbnailFileName(fileName),
              let underscore = fileName.firstIndex(of: "_"),
              let dot = fileName.lastIndex(of: ".") else { return nil }
        return Int(fileName[fileName.index(after: underscore)..<dot])
    }

    func fileURL(forName name: String, size: Int) -> URL? {
        guard let thumbName = Self.thumbnailFileName(forSourceName: name, size: size) else { return nil }
        return directory.appending(path: thumbName, directoryHint: .notDirectory)
    }

    /// Reads and immediately decodes an already-scaled thumbnail off the main actor.
    /// Removes corrupt or zero-byte files so callers cleanly fall back to decoding the source image.
    @concurrent func readAsync(name: String, size: Int) async -> CGImage? {
        read(name: name, size: size)
    }

    func read(name: String, size: Int) -> CGImage? {
        guard let url = fileURL(forName: name, size: size) else { return nil }
        let path = url.path(percentEncoded: false)
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        let decodeOptions = [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions),
              let image = CGImageSourceCreateImageAtIndex(source, 0, decodeOptions)
        else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        return image
    }

    /// Persists a scaled `CGImage` asynchronously as PNG with restricted permissions (`0o700` dir, `0o600` file).
    func scheduleWrite(_ image: CGImage, name: String, size: Int) {
        guard let url = fileURL(forName: name, size: size) else { return }
        writer.async { [directory] in
            Self.writeSync(image, to: url, in: directory)
        }
    }

    func waitForWrites() async {
        await withCheckedContinuation { continuation in
            writer.async { continuation.resume() }
        }
    }

    func deleteThumbnails(for names: some Sequence<String>) {
        let targets = Set(names.filter { ClipboardStore.isImageFileName($0) })
        guard !targets.isEmpty else { return }
        writer.sync {
            let fileManager = FileManager.default
            guard let files = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
            for file in files {
                guard let source = Self.sourceName(fromThumbnailFileName: file.lastPathComponent),
                      targets.contains(source) else { continue }
                try? fileManager.removeItem(at: file)
            }
        }
    }

    func deleteOrphanThumbnails(
        keeping referencedNames: Set<String>,
        validSizes: Set<Int> = ClipboardThumbnailCache.supportedPixelSizes
    ) {
        writer.sync {
            let fileManager = FileManager.default
            guard let files = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
            for file in files {
                let fileName = file.lastPathComponent
                guard let source = Self.sourceName(fromThumbnailFileName: fileName),
                      let size = Self.thumbnailSize(fromThumbnailFileName: fileName),
                      referencedNames.contains(source),
                      validSizes.contains(size) else {
                    if Self.isThumbnailFileName(fileName) {
                        try? fileManager.removeItem(at: file)
                    }
                    continue
                }
            }
        }
    }

    func bytes(for names: Set<String>? = nil) -> Int64 {
        let filter: Set<String>? = names.map { Set($0.filter { ClipboardStore.isImageFileName($0) }) }
        if let filter, filter.isEmpty { return 0 }
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey]
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: Array(keys)) else {
            return 0
        }
        var total: Int64 = 0
        for file in files {
            guard let source = Self.sourceName(fromThumbnailFileName: file.lastPathComponent) else { continue }
            if let filter, !filter.contains(source) { continue }
            guard let values = try? file.resourceValues(forKeys: keys), values.isRegularFile == true else { continue }
            total += Int64(values.fileSize ?? 0)
        }
        return total
    }

    private static func writeSync(_ image: CGImage, to url: URL, in directory: URL) {
        let fileManager = FileManager.default
        let path = url.path(percentEncoded: false)
        guard !fileManager.fileExists(atPath: path) else { return }
        do {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            let data = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
                return
            }
            CGImageDestinationAddImage(destination, image, nil)
            guard CGImageDestinationFinalize(destination) else { return }
            try (data as Data).write(to: url, options: .atomic)
            try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
        } catch {
            // Disk thumbnail caching is best-effort; callers can always re-decode from source PNG.
        }
    }
}
