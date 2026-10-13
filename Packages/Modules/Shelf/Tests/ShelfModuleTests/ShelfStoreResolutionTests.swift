import Foundation
import Testing
import UniformTypeIdentifiers
@testable import ShelfModule

/// Stands in for the bookmark resolver: counts the calls and says where each bookmark points, without the file system.
final class FakeBookmarks {
    private(set) var calls = 0
    private var table: [Data: URL] = [:]

    /// A file item whose bookmark is only a label; `locate` decides where it "is".
    func item(_ name: String, at url: URL? = nil) -> ShelfItem.Kind {
        let bookmark = Data(name.utf8)
        table[bookmark] = url ?? URL(filePath: "/fake/\(name)")
        return .file(bookmark: bookmark, name: name, utType: .plainText)
    }

    func move(_ name: String, to url: URL) { table[Data(name.utf8)] = url }
    func lose(_ name: String) { table[Data(name.utf8)] = nil }

    func resolve(_ bookmark: Data) -> ShelfStore.Resolution? {
        calls += 1
        return table[bookmark].map { ($0, false) }
    }

    func store(in directory: URL, limit: Int = 50) -> ShelfStore {
        ShelfStore(directory: directory, limit: limit, resolve: { [self] in resolve($0) })
    }
}

@Suite struct ShelfStoreResolutionTests {
    @Test func loadingResolvesEachFileOnceAndReadingLocationsNeverResolvesAgain() throws {
        let directory = try makeTempDirectory()
        let bookmarks = FakeBookmarks()
        let first = bookmarks.store(in: directory)
        for name in ["a", "b", "c"] { first.add(bookmarks.item(name), limit: 50) }

        let loaded = bookmarks.store(in: directory)
        let afterLoad = bookmarks.calls
        for _ in 0..<100 { for item in loaded.items { _ = loaded.url(of: item) } }
        #expect(loaded.items.count == 3)
        #expect(bookmarks.calls == afterLoad)
        #expect(loaded.items.allSatisfy { loaded.url(of: $0) != nil })
        #expect(loaded.url(of: loaded.items[0])?.path == "/fake/c")
    }

    @Test func loadingResolvesEachFileExactlyOnce() throws {
        let directory = try makeTempDirectory()
        let bookmarks = FakeBookmarks()
        let first = bookmarks.store(in: directory)
        for name in ["a", "b", "c"] { first.add(bookmarks.item(name), limit: 50) }
        let before = bookmarks.calls

        _ = bookmarks.store(in: directory)
        #expect(bookmarks.calls - before == 3)
    }

    @Test func addingAFileResolvesOnlyTheNewOne() throws {
        let bookmarks = FakeBookmarks()
        let store = bookmarks.store(in: try makeTempDirectory())
        for name in ["a", "b", "c", "d", "e"] { store.add(bookmarks.item(name), limit: 50) }
        let before = bookmarks.calls

        store.add(bookmarks.item("f"), limit: 50)
        #expect(bookmarks.calls - before == 1)
        #expect(store.url(of: store.items[0])?.path == "/fake/f")
    }

    @Test func textAndLinkItemsNeverResolveAnything() throws {
        let directory = try makeTempDirectory()
        let bookmarks = FakeBookmarks()
        let store = bookmarks.store(in: directory)
        store.add(.text("t"), limit: 50)
        store.add(.link(URL(string: "https://example.com")!), limit: 50)
        _ = bookmarks.store(in: directory)
        #expect(bookmarks.calls == 0)
        #expect(store.items.count == 2)
        #expect(store.items.allSatisfy { store.url(of: $0) == nil })
    }

    @Test func aMovedFileIsFoundAgainOnDemandOnly() throws {
        let bookmarks = FakeBookmarks()
        let store = bookmarks.store(in: try makeTempDirectory())
        store.add(bookmarks.item("a"), limit: 50)
        let item = store.items[0]
        bookmarks.move("a", to: URL(filePath: "/elsewhere/a"))

        #expect(store.url(of: item)?.path == "/fake/a")
        let before = bookmarks.calls
        #expect(store.refreshedURL(of: item)?.path == "/elsewhere/a")
        #expect(bookmarks.calls - before == 1)
        #expect(store.url(of: item)?.path == "/elsewhere/a")
    }

