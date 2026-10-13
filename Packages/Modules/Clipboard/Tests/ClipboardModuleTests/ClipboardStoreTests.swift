import Foundation
import MyNotchCore
import MyNotchTestSupport
import Testing
@testable import ClipboardModule

@Suite final class ClipboardStoreTests {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: "ClipboardStoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    let scheduler = ManualScheduler()

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    func makeStore(now: @escaping () -> Date = { .now }) -> ClipboardStore {
        ClipboardStore(directory: directory, scheduler: scheduler, logger: Log.logger(category: "ClipboardStoreTests"), now: now)
    }

    static func item(_ content: ClipboardContent) -> ClipboardItem {
        ClipboardItem(
            id: UUID(), content: content, contentHash: ClipboardContent.hash(of: content),
            copiedAt: .now, sourceBundleID: "com.apple.Safari", sourceAppName: "Safari"
        )
    }

    static func image(_ fileName: String) -> ClipboardContent {
        .image(ClipboardImage(fileName: fileName, pixelWidth: 1, pixelHeight: 1, byteCount: 4))
    }

    /// Three items, one of them an image, and a board pinning the first.
    static func history(_ text: String = "Xin chào") -> ClipboardHistory {
        var history = ClipboardHistory()
        history.items = [item(.text(text)), item(image("kept.png")), item(.link(URL(string: "https://example.com")!))]
        let board = history.createBoard(name: "Công việc")
        history.pin(itemID: history.items[0].id, to: board)
        return history
    }

    func file(_ name: String) -> URL {
        directory.appending(path: name)
    }

