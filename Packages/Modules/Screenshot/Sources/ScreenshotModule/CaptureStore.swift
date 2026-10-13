import CoreGraphics
import Foundation
import ImageIO
import os
import UniformTypeIdentifiers

/// The tray's captures: PNGs in `<directory>/captures/` listed newest first by `captures.json`, with
/// thumbnails cached in memory and in `<cachesDirectory>/thumbnails/`, which the system may purge.
/// PNG encoding and thumbnail decoding run off the main actor; the index and the caches stay on it.
final class CaptureStore {
    nonisolated enum StoreError: Error {
        case unknownCapture
        case encodingFailed
    }

    /// Newest first. Read from disk on first use, so changes never overwrite an index that was not read.
    private(set) lazy var records: [CaptureRecord] = reconciledRecords()

    private let capturesDirectory: URL
    private let thumbnailsDirectory: URL
    private let logger: Logger
    private let thumbnails = NSCache<NSString, CGImage>()
    /// Bumped when a capture's thumbnails are discarded, so one decoded meanwhile is not cached.
    private var thumbnailRevisions: [UUID: Int] = [:]

    init(directory: URL, cachesDirectory: URL, logger: Logger) {
        capturesDirectory = directory.appending(path: "captures", directoryHint: .isDirectory)
        thumbnailsDirectory = cachesDirectory.appending(path: "thumbnails", directoryHint: .isDirectory)
        self.logger = logger
    }

    /// Re-reads the index and reconciles it with the PNGs on disk; see `reconciledRecords()`.
    @discardableResult
    func load() -> [CaptureRecord] {
        records = reconciledRecords()
        return records
    }

    /// Saves `image` as the newest capture, then deletes the oldest ones beyond `keepCount` (at least 1).
    /// `scale` (pixels per point) becomes the PNG's DPI, so other apps show the capture at its size in points.
    func add(_ image: CGImage, scale: CGFloat = 1, keepCount: Int) async throws -> CaptureRecord {
        // Read the index before the new PNG exists, so rebuilding it cannot adopt the file as a second capture.
        _ = records
        let data = try await Self.pngData(image, scale: scale)
        let id = UUID()
        let record = CaptureRecord(
            id: id, fileName: "\(id.uuidString).png", createdAt: .now,
            pixelWidth: image.width, pixelHeight: image.height, hasMarkup: false
        )
        try FileManager.default.createDirectory(at: capturesDirectory, withIntermediateDirectories: true)
        try data.write(to: fileURL(of: record), options: .atomic)
        // `records` is read again here because another change may have landed while the image was encoded.
        let all = [record] + records
        let kept = Array(all.prefix(max(keepCount, 1)))
        do {
            try save(kept)
        } catch {
            try? FileManager.default.removeItem(at: fileURL(of: record))
            throw error
        }
        records = kept
        all.dropFirst(kept.count).forEach(removeFiles)
        return record
    }

    /// Removes a capture and its files; unknown IDs are ignored.
    func delete(id: UUID) {
        guard let record = record(id) else { return }
        records.removeAll { $0.id == id }
        do {
            try save(records)
        } catch {
            // The PNG goes anyway, so the next load drops the stale entry.
            logger.error("Could not save the capture index: \(error, privacy: .public)")
        }
        removeFiles(of: record)
    }

    /// The capture's PNG, e.g. for dragging it out as a file.
    func url(for id: UUID) -> URL? {
        record(id).map(fileURL)
    }

    /// Where the markup editor keeps the capture as it was before annotation; the file may not exist.
    func originalURL(for id: UUID) -> URL {
        capturesDirectory.appending(components: "originals", "\(id.uuidString).png")
    }

    /// Where the markup editor keeps the capture's annotations, so they can be edited again; the file may not exist.
    func markupURL(for id: UUID) -> URL {
        capturesDirectory.appending(components: "markup", "\(id.uuidString).json")
    }

    /// Overwrites a capture's PNG with its marked-up version; thumbnails are rebuilt on the next request.
    /// The record changes only once the index is saved.
    func replaceImage(id: UUID, with image: CGImage, scale: CGFloat = 1) async throws {
        guard record(id) != nil else { throw StoreError.unknownCapture }
        let data = try await Self.pngData(image, scale: scale)
        guard let index = records.firstIndex(where: { $0.id == id }) else { throw StoreError.unknownCapture }
        try data.write(to: fileURL(of: records[index]), options: .atomic)
        removeThumbnails(of: id)
        var updated = records
        updated[index].pixelWidth = image.width
        updated[index].pixelHeight = image.height
        updated[index].hasMarkup = true
        try save(updated)
        records = updated
    }

