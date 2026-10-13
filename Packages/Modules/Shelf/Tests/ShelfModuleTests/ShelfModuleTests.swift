import AppKit
import Foundation
import MyNotchCore
import MyNotchTestSupport
import Testing
import UniformTypeIdentifiers
@testable import ShelfModule

/// A provider whose file arrives only when the test calls `release()`, to stop a drop halfway.
nonisolated final class GatedProvider: @unchecked Sendable {
    let provider = NSItemProvider()
    private let lock = NSLock()
    private var completion: (@Sendable (Data?, (any Error)?) -> Void)?

    init() {
        provider.registerDataRepresentation(forTypeIdentifier: UTType.png.identifier, visibility: .all) { [self] completion in
            lock.withLock { self.completion = completion }
            return nil
        }
    }

    var isLoading: Bool { lock.withLock { completion != nil } }

    func release() { lock.withLock { completion }?(Data([0x89, 0x50, 0x4E, 0x47]), nil) }
}

@MainActor
struct ShelfFixture {
    let module: ShelfModule
    let harness: RegistryHarness

    /// Each fixture has its own notification center, so a quit posted in one test reaches no other module.
    init(notifications: NotificationCenter = NotificationCenter()) {
        module = ShelfModule(notifications: notifications)
        harness = RegistryHarness([module])
    }

    var storage: ModuleStorage { harness.storageRoot.storage(for: "shelf") }
    var keys: ShelfSettingKeys { ShelfSettingKeys(harness.settingsEnvironment(for: "shelf")!.settings) }
    var settings: ModuleSettings { harness.settingsEnvironment(for: "shelf")!.settings }
    var items: [ShelfItem] { module.state.store?.items ?? [] }
    var promisedEntries: [String] { (try? FileManager.default.contentsOfDirectory(atPath: storage.directory.appending(path: "promised").path)) ?? [] }

    /// Starts a drop with a file that stays pending until the returned provider is released.
    func startDropThatIsStillLoading() async throws -> (adding: Task<Int, Never>, gate: GatedProvider) {
        let gate = GatedProvider()
        let provider = gate.provider
        let adding = Task { await module.add(providers: [provider]) }
        for _ in 0..<500 where !gate.isLoading { try await Task.sleep(for: .milliseconds(10)) }
        try #require(gate.isLoading)
        return (adding, gate)
    }

    func start() async { await harness.registry.bootstrap() }
}

@Suite struct ShelfModuleTests {
    @Test func descriptorAndTab() throws {
        let module = ShelfModule()
        #expect(module.descriptor.id == "shelf")
        #expect(module.descriptor.displayName == "Khay")
        #expect(module.descriptor.systemImage == "tray.and.arrow.down")
        #expect(module.descriptor.order == 800)
        let tab = try #require(module.makeTab())
        #expect(tab.title == "Khay")
        #expect(tab.preferredHeight == 170)
        #expect(tab.dropTypes == [.fileURL, .url, .plainText, .image])
        #expect(tab.onDrop != nil)
    }

    @Test func settingDefaultsAndRange() async {
        let fixture = ShelfFixture()
        let settings = fixture.settings
        let keys = fixture.keys
        #expect(settings.value(keys.clearOnQuit) == false)
        #expect(settings.value(keys.removeAfterDragOut) == false)
        #expect(settings.value(keys.maxItems) == 50)
        settings.set(5, for: keys.maxItems)
        #expect(settings.value(keys.maxItems) == 10)
        settings.set(500, for: keys.maxItems)
        #expect(settings.value(keys.maxItems) == 200)
        #expect(fixture.module.makeSettingsView(fixture.harness.settingsEnvironment(for: "shelf")!) != nil)
    }

    @Test func dropWithoutARunningModuleIsRefused() {
        let module = ShelfModule()
        #expect(module.makeTab()?.onDrop?([NSItemProvider(object: "x" as NSString)]) == false)
    }