    func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }

    func contents(of url: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: url.path(percentEncoded: false))
    }

    @Test func loadWithoutFilesCreatesTheFoldersAndReturnsAnEmptyHistory() {
        #expect(makeStore().load() == ClipboardHistory())
        #expect(exists(file("images")))
        #expect(!exists(file("history.json")))
    }

    @Test func savedHistoryLoadsBackEqual() {
        let store = makeStore()
        _ = store.load()
        let history = Self.history()

        store.scheduleSave(history)
        scheduler.advance(by: .seconds(1))

        #expect(store.writeCount == 1)
        #expect(makeStore().load() == history)
    }

    @Test func savesWithinOneSecondCoalesceIntoOneWriteOfTheLatestValue() {
        let store = makeStore()
        _ = store.load()

        store.scheduleSave(Self.history("first"))
        scheduler.advance(by: .milliseconds(400))
        store.scheduleSave(Self.history("second"))
        scheduler.advance(by: .milliseconds(400))
        let last = Self.history("third")
        store.scheduleSave(last)
        scheduler.advance(by: .milliseconds(999))
        #expect(store.writeCount == 0)
        #expect(!exists(file("history.json")))

        scheduler.advance(by: .milliseconds(1))
        #expect(store.writeCount == 1)
        #expect(scheduler.pendingCount == 0)
        #expect(makeStore().load() == last)
    }

    @Test func nothingIsWrittenBeforeTheTimerAndFlushWritesAtOnce() {
        let store = makeStore()
        _ = store.load()
        let history = Self.history()

        store.scheduleSave(history)
        scheduler.advance(by: .milliseconds(500))
        #expect(store.writeCount == 0)
        #expect(!exists(file("history.json")) && !exists(file("boards.json")))

        store.flush()
        #expect(store.writeCount == 1)
        #expect(scheduler.pendingCount == 0)
        #expect(makeStore().load() == history)

        scheduler.advance(by: .seconds(2))
        store.flush()
        #expect(store.writeCount == 1)
    }

    @Test func failedWriteKeepsTheValueForTheNextFlush() throws {
        let store = makeStore()
        _ = store.load()
        let history = Self.history()
        try FileManager.default.createDirectory(at: file("history.json"), withIntermediateDirectories: false)

        store.scheduleSave(history)
        scheduler.advance(by: .seconds(1))
        #expect(store.writeCount == 0)

        try FileManager.default.removeItem(at: file("history.json"))
        store.flush()
        #expect(store.writeCount == 1)
        #expect(makeStore().load() == history)
    }

    @Test func undecodableItemIsDroppedAndTheRestLoad() throws {
        let store = makeStore()
        _ = store.load()
        let history = Self.history()
        store.scheduleSave(history)
        store.flush()

        let url = file("history.json")
        var items = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [Any])
        items.insert(["id": "not-a-uuid", "content": ["video": ["_0": "clip.mov"]]], at: 1)
        try JSONSerialization.data(withJSONObject: items).write(to: url)

        let loaded = makeStore().load()
        #expect(loaded.items == history.items)
        #expect(loaded.boards == history.boards)
        #expect(try contents(of: directory).filter { $0.contains("corrupt") }.isEmpty)
    }

    @Test(arguments: [#"{"items": []}"#, "not json"])
    func corruptHistoryIsRenamedAndBoardsStillLoad(corrupt: String) throws {
        let store = makeStore()
        _ = store.load()
        let history = Self.history()
        store.scheduleSave(history)
        store.flush()
        try Data(corrupt.utf8).write(to: file("history.json"))

        let loaded = makeStore().load()

        #expect(loaded.items.isEmpty)
        #expect(loaded.boards == history.boards)
        #expect(!exists(file("history.json")))
        let renamed = try contents(of: directory).filter { $0.wholeMatch(of: /history\.corrupt-\d{8}-\d{6}\.json/) != nil }
        #expect(renamed.count == 1)
        let kept = try Data(contentsOf: file(try #require(renamed.first)))
        #expect(kept == Data(corrupt.utf8))
    }

    @Test func corruptBoardsAreRenamedAndItemsStillLoad() throws {
        let store = makeStore()
        _ = store.load()
        let history = Self.history()
        store.scheduleSave(history)
        store.flush()
        try Data("{}".utf8).write(to: file("boards.json"))

        let loaded = makeStore().load()

        #expect(loaded.items == history.items)
        #expect(loaded.boards.isEmpty)
        #expect(try contents(of: directory).contains { $0.wholeMatch(of: /boards\.corrupt-\d{8}-\d{6}\.json/) != nil })
    }

    @Test func loadDeletesOrphanImagesAndKeepsReferencedOnes() throws {
        let store = makeStore()
        _ = store.load()
        try store.saveImage(Data("kept".utf8), fileName: "kept.png")
        try store.saveImage(Data("orphan".utf8), fileName: "orphan.png")
        store.scheduleSave(Self.history())
        store.flush()

        _ = makeStore().load()

        #expect(try contents(of: file("images")) == ["kept.png"])
    }

    @Test func saveImageKeepsAnExistingFileAndDeleteImagesRemovesFiles() throws {
        let store = makeStore()
        _ = store.load()
        #expect(store.imageURL(fileName: "a.png") == file("images").appending(path: "a.png"))

        try store.saveImage(Data("first".utf8), fileName: "a.png")
        try store.saveImage(Data("second".utf8), fileName: "a.png")
        try store.saveImage(Data("other".utf8), fileName: "b.png")
        #expect(try Data(contentsOf: #require(store.imageURL(fileName: "a.png"))) == Data("first".utf8))

        store.deleteImages(for: [Self.item(Self.image("a.png")), Self.item(.text("a.png")), Self.item(Self.image("missing.png"))])

        #expect(try contents(of: file("images")) == ["b.png"])
    }

    @Test func corruptFilesWithinTheSameSecondGetNumberedNames() throws {
        let instant = Date(timeIntervalSinceReferenceDate: 800_000_000)
        _ = makeStore { instant }.load()
        for index in 0..<3 {
            try Data("broken \(index)".utf8).write(to: file("history.json"))
            _ = makeStore { instant }.load()
        }

        let names = try contents(of: directory).filter { $0.hasPrefix("history.corrupt-") }
        let stems = names.compactMap { $0.wholeMatch(of: /(history\.corrupt-\d{8}-\d{6})\.json/)?.1 }
        let stem = try #require(stems.first)
        #expect(Set(names) == ["\(stem).json", "\(stem)-1.json", "\(stem)-2.json"])
        for (index, suffix) in ["", "-1", "-2"].enumerated() {
            #expect(try String(contentsOf: file("\(stem)\(suffix).json"), encoding: .utf8) == "broken \(index)")
        }
    }

    @Test func imagesAreKeptWhenTheHistoryFileIsMovedAside() throws {
        let store = makeStore()
        _ = store.load()
        try store.saveImage(Data("kept".utf8), fileName: "kept.png")
        try store.saveImage(Data("other".utf8), fileName: "other.png")
        store.scheduleSave(Self.history())
        store.flush()
        try Data("not json".utf8).write(to: file("history.json"))

        #expect(makeStore().load().items.isEmpty)
        #expect(try contents(of: file("images")).sorted() == ["kept.png", "other.png"])
    }

    nonisolated static let unsafeFileNames = ["", ".", "..", ".hidden.png", "../victim.png", "sub/a.png", "/tmp/a.png"]

    @Test(arguments: unsafeFileNames)
    func unsafeImageFileNamesAreRejected(fileName: String) throws {
        let store = makeStore()
        _ = store.load()
        let victim = file("victim.png")
        try Data("keep".utf8).write(to: victim)

        #expect(store.imageURL(fileName: fileName) == nil)
        #expect(throws: CocoaError.self) { try store.saveImage(Data("x".utf8), fileName: fileName) }
        store.deleteImages(for: [Self.item(Self.image(fileName))])

        #expect(try Data(contentsOf: victim) == Data("keep".utf8))
        #expect(try contents(of: file("images")).isEmpty)
    }
}
