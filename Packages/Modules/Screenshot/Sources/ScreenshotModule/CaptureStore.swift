import CoreGraphics
import Foundation
import ImageIO
import os
import UniformTypeIdentifiers

/// The tray's captures: PNGs in `<directory>/captures/` listed newest first by `captures.json`, with
/// thumbnails cached in memory and in `<cachesDirectory>/thumbnails/`, which the system may purge.
final class CaptureStore {
    enum StoreError: Error {
        case unknownCapture
        case encodingFailed
    }

    /// Newest first. Read from disk on first use, so changes never overwrite an index that was not loaded;
    /// only `load()` deletes unlisted PNGs, so a capture being written is never mistaken for one.
    private(set) lazy var records: [CaptureRecord] = readIndex() ?? []

    private let capturesDirectory: URL
    private let thumbnailsDirectory: URL
    private let logger: Logger
    private let thumbnails = NSCache<NSString, CGImage>()

    init(directory: URL, cachesDirectory: URL, logger: Logger) {
        capturesDirectory = directory.appending(path: "captures", directoryHint: .isDirectory)
        thumbnailsDirectory = cachesDirectory.appending(path: "thumbnails", directoryHint: .isDirectory)
        self.logger = logger
    }

    /// Re-reads the index, skipping malformed records and records whose PNG is gone, and deletes top-level PNGs
    /// it does not list. An unreadable index is set aside and nothing is deleted, since it lists no capture.
    @discardableResult
    func load() -> [CaptureRecord] {
        guard let listedRecords = readIndex() else {
            records = []
            return records
        }
        records = listedRecords
        let listed = Set(records.map(\.fileName))
        let files = (try? FileManager.default.contentsOfDirectory(at: capturesDirectory, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.pathExtension == "png" && !listed.contains(file.lastPathComponent) {
            try? FileManager.default.removeItem(at: file)
        }
        return records
    }

    /// Saves `image` as the newest capture, then deletes the oldest ones beyond `keepCount` (at least 1).
    func add(_ image: CGImage, keepCount: Int) throws -> CaptureRecord {
        let id = UUID()
        let record = CaptureRecord(
            id: id, fileName: "\(id.uuidString).png", createdAt: .now,
            pixelWidth: image.width, pixelHeight: image.height, hasMarkup: false
        )
        try FileManager.default.createDirectory(at: capturesDirectory, withIntermediateDirectories: true)
        try Self.pngData(image).write(to: fileURL(of: record), options: .atomic)
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
    func replaceImage(id: UUID, with image: CGImage) throws {
        guard let index = records.firstIndex(where: { $0.id == id }) else { throw StoreError.unknownCapture }
        try Self.pngData(image).write(to: fileURL(of: records[index]), options: .atomic)
        removeThumbnails(of: id)
        records[index].pixelWidth = image.width
        records[index].pixelHeight = image.height
        records[index].hasMarkup = true
        try save(records)
    }

    /// A thumbnail whose longer side is at most `maxPixel`, from memory, the disk cache or the PNG.
    func thumbnail(for id: UUID, maxPixel: Int) -> CGImage? {
        guard maxPixel > 0, let record = record(id) else { return nil }
        let key = "\(id.uuidString)-\(maxPixel)"
        if let cached = thumbnails.object(forKey: key as NSString) { return cached }
        let cacheURL = thumbnailsDirectory.appending(path: "\(key).png")
        let image: CGImage
        if let source = CGImageSourceCreateWithURL(cacheURL as CFURL, nil),
           let cachedOnDisk = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary) {
            image = cachedOnDisk
        } else {
            let options = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            ] as CFDictionary
            guard let source = CGImageSourceCreateWithURL(fileURL(of: record) as CFURL, nil),
                  let created = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
            image = created
            do {
                try FileManager.default.createDirectory(at: thumbnailsDirectory, withIntermediateDirectories: true)
                try Self.pngData(created).write(to: cacheURL, options: .atomic)
            } catch {
                logger.error("Could not cache a thumbnail: \(error, privacy: .public)")
            }
        }
        thumbnails.setObject(image, forKey: key as NSString)
        return image
    }

    /// Copies a capture into `directory` as "Ảnh chụp <yyyy-MM-dd HH.mm.ss>.png", adding " 2", " 3"… when taken.
    func export(id: UUID, to directory: URL) throws -> URL {
        guard let record = record(id) else { throw StoreError.unknownCapture }
        let baseName = "Ảnh chụp \(Self.timestamp(record.createdAt, format: "yyyy-MM-dd HH.mm.ss"))"
        let destination = Self.freeURL(in: directory, baseName: baseName, separator: " ", pathExtension: "png")
        try FileManager.default.copyItem(at: fileURL(of: record), to: destination)
        return destination
    }

    private var indexURL: URL { capturesDirectory.appending(path: "captures.json") }

    private func record(_ id: UUID) -> CaptureRecord? {
        records.first { $0.id == id }
    }

    private func fileURL(of record: CaptureRecord) -> URL {
        capturesDirectory.appending(path: record.fileName)
    }

    /// The listed records, or nil when the index exists but is not a readable array.
    private func readIndex() -> [CaptureRecord]? {
        let fileManager = FileManager.default
        var decoded: [CaptureRecord] = []
        if fileManager.fileExists(atPath: indexURL.path(percentEncoded: false)) {
            do {
                decoded = try JSONDecoder().decode([LossyRecord].self, from: Data(contentsOf: indexURL)).compactMap(\.record)
            } catch {
                setAsideUnreadableIndex(error)
                return nil
            }
        }
        // A file name that is not a plain PNG name could point outside the folder, and deleting it would be unsafe.
        return decoded
            .filter { !$0.fileName.contains("/") && $0.fileName.hasSuffix(".png") }
            .filter { fileManager.fileExists(atPath: fileURL(of: $0).path(percentEncoded: false)) }
            .sorted { $0.createdAt > $1.createdAt }
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
        for url in [fileURL(of: record), originalURL(for: record.id), markupURL(for: record.id)] {
            try? FileManager.default.removeItem(at: url)
        }
        removeThumbnails(of: record.id)
    }

    private func removeThumbnails(of id: UUID) {
        // NSCache cannot remove by prefix; clearing it is cheap because the disk cache refills it.
        thumbnails.removeAllObjects()
        let prefix = "\(id.uuidString)-"
        let files = (try? FileManager.default.contentsOfDirectory(at: thumbnailsDirectory, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.lastPathComponent.hasPrefix(prefix) {
            try? FileManager.default.removeItem(at: file)
        }
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

    private static func pngData(_ image: CGImage) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw StoreError.encodingFailed
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw StoreError.encodingFailed }
        return data as Data
    }
}

/// Decodes one index entry without failing the whole index when that entry is malformed.
private nonisolated struct LossyRecord: Decodable {
    let record: CaptureRecord?

    init(from decoder: any Decoder) throws {
        record = try? CaptureRecord(from: decoder)
    }
}
