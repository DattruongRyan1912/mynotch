import AppKit
import Foundation
import MyNotchCore
import MyNotchTestSupport
import Testing
@testable import ClipboardModule

/// What the module reads from the system, changeable per test.
final class FakeSystem {
    var trusted = true
    var frontmost: (bundleID: String?, name: String?) = ("com.apple.Safari", "Safari")
    var accessBehavior = NSPasteboard.AccessBehavior.alwaysAllow
    var now = Date(timeIntervalSince1970: 1_800_000_000)
}

@Suite final class ClipboardModuleTests {
    static let pollInterval: Duration = .milliseconds(300)

    let pasteboard = FakePasteboard()
    let keystrokes = FakeKeystrokeSender()
    let libraryWindow = FakeLibraryWindow()
    let panelWindow = FakePanelWindow()
    let libraryPreview = FakePreviewWindow()
    let panelPreview = FakePreviewWindow()
    let tabPreview = FakePreviewWindow()
    let system = FakeSystem()
    let modifiers = FakeModifierState()
    let module: ClipboardModule
    let harness: RegistryHarness
    /// The harness's temporary storage root, removed when the test ends.
    let temporaryRoot: URL

    init() {
        let system = system
        module = ClipboardModule(
            pasteboard: pasteboard, keystrokes: keystrokes,
            frontmostApp: { system.frontmost }, isTrusted: { system.trusted },
            pasteboardAccessBehavior: { system.accessBehavior }, modifiers: modifiers, now: { system.now },
            libraryWindow: libraryWindow, panelWindow: panelWindow, libraryPreview: libraryPreview, panelPreview: panelPreview,
            tabPreview: tabPreview
        )
        harness = RegistryHarness([module])
        temporaryRoot = harness.storageRoot.applicationSupport.deletingLastPathComponent()
    }

    deinit {
        try? FileManager.default.removeItem(at: temporaryRoot)
    }

    var directory: URL { harness.storageRoot.storage(for: "clipboard").directory }
    var state: ClipboardState { module.state }
    var items: [ClipboardItem] { module.state.history.items }

    func settings() throws -> (ModuleSettings, ClipboardSettingKeys) {
        let settings = try #require(harness.settingsEnvironment(for: "clipboard")).settings
        return (settings, ClipboardSettingKeys(settings))
    }

    func start() async {
        await harness.registry.bootstrap()
        #expect(harness.registry.state(of: "clipboard") == .running)
    }

    /// Another app copies; the next poll records it.
    func copy(_ snapshot: PasteboardSnapshot) {
        pasteboard.copy(snapshot)
        harness.scheduler.advance(by: Self.pollInterval)
    }

    func copy(_ text: String) {
        copy(PasteboardSnapshot(types: ["public.utf8-plain-text"], string: text))
    }

    func makeStore(in directory: URL? = nil) -> ClipboardStore {
        ClipboardStore(directory: directory ?? self.directory, scheduler: ManualScheduler(), logger: Log.logger(category: "ClipboardModuleTests"))
    }

    /// Writes history files as an earlier run would have left them.
    func persist(_ history: ClipboardHistory, in directory: URL? = nil) async {
        let store = makeStore(in: directory)
        _ = store.load()
        store.scheduleSave(history)
        await store.flush()
    }

