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

    /// A stored image name: the SHA-256 hex of some bytes plus ".png".
    nonisolated static func imageName(_ seed: String) -> String {
        Data(seed.utf8).sha256Hex + ".png"
    }

    static func image(_ fileName: String) -> ClipboardContent {
        .image(ClipboardImage(fileName: fileName, pixelWidth: 1, pixelHeight: 1, byteCount: 4))
    }

    /// Three items, one of them the image `imageName("kept")`, and a board pinning the first.
    static func history(_ text: String = "Xin chào") -> ClipboardHistory {
        var history = ClipboardHistory()
        history.items = [item(.text(text)), item(image(imageName("kept"))), item(.link(URL(string: "https://example.com")!))]
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

    /// The stamp of the single `history.corrupt-<stamp>.json` in the store folder.
    func corruptHistoryStamp() throws -> Substring {
        let stamps = try contents(of: directory).compactMap { $0.wholeMatch(of: /history\.corrupt-(\d{8}-\d{6})\.json/)?.1 }
        #expect(stamps.count == 1)
        return try #require(stamps.first)
    }

    @Test func loadWithoutFilesCreatesTheFoldersAndReturnsAnEmptyHistory() {
        #expect(makeStore().load() == ClipboardHistory())
        #expect(exists(file("images")))
        #expect(!exists(file("history.json")))
    }

    @Test func savedHistoryLoadsBackEqual() async {
        let store = makeStore()
        _ = store.load()
        let history = Self.history()

        store.scheduleSave(history)
        scheduler.advance(by: .seconds(1))
        await store.waitForWrites()

        #expect(store.writeCount == 1)
        #expect(makeStore().load() == history)
    }

    @Test func savesWithinOneSecondCoalesceIntoOneWriteOfTheLatestValue() async {
        let store = makeStore()
        _ = store.load()

        store.scheduleSave(Self.history("first"))
        scheduler.advance(by: .milliseconds(400))
        store.scheduleSave(Self.history("second"))
        scheduler.advance(by: .milliseconds(400))
        let last = Self.history("third")
        store.scheduleSave(last)
        scheduler.advance(by: .milliseconds(999))
        await store.waitForWrites()
        #expect(store.writeCount == 0)
        #expect(!exists(file("history.json")))

        scheduler.advance(by: .milliseconds(1))
        await store.waitForWrites()
        #expect(store.writeCount == 1)
        #expect(scheduler.pendingCount == 0)
        #expect(makeStore().load() == last)
    }

    @Test func changesEveryNineTenthsOfASecondStillWriteWithinFiveSeconds() async {
        let store = makeStore()
        _ = store.load()
        for index in 0..<5 {
            store.scheduleSave(Self.history("change \(index)"))
            scheduler.advance(by: .milliseconds(900))
        }
        let last = Self.history("change 5")
        store.scheduleSave(last)
        scheduler.advance(by: .milliseconds(499))
        await store.waitForWrites()
        #expect(store.writeCount == 0)

        scheduler.advance(by: .milliseconds(1))
        await store.waitForWrites()
        #expect(store.writeCount == 1)
        #expect(scheduler.pendingCount == 0)
        #expect(makeStore().load() == last)
    }

    @Test func nothingIsWrittenBeforeTheTimerAndFlushWritesAtOnce() async {
        let store = makeStore()
        _ = store.load()
        let history = Self.history()

        store.scheduleSave(history)
        scheduler.advance(by: .milliseconds(500))
        await store.waitForWrites()
        #expect(store.writeCount == 0)
        #expect(!exists(file("history.json")) && !exists(file("boards.json")))

        await store.flush()
        #expect(store.writeCount == 1)
        #expect(scheduler.pendingCount == 0)
        #expect(makeStore().load() == history)

        scheduler.advance(by: .seconds(6))
        await store.flush()
        #expect(store.writeCount == 1)
    }

    @Test func failedWriteKeepsTheValueForTheNextFlushAndWritesBoardsFirst() async throws {
        let store = makeStore()
        _ = store.load()
        let history = Self.history()
        try FileManager.default.createDirectory(at: file("boards.json"), withIntermediateDirectories: false)

        store.scheduleSave(history)
        scheduler.advance(by: .seconds(1))
        await store.waitForWrites()
        #expect(store.writeCount == 0)
        #expect(!exists(file("history.json")))

        try FileManager.default.removeItem(at: file("boards.json"))
        await store.flush()
        #expect(store.writeCount == 1)
        #expect(makeStore().load() == history)
    }

    @Test func failedWriteDoesNotReplaceANewerChange() async throws {
        let store = makeStore()
        _ = store.load()
        try FileManager.default.createDirectory(at: file("boards.json"), withIntermediateDirectories: false)
        store.scheduleSave(Self.history("older"))
        scheduler.advance(by: .seconds(1))
        let newer = Self.history("newer")
        store.scheduleSave(newer)
        await store.waitForWrites()
        #expect(store.writeCount == 0)

        try FileManager.default.removeItem(at: file("boards.json"))
        scheduler.advance(by: .seconds(1))
        await store.waitForWrites()
        #expect(store.writeCount == 1)
        #expect(makeStore().load() == newer)
    }

    @Test func undecodableItemIsDroppedAndTheRestLoad() async throws {
        let store = makeStore()
        _ = store.load()
        let history = Self.history()
        store.scheduleSave(history)
        await store.flush()

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
    func corruptHistoryIsRenamedAndBoardsStillLoad(corrupt: String) async throws {
        let store = makeStore()
        _ = store.load()
        let history = Self.history()
        store.scheduleSave(history)
        await store.flush()
        try Data(corrupt.utf8).write(to: file("history.json"))

        let loaded = makeStore().load()

        #expect(loaded.items.isEmpty)
        #expect(loaded.boards == history.boards)
        #expect(!exists(file("history.json")))
        let kept = try Data(contentsOf: file("history.corrupt-\(try corruptHistoryStamp()).json"))
        #expect(kept == Data(corrupt.utf8))
    }

    @Test func corruptBoardsAreRenamedAndItemsStillLoad() async throws {
        let store = makeStore()
        _ = store.load()
        let history = Self.history()
        store.scheduleSave(history)
        await store.flush()
        try Data("{}".utf8).write(to: file("boards.json"))

        let loaded = makeStore().load()

        #expect(loaded.items == history.items)
        #expect(loaded.boards.isEmpty)
        #expect(try contents(of: directory).contains { $0.wholeMatch(of: /boards\.corrupt-\d{8}-\d{6}\.json/) != nil })
        #expect(!exists(file("images.corrupt")))
    }

    @Test func corruptFilesWithinTheSameSecondGetNumberedNames() throws {
        let instant = Date(timeIntervalSinceReferenceDate: 800_000_000)
        _ = makeStore { instant }.load()
        for index in 0..<3 {
            try Data("broken \(index)".utf8).write(to: file("history.json"))
            _ = makeStore { instant }.load()
        }

        let names = try contents(of: directory).filter { $0.contains(".corrupt-") }
        let stems = names.compactMap { $0.wholeMatch(of: /history\.corrupt-(\d{8}-\d{6})\.json/)?.1 }
        let stem = try #require(stems.first)
        let suffixes = ["", "-1", "-2"]
        #expect(Set(names) == Set(suffixes.flatMap { ["history.corrupt-\(stem)\($0).json", "images.corrupt-\(stem)\($0)"] }))
        for (index, suffix) in suffixes.enumerated() {
            #expect(try String(contentsOf: file("history.corrupt-\(stem)\(suffix).json"), encoding: .utf8) == "broken \(index)")
        }
    }

    @Test func unreadableHistoryMovesItsImagesAsideWhereLaterLoadsKeepThem() async throws {
        let store = makeStore()
        _ = store.load()
        let names = [Self.imageName("kept"), Self.imageName("other")]
        for name in names { try store.saveImage(Data(name.utf8), fileName: name) }
        store.scheduleSave(Self.history())
        await store.flush()
        try Data("not json".utf8).write(to: file("history.json"))

        #expect(makeStore().load().items.isEmpty)
        _ = makeStore().load()

        #expect(try contents(of: file("images.corrupt-\(try corruptHistoryStamp())")).sorted() == names.sorted())
        #expect(try contents(of: file("images")).isEmpty)
    }

    @Test func loadDeletesOrphanImagesAndKeepsReferencedOnes() async throws {
        let store = makeStore()
        _ = store.load()
        let kept = Self.imageName("kept")
        try store.saveImage(Data("kept".utf8), fileName: kept)
        try store.saveImage(Data("orphan".utf8), fileName: Self.imageName("orphan"))
        store.scheduleSave(Self.history())
        await store.flush()

        _ = makeStore().load()

        #expect(try contents(of: file("images")) == [kept])
    }

    @Test func loadKeepsImagesOfTheUnsavedHistory() throws {
        let store = makeStore()
        _ = store.load()
        let kept = Self.imageName("kept")
        try store.saveImage(Data("kept".utf8), fileName: kept)
        store.scheduleSave(Self.history())

        _ = store.load()

        #expect(try contents(of: file("images")) == [kept])
    }

    @Test func saveImageKeepsAnExistingFileAndDeleteImagesRemovesFiles() throws {
        let store = makeStore()
        _ = store.load()
        let first = Self.imageName("a"), second = Self.imageName("b")
        #expect(store.imageURL(fileName: first) == file("images").appending(path: first))

        try store.saveImage(Data("first".utf8), fileName: first)
        try store.saveImage(Data("second".utf8), fileName: first)
        try store.saveImage(Data("other".utf8), fileName: second)
        #expect(try Data(contentsOf: #require(store.imageURL(fileName: first))) == Data("first".utf8))

        store.deleteImages(for: [Self.item(Self.image(first)), Self.item(.text(first)), Self.item(Self.image(Self.imageName("missing")))])

        #expect(try contents(of: file("images")) == [second])
    }

    nonisolated static let victim = imageName("victim")
    nonisolated static let unsafeFileNames: [String] = {
        let hex = String(victim.dropLast(4))
        return [
            "", ".", "..", "a.png", ".hidden.png", "../\(victim)", "sub/\(victim)", "/tmp/\(victim)",
            "\(hex.uppercased()).png", hex, "\(hex).PNG", "\(hex)0.png", "\(victim).png",
        ]
    }()

    @Test(arguments: unsafeFileNames)
    func unsafeImageFileNamesAreRejected(fileName: String) throws {
        let store = makeStore()
        _ = store.load()
        let victim = file(Self.victim)
        try Data("keep".utf8).write(to: victim)

        #expect(store.imageURL(fileName: fileName) == nil)
        #expect(throws: CocoaError.self) { try store.saveImage(Data("x".utf8), fileName: fileName) }
        store.deleteImages(for: [Self.item(Self.image(fileName))])

        #expect(try Data(contentsOf: victim) == Data("keep".utf8))
        #expect(try contents(of: file("images")).isEmpty)
    }

    // MARK: The copy stack

    static func stack(_ texts: String...) -> CopyStack {
        var stack = CopyStack()
        stack.start()
        for text in texts { stack.collect(item(.text(text))) }
        return stack
    }

    @Test func aSavedStackLoadsBackEqual() async throws {
        let store = makeStore()
        _ = store.load()
        let stack = Self.stack("một", "hai")

        store.saveStack(stack)
        await store.waitForWrites()

        #expect(exists(file("stack.json")))
        #expect(makeStore().loadStack() == stack)
    }

    @Test func thereIsNoStackToLoadWithoutAFileOrFromAFileThatCannotBeRead() throws {
        let store = makeStore()
        _ = store.load()
        #expect(store.loadStack() == nil)

        try Data("not json".utf8).write(to: file("stack.json"))
        #expect(store.loadStack() == nil)
    }

    @Test func savingNothingDeletesTheFileAndIsFineWithoutOne() async throws {
        let store = makeStore()
        _ = store.load()
        store.saveStack(nil)
        await store.waitForWrites()
        #expect(!exists(file("stack.json")))

        store.saveStack(Self.stack("một"))
        store.saveStack(nil)
        await store.waitForWrites()
        #expect(!exists(file("stack.json")))
    }

    @Test func theNewestSavedStackWins() async throws {
        let store = makeStore()
        _ = store.load()
        store.saveStack(Self.stack("một"))
        let newest = Self.stack("một", "hai")
        store.saveStack(newest)

        await store.flush()

        #expect(makeStore().loadStack() == newest)
    }

    @Test func theStackIsKeptApartFromTheHistoryFiles() async throws {
        let store = makeStore()
        _ = store.load()
        store.scheduleSave(Self.history())
        store.saveStack(Self.stack("một"))
        await store.flush()

        #expect(makeStore().load().items.count == 3)
        #expect(makeStore().loadStack()?.entries.count == 1)
    }
}
