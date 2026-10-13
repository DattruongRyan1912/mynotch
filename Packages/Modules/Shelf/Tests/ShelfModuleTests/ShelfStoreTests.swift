import Foundation
import Testing
import UniformTypeIdentifiers
@testable import ShelfModule

/// A unique temporary folder, removed by the caller's OS cleanup like the other packages' test folders.
func makeTempDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: "MyNotchShelfTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

func makeTempFile(named name: String = "note.txt", in directory: URL) throws -> URL {
    let url = directory.appending(path: name)
    try Data("hello".utf8).write(to: url)
    return url
}

@Suite struct ShelfStoreTests {
    @Test func itemsRoundTripThroughShelfJson() throws {
        let directory = try makeTempDirectory()
        let file = try makeTempFile(in: directory)
        let store = ShelfStore(directory: directory, limit: 50)
        store.add(try .file(at: file), limit: 50)
        store.add(.text("xin chào"), limit: 50)
        store.add(.link(URL(string: "https://example.com")!), limit: 50)

        let reloaded = ShelfStore(directory: directory, limit: 50)
        #expect(reloaded.items == store.items)
        #expect(reloaded.items.map(\.kind).count == 3)
        #expect(FileManager.default.fileExists(atPath: directory.appending(path: "shelf.json").path))
        if case .file(_, let name, let type) = reloaded.items.last?.kind {
            #expect(name == "note.txt")
            #expect(type.conforms(to: .plainText))
        } else {
            Issue.record("the first added item should be the file")
        }
    }

    @Test func newestItemComesFirst() throws {
        let store = ShelfStore(directory: try makeTempDirectory(), limit: 50)
        store.add(.text("a"), limit: 50)
        store.add(.text("b"), limit: 50)
        #expect(store.items.map(\.kind) == [.text("b"), .text("a")])
    }

    @Test func brokenBookmarkIsDroppedOnLoad() throws {
        let directory = try makeTempDirectory()
        let doomed = try makeTempFile(named: "gone.txt", in: directory)
        let kept = try makeTempFile(named: "kept.txt", in: directory)
        let store = ShelfStore(directory: directory, limit: 50)
        store.add(try .file(at: doomed), limit: 50)
        store.add(try .file(at: kept), limit: 50)
        store.add(.text("stays"), limit: 50)
        try FileManager.default.removeItem(at: doomed)

        let reloaded = ShelfStore(directory: directory, limit: 50)
        #expect(reloaded.items.count == 2)
        #expect(reloaded.items.contains { $0.kind == .text("stays") })
        #expect(reloaded.url(of: reloaded.items[1])?.lastPathComponent == "kept.txt")
    }

    @Test func undecodableEntriesAreSkippedAndCorruptFileStartsEmpty() throws {
        let directory = try makeTempDirectory()
        let good = ShelfItem(kind: .text("ok"), addedAt: Date(timeIntervalSinceReferenceDate: 5))
        let goodJSON = String(decoding: try JSONEncoder().encode(good), as: UTF8.self)
        let file = directory.appending(path: "shelf.json")
        try Data("[\(goodJSON), {\"nonsense\": 1}]".utf8).write(to: file)
        #expect(ShelfStore(directory: directory, limit: 50).items == [good])

        try Data("not json".utf8).write(to: file)
        #expect(ShelfStore(directory: directory, limit: 50).items.isEmpty)
    }

    @Test func addingBeyondTheLimitDropsTheOldest() throws {
        let store = ShelfStore(directory: try makeTempDirectory(), limit: 2)
        for text in ["a", "b", "c"] { store.add(.text(text), limit: 2) }
        #expect(store.items.map(\.kind) == [.text("c"), .text("b")])
    }

    @Test func loadingTrimsToTheCurrentLimit() throws {
        let directory = try makeTempDirectory()
        let store = ShelfStore(directory: directory, limit: 50)
        for text in ["a", "b", "c"] { store.add(.text(text), limit: 50) }
        #expect(ShelfStore(directory: directory, limit: 2).items.map(\.kind) == [.text("c"), .text("b")])
    }

    @Test func removeAndRemoveAllPersist() throws {
        let directory = try makeTempDirectory()
        let store = ShelfStore(directory: directory, limit: 50)
        store.add(.text("a"), limit: 50)
        store.add(.text("b"), limit: 50)
        store.remove(id: store.items[0].id)
        #expect(ShelfStore(directory: directory, limit: 50).items.map(\.kind) == [.text("a")])
        store.removeAll()
        #expect(ShelfStore(directory: directory, limit: 50).items.isEmpty)
    }

    @Test func removingAPromisedFileDeletesItsCopyButNeverAUserFile() throws {
        let directory = try makeTempDirectory()
        let store = ShelfStore(directory: directory, limit: 50)
        let folder = store.promisedDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let promised = try makeTempFile(named: "photo.txt", in: folder)
        let own = try makeTempFile(named: "own.txt", in: directory)
        store.add(try .file(at: promised), limit: 50)
        store.add(try .file(at: own), limit: 50)

        store.removeAll()
        #expect(!FileManager.default.fileExists(atPath: folder.path))
        #expect(FileManager.default.fileExists(atPath: own.path))
    }
}