    /// A thumbnail whose longer side is at most `maxPixel`, from memory, the disk cache or the PNG.
    func thumbnail(for id: UUID, maxPixel: Int) async -> CGImage? {
        guard maxPixel > 0, let record = record(id) else { return nil }
        let key = "\(id.uuidString)-\(maxPixel)"
        if let cached = thumbnails.object(forKey: key as NSString) { return cached }
        let revision = thumbnailRevisions[id, default: 0]
        let cacheURL = thumbnailsDirectory.appending(path: "\(key).png")
        guard let loaded = await Self.loadThumbnail(of: fileURL(of: record), cachedAt: cacheURL, maxPixel: maxPixel) else { return nil }
        // The capture was replaced or deleted while decoding: start again from its current state.
        guard thumbnailRevisions[id, default: 0] == revision else { return await thumbnail(for: id, maxPixel: maxPixel) }
        if let data = loaded.pngForDiskCache {
            do {
                try FileManager.default.createDirectory(at: thumbnailsDirectory, withIntermediateDirectories: true)
                try data.write(to: cacheURL, options: .atomic)
            } catch {
                logger.error("Could not cache a thumbnail: \(error, privacy: .public)")
            }
        }
        thumbnails.setObject(loaded.image, forKey: key as NSString)
        return loaded.image
    }

    /// Copies a capture into `directory` as "Ảnh chụp <yyyy-MM-dd HH.mm.ss>.png", adding " 2", " 3"… when taken.
    func export(id: UUID, to directory: URL) throws -> URL {
        guard let record = record(id) else { throw StoreError.unknownCapture }
        let destination = Self.freeURL(in: directory, baseName: Self.exportBaseName(of: record), separator: " ", pathExtension: "png")
        try FileManager.default.copyItem(at: fileURL(of: record), to: destination)
        return destination
    }

    /// "Ảnh chụp <yyyy-MM-dd HH.mm.ss>": the name a capture gets outside the store, from when it was taken.
    static func exportBaseName(of record: CaptureRecord) -> String {
        "Ảnh chụp \(timestamp(record.createdAt, format: "yyyy-MM-dd HH.mm.ss"))"
    }

    private var indexURL: URL { capturesDirectory.appending(path: "captures.json") }

    private func record(_ id: UUID) -> CaptureRecord? {
        records.first { $0.id == id }
    }

    private func fileURL(of record: CaptureRecord) -> URL {
        capturesDirectory.appending(path: record.fileName)
    }

