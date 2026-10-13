import CoreGraphics
import Foundation
import ImageIO
import os
import Testing
@testable import ScreenshotModule

@Suite final class CaptureStoreTests {
    /// Ways the index can fail to prove which PNGs are captures; none of them may cost a capture.
    enum IndexDamage: CaseIterable { case missing, unreadable, allEntriesUndecodable, oneEntryUndecodable }

    let root: URL
    var directory: URL { root.appending(path: "Data", directoryHint: .isDirectory) }
    var cachesDirectory: URL { root.appending(path: "Caches", directoryHint: .isDirectory) }
    var capturesDirectory: URL { directory.appending(path: "captures", directoryHint: .isDirectory) }
    var thumbnailsDirectory: URL { cachesDirectory.appending(path: "thumbnails", directoryHint: .isDirectory) }
    var indexURL: URL { capturesDirectory.appending(path: "captures.json") }

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

    static func json(_ record: CaptureRecord) throws -> String {
        String(decoding: try JSONEncoder().encode(record), as: UTF8.self)
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

    /// Horizontal and vertical DPI, rounded: PNG stores pixels per metre.
    func dpi(of url: URL) -> [Double]? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyDPIWidth] as? Double,
              let height = properties[kCGImagePropertyDPIHeight] as? Double else { return nil }
        return [width.rounded(), height.rounded()]
    }

    func writeIndex(_ json: String) throws {
        try FileManager.default.createDirectory(at: capturesDirectory, withIntermediateDirectories: true)
        try Data(json.utf8).write(to: indexURL)
    }

    func savedIndex() throws -> [CaptureRecord] {
        try JSONDecoder().decode([CaptureRecord].self, from: Data(contentsOf: indexURL))
    }

    /// A folder where the index belongs makes every save fail.
    func blockIndexSaves() throws {
        try FileManager.default.removeItem(at: indexURL)
        try FileManager.default.createDirectory(at: indexURL, withIntermediateDirectories: true)
    }

    /// Plants an original and an annotation sidecar for `id`, as the markup editor would.
    func writeMarkupFiles(for id: UUID, in store: CaptureStore) throws {
        for url in [store.originalURL(for: id), store.markupURL(for: id)] {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("markup".utf8).write(to: url)
        }
    }

    func writeThumbnail(for id: UUID) throws {
        try FileManager.default.createDirectory(at: thumbnailsDirectory, withIntermediateDirectories: true)
        try Data("thumbnail".utf8).write(to: thumbnailsDirectory.appending(path: "\(id.uuidString)-64.png"))
    }

    @Test func addThenLoadRoundTrip() async throws {
        let store = makeStore()
        let first = try await store.add(Self.image(width: 40, height: 30), keepCount: 30)
        let second = try await store.add(Self.image(width: 50, height: 20), keepCount: 30)

        #expect(first.fileName == "\(first.id.uuidString).png")
        #expect((first.pixelWidth, first.pixelHeight, first.hasMarkup) == (40, 30, false))
        #expect(store.records == [second, first])
        #expect(try savedIndex() == [second, first])
        #expect(pixelSize(of: try #require(store.url(for: second.id))) == CGSize(width: 50, height: 20))
        #expect(makeStore().load() == [second, first])
    }

    @Test func addingWithoutLoadingKeepsExistingCaptures() async throws {
        let existing = try await makeStore().add(Self.image(width: 10, height: 10), keepCount: 30)
        let store = makeStore()
        let added = try await store.add(Self.image(width: 10, height: 10), keepCount: 30)

        #expect(store.records == [added, existing])
        #expect(fileNames(in: capturesDirectory) == ["captures.json", added.fileName, existing.fileName])
    }

    @Test(arguments: [1, 2])
    func addingBeforeAnUnreadableIndexIsReadDoesNotDuplicateTheNewCapture(keepCount: Int) async throws {
        let existing = try await makeStore().add(Self.image(width: 10, height: 10), keepCount: 30)
        try writeIndex("{ not json")
        let store = makeStore()

        let added = try await store.add(Self.image(width: 20, height: 20), keepCount: keepCount)

        let expected = keepCount == 1 ? [added.id] : [added.id, existing.id]
        #expect(store.records.map(\.id) == expected)
        #expect(store.url(for: added.id).map(exists) == true)
        #expect(makeStore().load().map(\.id) == expected)
    }

    @Test func pngsRecordTheScaleAsDPI() async throws {
        let store = makeStore()
        let plain = try await store.add(Self.image(width: 10, height: 10), keepCount: 30)
        let retina = try await store.add(Self.image(width: 20, height: 20), scale: 2, keepCount: 30)
        #expect(dpi(of: try #require(store.url(for: plain.id))) == [72, 72])
        #expect(dpi(of: try #require(store.url(for: retina.id))) == [144, 144])

        try await store.replaceImage(id: plain.id, with: Self.image(width: 30, height: 30), scale: 3)
        #expect(dpi(of: try #require(store.url(for: plain.id))) == [216, 216])
    }

    @Test func addRollsBackWhenTheIndexCannotBeSaved() async throws {
        let store = makeStore()
        let existing = try await store.add(Self.image(width: 10, height: 10), keepCount: 30)
        try blockIndexSaves()

        await #expect(throws: (any Error).self) { try await store.add(Self.image(width: 10, height: 10), keepCount: 1) }

        #expect(store.records == [existing])
        #expect(fileNames(in: capturesDirectory) == ["captures.json", existing.fileName])
    }

    @Test func loadListsNewestFirst() async throws {
        let store = makeStore()
        let older = try await store.add(Self.image(width: 10, height: 10), keepCount: 30)
        let newer = try await store.add(Self.image(width: 10, height: 10), keepCount: 30)
        var oldestFirst = [older, newer]
        oldestFirst[0].createdAt = newer.createdAt.addingTimeInterval(-60)
        try writeIndex(String(decoding: JSONEncoder().encode(oldestFirst), as: UTF8.self))

        #expect(makeStore().load().map(\.id) == [newer.id, older.id])
    }

    @Test func keepCountTrimsOldestAndDeletesTheirFiles() async throws {
        let store = makeStore()
        let oldest = try await store.add(Self.image(width: 10, height: 10), keepCount: 2)
        #expect(await store.thumbnail(for: oldest.id, maxPixel: 8) != nil)
        let middle = try await store.add(Self.image(width: 10, height: 10), keepCount: 2)
        let newest = try await store.add(Self.image(width: 10, height: 10), keepCount: 2)

        #expect(store.records.map(\.id) == [newest.id, middle.id])
        #expect(fileNames(in: capturesDirectory) == ["captures.json", newest.fileName, middle.fileName])
        #expect(fileNames(in: thumbnailsDirectory).isEmpty)
        #expect(makeStore().load().map(\.id) == [newest.id, middle.id])
    }

    @Test func keepCountBelowOneStillKeepsTheNewCapture() async throws {
        let store = makeStore()
        _ = try await store.add(Self.image(width: 10, height: 10), keepCount: 0)
        let record = try await store.add(Self.image(width: 10, height: 10), keepCount: 0)
        #expect(store.records == [record])
        #expect(store.url(for: record.id).map(exists) == true)
    }

    @Test func completeIndexSweepsUnlistedPNGsWithTheirFiles() async throws {
        let store = makeStore()
        let record = try await store.add(Self.image(width: 10, height: 10), keepCount: 30)
        let unlisted = UUID()
        try Self.pngData(Self.image(width: 10, height: 10)).write(to: capturesDirectory.appending(path: "\(unlisted.uuidString).png"))
        for id in [record.id, unlisted] {
            try writeMarkupFiles(for: id, in: store)
            try writeThumbnail(for: id)
        }
        try Data("not an image".utf8).write(to: capturesDirectory.appending(path: "orphan.png"))
        try Data("notes".utf8).write(to: capturesDirectory.appending(path: "notes.txt"))

        #expect(makeStore().load() == [record])
        #expect(fileNames(in: capturesDirectory) == ["captures.json", record.fileName, "notes.txt", "originals", "markup"])
        #expect(!exists(store.originalURL(for: unlisted)))
        #expect(!exists(store.markupURL(for: unlisted)))
        #expect(exists(store.originalURL(for: record.id)))
        #expect(exists(store.markupURL(for: record.id)))
        #expect(fileNames(in: thumbnailsDirectory) == ["\(record.id.uuidString)-64.png"])
    }

    @Test func sweepLeavesTheMarkupFoldersAlone() async throws {
        let store = makeStore()
        let record = try await store.add(Self.image(width: 10, height: 10), keepCount: 30)
        let unlisted = UUID()
        try writeMarkupFiles(for: record.id, in: store)
        try writeMarkupFiles(for: unlisted, in: store)
        try Data("not an image".utf8).write(to: capturesDirectory.appending(path: "orphan.png"))

        #expect(makeStore().load() == [record])
        #expect(!exists(capturesDirectory.appending(path: "orphan.png")))
        for id in [record.id, unlisted] {
            #expect(exists(store.originalURL(for: id)))
            #expect(exists(store.markupURL(for: id)))
        }
    }

    @Test func loadDropsRecordsWhosePNGIsMissingWithTheirFiles() async throws {
        let store = makeStore()
        let kept = try await store.add(Self.image(width: 10, height: 10), keepCount: 30)
        let lost = try await store.add(Self.image(width: 10, height: 10), keepCount: 30)
        for id in [kept.id, lost.id] {
            try writeMarkupFiles(for: id, in: store)
            try writeThumbnail(for: id)
        }
        try FileManager.default.removeItem(at: capturesDirectory.appending(path: lost.fileName))

        let reloaded = makeStore()
        #expect(reloaded.load() == [kept])
        #expect(reloaded.url(for: lost.id) == nil)
        #expect(!exists(store.originalURL(for: lost.id)))
        #expect(!exists(store.markupURL(for: lost.id)))
        #expect(exists(store.originalURL(for: kept.id)))
        #expect(fileNames(in: thumbnailsDirectory) == ["\(kept.id.uuidString)-64.png"])
        #expect(try savedIndex() == [kept])
    }

    @Test func loadSkipsMalformedRecords() async throws {
        let record = try await makeStore().add(Self.image(width: 10, height: 10), keepCount: 30)
        try writeIndex("[\(Self.json(record)), {\"id\": 3}, 7]")
        #expect(makeStore().load() == [record])
    }

    @Test func loadNeverUsesFileNamesOutsideTheCapturesFolder() async throws {
        let record = try await makeStore().add(Self.image(width: 10, height: 10), keepCount: 30)
        let outside = directory.appending(path: "outside.png")
        let nested = capturesDirectory.appending(path: "sub/inside.png")
        try FileManager.default.createDirectory(at: nested.deletingLastPathComponent(), withIntermediateDirectories: true)
        for url in [outside, nested] { try Self.pngData(Self.image(width: 10, height: 10)).write(to: url) }
        let escaping = CaptureRecord(id: UUID(), fileName: "../outside.png", createdAt: .now, pixelWidth: 10, pixelHeight: 10, hasMarkup: false)
        var inSubfolder = escaping
        inSubfolder.id = UUID()
        inSubfolder.fileName = "sub/inside.png"
        try writeIndex("[\(Self.json(escaping)), \(Self.json(inSubfolder)), \(Self.json(record))]")

        let store = makeStore()
        #expect(store.load() == [record])
        #expect(store.url(for: escaping.id) == nil)
        store.delete(id: escaping.id)
        #expect(exists(outside))
        #expect(exists(nested))
    }

    @Test(arguments: IndexDamage.allCases)
    func damagedIndexAdoptsCapturesAndDeletesOnlyJunk(_ damage: IndexDamage) async throws {
        let store = makeStore()
        let older = try await store.add(Self.image(width: 40, height: 30), keepCount: 30)
        let newer = try await store.add(Self.image(width: 20, height: 50), keepCount: 30)
        // Adopted captures are dated by their files; giving the files the capture dates makes the order known.
        for record in [older, newer] {
            let path = capturesDirectory.appending(path: record.fileName).path(percentEncoded: false)
            try FileManager.default.setAttributes([.creationDate: record.createdAt], ofItemAtPath: path)
        }
        try writeMarkupFiles(for: newer.id, in: store)
        let unreadable = UUID()
        try Data("not an image".utf8).write(to: capturesDirectory.appending(path: "\(unreadable.uuidString).png"))
        try writeMarkupFiles(for: unreadable, in: store)
        let notACapture = capturesDirectory.appending(path: "Screenshot.png")
        try Self.pngData(Self.image(width: 10, height: 10)).write(to: notACapture)
        switch damage {
        case .missing: try FileManager.default.removeItem(at: indexURL)
        case .unreadable: try writeIndex("{ not json")
        case .allEntriesUndecodable: try writeIndex("[{\"id\": 3}, 7]")
        case .oneEntryUndecodable: try writeIndex("[\(Self.json(older)), {\"id\": 3}]")
        }

        let loaded = makeStore().load()

        #expect(loaded.map(\.id) == [newer.id, older.id])
        #expect(loaded.map(\.fileName) == [newer.fileName, older.fileName])
        #expect(loaded.map { [$0.pixelWidth, $0.pixelHeight] } == [[20, 50], [40, 30]])
        #expect(loaded.map(\.hasMarkup) == [true, false])
        for (adopted, original) in zip(loaded, [newer, older]) {
            #expect(abs(adopted.createdAt.timeIntervalSince(original.createdAt)) < 0.01)
        }
        #expect(exists(store.originalURL(for: newer.id)))
        #expect(!exists(capturesDirectory.appending(path: "\(unreadable.uuidString).png")))
        #expect(!exists(store.originalURL(for: unreadable)))
        #expect(!exists(store.markupURL(for: unreadable)))
        #expect(!exists(notACapture))
        #expect(try savedIndex() == loaded)
        #expect(makeStore().load() == loaded)
    }

    @Test func unreadableIndexIsSetAside() async throws {
        let record = try await makeStore().add(Self.image(width: 10, height: 10), keepCount: 30)
        let corruptName = /captures\.corrupt-\d{8}-\d{6}(-\d+)?\.json/

        for contents in ["{ not json", "{\"records\": []}"] {
            try writeIndex(contents)
            #expect(makeStore().load().map(\.id) == [record.id])
        }

        let files = fileNames(in: capturesDirectory)
        let setAside = files.filter { $0.wholeMatch(of: corruptName) != nil }
        #expect(setAside.count == 2)
        #expect(files.subtracting(setAside) == ["captures.json", record.fileName])
        let contents = try setAside.map { try String(contentsOf: capturesDirectory.appending(path: $0), encoding: .utf8) }
        #expect(Set(contents) == ["{ not json", "{\"records\": []}"])
    }

    @Test func markupFilesLiveInSubfoldersOfCaptures() {
        let id = UUID()
        let store = makeStore()
        #expect(store.originalURL(for: id) == capturesDirectory.appending(path: "originals/\(id.uuidString).png"))
        #expect(store.markupURL(for: id) == capturesDirectory.appending(path: "markup/\(id.uuidString).json"))
    }

    @Test func deleteAndTrimRemoveOriginalsAndMarkup() async throws {
        let store = makeStore()
        let oldest = try await store.add(Self.image(width: 10, height: 10), keepCount: 30)
        let deleted = try await store.add(Self.image(width: 10, height: 10), keepCount: 30)
        let kept = try await store.add(Self.image(width: 10, height: 10), keepCount: 30)
        for record in [oldest, deleted, kept] { try writeMarkupFiles(for: record.id, in: store) }

        store.delete(id: deleted.id)
        #expect(!exists(store.originalURL(for: deleted.id)))
        #expect(!exists(store.markupURL(for: deleted.id)))

        _ = try await store.add(Self.image(width: 10, height: 10), keepCount: 2)
        #expect(!exists(store.originalURL(for: oldest.id)))
        #expect(!exists(store.markupURL(for: oldest.id)))

        #expect(exists(store.originalURL(for: kept.id)))
        #expect(exists(store.markupURL(for: kept.id)))
    }

    @Test func deleteRemovesTheRecordAndItsFiles() async throws {
        let store = makeStore()
        let kept = try await store.add(Self.image(width: 10, height: 10), keepCount: 30)
        let deleted = try await store.add(Self.image(width: 10, height: 10), keepCount: 30)
        #expect(await store.thumbnail(for: deleted.id, maxPixel: 8) != nil)

        store.delete(id: deleted.id)
        store.delete(id: UUID())

        #expect(store.records == [kept])
        #expect(store.url(for: deleted.id) == nil)
        #expect(await store.thumbnail(for: deleted.id, maxPixel: 8) == nil)
        #expect(fileNames(in: capturesDirectory) == ["captures.json", kept.fileName])
        #expect(fileNames(in: thumbnailsDirectory).isEmpty)
        #expect(makeStore().load() == [kept])
    }

    @Test func thumbnailIsCachedInMemoryAndOnDisk() async throws {
        let store = makeStore()
        let record = try await store.add(Self.image(width: 400, height: 200), keepCount: 30)

        let first = try #require(await store.thumbnail(for: record.id, maxPixel: 100))
        #expect((first.width, first.height) == (100, 50))
        #expect(await store.thumbnail(for: record.id, maxPixel: 100) === first)
        let diskCopy = thumbnailsDirectory.appending(path: "\(record.id.uuidString)-100.png")
        #expect(pixelSize(of: diskCopy) == CGSize(width: 100, height: 50))

        let other = try #require(await store.thumbnail(for: record.id, maxPixel: 40))
        #expect((other.width, other.height) == (40, 20))
        #expect(await store.thumbnail(for: record.id, maxPixel: 0) == nil)

        // A new store has an empty memory cache, so a marker planted in the disk cache proves it is read.
        try Self.pngData(Self.image(width: 7, height: 7)).write(to: diskCopy)
        let fromDisk = try #require(await makeStore().thumbnail(for: record.id, maxPixel: 100))
        #expect((fromDisk.width, fromDisk.height) == (7, 7))
    }

    @Test func replaceImageUpdatesRecordAndThumbnails() async throws {
        let store = makeStore()
        let record = try await store.add(Self.image(width: 400, height: 200), keepCount: 30)
        let before = try #require(await store.thumbnail(for: record.id, maxPixel: 100))

        try await store.replaceImage(id: record.id, with: Self.image(width: 200, height: 400))

        let updated = try #require(store.records.first)
        #expect((updated.id, updated.fileName, updated.createdAt) == (record.id, record.fileName, record.createdAt))
        #expect((updated.pixelWidth, updated.pixelHeight, updated.hasMarkup) == (200, 400, true))
        #expect(pixelSize(of: try #require(store.url(for: record.id))) == CGSize(width: 200, height: 400))
        let after = try #require(await store.thumbnail(for: record.id, maxPixel: 100))
        #expect(after !== before)
        #expect((after.width, after.height) == (50, 100))
        #expect(makeStore().load() == [updated])
    }

    @Test func replaceImageKeepsTheRecordWhenTheIndexCannotBeSaved() async throws {
        let store = makeStore()
        let record = try await store.add(Self.image(width: 40, height: 30), keepCount: 30)
        try blockIndexSaves()

        await #expect(throws: (any Error).self) { try await store.replaceImage(id: record.id, with: Self.image(width: 10, height: 10)) }

        #expect(store.records == [record])
    }

    @Test func exportUsesReadableNamesAndAvoidsCollisions() async throws {
        let store = makeStore()
        let record = try await store.add(Self.image(width: 10, height: 10), keepCount: 30)
        let destination = root.appending(path: "Desktop", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let base = "Ảnh chụp \(formatter.string(from: record.createdAt))"

        var exported: [URL] = []
        for _ in 1...3 { exported.append(try await store.export(id: record.id, to: destination)) }

        #expect(exported.map(\.lastPathComponent) == ["\(base).png", "\(base) 2.png", "\(base) 3.png"])
        let original = try Data(contentsOf: try #require(store.url(for: record.id)))
        for url in exported {
            #expect(url.deletingLastPathComponent().standardizedFileURL == destination.standardizedFileURL)
            #expect(try Data(contentsOf: url) == original)
        }
    }

    @Test func unknownCapturesAreRejected() async throws {
        let store = makeStore()
        let unknown = UUID()
        #expect(store.url(for: unknown) == nil)
        #expect(await store.thumbnail(for: unknown, maxPixel: 64) == nil)
        await #expect(throws: CaptureStore.StoreError.unknownCapture) {
            try await store.replaceImage(id: unknown, with: Self.image(width: 10, height: 10))
        }
        await #expect(throws: CaptureStore.StoreError.unknownCapture) { try await store.export(id: unknown, to: self.root) }
    }
}
