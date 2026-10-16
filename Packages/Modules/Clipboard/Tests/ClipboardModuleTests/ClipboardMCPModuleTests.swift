import AppKit
import ClipboardMCPKit
import Foundation
import MyNotchCore
import MyNotchTestSupport
import Testing
@testable import ClipboardModule

/// The module with the feature for agents: off until the user turns it on, then a socket that answers from the history, and
/// closed again the moment it is turned off.
@Suite final class ClipboardMCPModuleTests {
    final class Placed: @unchecked Sendable {
        var destinations: [URL] = []
        var failure: (any Error)?
    }

    struct PlacementFailed: LocalizedError {
        var errorDescription: String? { "no helper in the bundle" }
    }

    let pasteboard = FakePasteboard()
    let system = FakeSystem()
    let placed = Placed()
    let module: ClipboardModule
    let harness: RegistryHarness
    /// The harness's temporary storage root, removed when the test ends.
    let temporaryRoot: URL
    let socketFolder = "/tmp/mn-\(UUID().uuidString.prefix(8))"
    var socketPath: String { socketFolder + "/mcp.sock" }

    init() {
        let system = system
        let placed = placed
        let folder = socketFolder
        module = ClipboardModule(
            pasteboard: pasteboard, keystrokes: FakeKeystrokeSender(),
            frontmostApp: { system.frontmost }, isTrusted: { system.trusted },
            pasteboardAccessBehavior: { system.accessBehavior }, modifiers: FakeModifierState(), now: { system.now },
            libraryWindow: FakeLibraryWindow(), panelWindow: FakePanelWindow(),
            mcpSocketPath: { _ in folder + "/mcp.sock" },
            installMCPHelper: { destination in
                placed.destinations.append(destination)
                if let failure = placed.failure { throw failure }
            }
        )
        harness = RegistryHarness([module])
        temporaryRoot = harness.storageRoot.applicationSupport.deletingLastPathComponent()
    }

    deinit {
        try? FileManager.default.removeItem(atPath: socketFolder)
        try? FileManager.default.removeItem(at: temporaryRoot)
    }

    var directory: URL { harness.storageRoot.storage(for: "clipboard").directory }

    func settings() throws -> (ModuleSettings, ClipboardSettingKeys) {
        let settings = try #require(harness.settingsEnvironment(for: "clipboard")).settings
        return (settings, ClipboardSettingKeys(settings))
    }

    func start() async {
        await harness.registry.bootstrap()
        #expect(harness.registry.state(of: "clipboard") == .running)
    }

    func copy(_ text: String, extraTypes: [String] = []) {
        pasteboard.copy(PasteboardSnapshot(types: ["public.utf8-plain-text"] + extraTypes, string: text))
        harness.scheduler.advance(by: ClipboardModuleTests.pollInterval)
    }

    func turnOn() async throws {
        let (settings, keys) = try settings()
        settings.set(true, for: keys.mcpEnabled)
        await until { module.mcpListening }
        #expect(module.mcpListening)
    }

    /// Other tests keep the main actor busy: a generous wait costs nothing when it is free.
    func until(_ condition: () -> Bool) async {
        for _ in 0..<3_000 where !condition() { try? await Task.sleep(for: .milliseconds(10)) }
    }

    func ask(_ request: ClipboardMCPRequest) async -> ClipboardMCPClient.Outcome {
        let path = socketPath
        return await Task.detached { ClipboardMCPClient.send(request, socketPath: path, timeout: 600) }.value
    }

    func search(_ query: String) -> ClipboardMCPRequest {
        .search(ClipboardMCPSearch(query: query))
    }

    func count(of outcome: ClipboardMCPClient.Outcome) -> Int? {
        guard case .reply(.success(let result)) = outcome else { return nil }
        return result["count"]?.int
    }

    // MARK: Off by default

    @Test func theFeatureIsOffByDefaultAndNothingListensOrIsPlaced() async throws {
        let (settings, keys) = try settings()
        #expect(settings.value(keys.mcpEnabled) == false)
        await start()
        copy("find me")
        #expect(!module.mcpListening)
        #expect(!module.mcp.isListening)
        #expect(await ask(search("find")) == .unreachable)
        #expect(!FileManager.default.fileExists(atPath: socketPath))
        #expect(placed.destinations.isEmpty)
    }

    // MARK: On

    @Test func turningItOnOpensTheSocketThatAnswersFromTheHistoryAndPlacesTheHelper() async throws {
        await start()
        copy("find me please")
        copy("something else")
        try await turnOn()
        #expect(module.mcp.isListening)
        #expect(module.mcp.listenFailure == nil)
        #expect(count(of: await ask(search("find"))) == 1)
        #expect(count(of: await ask(search("zzz"))) == 0)
        #expect(placed.destinations == [directory.appending(path: "bin/mynotch-clipboard-mcp")])
    }

    @Test func aCopyMadeAfterTheSocketOpenedIsFoundToo() async throws {
        await start()
        try await turnOn()
        copy("fresh words")
        #expect(count(of: await ask(search("fresh"))) == 1)
    }

    @Test func aSecretIsNeverHandedOverEvenWhenTheHistoryKeepsIt() async throws {
        let (settings, keys) = try settings()
        settings.set(false, for: keys.ignoreSensitive)
        await start()
        copy("hunter2 is my password", extraTypes: ["org.nspasteboard.ConcealedType"])
        copy("hunter2 recipe for soup")
        let secret = try #require(module.state.history.items.first { $0.isSensitive })
        try await turnOn()
        #expect(count(of: await ask(search("hunter2"))) == 1)
        guard case .reply(.failure(let reason, _)) = await ask(.item(secret.id)) else {
            Issue.record("a secret was handed over by id")
            return
        }
        #expect(reason == .notFound)
    }