    func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }

    func imageFile(_ fileName: String) -> URL {
        directory.appending(components: "images", fileName)
    }

    static func item(_ content: ClipboardContent, copiedAt: Date) -> ClipboardItem {
        // As the module records an item, which decides what a text is when it is copied.
        ClipboardItem(
            id: UUID(), content: content, contentHash: ClipboardContent.hash(of: content),
            copiedAt: copiedAt, sourceBundleID: "com.apple.Safari", sourceAppName: "Safari",
            codeDetection: ClipboardCodeDetector.detect(content)
        )
    }

    static func image(_ seed: String, byteCount: Int = 4) -> ClipboardContent {
        .image(ClipboardImage(fileName: Data(seed.utf8).sha256Hex + ".png", pixelWidth: 1, pixelHeight: 1, byteCount: byteCount))
    }

    // MARK: Lifecycle

    @Test func declaresThePermissionsItUsesAndWhy() {
        let descriptor = module.descriptor
        #expect(descriptor.permissions.isEmpty)
        #expect(descriptor.optionalPermissions == [.accessibility, .pasteboard])
        #expect(descriptor.permissionReasons == [
            .accessibility: "Dán mục bạn chọn vào app đang dùng (giả lập ⌘V).",
            .pasteboard: "Ghi lại mọi lần chép mà macOS không hỏi lại.",
        ])
    }

    @Test func descriptorAndTabMatchTheSpec() throws {
        #expect(module.descriptor.id == "clipboard")
        #expect(module.descriptor.order == 100)
        let tab = try #require(module.makeTab())
        #expect(tab.id == "clipboard")
        #expect(tab.preferredHeight == 230)
        #expect(tab.acceptsKeyboard)
    }

    @Test func startLoadsHistoryDropsDanglingPinsAndPrunesOldItems() async throws {
        let recent = Self.item(.text("Xin chào"), copiedAt: system.now.addingTimeInterval(-60))
        let old = Self.item(Self.image("old"), copiedAt: system.now.addingTimeInterval(-40 * 24 * 60 * 60))
        var history = ClipboardHistory(items: [recent, old])
        let board = history.createBoard(name: "Công việc")
        history.pin(itemID: recent.id, to: board)
        history.boards[0].itemIDs.append(UUID())
        await persist(history)
        try Data([1, 2, 3, 4]).write(to: imageFile(Self.image("old").imageFileName))

        await start()

        #expect(items == [recent])
        #expect(state.history.boards.first?.itemIDs == [recent.id])
        #expect(!exists(imageFile(Self.image("old").imageFileName)))
    }

    @Test func startRegistersTheOpenClipboardHotkey() async throws {
        await start()

        let registration = try #require(harness.hotkeys.registrations.first { $0.id == "clipboard_openClipboard" })
        // The library's, the floating panel's and the two of the copy stack come with it.
        #expect(harness.hotkeys.registrations.count == 5)
        #expect(registration.id == "clipboard_openClipboard")
        #expect(registration.title == "Mở lịch sử clipboard")
        #expect(harness.hotkeyBackend.getShortcut(for: registration.name) == KeyboardShortcuts.Shortcut(.v, modifiers: [.control, .option]))

        #expect(harness.hotkeyBackend.trigger("clipboard_openClipboard"))
        #expect(harness.presenter.openedTabs == ["clipboard"])

        await harness.registry.setEnabled(false, for: "clipboard")
        #expect(harness.hotkeys.registrations.isEmpty)
        #expect(!harness.hotkeyBackend.trigger("clipboard_openClipboard"))
    }

    @Test func stopFlushesACaptureWithoutWaitingForTheSaveDelay() async {
        await start()
        copy("Xin chào")
        #expect(items.map(\.content) == [.text("Xin chào")])

        await harness.registry.setEnabled(false, for: "clipboard")

        #expect(makeStore().load().items.map(\.content) == [.text("Xin chào")])
        #expect(items.isEmpty)
    }

    @Test func alwaysDenyMarksThePasteboardDenied() async {
        system.accessBehavior = .alwaysDeny
        await start()
        #expect(state.pasteboardDenied)

        system.accessBehavior = .alwaysAllow
        module.refreshPasteboardAccess()
        #expect(!state.pasteboardDenied)
    }

    // MARK: Capture

    @Test func aCaptureAddsAnItemAndShowsTheCopiedActivity() async {
        await start()
        copy("Xin chào")

        let item = items.first
        #expect(items.count == 1)
        #expect(item?.content == .text("Xin chào"))
        #expect(item?.sourceBundleID == "com.apple.Safari")
        #expect(item?.copiedAt == system.now)
        #expect(harness.activities.current?.id == "clipboard/copied")
        harness.scheduler.advance(by: .milliseconds(1500))
        #expect(harness.activities.current == nil)
    }

    @Test func noCopiedActivityWhenTheSettingIsOff() async throws {
        let (settings, keys) = try settings()
        settings.set(false, for: keys.showCopiedActivity)
        await start()
        copy("Xin chào")

        #expect(items.count == 1)
        #expect(harness.activities.current == nil)
    }

    @Test func aCapturedImageIsStoredInTheImagesFolder() async throws {
        await start()
        copy(PasteboardSnapshot(types: ["public.png"], png: ClipboardClassifierTests.png))

        guard case .image(let image) = try #require(items.first).content else {
            Issue.record("Expected an image item")
            return
        }
        #expect(try Data(contentsOf: imageFile(image.fileName)) == ClipboardClassifierTests.png)
    }

    @Test func pausedAndExcludedAppsAreNotCaptured() async throws {
        let (settings, keys) = try settings()
        await start()

        settings.set(true, for: keys.paused)
        copy("while paused")
        settings.set(false, for: keys.paused)
        settings.set(["com.apple.Notes"], for: keys.excludedBundleIDs)
        system.frontmost = ("com.apple.Notes", "Notes")
        copy("private note")
        #expect(items.isEmpty)

        settings.set([], for: keys.excludedBundleIDs)
        copy("Xin chào")
        #expect(items.map(\.content) == [.text("Xin chào")])
    }

    @Test func shorteningTheRetentionInSettingsPrunesAtOnce() async throws {
        let (settings, keys) = try settings()
        await start()
        copy("Xin chào")
        system.now += 2 * 24 * 60 * 60

        settings.set(.day, for: keys.retention)
        for _ in 0..<100 where !items.isEmpty { await Task.yield() }

        #expect(items.isEmpty)
    }

    @Test func theSearchIndexFoldsOnlyNewItems() async {
        await start()
        copy("Xin chào")
        copy("Tạm biệt")
        #expect(state.searchIndex.foldCount == 0)

        state.query.text = "chao"
        #expect(state.searchIndex.foldCount == 2)
        #expect(state.visibleItems.map(\.content) == [.text("Xin chào")])
        state.query.text = "CHÀO"
        #expect(state.visibleItems.count == 1)
        #expect(state.searchIndex.foldCount == 2)

        copy("Chào buổi sáng")
        #expect(state.searchIndex.foldCount == 3)
        #expect(state.visibleItems.map(\.content) == [.text("Chào buổi sáng"), .text("Xin chào")])
    }

    // MARK: Actions

    @Test func activateWithPasteWhenTrustedClosesTheNotchThenPastesAfterTheDelay() async throws {
        let (settings, keys) = try settings()
        settings.set(.paste, for: keys.clickAction)
        settings.set(false, for: keys.closeAfterAction)
        await start()
        copy("Xin chào")
        let item = try #require(items.first)

        module.activate(item)

        #expect(pasteboard.writes.map(\.content) == [.text("Xin chào")])
        #expect(harness.presenter.closeCount == 1)
        harness.scheduler.advance(by: .milliseconds(79))
        #expect(keystrokes.pasteCount == 0)
        harness.scheduler.advance(by: .milliseconds(1))
        #expect(keystrokes.pasteCount == 1)
    }

    @Test func activateWithPasteWithoutAccessibilityOnlyCopiesClosesAndShowsTheHint() async throws {
        let (settings, keys) = try settings()
        settings.set(.paste, for: keys.clickAction)
        settings.set(false, for: keys.closeAfterAction)
        system.trusted = false
        await start()
        copy("Xin chào")
        let item = try #require(items.first)

        module.activate(item)
        harness.scheduler.advance(by: .seconds(1))

        #expect(pasteboard.writes.count == 1)
        #expect(keystrokes.pasteCount == 0)
        #expect(harness.presenter.closeCount == 1)
        #expect(harness.activities.current?.id == "clipboard/pasteHint")
    }

    @Test func activateWithCopyMovesTheItemUpAndClosesOnlyWhenSet() async throws {
        let (settings, keys) = try settings()
        settings.set(.copy, for: keys.clickAction)
        settings.set(false, for: keys.closeAfterAction)
        await start()
        copy("one")
        system.now += 60
        copy("two")
        let older = try #require(items.last)
        system.now += 60

        module.activate(older)
        harness.scheduler.advance(by: .seconds(1))

        #expect(pasteboard.writes.map(\.content) == [.text("one")])
        #expect(keystrokes.pasteCount == 0)
        #expect(harness.presenter.closeCount == 0)
        #expect(items.map(\.content) == [.text("one"), .text("two")])
        #expect(items.first?.copiedAt == system.now)

        settings.set(true, for: keys.closeAfterAction)
        module.copy(older)
        #expect(harness.presenter.closeCount == 1)
    }

    @Test func copyAsPlainTextAndPasteFromTheMenu() async throws {
        await start()
        copy(PasteboardSnapshot(types: ["public.utf8-plain-text", "public.rtf"], string: "Xin chào", rtf: Data("{\\rtf1 Xin chào}".utf8)))
        let item = try #require(items.first)

        module.copy(item, plainText: true)
        module.paste(item)
        harness.scheduler.advance(by: .milliseconds(80))

        #expect(pasteboard.writes.map(\.plainTextOnly) == [true, false])
        #expect(keystrokes.pasteCount == 1)
    }

    @Test func anImageIsWrittenFromItsStoredFile() async throws {
        await start()
        copy(PasteboardSnapshot(types: ["public.png"], png: ClipboardClassifierTests.png))
        let item = try #require(items.first)

        module.copy(item)

        #expect(pasteboard.writes.first?.imageURL == module.fileURLs(of: item).first)
        #expect(module.fileURLs(of: item).first.map(exists) == true)
    }

    /// The real write path on a private named pasteboard decides; an image whose file is gone cannot be written.
    @Test func aFailedCopyKeepsTheNotchOpenAndSaysSo() async throws {
        let named = NSPasteboard(name: .init("MyNotchTests.\(UUID().uuidString)"))
        defer { named.releaseGlobally() }
        let system = system
        let module = ClipboardModule(
            pasteboard: SystemPasteboard(pasteboard: named), keystrokes: keystrokes,
            frontmostApp: { system.frontmost }, isTrusted: { true },
            pasteboardAccessBehavior: { .alwaysAllow }, modifiers: FakeModifierState(), now: { system.now }
        )
        let harness = RegistryHarness([module])
        let root = harness.storageRoot.applicationSupport.deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: root) }
        let missing = Self.item(Self.image("gone"), copiedAt: system.now.addingTimeInterval(-60))
        let directory = harness.storageRoot.storage(for: "clipboard").directory
        let file = directory.appending(components: "images", Self.image("gone").imageFileName)
        await persist(ClipboardHistory(items: [missing]), in: directory)
        try Data([1, 2, 3, 4]).write(to: file)
        await harness.registry.bootstrap()
        // Gone while running, e.g. deleted in Finder.
        try FileManager.default.removeItem(at: file)

        module.activate(missing)
        harness.scheduler.advance(by: .seconds(1))

        #expect(harness.presenter.closeCount == 0)
        #expect(harness.presenter.toastCount == 1)
        #expect(harness.activities.current == nil)
        #expect(module.state.history.items == [missing])
        #expect(keystrokes.pasteCount == 0)
    }

    @Test func applyRecordsTheTransformedTextAsANewItemAndCopiesIt() async throws {
        await start()
        copy("https%3A%2F%2Fexample.com")
        let item = try #require(items.first)

        #expect(module.apply(.urlDecode, to: item))
        #expect(items.map(\.content) == [.link(URL(string: "https://example.com")!), .text("https%3A%2F%2Fexample.com")])
        #expect(items.first?.sourceBundleID == nil)
        #expect(pasteboard.writes.map(\.content) == [.link(URL(string: "https://example.com")!)])

        #expect(!module.apply(.jsonPretty, to: item))
        #expect(items.count == 2)
        #expect(pasteboard.writes.count == 1)
    }

    @Test func deleteRemovesTheItemItsImageAndSaves() async throws {
        await start()
        copy(PasteboardSnapshot(types: ["public.png"], png: ClipboardClassifierTests.png))
        copy("Xin chào")
        let image = try #require(items.last)
        let imageURL = try #require(module.fileURLs(of: image).first)
        state.selectedID = image.id

        module.delete(image)
        harness.scheduler.advance(by: .seconds(1))
        await module.store?.waitForWrites()

        #expect(items.map(\.content) == [.text("Xin chào")])
        #expect(!exists(imageURL))
        #expect(state.selectedID == nil)
        #expect(makeStore().load().items.map(\.content) == [.text("Xin chào")])
    }

    @Test func boardOperations() async throws {
        await start()
        copy("Xin chào")
        let item = try #require(items.first)

        #expect(module.createBoard(named: "   ") == nil)
        let boardID = try #require(module.createBoard(named: "  Công việc "))
        #expect(state.history.boards.map(\.name) == ["Công việc"])

        module.pin(item, to: boardID)
        #expect(state.history.isPinned(item.id))
        state.query.boardID = boardID
        #expect(state.visibleItems.map(\.id) == [item.id])

        module.renameBoard(boardID, to: "Việc")
        #expect(state.history.boards.map(\.name) == ["Việc"])

        module.unpin(item, from: boardID)
        #expect(!state.history.isPinned(item.id))

        module.deleteBoard(boardID)
        #expect(state.history.boards.isEmpty)
        #expect(state.query.boardID == nil)
        #expect(state.visibleItems.map(\.id) == [item.id])
    }

    @Test func clearHistoryKeepsPinnedAndRecentItems() async throws {
        await start()
        copy("pinned")
        let pinned = try #require(items.first)
        let boardID = try #require(module.createBoard(named: "Board"))
        module.pin(pinned, to: boardID)
        system.now += 60
        copy("two days ago")
        system.now += 2 * 24 * 60 * 60
        copy("just now")

        await module.clearHistory(.olderThanOneDay, directory: directory).value
        #expect(items.map(\.content) == [.text("just now"), .text("pinned")])

        await module.clearHistory(.all, directory: directory).value
        #expect(items.map(\.id) == [pinned.id])
    }

    @Test func clearingWhileStoppedEditsTheFiles() async throws {
        let pinned = Self.item(.text("pinned"), copiedAt: system.now)
        let image = Self.item(Self.image("photo"), copiedAt: system.now)
        var history = ClipboardHistory(items: [image, pinned])
        history.pin(itemID: pinned.id, to: history.createBoard(name: "Board"))
        await persist(history)
        try Data([1, 2, 3, 4]).write(to: imageFile(Self.image("photo").imageFileName))

        await module.clearHistory(.all, directory: directory).value

        // Checked before `load()`, which would delete the orphaned file itself.
        #expect(!exists(imageFile(Self.image("photo").imageFileName)))
        #expect(harness.registry.state(of: "clipboard") == .disabled)
        #expect(makeStore().load().items == [pinned])
    }

    @Test func aFailedWriteWhileStoppedKeepsTheImages() async throws {
        let image = Self.item(Self.image("photo"), copiedAt: system.now)
        await persist(ClipboardHistory(items: [image]))
        try Data([1, 2, 3, 4]).write(to: imageFile(Self.image("photo").imageFileName))
        let path = directory.path(percentEncoded: false)
        // History files are replaced atomically, which needs a writable folder; `images/` itself stays writable.
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path) }

        await module.clearHistory(.all, directory: directory).value

        #expect(exists(imageFile(Self.image("photo").imageFileName)))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
        #expect(makeStore().load().items == [image])
    }

    @Test func startWaitsForAClearQueuedWhileStopped() async {
        await persist(ClipboardHistory(items: [Self.item(.text("Xin chào"), copiedAt: system.now)]))

        let clearing = module.clearHistory(.all, directory: directory)
        await start()
        await clearing.value

        #expect(items.isEmpty)
        #expect(makeStore().load().items.isEmpty)
    }

    @Test func startWaitsForQueuedDiskWork() async {
        let (release, finish) = AsyncStream<Void>.makeStream()
        module.diskWork = Task { for await _ in release {} }

        let starting = Task { await harness.registry.bootstrap() }
        for _ in 0..<100 { await Task.yield() }
        #expect(harness.registry.state(of: "clipboard") == .starting)
        #expect(module.store == nil)

        finish.finish()
        await starting.value
        #expect(harness.registry.state(of: "clipboard") == .running)
    }

    @Test func aClearDuringStopRunsAfterTheFinalFlush() async {
        await start()
        copy("Xin chào")

        let stopping = Task { await harness.registry.setEnabled(false, for: "clipboard") }
        for _ in 0..<1000 where module.store != nil { await Task.yield() }
        #expect(module.store == nil)
        let clearing = module.clearHistory(.all, directory: directory)
        await stopping.value
        await clearing.value

        #expect(makeStore().load().items.isEmpty)
    }

    @Test func startDropsImageItemsWhoseFileIsGone() async throws {
        let text = Self.item(.text("Xin chào"), copiedAt: system.now)
        let kept = Self.item(Self.image("kept"), copiedAt: system.now)
        let gone = Self.item(Self.image("gone"), copiedAt: system.now)
        var history = ClipboardHistory(items: [gone, kept, text])
        history.pin(itemID: gone.id, to: history.createBoard(name: "Board"))
        await persist(history)
        try Data([1, 2, 3, 4]).write(to: imageFile(Self.image("kept").imageFileName))

        await start()

        #expect(items == [kept, text])
        #expect(state.history.boards.first?.itemIDs == [])
        await harness.registry.setEnabled(false, for: "clipboard")
        #expect(makeStore().load().items == [kept, text])
    }

    @Test func stopDropsAPasteStillWaitingForTheDelay() async throws {
        let (settings, keys) = try settings()
        settings.set(.paste, for: keys.clickAction)
        await start()
        copy("Xin chào")
        module.activate(try #require(items.first))

        // Called directly, so only the module (not the registry's cancelled scheduler) can stop the ⌘V.
        await module.stop()
        harness.scheduler.advance(by: .seconds(1))

        #expect(keystrokes.pasteCount == 0)
    }

    @Test func clearingWhileStoppedCreatesNothingWhenThereIsNoHistory() async {
        await module.clearHistory(.all, directory: directory).value
        #expect(!exists(directory))
    }

    @Test func fileURLsAndLinksForTheMenu() async throws {
        await start()
        let files = [URL(fileURLWithPath: "/tmp/a.txt"), URL(fileURLWithPath: "/tmp/b.txt")]
        #expect(module.fileURLs(of: Self.item(.files(files), copiedAt: system.now)) == files)
        #expect(module.fileURLs(of: Self.item(.text("a"), copiedAt: system.now)).isEmpty)
        #expect(module.fileURLs(of: Self.item(Self.image("photo"), copiedAt: system.now)) == [imageFile(Self.image("photo").imageFileName)])

        let link = URL(string: "https://example.com/a")!
        #expect(ClipboardModule.openableLink(of: Self.item(.link(link), copiedAt: system.now)) == link)
        #expect(ClipboardModule.openableLink(of: Self.item(.link(URL(fileURLWithPath: "/Applications/Calculator.app")), copiedAt: system.now)) == nil)
        #expect(ClipboardModule.openableLink(of: Self.item(.text("https://example.com"), copiedAt: system.now)) == nil)
    }

    @Test func actionsDoNothingWhileStopped() async throws {
        let item = Self.item(.text("Xin chào"), copiedAt: system.now)
        module.activate(item)
        module.delete(item)
        #expect(!module.apply(.uppercase, to: item))
        #expect(module.createBoard(named: "Board") == nil)
        #expect(pasteboard.writes.isEmpty)
        #expect(!exists(directory))
    }

    // MARK: Settings

    @Test func settingsRowsExistWhileStopped() throws {
        #expect(harness.registry.state(of: "clipboard") == .disabled)
        let view = try #require(harness.registry.settingsView(for: "clipboard"))
        #expect(String(describing: view).hasPrefix("AnyView(ClipboardSettingsView("))
        #expect(!exists(directory))
    }

    @Test func storageUsageFromHistory() {
        let history = ClipboardHistory(items: [
            Self.item(.text("a"), copiedAt: system.now),
            Self.item(Self.image("one", byteCount: 1_048_576), copiedAt: system.now),
            Self.item(Self.image("two", byteCount: 524_288), copiedAt: system.now),
        ])
        let usage = ClipboardStorageUsage(history: history)

        #expect(usage == ClipboardStorageUsage(itemCount: 3, imageBytes: 1_572_864))
        #expect(usage.summary(locale: Locale(identifier: "vi_VN")) == "3 mục · 1,5 MB ảnh")
    }

    @Test func storageUsageFromDisk() async throws {
        #expect(await ClipboardStorageUsage.read(directory: directory) == ClipboardStorageUsage(itemCount: 0, imageBytes: 0))

        await persist(ClipboardHistory(items: [
            Self.item(.text("a"), copiedAt: system.now), Self.item(Self.image("photo"), copiedAt: system.now),
        ]))
        try Data(count: 1000).write(to: imageFile(Self.image("photo").imageFileName))

        #expect(await ClipboardStorageUsage.read(directory: directory) == ClipboardStorageUsage(itemCount: 2, imageBytes: 1000))
    }

    @Test func clearRangesCutOffAtTheirAge() {
        let now = system.now
        let day: TimeInterval = 24 * 60 * 60
        #expect(ClipboardClearRange.olderThanOneDay.cutoff(from: now) == now.addingTimeInterval(-1 * day))
        #expect(ClipboardClearRange.olderThanOneWeek.cutoff(from: now) == now.addingTimeInterval(-7 * day))
        #expect(ClipboardClearRange.olderThanOneMonth.cutoff(from: now) == now.addingTimeInterval(-30 * day))
        #expect(ClipboardClearRange.olderThanThreeMonths.cutoff(from: now) == now.addingTimeInterval(-90 * day))
        #expect(ClipboardClearRange.all.cutoff(from: now) == nil)
        #expect(ClipboardClearRange.olderThanOneDay.title == "Cũ hơn 24 giờ")
        #expect(ClipboardClearRange.olderThanOneWeek.title == "Cũ hơn 7 ngày")
        #expect(ClipboardClearRange.olderThanOneMonth.title == "Cũ hơn 30 ngày")
        #expect(ClipboardClearRange.olderThanThreeMonths.title == "Cũ hơn 3 tháng")
        #expect(ClipboardClearRange.all.title == "Tất cả")
        #expect(ClipboardClearRange.olderThanOneDay.confirmationTitle == "Xoá lịch sử cũ hơn 24 giờ?")
        #expect(ClipboardClearRange.all.confirmationTitle == "Xoá tất cả lịch sử?")
    }
}

private extension ClipboardContent {
    var imageFileName: String {
        if case .image(let image) = self { image.fileName } else { "" }
    }
}
