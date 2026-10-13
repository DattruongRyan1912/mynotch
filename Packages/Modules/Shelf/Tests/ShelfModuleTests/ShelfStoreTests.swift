import Foundation
import MyNotchTestSupport
import Testing
import UniformTypeIdentifiers
@testable import ShelfModule

/// A unique temporary folder, removed when the test process exits.
func makeTempDirectory() throws -> URL {
    let url = ScratchFolders.shared.reserve("Shelf")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

func makeTempFile(named name: String = "note.txt", in directory: URL) throws -> URL {
    let url = directory.appending(path: name)
    try Data("hello".utf8).write(to: url)
    return url
}

/// A file in its own folder of `promised/`, the way a drop that only promised its file is stored.
func makePromisedFile(named name: String = "photo.txt", in store: ShelfStore) throws -> (folder: URL, file: URL) {
    let folder = store.promisedDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return (folder, try makeTempFile(named: name, in: folder))
}

func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

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
        let (folder, promised) = try makePromisedFile(in: store)
        let own = try makeTempFile(named: "own.txt", in: directory)
        store.add(try .file(at: promised), limit: 50)
        store.add(try .file(at: own), limit: 50)

        store.removeAll()
        #expect(!exists(folder))
        #expect(exists(own))
    }

    @Test func removingCanLeaveThePromisedCopyForTheNextLoadToSweep() throws {
        let store = ShelfStore(directory: try makeTempDirectory(), limit: 50)
        let (folder, promised) = try makePromisedFile(in: store)
        store.add(try .file(at: promised), limit: 50)

        store.remove(id: store.items[0].id, deletingCopy: false)
        #expect(store.items.isEmpty)
        #expect(exists(folder))
    }

    @Test func aFileDirectlyInThePromisedFolderNeverWipesIt() throws {
        let store = ShelfStore(directory: try makeTempDirectory(), limit: 50)
        let (otherFolder, _) = try makePromisedFile(in: store)
        let stray = try makeTempFile(named: "stray.txt", in: store.promisedDirectory)
        store.add(try .file(at: stray), limit: 50)

        store.removeAll()
        #expect(exists(otherFolder))
    }

    @Test func loadingDeletesTheCopiesOfItemsTheLimitTrimmed() throws {
        let directory = try makeTempDirectory()
        let store = ShelfStore(directory: directory, limit: 50)
        let (folder, promised) = try makePromisedFile(in: store)
        store.add(try .file(at: promised), limit: 50)
        store.add(.text("a"), limit: 50)
        store.add(.text("b"), limit: 50)

        let reloaded = ShelfStore(directory: directory, limit: 2)
        #expect(reloaded.items.map(\.kind) == [.text("b"), .text("a")])
        #expect(!exists(folder))
    }

    @Test func loadingSweepsFoldersNoItemPointsAtAndKeepsTheOnesItDoes() throws {
        let directory = try makeTempDirectory()
        let store = ShelfStore(directory: directory, limit: 50)
        let (kept, promised) = try makePromisedFile(in: store)
        store.add(try .file(at: promised), limit: 50)
        let (orphan, _) = try makePromisedFile(in: store)
        let empty = store.promisedDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)

        let reloaded = ShelfStore(directory: directory, limit: 50)
        #expect(reloaded.items.count == 1)
        #expect(exists(kept))
        #expect(!exists(orphan))
        #expect(!exists(empty))
    }

    @Test func addingAFileAlreadyOnTheShelfMovesItToTheFrontInsteadOfDuplicatingIt() throws {
        let directory = try makeTempDirectory()
        let file = try makeTempFile(in: directory)
        let store = ShelfStore(directory: directory, limit: 50)
        store.add(try .file(at: file), limit: 50)
        store.add(.text("a"), limit: 50)
        let original = store.items[1]

        store.add(try .file(at: file), limit: 50)
        #expect(store.items.count == 2)
        #expect(store.items[0].id == original.id)
        #expect(store.items[0].addedAt > original.addedAt)
        #expect(ShelfStore(directory: directory, limit: 50).items == store.items)
    }

    @Test func aPromisedCardDroppedBackOnTheShelfKeepsItsCopy() throws {
        let store = ShelfStore(directory: try makeTempDirectory(), limit: 50)
        let (folder, promised) = try makePromisedFile(in: store)
        store.add(try .file(at: promised), limit: 50)
        store.add(try .file(at: promised), limit: 50)
        #expect(store.items.count == 1)

        store.remove(id: store.items[0].id)
        #expect(!exists(folder))
    }

    @Test func renamedFileShowsItsNewNameAndKeepsAFreshBookmarkAfterLoad() throws {
        let directory = try makeTempDirectory()
        let file = try makeTempFile(named: "a.txt", in: directory)
        let store = ShelfStore(directory: directory, limit: 50)
        store.add(try .file(at: file), limit: 50)
        guard case .file(let oldBookmark, _, _) = store.items[0].kind else { Issue.record("not a file"); return }

        let elsewhere = try makeTempDirectory().appending(path: "renamed.txt")
        try FileManager.default.moveItem(at: file, to: elsewhere)

        let reloaded = ShelfStore(directory: directory, limit: 50)
        guard case .file(let newBookmark, let name, _) = reloaded.items[0].kind else { Issue.record("file was dropped"); return }
        #expect(name == "renamed.txt")
        #expect(newBookmark != oldBookmark)
        #expect(ShelfStore(directory: directory, limit: 50).items == reloaded.items)
    }
}
