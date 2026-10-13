import CoreGraphics
import Foundation
import ImageIO
import os
import Testing
@testable import ScreenshotModule

@Suite final class CaptureStoreTests {
    let root: URL
    var directory: URL { root.appending(path: "Data", directoryHint: .isDirectory) }
    var cachesDirectory: URL { root.appending(path: "Caches", directoryHint: .isDirectory) }
    var capturesDirectory: URL { directory.appending(path: "captures", directoryHint: .isDirectory) }
    var thumbnailsDirectory: URL { cachesDirectory.appending(path: "thumbnails", directoryHint: .isDirectory) }

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "CaptureStoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: root) }

    func makeStore() -> CaptureStore {
        CaptureStore(directory: directory, cachesDirectory: cachesDirectory, logger: Logger(subsystem: "MyNotchTests", category: "CaptureStore"))
    }

    static func image(width: Int, height: Int, gray: CGFloat = 0.5) throws -> CGImage {
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(gray: gray, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try #require(context.makeImage())
    }

    static func pngData(_ image: CGImage) throws -> Data {
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        try #require(CGImageDestinationFinalize(destination))
        return data as Data
    }

    func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) }

    func fileNames(in directory: URL) -> Set<String> {
        Set((try? FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false))) ?? [])
    }

    func pixelSize(of url: URL) -> CGSize? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        return CGSize(width: image.width, height: image.height)
    }

    func writeIndex(_ json: String) throws {
        try FileManager.default.createDirectory(at: capturesDirectory, withIntermediateDirectories: true)
        try Data(json.utf8).write(to: capturesDirectory.appending(path: "captures.json"))
    }

    @Test func addThenLoadRoundTrip() throws {
        let store = makeStore()
        let first = try store.add(Self.image(width: 40, height: 30), keepCount: 30)
        let second = try store.add(Self.image(width: 50, height: 20), keepCount: 30)

        #expect(first.fileName == "\(first.id.uuidString).png")
        #expect((first.pixelWidth, first.pixelHeight, first.hasMarkup) == (40, 30, false))
        #expect(store.records == [second, first])
        #expect(exists(capturesDirectory.appending(path: "captures.json")))
        #expect(pixelSize(of: try #require(store.url(for: second.id))) == CGSize(width: 50, height: 20))

        let reloaded = makeStore().load()
        #expect(reloaded == [second, first])
    }

    @Test func addingWithoutLoadingKeepsExistingCaptures() throws {
        let existing = try makeStore().add(Self.image(width: 10, height: 10), keepCount: 30)
        let store = makeStore()
        let added = try store.add(Self.image(width: 10, height: 10), keepCount: 30)

        #expect(store.records == [added, existing])
        #expect(fileNames(in: capturesDirectory) == ["captures.json", added.fileName, existing.fileName])
    }

    @Test func loadListsNewestFirst() throws {
        let store = makeStore()
        let older = try store.add(Self.image(width: 10, height: 10), keepCount: 30)
        let newer = try store.add(Self.image(width: 10, height: 10), keepCount: 30)
        var oldestFirst = [older, newer]
        oldestFirst[0].createdAt = newer.createdAt.addingTimeInterval(-60)
        try writeIndex(String(decoding: JSONEncoder().encode(oldestFirst), as: UTF8.self))

        #expect(makeStore().load().map(\.id) == [newer.id, older.id])
    }

    @Test func keepCountTrimsOldestAndDeletesTheirFiles() throws {
        let store = makeStore()
        let oldest = try store.add(Self.image(width: 10, height: 10), keepCount: 2)
        #expect(store.thumbnail(for: oldest.id, maxPixel: 8) != nil)
        let middle = try store.add(Self.image(width: 10, height: 10), keepCount: 2)
        let newest = try store.add(Self.image(width: 10, height: 10), keepCount: 2)

        #expect(store.records.map(\.id) == [newest.id, middle.id])
        #expect(fileNames(in: capturesDirectory) == ["captures.json", newest.fileName, middle.fileName])
        #expect(fileNames(in: thumbnailsDirectory).isEmpty)
        #expect(makeStore().load().map(\.id) == [newest.id, middle.id])
    }

    @Test func keepCountBelowOneStillKeepsTheNewCapture() throws {
        let store = makeStore()
        _ = try store.add(Self.image(width: 10, height: 10), keepCount: 0)
        let record = try store.add(Self.image(width: 10, height: 10), keepCount: 0)
        #expect(store.records == [record])
        #expect(store.url(for: record.id).map(exists) == true)
    }

    @Test func loadDeletesPNGsMissingFromTheIndex() throws {
        let record = try makeStore().add(Self.image(width: 10, height: 10), keepCount: 30)
        try Data("not an image".utf8).write(to: capturesDirectory.appending(path: "orphan.png"))
        try Data("notes".utf8).write(to: capturesDirectory.appending(path: "notes.txt"))

        #expect(makeStore().load() == [record])
        #expect(fileNames(in: capturesDirectory) == ["captures.json", record.fileName, "notes.txt"])
    }

    @Test func loadDropsRecordsWhosePNGIsMissing() throws {
        let store = makeStore()
        let kept = try store.add(Self.image(width: 10, height: 10), keepCount: 30)
        let lost = try store.add(Self.image(width: 10, height: 10), keepCount: 30)
        try FileManager.default.removeItem(at: capturesDirectory.appending(path: lost.fileName))

        let reloaded = makeStore()
        #expect(reloaded.load() == [kept])
        #expect(reloaded.url(for: lost.id) == nil)
    }

    @Test func loadSkipsMalformedAndUnsafeRecords() throws {
        let record = try makeStore().add(Self.image(width: 10, height: 10), keepCount: 30)
        let valid = String(decoding: try JSONEncoder().encode(record), as: UTF8.self)
        let escaping = valid.replacingOccurrences(of: record.fileName, with: "../\(record.fileName)")
        try writeIndex("[\(valid), {\"id\": 3}, 7, \(escaping)]")

        #expect(makeStore().load() == [record])
    }

    @Test func unreadableIndexLoadsEmpty() throws {
        try writeIndex("{ not json")
        #expect(makeStore().load().isEmpty)
    }

    @Test func deleteRemovesTheRecordAndItsFiles() throws {
        let store = makeStore()
        let kept = try store.add(Self.image(width: 10, height: 10), keepCount: 30)
        let deleted = try store.add(Self.image(width: 10, height: 10), keepCount: 30)
        #expect(store.thumbnail(for: deleted.id, maxPixel: 8) != nil)

        store.delete(id: deleted.id)
        store.delete(id: UUID())

        #expect(store.records == [kept])
        #expect(store.url(for: deleted.id) == nil)
        #expect(store.thumbnail(for: deleted.id, maxPixel: 8) == nil)
        #expect(fileNames(in: capturesDirectory) == ["captures.json", kept.fileName])
        #expect(fileNames(in: thumbnailsDirectory).isEmpty)
        #expect(makeStore().load() == [kept])
    }

    @Test func thumbnailIsCachedInMemoryAndOnDisk() throws {
        let store = makeStore()
        let record = try store.add(Self.image(width: 400, height: 200), keepCount: 30)

        let first = try #require(store.thumbnail(for: record.id, maxPixel: 100))
        #expect((first.width, first.height) == (100, 50))
        #expect(store.thumbnail(for: record.id, maxPixel: 100) === first)
        let diskCopy = thumbnailsDirectory.appending(path: "\(record.id.uuidString)-100.png")
        #expect(pixelSize(of: diskCopy) == CGSize(width: 100, height: 50))

        let other = try #require(store.thumbnail(for: record.id, maxPixel: 40))
        #expect((other.width, other.height) == (40, 20))
        #expect(store.thumbnail(for: record.id, maxPixel: 0) == nil)

        // A new store has an empty memory cache, so a marker planted in the disk cache proves it is read.
        try Self.pngData(Self.image(width: 7, height: 7)).write(to: diskCopy)
        let fromDisk = try #require(makeStore().thumbnail(for: record.id, maxPixel: 100))
        #expect((fromDisk.width, fromDisk.height) == (7, 7))
    }

    @Test func replaceImageUpdatesRecordAndThumbnails() throws {
        let store = makeStore()
        let record = try store.add(Self.image(width: 400, height: 200), keepCount: 30)
        let before = try #require(store.thumbnail(for: record.id, maxPixel: 100))

        try store.replaceImage(id: record.id, with: Self.image(width: 200, height: 400))

        let updated = try #require(store.records.first)
        #expect((updated.id, updated.fileName, updated.createdAt) == (record.id, record.fileName, record.createdAt))
        #expect((updated.pixelWidth, updated.pixelHeight, updated.hasMarkup) == (200, 400, true))
        #expect(pixelSize(of: try #require(store.url(for: record.id))) == CGSize(width: 200, height: 400))
        let after = try #require(store.thumbnail(for: record.id, maxPixel: 100))
        #expect(after !== before)
        #expect((after.width, after.height) == (50, 100))
        #expect(makeStore().load() == [updated])
    }

    @Test func exportUsesReadableNamesAndAvoidsCollisions() throws {
        let store = makeStore()
        let record = try store.add(Self.image(width: 10, height: 10), keepCount: 30)
        let destination = root.appending(path: "Desktop", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let base = "Ảnh chụp \(formatter.string(from: record.createdAt))"

        let exported = try (1...3).map { _ in try store.export(id: record.id, to: destination) }

        #expect(exported.map(\.lastPathComponent) == ["\(base).png", "\(base) 2.png", "\(base) 3.png"])
        let original = try Data(contentsOf: try #require(store.url(for: record.id)))
        for url in exported {
            #expect(url.deletingLastPathComponent().standardizedFileURL == destination.standardizedFileURL)
            #expect(try Data(contentsOf: url) == original)
        }
    }

    @Test func unknownCapturesAreRejected() throws {
        let store = makeStore()
        let unknown = UUID()
        #expect(store.url(for: unknown) == nil)
        #expect(store.thumbnail(for: unknown, maxPixel: 64) == nil)
        #expect(throws: CaptureStore.StoreError.unknownCapture) { try store.replaceImage(id: unknown, with: Self.image(width: 10, height: 10)) }
        #expect(throws: CaptureStore.StoreError.unknownCapture) { try store.export(id: unknown, to: self.root) }
    }
}