    @Test func droppedTextLinkAndFileProvidersBecomeItems() async throws {
        let fixture = ShelfFixture()
        await fixture.start()
        let directory = try makeTempDirectory()
        let file = try makeTempFile(in: directory)

        let added = await fixture.module.add(providers: [
            NSItemProvider(object: "ghi chú" as NSString),
            NSItemProvider(object: URL(string: "https://example.com/a")! as NSURL),
            NSItemProvider(object: file as NSURL),
        ])
        #expect(added == 3)
        let kinds = fixture.items.map(\.kind)
        #expect(kinds.contains(.text("ghi chú")))
        #expect(kinds.contains(.link(URL(string: "https://example.com/a")!)))
        let fileItem = try #require(fixture.items.first { if case .file = $0.kind { true } else { false } })
        #expect(fixture.module.state.store?.url(of: fileItem)?.lastPathComponent == "note.txt")
    }

    @Test func providerWithNothingUsableAddsNothing() async {
        let fixture = ShelfFixture()
        await fixture.start()
        #expect(await fixture.module.add(providers: [NSItemProvider()]) == 0)
        #expect(fixture.items.isEmpty)
    }

    @Test func imageProviderWithoutAFileIsCopiedIntoPromised() async throws {
        let fixture = ShelfFixture()
        await fixture.start()
        let provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier: UTType.png.identifier, visibility: .all) { completion in
            completion(Data([0x89, 0x50, 0x4E, 0x47]), nil)
            return nil
        }
        #expect(await fixture.module.add(providers: [provider]) == 1)
        let item = try #require(fixture.items.first)
        let url = try #require(fixture.module.state.store?.url(of: item))
        #expect(url.resolvingSymlinksInPath().path.hasPrefix(fixture.storage.directory.appending(path: "promised").resolvingSymlinksInPath().path))
        #expect(url.pathExtension == "png")
    }

    @Test func onDropAcceptsProvidersAndAddsThemInTheBackground() async throws {
        let fixture = ShelfFixture()
        await fixture.start()
        let onDrop = try #require(fixture.module.makeTab()?.onDrop)
        #expect(onDrop([NSItemProvider(object: "x" as NSString)]))
        for _ in 0..<200 where fixture.items.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        #expect(fixture.items.map(\.kind) == [.text("x")])
    }

    @Test func itemsSurviveARestartAndRespectTheLimit() async {
        let fixture = ShelfFixture()
        await fixture.start()
        fixture.settings.set(10, for: fixture.keys.maxItems)
        for index in 0..<12 { _ = await fixture.module.add(providers: [NSItemProvider(object: "t\(index)" as NSString)]) }
        #expect(fixture.items.count == 10)
        #expect(fixture.items.first?.kind == .text("t11"))

        await fixture.harness.registry.setEnabled(false, for: "shelf")
        #expect(fixture.items.isEmpty)
        await fixture.harness.registry.setEnabled(true, for: "shelf")
        #expect(fixture.items.count == 10)
    }

    @Test func stoppingKeepsTheShelfEvenWithClearOnQuitOn() async {
        let fixture = ShelfFixture()
        await fixture.start()
        fixture.settings.set(true, for: fixture.keys.clearOnQuit)
        _ = await fixture.module.add(providers: [NSItemProvider(object: "x" as NSString)])

        // Pause, disabling the module and retry all stop it without the app quitting.
        await fixture.harness.registry.pauseAll()
        #expect(ShelfStore(directory: fixture.storage.directory, limit: 50).items.count == 1)
        await fixture.harness.registry.resumeAll()
        #expect(fixture.items.count == 1)
    }

    /// What the app does on quit: the modules are stopped first, then AppKit announces the termination.
    private func quit(_ fixture: ShelfFixture, _ center: NotificationCenter) async {
        await fixture.harness.registry.shutdown()
        center.post(name: NSApplication.willTerminateNotification, object: nil)
    }

    @Test func quittingClearsTheShelfWhenClearOnQuitIsOn() async {
        let center = NotificationCenter()
        let fixture = ShelfFixture(notifications: center)
        await fixture.start()
        fixture.settings.set(true, for: fixture.keys.clearOnQuit)
        _ = await fixture.module.add(providers: [NSItemProvider(object: "x" as NSString)])
        #expect(fixture.items.count == 1)

        await quit(fixture, center)
        #expect(ShelfStore(directory: fixture.storage.directory, limit: 50).items.isEmpty)
    }

    @Test func quittingKeepsTheShelfWhenClearOnQuitIsOff() async {
        let center = NotificationCenter()
        let fixture = ShelfFixture(notifications: center)
        await fixture.start()
        _ = await fixture.module.add(providers: [NSItemProvider(object: "x" as NSString)])

        await quit(fixture, center)
        #expect(ShelfStore(directory: fixture.storage.directory, limit: 50).items.count == 1)
    }

    @Test func quittingWhilePausedStillClearsTheShelf() async {
        let center = NotificationCenter()
        let fixture = ShelfFixture(notifications: center)
        await fixture.start()
        fixture.settings.set(true, for: fixture.keys.clearOnQuit)
        _ = await fixture.module.add(providers: [NSItemProvider(object: "x" as NSString)])
        await fixture.harness.registry.pauseAll()

        await quit(fixture, center)
        #expect(ShelfStore(directory: fixture.storage.directory, limit: 50).items.isEmpty)
    }

    @Test func draggingOutRemovesTheItemOnlyWhenTheSettingIsOn() async {
        let fixture = ShelfFixture()
        await fixture.start()
        _ = await fixture.module.add(providers: [NSItemProvider(object: "a" as NSString), NSItemProvider(object: "b" as NSString)])
        let first = fixture.items[0]

        fixture.module.didDragOut(first)
        #expect(fixture.items.count == 2)

        fixture.settings.set(true, for: fixture.keys.removeAfterDragOut)
        fixture.module.didDragOut(first)
        #expect(fixture.items.map(\.kind) == [.text("b")])
    }

    @Test func draggingOutNeverDeletesAPromisedCopyTheDestinationMayStillBeReading() async throws {
        let fixture = ShelfFixture()
        await fixture.start()
        fixture.settings.set(true, for: fixture.keys.removeAfterDragOut)
        let (adding, gate) = try await fixture.startDropThatIsStillLoading()
        gate.release()
        #expect(await adding.value == 1)
        let item = try #require(fixture.items.first)
        let copy = try #require(fixture.module.state.store?.url(of: item))

        fixture.module.didDragOut(item)
        #expect(fixture.items.isEmpty)
        #expect(FileManager.default.fileExists(atPath: copy.path))
    }

    @Test func aFileCardDroppedBackOnTheShelfSurvivesTheEndOfItsOwnDrag() async throws {
        let fixture = ShelfFixture()
        await fixture.start()
        fixture.settings.set(true, for: fixture.keys.removeAfterDragOut)
        let file = try makeTempFile(in: try makeTempDirectory())
        _ = await fixture.module.add(providers: [NSItemProvider(object: file as NSURL)])
        let dragged = try #require(fixture.items.first)   // what the card captured when the drag began

        _ = await fixture.module.add(providers: [NSItemProvider(object: file as NSURL)])   // dropped back on the shelf
        fixture.module.didDragOut(dragged)
        #expect(fixture.items.count == 1)
        #expect(fixture.items.first?.id == dragged.id)
    }

    @Test func aDropStillLoadingWhenTheModuleStopsIsDiscardedWithItsCopy() async throws {
        let fixture = ShelfFixture()
        await fixture.start()
        let (adding, gate) = try await fixture.startDropThatIsStillLoading()

        await fixture.harness.registry.setEnabled(false, for: "shelf")
        gate.release()
        #expect(await adding.value == 0)
        #expect(ShelfStore(directory: fixture.storage.directory, limit: 50).items.isEmpty)
        #expect(fixture.promisedEntries.isEmpty)
    }

    @Test func aCancelledDropIsDiscardedWithItsCopy() async throws {
        let fixture = ShelfFixture()
        await fixture.start()
        let (adding, gate) = try await fixture.startDropThatIsStillLoading()

        adding.cancel()
        gate.release()
        #expect(await adding.value == 0)
        #expect(fixture.items.isEmpty)
        #expect(fixture.promisedEntries.isEmpty)
    }

    @Test func aDropFinishingAfterARestartDoesNotTouchTheNewShelf() async throws {
        let fixture = ShelfFixture()
        await fixture.start()
        let (adding, gate) = try await fixture.startDropThatIsStillLoading()

        await fixture.harness.registry.setEnabled(false, for: "shelf")
        await fixture.harness.registry.setEnabled(true, for: "shelf")
        gate.release()
        #expect(await adding.value == 0)
        #expect(fixture.items.isEmpty)
        #expect(ShelfStore(directory: fixture.storage.directory, limit: 50).items.isEmpty)
        #expect(fixture.promisedEntries.isEmpty)
    }

    @Test func droppedItemsKeepTheOrderTheyWereDroppedIn() async {
        let fixture = ShelfFixture()
        await fixture.start()
        _ = await fixture.module.add(providers: [NSItemProvider(object: "first" as NSString), NSItemProvider(object: "second" as NSString)])
        #expect(fixture.items.map(\.kind) == [.text("first"), .text("second")])
    }

    @Test func whitespaceOnlyTextIsNotKept() async {
        let fixture = ShelfFixture()
        await fixture.start()
        #expect(await fixture.module.add(providers: [NSItemProvider(object: " \n\t" as NSString)]) == 0)
    }

    @Test func removeAndRemoveAllUpdateTheShelf() async {
        let fixture = ShelfFixture()
        await fixture.start()
        _ = await fixture.module.add(providers: [NSItemProvider(object: "a" as NSString), NSItemProvider(object: "b" as NSString)])
        fixture.module.remove(fixture.items[0])
        #expect(fixture.items.map(\.kind) == [.text("b")])
        fixture.module.removeAll()
        #expect(fixture.items.isEmpty)
        #expect(ShelfStore(directory: fixture.storage.directory, limit: 50).items.isEmpty)
    }

    @Test func shareItemsAreTheFileTheTextOrTheLink() async throws {
        let fixture = ShelfFixture()
        await fixture.start()
        let file = try makeTempFile(in: try makeTempDirectory())
        let link = try #require(URL(string: "https://example.com"))
        _ = await fixture.module.add(providers: [
            NSItemProvider(object: file as NSURL),
            NSItemProvider(object: "t" as NSString),
            NSItemProvider(object: link as NSURL),
        ])
        let shared = fixture.items.map { fixture.module.shareItems(for: $0) }
        #expect((shared[0].first as? URL)?.lastPathComponent == "note.txt")
        #expect(shared[1].first as? String == "t")
        #expect(shared[2].first as? URL == link)
    }

    @Test func dragProviderCarriesTheFileTheTextOrTheLink() async throws {
        let fixture = ShelfFixture()
        await fixture.start()
        let file = try makeTempFile(in: try makeTempDirectory())
        let link = try #require(URL(string: "https://example.com"))
        _ = await fixture.module.add(providers: [
            NSItemProvider(object: file as NSURL),
            NSItemProvider(object: "t" as NSString),
            NSItemProvider(object: link as NSURL),
        ])
        let providers = fixture.items.map { fixture.module.dragProvider(for: $0) }   // file, text, link
        #expect(providers.count == 3)
        let dragged = try #require(await providers[0].loadURL())
        #expect(dragged.lastPathComponent == "note.txt")
        #expect(dragged.isFileURL)
        #expect(await providers[1].loadString() == "t")
        #expect(await providers[2].loadURL() == link)
    }
}

private extension NSItemProvider {
    func loadURL() async -> URL? {
        await withCheckedContinuation { continuation in
            _ = loadObject(ofClass: URL.self) { url, _ in continuation.resume(returning: url) }
        }
    }

    func loadString() async -> String? {
        await withCheckedContinuation { continuation in
            _ = loadObject(ofClass: String.self) { string, _ in continuation.resume(returning: string) }
        }
    }
}