    /// The captures on disk, newest first. Entries whose PNG is gone are dropped. Only a fully valid index proves
    /// which PNGs are captures, so only then are unlisted top-level PNGs deleted; otherwise unlisted `<uuid>.png`
    /// images are adopted and only PNGs that are not readable captures are deleted. Captures that are dropped or
    /// deleted lose their thumbnails, originals and annotations. The index is saved when the result differs.
    private func reconciledRecords() -> [CaptureRecord] {
        let fileManager = FileManager.default
        let (entries, isComplete) = readIndex()
        var records = entries.filter {
            Self.hasPlainFileName($0) && fileManager.fileExists(atPath: fileURL(of: $0).path(percentEncoded: false))
        }
        var abandonedIDs = Set(entries.map(\.id))
        let listed = Set(records.map(\.fileName))
        let files = (try? fileManager.contentsOfDirectory(at: capturesDirectory, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.pathExtension == "png" && !listed.contains(file.lastPathComponent) {
            if !isComplete, let adopted = adoptedRecord(from: file), !records.contains(where: { $0.id == adopted.id }) {
                records.append(adopted)
            } else {
                try? fileManager.removeItem(at: file)
                if let id = Self.captureID(of: file) { abandonedIDs.insert(id) }
            }
        }
        records.sort { $0.createdAt > $1.createdAt }
        abandonedIDs.subtracting(records.map(\.id)).forEach(removeDerivedFiles)
        if records != entries {
            do {
                try save(records)
            } catch {
                logger.error("Could not save the reconciled capture index: \(error, privacy: .public)")
            }
        }
        return records
    }

    /// The entries that decode, and whether the index exists and every entry decodes with a plain PNG file name.
    /// An index that is not a JSON array is set aside first.
    private func readIndex() -> (entries: [CaptureRecord], isComplete: Bool) {
        guard FileManager.default.fileExists(atPath: indexURL.path(percentEncoded: false)) else { return ([], false) }
        do {
            let lossy = try JSONDecoder().decode([LossyRecord].self, from: Data(contentsOf: indexURL))
            let entries = lossy.compactMap(\.record)
            return (entries, entries.count == lossy.count && entries.allSatisfy(Self.hasPlainFileName))
        } catch {
            setAsideUnreadableIndex(error)
            return ([], false)
        }
    }

    /// A capture for a top-level `<uuid>.png` that is a readable image; it is dated by the file since its entry is lost.
    private func adoptedRecord(from file: URL) -> CaptureRecord? {
        guard let id = Self.captureID(of: file),
              let source = CGImageSourceCreateWithURL(file as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { return nil }
        let dates = try? file.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        return CaptureRecord(
            id: id, fileName: file.lastPathComponent,
            createdAt: dates?.creationDate ?? dates?.contentModificationDate ?? .now,
            pixelWidth: width, pixelHeight: height,
            hasMarkup: FileManager.default.fileExists(atPath: originalURL(for: id).path(percentEncoded: false))
        )
    }

    /// Renames the index to `captures.corrupt-<yyyyMMdd-HHmmss>[-n].json`, so the next save cannot overwrite it.
    private func setAsideUnreadableIndex(_ error: any Error) {
        let baseName = "captures.corrupt-\(Self.timestamp(.now, format: "yyyyMMdd-HHmmss"))"
        let destination = Self.freeURL(in: capturesDirectory, baseName: baseName, separator: "-", pathExtension: "json")
        do {
            try FileManager.default.moveItem(at: indexURL, to: destination)
            logger.error("Unreadable capture index moved to \(destination.lastPathComponent, privacy: .public): \(error, privacy: .public)")
        } catch let moveError {
            logger.error("Unreadable capture index (\(error, privacy: .public)) could not be moved: \(moveError, privacy: .public)")
        }
    }

    private func save(_ records: [CaptureRecord]) throws {
        try FileManager.default.createDirectory(at: capturesDirectory, withIntermediateDirectories: true)
        try JSONEncoder().encode(records).write(to: indexURL, options: .atomic)
    }

    private func removeFiles(of record: CaptureRecord) {
        try? FileManager.default.removeItem(at: fileURL(of: record))
        removeDerivedFiles(of: record.id)
    }

    /// Everything kept for a capture besides its PNG.
    private func removeDerivedFiles(of id: UUID) {
        for url in [originalURL(for: id), markupURL(for: id)] {
            try? FileManager.default.removeItem(at: url)
        }
        removeThumbnails(of: id)
    }

    private func removeThumbnails(of id: UUID) {
        thumbnailRevisions[id, default: 0] += 1
        // NSCache cannot remove by prefix; clearing it is cheap because the disk cache refills it.
        thumbnails.removeAllObjects()
        let prefix = "\(id.uuidString)-"
        let files = (try? FileManager.default.contentsOfDirectory(at: thumbnailsDirectory, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.lastPathComponent.hasPrefix(prefix) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    /// A file name that is not a plain PNG name could point outside the folder, so it is never used.
    private nonisolated static func hasPlainFileName(_ record: CaptureRecord) -> Bool {
        !record.fileName.contains("/") && record.fileName.hasSuffix(".png")
    }

    private nonisolated static func captureID(of file: URL) -> UUID? {
        UUID(uuidString: file.deletingPathExtension().lastPathComponent)
    }

    /// `date` in the user's time zone with a fixed, locale-independent `format`.
    private static func timestamp(_ date: Date, format: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = format
        return formatter.string(from: date)
    }

    /// `<baseName>.<pathExtension>` in `directory`, or the first free `<baseName><separator>2…` when taken.
    private static func freeURL(in directory: URL, baseName: String, separator: String, pathExtension: String) -> URL {
        var url = directory.appending(path: "\(baseName).\(pathExtension)")
        var number = 1
        while FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
            number += 1
            url = directory.appending(path: "\(baseName)\(separator)\(number).\(pathExtension)")
        }
        return url
    }

    /// PNG bytes via ImageIO with a DPI of 72 × `scale`. Encoding a large capture takes a while, hence off the main actor.
    @concurrent
    nonisolated static func pngData(_ image: CGImage, scale: CGFloat) async throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw StoreError.encodingFailed
        }
        let properties = [kCGImagePropertyDPIWidth: 72 * scale, kCGImagePropertyDPIHeight: 72 * scale] as CFDictionary
        CGImageDestinationAddImage(destination, image, properties)
        guard CGImageDestinationFinalize(destination) else { throw StoreError.encodingFailed }
        return data as Data
    }

    /// The disk-cached thumbnail, or else one made from the capture, with its PNG bytes for the disk cache.
    /// Decoding a large capture takes a while, hence off the main actor.
    @concurrent
    private nonisolated static func loadThumbnail(of png: URL, cachedAt cacheURL: URL, maxPixel: Int) async -> (image: CGImage, pngForDiskCache: Data?)? {
        if let source = CGImageSourceCreateWithURL(cacheURL as CFURL, nil),
           let cached = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary) {
            return (cached, nil)
        }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(png as CFURL, nil),
              let created = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
        return (created, try? await pngData(created, scale: 1))
    }
}

/// Decodes one index entry without failing the whole index when that entry is malformed.
private nonisolated struct LossyRecord: Decodable {
    let record: CaptureRecord?

    init(from decoder: any Decoder) throws {
        record = try? CaptureRecord(from: decoder)
    }
}
