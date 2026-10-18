import AppKit
import Foundation
import ImageIO
import MyNotchCore
import MyNotchTestSupport
import Testing
import UniformTypeIdentifiers
@testable import ClipboardModule

/// What the Storage page asks of Clipboard: sizes, the two cleans and the daily rule, with the module running and with it stopped. Every
/// folder is the harness's temporary one, and the pasteboard is a fake.
@Suite final class ClipboardStorageCleaningTests {
    static let mediaID = "clipboard.media"
    static let previewsID = "clipboard.linkpreviews"
    static let keeps = "Giữ mục đã ghim, các bảng và mục đã khoá"
    static let hour: TimeInterval = 3_600
    static let day: TimeInterval = 86_400

    let fixture = OptionalFeaturesFixture()
    /// Stands in for the app's settings of the module when none has reached it, so no test reads the test runner's own.
    let appDefaults = makeIsolatedDefaults()
    var module: ClipboardModule { fixture.module }
    var directory: URL { fixture.directory }
    var storage: ModuleStorage { fixture.harness.storageRoot.storage(for: "clipboard") }
    var imagesDirectory: URL { directory.appending(path: "images", directoryHint: .isDirectory) }
    var previewsDirectory: URL { fixture.linkPreviewsDirectory }
    var now: Date { fixture.system.now }

    init() {
        fixture.module.storageFallbackSettings = SettingsStore(defaults: appDefaults)
    }

    // MARK: Fixtures

    /// A picture the history holds: the item, the name of its file and how big the file is.
    struct Picture {
        let item: ClipboardItem
        let name: String
        let bytes: Int
    }

    func picture(_ seed: String, bytes: Int, daysAgo: Double = 1, secret: Bool = false) -> Picture {
        let content = ClipboardModuleTests.image(seed, byteCount: bytes)
        var item = ClipboardModuleTests.item(content, copiedAt: now.addingTimeInterval(-daysAgo * Self.day))
        if secret { item.sensitive = true }
        return Picture(item: item, name: Data(seed.utf8).sha256Hex + ".png", bytes: bytes)
    }