    @Test func refreshingLocationsResolvesEveryFileOnce() throws {
        let bookmarks = FakeBookmarks()
        let store = bookmarks.store(in: try makeTempDirectory())
        store.add(bookmarks.item("a"), limit: 50)
        store.add(.text("t"), limit: 50)
        store.add(bookmarks.item("b"), limit: 50)
        bookmarks.move("a", to: URL(filePath: "/elsewhere/a"))
        let before = bookmarks.calls

        store.refreshLocations()
        #expect(bookmarks.calls - before == 2)
        #expect(store.items.count == 3)
        let a = try #require(store.items.first { if case .file(_, "a", _) = $0.kind { true } else { false } })
        #expect(store.url(of: a)?.path == "/elsewhere/a")
    }

    @Test func aFileThatIsGoneHasNoLocationButItsCardStays() throws {
        let bookmarks = FakeBookmarks()
        let store = bookmarks.store(in: try makeTempDirectory())
        store.add(bookmarks.item("a"), limit: 50)
        let item = store.items[0]
        bookmarks.lose("a")

        #expect(store.refreshedURL(of: item) == nil)
        #expect(store.url(of: item) == nil)
        #expect(store.items == [item])
    }

    @Test func aRenamedFileShowsItsNewNameAfterARefresh() throws {
        let directory = try makeTempDirectory()
        let file = try makeTempFile(named: "a.txt", in: directory)
        let store = ShelfStore(directory: directory, limit: 50)
        store.add(try .file(at: file), limit: 50)
        let item = store.items[0]
        let renamed = directory.appending(path: "b.txt")
        try FileManager.default.moveItem(at: file, to: renamed)

        let url = try #require(store.refreshedURL(of: item))
        #expect(url.lastPathComponent == "b.txt")
        guard case .file(_, let name, _) = store.items[0].kind else { Issue.record("not a file"); return }
        #expect(name == "b.txt")
        #expect(store.items[0].id == item.id)
        #expect(ShelfStore(directory: directory, limit: 50).items == store.items)
    }

    @Test func removingItemsForgetsTheirLocations() throws {
        let bookmarks = FakeBookmarks()
        let store = bookmarks.store(in: try makeTempDirectory())
        store.add(bookmarks.item("a"), limit: 50)
        store.add(bookmarks.item("b"), limit: 50)
        let (b, a) = (store.items[0], store.items[1])

        store.remove(id: a.id)
        #expect(store.url(of: a) == nil)
        #expect(store.url(of: b) != nil)
        store.removeAll()
        #expect(store.url(of: b) == nil)
    }

    @Test func addingTheSameTextOrLinkAgainMovesItToTheFrontInsteadOfDuplicatingIt() throws {
        let directory = try makeTempDirectory()
        let store = ShelfStore(directory: directory, limit: 50)
        let link = ShelfItem.Kind.link(URL(string: "https://example.com")!)
        store.add(.text("a"), limit: 50)
        store.add(link, limit: 50)
        store.add(.text("b"), limit: 50)
        let original = store.items[2]

        store.add(.text("a"), limit: 50)
        #expect(store.items.map(\.kind) == [.text("a"), .text("b"), link])
        #expect(store.items[0].id == original.id)
        store.add(link, limit: 50)
        #expect(store.items.map(\.kind) == [link, .text("a"), .text("b")])
        #expect(ShelfStore(directory: directory, limit: 50).items == store.items)
    }

    @Test func theSystemResolverFindsARealFileAndRefusesAMissingOne() throws {
        let file = try makeTempFile(in: try makeTempDirectory())
        let bookmark = try file.bookmarkData()
        let found = try #require(ShelfStore.resolveBookmark(bookmark))
        #expect(found.url.lastPathComponent == "note.txt")
        #expect(!found.isStale)

        try FileManager.default.removeItem(at: file)
        #expect(ShelfStore.resolveBookmark(bookmark) == nil)
    }
}