    @Test func anItemThatLooksLikeASecretIsNeverHandedOverAndTheLogCountsIt() async throws {
        await start()
        copy("password: hunter2!")
        copy("my shopping list")
        let secret = try #require(module.state.history.items.first { $0.content.plainText == "password: hunter2!" })
        #expect(secret.sensitive == false)
        try await turnOn()
        #expect(count(of: await ask(search(""))) == 1)
        guard case .reply(.failure(let reason, _)) = await ask(.item(secret.id)) else {
            Issue.record("a secret-looking item was handed over by id")
            return
        }
        #expect(reason == .notFound)
        #expect(module.mcp.entries.map(\.outcome) == [.answered(count: 0, hidden: 1), .answered(count: 1, hidden: 1)])
    }

    @Test func aSocketAnotherMyNotchHoldsIsReportedAndNotTakenOver() async throws {
        let other = ClipboardMCPServer(socketPath: socketPath) { _ in .failure(.failed, "other") }
        try other.start()
        await start()
        let (settings, keys) = try settings()
        settings.set(true, for: keys.mcpEnabled)
        await until { module.mcp.listenFailure != nil }
        #expect(!module.mcpListening)
        #expect(module.mcp.listenFailure == "Một MyNotch khác đang giữ cổng này nên cổng chưa mở được.")
        #expect(await ask(search("")) == .reply(.failure(.failed, "other")))
        other.stop()
    }

    @Test func eachQueryIsLoggedByToolAndCountAndNeverByItsWords() async throws {
        await start()
        copy("find me")
        try await turnOn()
        _ = await ask(search("find"))
        _ = await ask(search("never-matches-secret-words"))
        #expect(module.mcp.entries.map(\.tool) == ["search_clipboard", "search_clipboard"])
        #expect(module.mcp.entries.map(\.outcome) == [.answered(count: 0), .answered(count: 1)])
        #expect(!String(describing: module.mcp.entries).contains("secret-words"))
    }

    @Test func aHelperThatCannotBePlacedIsReportedAndTheSocketOpensAnyway() async throws {
        placed.failure = PlacementFailed()
        await start()
        try await turnOn()
        #expect(module.mcp.helperFailure == "no helper in the bundle")
        #expect(count(of: await ask(search(""))) == 0)
    }

    // MARK: Off again

    @Test func turningItOffClosesTheSocketAtOnceAndTheLogIsKept() async throws {
        await start()
        copy("find me")
        try await turnOn()
        _ = await ask(search("find"))
        let (settings, keys) = try settings()
        settings.set(false, for: keys.mcpEnabled)
        await until { !module.mcpListening }
        #expect(!module.mcpListening)
        #expect(!module.mcp.isListening)
        #expect(await ask(search("find")) == .unreachable)
        #expect(module.mcp.entries.count == 1)
    }

    @Test func theTurnOffNowButtonStopsListeningBeforeAnythingElseHasRun() async throws {
        await start()
        try await turnOn()
        let (settings, keys) = try settings()
        module.turnOffMCPNow(settings: settings)
        // Not after a wait: the socket is gone when the button's action returns.
        #expect(!module.mcpListening)
        #expect(settings.value(keys.mcpEnabled) == false)
        #expect(await ask(search("")) == .unreachable)
    }

    @Test func stoppingTheModuleClosesTheSocketAndStartingItAgainOpensItWhileTheSettingIsOn() async throws {
        await start()
        try await turnOn()
        await harness.registry.setEnabled(false, for: "clipboard")
        #expect(!module.mcpListening)
        #expect(await ask(search("")) == .unreachable)
        await harness.registry.setEnabled(true, for: "clipboard")
        await until { module.mcpListening }
        #expect(module.mcpListening)
        #expect(count(of: await ask(search(""))) != nil)
    }

    @Test func aModuleThatWasSwitchedOffInTheAppListensToNothingEvenWithTheSettingOn() async throws {
        let (settings, keys) = try settings()
        settings.set(true, for: keys.mcpEnabled)
        await harness.registry.setEnabled(false, for: "clipboard")
        await harness.registry.bootstrap()
        #expect(!module.mcpListening)
        #expect(await ask(search("")) == .unreachable)
    }

    // MARK: The default place

    @Test func theSocketNormallyLivesInTheModulesFolder() {
        let storage = URL(filePath: "/tmp/x/clipboard", directoryHint: .isDirectory)
        #expect(ClipboardModule.defaultMCPSocketPath(storage) == "/tmp/x/clipboard/mcp.sock")
    }

    @Test func theAppAndTheHelperAgreeOnWhereTheSocketIs() {
        // The app puts its module folders under its bundle identifier; the helper has no bundle and spells the same path out.
        let storage = StorageRoot.standard(bundleID: "io.lucasvu.mynotch").storage(for: "clipboard").directory
        #expect(ClipboardModule.defaultMCPSocketPath(storage) == ClipboardMCPSocket.defaultPath())
    }

    @Test func theHelperIsPlacedInABinFolderOfTheModulesFolder() {
        let storage = URL(filePath: "/tmp/x/clipboard", directoryHint: .isDirectory)
        #expect(ClipboardMCPHelperFile.destination(in: storage).path == "/tmp/x/clipboard/bin/mynotch-clipboard-mcp")
    }
}