    /// A file of `bytes` bytes last changed `age` seconds before the fixed "now" the module and the tests share.
    @discardableResult
    func writeBlob(_ name: String, in folder: URL, bytes: Int, age: TimeInterval = 2 * hour) throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: name, directoryHint: .notDirectory)
        try Data(repeating: 7, count: bytes).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-age)], ofItemAtPath: url.path(percentEncoded: false))
        return url
    }

    var hour: TimeInterval { Self.hour }

    func store(_ picture: Picture) throws {
        try writeBlob(picture.name, in: imagesDirectory, bytes: picture.bytes)
    }

    func orphanName(_ seed: String) -> String {
        Data(seed.utf8).sha256Hex + ".png"
    }

    func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }

    func imageFile(_ name: String) -> URL {
        imagesDirectory.appending(path: name, directoryHint: .notDirectory)
    }

    /// Writes history files as an earlier run would have left them.
    func persist(_ history: ClipboardHistory) async {
        let store = ClipboardStore(directory: directory, scheduler: ManualScheduler(), logger: Log.logger(category: "ClipboardStorageCleaningTests"))
        _ = store.load()
        store.scheduleSave(history)
        await store.flush()
    }

    func saved() async throws -> ClipboardHistory {
        try #require(await ClipboardStoredHistory.peek(directory: directory))
    }

    /// Lets a running module write what it has not written yet.
    func settle() async {
        if let store = module.store { await store.flush() }
    }

    /// The history files and the module's memory, which must say the same once settled.
    func savedIDs(running: Bool) async throws -> [UUID] {
        await settle()
        let ids = try await saved().items.map(\.id)
        if running { #expect(module.state.history.items.map(\.id) == ids) }
        return ids
    }

    /// Three unpinned pictures (1,000 and 4,000 bytes, and a secret of 3,000), one pinned to a board (2,000), a text, a link and a copied file (a path, which stores nothing).
    struct World {
        let a: Picture
        let b: Picture
        let c: Picture
        let d: Picture
        let text: ClipboardItem
        let link: ClipboardItem
        let files: ClipboardItem
        var history: ClipboardHistory

        var pictures: [Picture] { [a, b, c, d] }
    }

    func makeWorld() -> World {
        let a = picture("a", bytes: 1_000, daysAgo: 1)
        let b = picture("b", bytes: 2_000, daysAgo: 2)
        let c = picture("c", bytes: 3_000, daysAgo: 3, secret: true)
        let d = picture("d", bytes: 4_000, daysAgo: 4)
        let text = ClipboardModuleTests.item(.text("văn bản riêng của tôi"), copiedAt: now.addingTimeInterval(-5 * Self.day))
        let link = ClipboardModuleTests.item(.link(URL(string: "https://example.com/bai-viet-rieng-tu")!), copiedAt: now.addingTimeInterval(-6 * Self.day))
        let files = ClipboardModuleTests.item(
            .files([URL(filePath: "/Users/ai-do/Tài liệu/hợp-đồng-bí-mật.pdf")]), copiedAt: now.addingTimeInterval(-7 * Self.day)
        )
        var history = ClipboardHistory(items: [a.item, b.item, c.item, d.item, text, link, files])
        history.pin(itemID: b.item.id, to: history.createBoard(name: "Công việc"))
        return World(a: a, b: b, c: c, d: d, text: text, link: link, files: files, history: history)
    }

    /// Brings the world to the state under test: on disk only, or loaded by a running module.
    func arrange(_ world: World, running: Bool) async throws {
        await persist(world.history)
        for picture in world.pictures { try store(picture) }
        if running {
            await fixture.start()
            #expect(module.state.history.items.count == world.history.items.count)
        } else {
            #expect(fixture.harness.registry.state(of: "clipboard") == .disabled)
        }
    }

    final class Lines {
        var all: [String] = []
    }

    // MARK: Sizes

    @Test(arguments: [false, true]) func theCategoriesMeasureOnlyWhatACleanMayRemove(running: Bool) async throws {
        let world = makeWorld()
        try await arrange(world, running: running)
        // A picture no item holds, and the pictures of two links, written after a start would have swept them.
        try writeBlob(orphanName("orphan"), in: imagesDirectory, bytes: 5_000)
        try writeBlob("link-" + Data("x".utf8).sha256Hex + ".png", in: previewsDirectory, bytes: 700)
        try writeBlob("link-" + Data("y".utf8).sha256Hex + ".png", in: previewsDirectory, bytes: 300)

        let categories = await module.storageCategories(storage: storage)

        #expect(categories == [
            StorageCategory(id: Self.mediaID, title: "Ảnh và file", bytes: 5_000, keeps: Self.keeps, canClean: true),
            StorageCategory(id: Self.previewsID, title: "Xem trước link", bytes: 1_000, keeps: nil, canClean: true),
        ])
    }

    @Test func aModuleThatNeverRanIsMeasuredAsZeroAndLeavesNoFolder() async {
        let categories = await module.storageCategories(storage: storage)

        #expect(categories.map(\.bytes) == [0, 0])
        #expect(await ClipboardStoredHistory.peek(directory: directory) == ClipboardHistory())
        #expect(!exists(directory))
        #expect(await module.clean(categoryID: Self.mediaID, storage: storage) == 0)
        #expect(await module.clean(categoryID: Self.previewsID, storage: storage) == 0)
        #expect(await module.autoClean(now: now, storage: storage) == 0)
        #expect(!exists(directory))
    }

    @Test func aRunningModuleIsMeasuredFromWhatItHoldsNotWhatItSaved() async throws {
        let world = makeWorld()
        try await arrange(world, running: true)
        // A copy the files do not know yet: its picture is on disk, its item only in memory, as in the second before a save.
        let fresh = picture("fresh", bytes: 800)
        try store(fresh)
        module.update { history in
            history.items.insert(fresh.item, at: 0)
            return []
        }

        let media = try #require(await module.storageCategories(storage: storage).first)

        #expect(media.bytes == 5_800)
    }

    // MARK: Cleaning pictures and files

    @Test(arguments: [false, true]) func cleaningPicturesRemovesTheOthersFromHistoryAndDisk(running: Bool) async throws {
        let world = makeWorld()
        try await arrange(world, running: running)

        let freed = await module.clean(categoryID: Self.mediaID, storage: storage)

        #expect(freed == 5_000)
        // Pinned, in a board and secret stay; so do the text, the link and the copied file, which stores nothing a clean could free.
        let kept = try await savedIDs(running: running)
        #expect(kept == [world.b.item.id, world.c.item.id, world.text.id, world.link.id, world.files.id])
        #expect(!exists(imageFile(world.a.name)))
        #expect(!exists(imageFile(world.d.name)))
        #expect(exists(imageFile(world.b.name)))
        #expect(exists(imageFile(world.c.name)))
        #expect(try await saved().boards.first?.itemIDs == [world.b.item.id])
        let after = try #require(await module.storageCategories(storage: storage).first)
        #expect(after.bytes == 0)
    }

    @Test(arguments: [false, true]) func aSecondCleanFreesNothingAndWritesNothing(running: Bool) async throws {
        let world = makeWorld()
        try await arrange(world, running: running)
        #expect(await module.clean(categoryID: Self.mediaID, storage: storage) == 5_000)
        await settle()
        let history = directory.appending(path: "history.json")
        let before = try Data(contentsOf: history)
        let modified = try FileManager.default.attributesOfItem(atPath: history.path(percentEncoded: false))[.modificationDate] as? Date

        #expect(await module.clean(categoryID: Self.mediaID, storage: storage) == 0)
        await settle()

        #expect(try Data(contentsOf: history) == before)
        #expect(try FileManager.default.attributesOfItem(atPath: history.path(percentEncoded: false))[.modificationDate] as? Date == modified)
    }

    @Test func anUnknownCategoryCleansNothing() async throws {
        let world = makeWorld()
        try await arrange(world, running: false)

        #expect(await module.clean(categoryID: "clipboard.nothing", storage: storage) == 0)
        #expect(await module.clean(categoryID: "clipboard.cache", storage: storage) == 0)

        #expect(try await saved().items.count == world.history.items.count)
    }

    @Test func onlyLooseNonSecretStoredPicturesCanBeCleaned() {
        let world = makeWorld()
        var history = world.history
        let open = history.createBoard(name: "Mở")
        let closed = history.createBoard(name: "Đóng")
        let loose = picture("loose", bytes: 10).item
        let inOpen = picture("in-open", bytes: 10).item
        let inClosed = picture("in-closed", bytes: 10).item
        history.items += [loose, inOpen, inClosed]
        history.pin(itemID: inOpen.id, to: open)
        history.pin(itemID: inClosed.id, to: closed)
        // Two boards that have a lock: one opened with the password, one that opens with Touch ID.
        history.boards[1].lock = ClipboardBoardLock(method: .password, itemCount: 1, isUnlocked: true)
        history.boards[2].lock = ClipboardBoardLock(method: .touchID, itemCount: 1, isUnlocked: true)

        // The two unpinned pictures and the loose one; not the pinned, the secret, the two of boards with a lock, and nothing that stores
        // nothing (text, link, copied file).
        #expect(history.releasableMediaItems.map(\.id) == [world.a.item.id, world.d.item.id, loose.id])
    }

    @Test func aLockedBoardsPicturesAreNeitherCleanedNorLost() async throws {
        await fixture.start()
        // Sealing reads the picture and checks that its name is the hash of what it holds, as every stored picture's is.
        let keptBytes = Data(repeating: 9, count: 1_200)
        let keptName = keptBytes.sha256Hex + ".png"
        let keptContent = ClipboardContent.image(ClipboardImage(fileName: keptName, pixelWidth: 1, pixelHeight: 1, byteCount: keptBytes.count))
        let kept = Picture(item: ClipboardModuleTests.item(keptContent, copiedAt: now.addingTimeInterval(-Self.day)), name: keptName, bytes: keptBytes.count)
        try writeBlob(keptName, in: imagesDirectory, bytes: 0)
        try keptBytes.write(to: imageFile(keptName))
        let loose = picture("loose", bytes: 900)
        try store(loose)
        module.update { history in
            history.items.insert(contentsOf: [kept.item, loose.item], at: 0)
            return []
        }
        let board = try #require(module.createBoard(named: "Két"))
        module.pin(kept.item, to: board)
        try await module.lockBoard(board, setup: .password(OptionalFeaturesFixture.password))
        #expect(!exists(imageFile(kept.name)))

        // Closed: its picture is in the vault file, and the history holds nothing of it.
        #expect(await module.clean(categoryID: Self.mediaID, storage: storage) == 900)
        #expect(!module.state.history.items.contains { $0.id == kept.item.id })
        try await module.unlockBoard(board, credential: .password(OptionalFeaturesFixture.password))
        #expect(module.state.history.items.contains { $0.id == kept.item.id })

        // Open: the picture is in memory and its item is in the board, so a clean leaves both.
        #expect(await module.clean(categoryID: Self.mediaID, storage: storage) == 0)
        #expect(module.state.history.items.contains { $0.id == kept.item.id })
        #expect(module.openImages.data(forFileName: kept.name) != nil)
    }

    @Test func aRunningCleanForgetsTheThumbnailsOfWhatWasRemoved() async throws {
        let world = makeWorld()
        try await arrange(world, running: true)
        try writePNG(to: imageFile(world.a.name))
        let url = imageFile(world.a.name)
        _ = try #require(await module.thumbnails.thumbnail(for: url))
        #expect(module.thumbnails.cachedThumbnail(for: url) != nil)

        _ = await module.clean(categoryID: Self.mediaID, storage: storage)

        #expect(module.thumbnails.cachedThumbnail(for: url) == nil)
        #expect(!exists(url))
    }

    func writePNG(to url: URL) throws {
        let context = try #require(CGContext(
            data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let image = try #require(context.makeImage())
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
    }

    @Test(arguments: [false, true]) func anEntryThatStoresNothingSurvivesEveryCleanAndAgesOutWithTheRetentionRule(running: Bool) async throws {
        let world = makeWorld()
        try await arrange(world, running: running)
        let pathOnly = world.files.id

        // The category's own clean, then the page's "clean everything" with its confirmation total.
        #expect(await module.clean(categoryID: Self.mediaID, storage: storage) == 5_000)
        #expect(try await savedIDs(running: running).contains(pathOnly))
        let center = fixture.harness.registry.storageCenter
        await center.refresh()
        #expect(center.cleanableBytes == 0)
        #expect(await center.cleanAll() == 0)
        #expect(try await savedIDs(running: running) == [world.b.item.id, world.c.item.id, world.text.id, world.link.id, pathOnly])

        // No clean reached it, but its age does: the daily rule (a month by default) takes it with the text, the link and the secret
        // picture, which retention does not protect, while the pinned picture stays.
        #expect(await module.autoClean(now: now.addingTimeInterval(40 * Self.day), storage: storage) == 3_000)
        #expect(try await savedIDs(running: running) == [world.b.item.id])
    }

    // MARK: Things that stop a clean

    @Test func aDamagedBoardsFileMeansNothingIsDeleted() async throws {
        let world = makeWorld()
        try await arrange(world, running: false)
        let boards = directory.appending(path: "boards.json")
        try Data("[{\"id\": 12}]".utf8).write(to: boards)

        #expect(await module.clean(categoryID: Self.mediaID, storage: storage) == 0)
        #expect(await module.autoClean(now: now, storage: storage) == 0)
        #expect((await module.storageCategories(storage: storage)).first?.bytes == 0)

        // Without the boards nothing says what is pinned, so no picture goes, and the damaged file is left where it is.
        for picture in world.pictures { #expect(exists(imageFile(picture.name))) }
        #expect(try Data(contentsOf: boards) == Data("[{\"id\": 12}]".utf8))
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false))
        #expect(!names.contains { $0.contains("corrupt") })
    }

    @Test func aDamagedItemEntryMeansNothingIsDeleted() async throws {
        let world = makeWorld()
        try await arrange(world, running: false)
        let historyFile = directory.appending(path: "history.json")
        let good = try String(contentsOf: historyFile, encoding: .utf8)
        try Data((String(good.dropLast()) + ",{\"id\":\"không phải\"}]").utf8).write(to: historyFile)
        try writeBlob(orphanName("orphan"), in: imagesDirectory, bytes: 100)

        #expect(await module.clean(categoryID: Self.mediaID, storage: storage) == 0)
        #expect(await module.autoClean(now: now, storage: storage) == 0)

        for picture in world.pictures { #expect(exists(imageFile(picture.name))) }
        #expect(exists(imageFile(orphanName("orphan"))))
    }

    @Test(arguments: [false, true]) func nothingIsCleanedWhileABackupIsWrittenOrRestored(running: Bool) async throws {
        let world = makeWorld()
        try await arrange(world, running: running)
        try writeBlob(orphanName("orphan"), in: imagesDirectory, bytes: 100)
        module.backupsInFlight = 1

        #expect(await module.clean(categoryID: Self.mediaID, storage: storage) == 0)
        #expect(await module.autoClean(now: now, storage: storage) == 0)
        for picture in world.pictures { #expect(exists(imageFile(picture.name))) }
        #expect(exists(imageFile(orphanName("orphan"))))

        module.backupsInFlight = 0
        #expect(await module.clean(categoryID: Self.mediaID, storage: storage) == 5_000)
    }

    @Test func aBackupAndARestoreLeaveNothingInFlight() async throws {
        await fixture.start()
        fixture.copy("một")
        let file = fixture.temporaryRoot.appending(path: "backup.mynotchclip")

        _ = try await module.exportBackup(ClipboardBackupOptions(), to: file)
        #expect(module.backupsInFlight == 0)
        module.delete(ids: Set(fixture.items.map(\.id)))
        let offer = try await module.planRestore(from: file)
        _ = try await offer.commit(.applyLimits, { _ in })

        #expect(module.backupsInFlight == 0)
        #expect(fixture.items.count == 1)
    }

    @Test func aCleanQueuedWhileStoppedWaitsForTheDiskWorkBeforeIt() async throws {
        let world = makeWorld()
        try await arrange(world, running: false)
        let (release, finish) = AsyncStream<Void>.makeStream()
        module.diskWork = Task { for await _ in release {} }

        let cleaning = Task { await module.clean(categoryID: Self.mediaID, storage: storage) }
        for _ in 0..<100 { await Task.yield() }
        #expect(exists(imageFile(world.a.name)))

        finish.finish()
        #expect(await cleaning.value == 5_000)
        #expect(!exists(imageFile(world.a.name)))
    }

    @Test func aStartQueuedBehindACleanLoadsWhatItLeft() async throws {
        let world = makeWorld()
        try await arrange(world, running: false)
        let (release, finish) = AsyncStream<Void>.makeStream()
        module.diskWork = Task { for await _ in release {} }

        let cleaning = Task { await module.clean(categoryID: Self.mediaID, storage: storage) }
        for _ in 0..<100 { await Task.yield() }
        let starting = Task { await fixture.harness.registry.bootstrap() }
        for _ in 0..<100 { await Task.yield() }
        #expect(module.store == nil)
        finish.finish()
        await starting.value

        #expect(await cleaning.value == 5_000)
        #expect(module.state.history.items.map(\.id) == [world.b.item.id, world.c.item.id, world.text.id, world.link.id, world.files.id])
        #expect(!exists(imageFile(world.a.name)))
        #expect(exists(imageFile(world.b.name)))
    }

    // MARK: Link previews

    func linkWithPreview(_ address: String, title: String?, hasImage: Bool, bytes: Int = 0) throws -> ClipboardItem {
        var item = ClipboardModuleTests.item(.link(URL(string: address)!), copiedAt: now.addingTimeInterval(-Self.day))
        item.linkPreview = ClipboardLinkPreview(title: title, hasImage: hasImage)
        if hasImage { try writeBlob(try #require(item.linkPreviewFileName), in: previewsDirectory, bytes: bytes) }
        return item
    }

    @Test(arguments: [false, true]) func clearingLinkPicturesLeavesTheHistoryIntact(running: Bool) async throws {
        let withPicture = try linkWithPreview("https://example.com/mot", title: "Tiêu đề một", hasImage: true, bytes: 600)
        let alsoPicture = try linkWithPreview("https://example.com/hai", title: nil, hasImage: true, bytes: 400)
        let titleOnly = try linkWithPreview("https://example.com/ba", title: "Chỉ có tiêu đề", hasImage: false)
        let world = makeWorld()
        var history = world.history
        history.items.insert(contentsOf: [withPicture, alsoPicture, titleOnly], at: 0)
        history.pin(itemID: alsoPicture.id, to: history.boards[0].id)
        await persist(history)
        for picture in world.pictures { try store(picture) }
        if running { await fixture.start() }
        // A picture no item names, left by a crash, goes with the rest.
        try writeBlob("link-" + Data("orphan".utf8).sha256Hex + ".png", in: previewsDirectory, bytes: 50)

        let freed = await module.clean(categoryID: Self.previewsID, storage: storage)

        #expect(freed == 1_050)
        await settle()
        let after = try await saved()
        // The same items in the same order with the same words, and the same boards; only the pictures read of two links are forgotten.
        #expect(after.items.map(\.id) == history.items.map(\.id))
        #expect(after.items.map(\.content) == history.items.map(\.content))
        #expect(after.boards == history.boards)
        let byID = Dictionary(uniqueKeysWithValues: after.items.map { ($0.id, $0) })
        #expect(byID[withPicture.id]?.linkPreview == nil)
        #expect(byID[alsoPicture.id]?.linkPreview == nil)
        #expect(byID[titleOnly.id]?.linkPreview == ClipboardLinkPreview(title: "Chỉ có tiêu đề", hasImage: false))
        #expect(try FileManager.default.contentsOfDirectory(atPath: previewsDirectory.path(percentEncoded: false)).isEmpty)
        // The pictures of the history and the numbers the page shows are untouched.
        for picture in world.pictures { #expect(exists(imageFile(picture.name))) }
        #expect(try #require(await module.storageCategories(storage: storage).last).bytes == 0)
        #expect(try #require(await module.storageCategories(storage: storage).first).bytes == 5_000)
        if running { #expect(module.state.history.items.map(\.id) == history.items.map(\.id)) }
    }

    @Test func clearingLinkPicturesCreatesNoFolder() async {
        #expect(await module.clean(categoryID: Self.previewsID, storage: storage) == 0)
        #expect(!exists(previewsDirectory))
    }

    // MARK: The daily rule

    @Test(arguments: [false, true]) func theDailyRuleDeletesPicturesNoItemNamesButOnlyOldOnes(running: Bool) async throws {
        let world = makeWorld()
        try await arrange(world, running: running)
        let old = try writeBlob(orphanName("old-orphan"), in: imagesDirectory, bytes: 700, age: 3 * Self.hour)
        let alsoOld = try writeBlob(orphanName("older-orphan"), in: imagesDirectory, bytes: 300, age: 10 * Self.day)
        // A restore stores its pictures before it adds their items, and a copy saves its picture just before its item.
        let recent = try writeBlob(orphanName("recent-orphan"), in: imagesDirectory, bytes: 200, age: 60)
        // Not the module's: whatever else a person leaves in the folder stays.
        let stranger = try writeBlob("notes.txt", in: imagesDirectory, bytes: 20)
        let oldPreview = try writeBlob("link-" + Data("orphan".utf8).sha256Hex + ".png", in: previewsDirectory, bytes: 90)
        let recentPreview = try writeBlob("link-" + Data("recent".utf8).sha256Hex + ".png", in: previewsDirectory, bytes: 90, age: 60)

        let freed = await module.autoClean(now: now, storage: storage)

        #expect(freed == 700 + 300 + 90)
        #expect(!exists(old))
        #expect(!exists(alsoOld))
        #expect(!exists(oldPreview))
        #expect(exists(recent))
        #expect(exists(recentPreview))
        #expect(exists(stranger))
        // Every picture an item names stays, pinned or not: the daily rule is not the picture clean.
        for picture in world.pictures { #expect(exists(imageFile(picture.name))) }
        #expect(try await savedIDs(running: running).count == world.history.items.count)
    }

    @Test(arguments: [false, true]) func theDailyRuleAppliesTheRetentionOfTheSettings(running: Bool) async throws {
        // Started once so the module has seen its settings; stopped, the rule must still run.
        await fixture.start()
        let (settings, keys) = try fixture.settings()
        settings.set(.week, for: keys.retention)
        let fresh = picture("fresh", bytes: 100, daysAgo: 1)
        let stale = picture("stale", bytes: 250, daysAgo: 5)
        let pinned = picture("pinned", bytes: 400, daysAgo: 40)
        let staleText = ClipboardModuleTests.item(.text("cũ"), copiedAt: now.addingTimeInterval(-6 * Self.day))
        var history = ClipboardHistory(items: [fresh.item, stale.item, staleText, pinned.item])
        history.pin(itemID: pinned.item.id, to: history.createBoard(name: "Giữ"))
        if running {
            for picture in [fresh, stale, pinned] { try store(picture) }
            // Nothing is a week old by the module's own clock yet, so it keeps all four.
            module.update { current in
                current = history
                return []
            }
            #expect(module.state.history.items.count == 4)
        } else {
            await fixture.harness.registry.setEnabled(false, for: "clipboard")
            await persist(history)
            for picture in [fresh, stale, pinned] { try store(picture) }
            #expect(module.store == nil)
        }

        // Three days on, the 5 and 6 days old items are older than a week, the day-old one is not, and the pinned one never is.
        let freed = await module.autoClean(now: now.addingTimeInterval(3 * Self.day), storage: storage)

        #expect(freed == 250)
        #expect(try await savedIDs(running: running) == [fresh.item.id, pinned.item.id])
        #expect(exists(imageFile(fresh.name)))
        #expect(exists(imageFile(pinned.name)))
        #expect(!exists(imageFile(stale.name)))
    }

    @Test func theDailyRuleAppliesTheCountLimit() async throws {
        await fixture.start()
        let (settings, keys) = try fixture.settings()
        settings.set(50, for: keys.historyLimit)
        await fixture.harness.registry.setEnabled(false, for: "clipboard")
        var history = ClipboardHistory()
        for number in 0..<55 {
            history.items.append(ClipboardModuleTests.item(.text("mục \(number)"), copiedAt: now.addingTimeInterval(-Double(number) * 60)))
        }
        await persist(history)

        _ = await module.autoClean(now: now, storage: storage)

        let kept = try await saved().items
        #expect(kept.count == 50)
        #expect(kept.map(\.id) == history.items.prefix(50).map(\.id))
    }

    @Test func aModuleThatNeverStartedReadsTheRuleFromTheAppsSettings() async throws {
        // Not what the defaults say: the defaults keep a month and 500 items, so only the settings can remove these.
        let app = SettingsStore(defaults: appDefaults)
        app.set(Retention.day, for: ClipboardRetentionKeys.retention)
        app.set(50, for: ClipboardRetentionKeys.historyLimit)
        let stale = picture("stale", bytes: 300, daysAgo: 2)
        let fresh = ClipboardModuleTests.item(.text("mới"), copiedAt: now.addingTimeInterval(-Self.hour))
        await persist(ClipboardHistory(items: [fresh, stale.item]))
        try store(stale)
        #expect(module.storageSettings == nil)

        let freed = await module.autoClean(now: now, storage: storage)

        #expect(freed == 300)
        #expect(try await saved().items.map(\.id) == [fresh.id])
        #expect(!exists(imageFile(stale.name)))
        #expect(fixture.harness.registry.state(of: "clipboard") == .disabled)
    }

    @Test func aRuleThatKeepsEverythingKeepsEverything() async throws {
        let app = SettingsStore(defaults: appDefaults)
        app.set(Retention.forever, for: ClipboardRetentionKeys.retention)
        let ancient = picture("ancient", bytes: 300, daysAgo: 900)
        await persist(ClipboardHistory(items: [ancient.item]))
        try store(ancient)

        #expect(await module.autoClean(now: now, storage: storage) == 0)

        #expect(try await saved().items.map(\.id) == [ancient.item.id])
        #expect(exists(imageFile(ancient.name)))
    }

    @Test func theRuleOfTheStoragePageAndTheRowsInSettingsAreTheSame() throws {
        let (settings, keys) = try fixture.settings()
        let store = SettingsStore(defaults: appDefaults)

        #expect(ClipboardRetentionKeys.historyLimit.name == keys.historyLimit.name)
        #expect(ClipboardRetentionKeys.retention.name == keys.retention.name)
        #expect(ClipboardRetentionKeys.imageStorageLimitMB.name == keys.imageStorageLimitMB.name)
        #expect(ClipboardRetentionKeys.historyLimit.defaultValue == keys.historyLimit.defaultValue)
        #expect(ClipboardRetentionKeys.retention.defaultValue == keys.retention.defaultValue)
        #expect(ClipboardRetentionKeys.imageStorageLimitMB.defaultValue == keys.imageStorageLimitMB.defaultValue)
        // The same value written through either is read the same through the other, clamped alike.
        for value in [-5, 1, 75, 1_000_000] {
            store.set(value, for: ClipboardRetentionKeys.historyLimit)
            settings.set(value, for: keys.historyLimit)
            #expect(store.value(ClipboardRetentionKeys.historyLimit) == settings.value(keys.historyLimit))
            store.set(value, for: ClipboardRetentionKeys.imageStorageLimitMB)
            settings.set(value, for: keys.imageStorageLimitMB)
            #expect(store.value(ClipboardRetentionKeys.imageStorageLimitMB) == settings.value(keys.imageStorageLimitMB))
        }
        for retention in Retention.allCases {
            store.set(retention, for: ClipboardRetentionKeys.retention)
            settings.set(retention, for: keys.retention)
            #expect(store.value(ClipboardRetentionKeys.retention) == settings.value(keys.retention))
        }
    }

    @Test func theSummaryReadsTheRuleFromTheSettings() async throws {
        #expect(module.autoCleanSummary == "Tự xoá mục chưa ghim sau 1 tháng, tối đa 500 mục")

        await fixture.start()
        let (settings, keys) = try fixture.settings()
        settings.set(.week, for: keys.retention)
        settings.set(100, for: keys.historyLimit)
        #expect(module.autoCleanSummary == "Tự xoá mục chưa ghim sau 1 tuần, tối đa 100 mục")
        settings.set(.day, for: keys.retention)
        #expect(module.autoCleanSummary == "Tự xoá mục chưa ghim sau 1 ngày, tối đa 100 mục")
        settings.set(.year, for: keys.retention)
        #expect(module.autoCleanSummary == "Tự xoá mục chưa ghim sau 1 năm, tối đa 100 mục")
        settings.set(.forever, for: keys.retention)
        #expect(module.autoCleanSummary == "Không tự xoá theo thời gian, tối đa 100 mục")

        // Still true after the module stops, from the settings it saw.
        await fixture.harness.registry.setEnabled(false, for: "clipboard")
        #expect(module.autoCleanSummary == "Không tự xoá theo thời gian, tối đa 100 mục")
    }

    @Test func theSummaryOfAModuleThatNeverStartedReadsTheAppsSettings() {
        SettingsStore(defaults: appDefaults).set(Retention.week, for: ClipboardRetentionKeys.retention)

        #expect(module.autoCleanSummary == "Tự xoá mục chưa ghim sau 1 tuần, tối đa 500 mục")
    }

    // MARK: Logs

    @Test func theLogsSayNumbersAndNeverWhatWasCopied() async throws {
        let lines = Lines()
        module.storageReport = { lines.all.append($0) }
        var world = makeWorld()
        let secretTitle = "Tiêu đề tuyệt mật"
        let preview = try linkWithPreview("https://riêng-tư.example.com/mật", title: secretTitle, hasImage: true, bytes: 300)
        world.history.items.insert(preview, at: 0)
        try await arrange(world, running: false)
        try writeBlob(orphanName("orphan"), in: imagesDirectory, bytes: 10)

        _ = await module.autoClean(now: now, storage: storage)
        _ = await module.clean(categoryID: Self.mediaID, storage: storage)
        _ = await module.clean(categoryID: Self.previewsID, storage: storage)
        _ = await module.storageCategories(storage: storage)

        #expect(lines.all.count >= 3)
        let secrets = ["văn bản riêng", "riêng-tư", "mật", "bai-viet", "hợp-đồng", "Tài liệu", "ai-do", secretTitle, ".png", ".pdf", "/", "http"]
            + world.pictures.map(\.name) + [orphanName("orphan"), directory.path(percentEncoded: false), preview.linkPreviewFileName ?? ""]
        for line in lines.all {
            #expect(line.allSatisfy { $0.isASCII }, Comment(rawValue: line))
            for secret in secrets { #expect(!line.contains(secret), Comment(rawValue: line)) }
            #expect(line.contains { $0.isNumber }, Comment(rawValue: line))
        }
    }

    // MARK: The storage page

    @Test func theStoragePageFindsTheCategoriesAndCleansThemWithTheModuleOff() async throws {
        let world = makeWorld()
        try await arrange(world, running: false)
        let center = fixture.harness.registry.storageCenter

        await center.refresh()

        let group = try #require(center.groups.first { $0.id == "clipboard" })
        #expect(group.categories.map(\.id) == [Self.mediaID, Self.previewsID, "clipboard.cache"])
        #expect(group.categories.map(\.bytes) == [5_000, 0, 0])
        #expect(group.autoCleanSummary == "Tự xoá mục chưa ghim sau 1 tháng, tối đa 500 mục")
        #expect(center.cleanableBytes == 5_000)

        #expect(await center.clean(Self.mediaID) == 5_000)

        #expect(try await saved().items.map(\.id) == [world.b.item.id, world.c.item.id, world.text.id, world.link.id, world.files.id])
        #expect(center.groups.first { $0.id == "clipboard" }?.categories.first?.bytes == 0)
    }

    @Test func theDailyAutoRunOfTheCenterAppliesTheRuleToAModuleThatIsOff() async throws {
        SettingsStore(defaults: appDefaults).set(Retention.day, for: ClipboardRetentionKeys.retention)
        let stale = picture("stale", bytes: 300, daysAgo: 2)
        await persist(ClipboardHistory(items: [stale.item]))
        try store(stale)
        try writeBlob(orphanName("orphan"), in: imagesDirectory, bytes: 40)

        let freed = await fixture.harness.registry.storageCenter.autoClean(now: now)

        #expect(freed == 340)
        #expect(try await saved().items.isEmpty)
    }
}
