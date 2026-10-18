import CoreGraphics
import Foundation
import Testing
@testable import ScreenshotModule

/// What the Storage page asks of the store: the keep count applied now, and everything removed.
@Suite final class CaptureStoreCleanTests {
    let root: URL
    var directory: URL { root.appending(path: "Data", directoryHint: .isDirectory) }
    var cachesDirectory: URL { root.appending(path: "Caches", directoryHint: .isDirectory) }

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "CaptureStoreCleanTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: root) }

    func makeStore() -> CaptureStore {
        CaptureStore(directory: directory, cachesDirectory: cachesDirectory, logger: .init(subsystem: "MyNotchTests", category: "CaptureStoreClean"))
    }

    func fill(_ store: CaptureStore, count: Int) async throws -> [CaptureRecord] {
        var records: [CaptureRecord] = []
        for index in 0..<count {
            records.append(try await store.add(CaptureStoreTests.image(width: 20 + index, height: 10), keepCount: 100))
        }
        return records
    }

    func size(_ url: URL) -> Int64 {
        Int64((try? FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))[.size] as? Int) ?? 0)
    }

    @Test func theCapturesFolderIsNamedInOnePlace() {
        #expect(CaptureStore.capturesFolder(in: directory) == directory.appending(path: "captures", directoryHint: .isDirectory))
    }

    @Test func trimKeepsTheNewestAndRemovesTheOldestWithEverythingKeptForThem() async throws {
        let store = makeStore()
        let records = try await fill(store, count: 6)
        let doomed = Array(records.prefix(2))
        // An original and annotations, as the markup editor leaves them, and a thumbnail in the caches.
        for record in doomed {
            try FileManager.default.createDirectory(at: store.originalURL(for: record.id).deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(count: 100).write(to: store.originalURL(for: record.id))
            try FileManager.default.createDirectory(at: store.markupURL(for: record.id).deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(count: 10).write(to: store.markupURL(for: record.id))
        }
        _ = await store.thumbnail(for: doomed[0].id, maxPixel: 16)
        let expected = try doomed.reduce(Int64(0)) { total, record in
            total + size(try #require(store.url(for: record.id))) + size(store.originalURL(for: record.id)) + size(store.markupURL(for: record.id))
        }

        let freed = store.trim(keepCount: 4)

        #expect(freed == expected && freed > 110)
        #expect(store.records.map(\.id) == records.dropFirst(2).reversed().map(\.id))
        for record in doomed {
            #expect(store.url(for: record.id) == nil)
            #expect(!FileManager.default.fileExists(atPath: store.originalURL(for: record.id).path))
            #expect(!FileManager.default.fileExists(atPath: store.markupURL(for: record.id).path))
        }
        let thumbnails = (try? FileManager.default.contentsOfDirectory(atPath: cachesDirectory.appending(path: "thumbnails").path)) ?? []
        #expect(!thumbnails.contains { $0.hasPrefix(doomed[0].id.uuidString) })
        // What is on disk is what the store says: a new store reads the same list.
        #expect(makeStore().load().map(\.id) == store.records.map(\.id))
    }

    @Test func trimWithinTheKeepCountChangesNothing() async throws {
        let store = makeStore()
        let records = try await fill(store, count: 3)

        #expect(store.trim(keepCount: 3) == 0 && store.trim(keepCount: 50) == 0)

        #expect(store.records.count == 3 && store.records.map(\.id) == records.reversed().map(\.id))
    }

    @Test func trimAlwaysKeepsTheNewestCapture() async throws {
        let store = makeStore()
        let records = try await fill(store, count: 3)

        store.trim(keepCount: 0)

        #expect(store.records.map(\.id) == [records[2].id])
    }

    @Test func deleteAllLeavesAnEmptyListAndAnEmptyFolderWithNoStrays() async throws {
        let store = makeStore()
        let records = try await fill(store, count: 3)
        let stray = directory.appending(path: "captures/stray.bin")
        try Data(count: 50).write(to: stray)
        _ = await store.thumbnail(for: records[0].id, maxPixel: 16)

        await store.deleteAll()

        #expect(store.records.isEmpty)
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.appending(path: "captures").path)
        #expect(names == ["captures.json"])
        #expect(makeStore().load().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: stray.path))
        let thumbnails = (try? FileManager.default.contentsOfDirectory(atPath: cachesDirectory.appending(path: "thumbnails").path)) ?? []
        #expect(thumbnails.isEmpty)
        // The store works afterwards.
        let again = try await store.add(CaptureStoreTests.image(width: 10, height: 10), keepCount: 30)
        #expect(store.records.map(\.id) == [again.id])
    }
}
