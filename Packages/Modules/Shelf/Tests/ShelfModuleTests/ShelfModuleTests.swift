import Foundation
import MyNotchCore
import MyNotchTestSupport
import Testing
import UniformTypeIdentifiers
@testable import ShelfModule

@MainActor
struct ShelfFixture {
    let module = ShelfModule()
    let harness: RegistryHarness

    init() { harness = RegistryHarness([module]) }

    var storage: ModuleStorage { harness.storageRoot.storage(for: "shelf") }
    var keys: ShelfSettingKeys { ShelfSettingKeys(harness.settingsEnvironment(for: "shelf")!.settings) }
    var settings: ModuleSettings { harness.settingsEnvironment(for: "shelf")!.settings }
    var items: [ShelfItem] { module.state.store?.items ?? [] }

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

    @Test func clearOnQuitEmptiesTheShelfWhenTheModuleStops() async {
        let fixture = ShelfFixture()
        await fixture.start()
        fixture.settings.set(true, for: fixture.keys.clearOnQuit)
        _ = await fixture.module.add(providers: [NSItemProvider(object: "x" as NSString)])
        #expect(fixture.items.count == 1)
        await fixture.harness.registry.setEnabled(false, for: "shelf")
        #expect(ShelfStore(directory: fixture.storage.directory, limit: 50).items.isEmpty)
    }

    @Test func shelfIsKeptWhenClearOnQuitIsOff() async {
        let fixture = ShelfFixture()
        await fixture.start()
        _ = await fixture.module.add(providers: [NSItemProvider(object: "x" as NSString)])
        await fixture.harness.registry.setEnabled(false, for: "shelf")
        #expect(ShelfStore(directory: fixture.storage.directory, limit: 50).items.count == 1)
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
        #expect(fixture.items.map(\.kind) == [.text("a")])
    }

    @Test func dragProviderCarriesTheFileTheTextOrTheLink() async throws {
        let fixture = ShelfFixture()
        await fixture.start()
        let file = try makeTempFile(in: try makeTempDirectory())
        _ = await fixture.module.add(providers: [
            NSItemProvider(object: file as NSURL),
            NSItemProvider(object: "t" as NSString),
            NSItemProvider(object: URL(string: "https://example.com")! as NSURL),
        ])
        let providers = fixture.items.map { fixture.module.dragProvider(for: $0) }
        #expect(providers.count == 3)
        #expect(providers.allSatisfy { $0.canLoadObject(ofClass: URL.self) || $0.canLoadObject(ofClass: String.self) })
        #expect(providers[2].canLoadObject(ofClass: URL.self))   // link
        #expect(providers[1].canLoadObject(ofClass: String.self))
        #expect(providers[0].canLoadObject(ofClass: URL.self))   // file
    }
}
