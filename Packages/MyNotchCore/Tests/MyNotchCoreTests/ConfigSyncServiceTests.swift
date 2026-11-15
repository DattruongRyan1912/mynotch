import Foundation
import Testing
@testable import MyNotchCore
import MyNotchTestSupport

@Suite struct ConfigSyncServiceTests {
    @Test func resolvesStandardAndXdgPaths() {
        let fakeHome = URL(fileURLWithPath: "/Users/testuser", isDirectory: true)

        // Case 1: Standard .config/mynotch/config.toml exists
        let standardURL = ConfigPaths.resolve(
            homeDirectory: fakeHome,
            environment: [:],
            fileExists: { path in path == "/Users/testuser/.config/mynotch/config.toml" }
        )
        #expect(standardURL.path == "/Users/testuser/.config/mynotch/config.toml")

        // Case 2: XDG_CONFIG_HOME set, ~/.config exists but ~/.config/mynotch does NOT exist
        let xdgURL = ConfigPaths.resolve(
            homeDirectory: fakeHome,
            environment: ["XDG_CONFIG_HOME": "/custom/xdg"],
            fileExists: { path in path == "/Users/testuser/.config" }
        )
        #expect(xdgURL.path == "/custom/xdg/mynotch/config.toml")
    }

    @Test func bootstrapCreatesStarterFileWithoutOverwritingDefaults() throws {
        let folder = ScratchFolders.shared.reserve("config-sync-bootstrap")
        let configFile = folder.appendingPathComponent("config.toml")
        let defaults = makeIsolatedDefaults()
        let store = SettingsStore(defaults: defaults)

        let service = ConfigSyncService(
            settings: store,
            configFileURL: configFile,
            scheduler: ManualScheduler()
        )
        service.bootstrap(startWatching: false)

        #expect(FileManager.default.fileExists(atPath: configFile.path))
        let content = try String(contentsOf: configFile, encoding: .utf8)
        #expect(content.contains("# MyNotch Configuration (config.toml)"))
        #expect(content.contains("# openDelayMs = 150"))
        #expect(content.contains("[interface]"))
        #expect(content.contains("[module.clipboard]"))
        #expect(content.contains("[module.pet]"))
    }

    @Test func reloadsSettingsFromTOMLIntoSettingsStore() throws {
        let folder = ScratchFolders.shared.reserve("config-sync-reload")
        let configFile = folder.appendingPathComponent("config.toml")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let toml = """
        [app]
        showMenuBarIcon = false
        "permissionIdentity" = "hacked_signature"

        [app.menuBarHider]
        autoCollapseSeconds = 7

        [interface]
        openDelayMs = 220
        clampedDelay = 9999

        [module.clipboard]
        historyLimit = 750
        """
        try toml.write(to: configFile, atomically: true, encoding: .utf8)

        let defaults = makeIsolatedDefaults()
        let store = SettingsStore(defaults: defaults)
        let openKey = SettingKey("interface.openDelayMs", default: 150)
        let clampedKey = SettingKey("interface.clampedDelay", default: 300, clampedTo: 0...1000)
        let iconKey = SettingKey("app.showMenuBarIcon", default: true)
        let hiderKey = SettingKey("app.menuBarHider.autoCollapseSeconds", default: 0)
        let clipCountKey = SettingKey("module.clipboard.historyLimit", default: 500)
        let identityKey = SettingKey("app.permissionIdentity", default: "safe")

        let service = ConfigSyncService(
            settings: store,
            configFileURL: configFile,
            scheduler: ManualScheduler()
        )
        let ok = service.reload()

        #expect(ok == true)
        #expect(service.lastLoadError == nil)
        #expect(store.value(openKey) == 220)
        #expect(store.value(clampedKey) == 1000)
        #expect(store.value(iconKey) == false)
        #expect(store.value(hiderKey) == 7)
        #expect(store.value(clipCountKey) == 750)
        // app.permissionIdentity must be rejected/ignored
        #expect(store.value(identityKey) == "safe")
    }

    @Test func handlesSyntaxErrorGracefully() throws {
        let folder = ScratchFolders.shared.reserve("config-sync-err")
        let configFile = folder.appendingPathComponent("config.toml")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let initialToml = """
        [interface]
        openDelayMs = 200
        """
        try initialToml.write(to: configFile, atomically: true, encoding: .utf8)

        let defaults = makeIsolatedDefaults()
        let store = SettingsStore(defaults: defaults)
        let key = SettingKey("interface.openDelayMs", default: 150)

        let service = ConfigSyncService(
            settings: store,
            configFileURL: configFile,
            scheduler: ManualScheduler()
        )
        #expect(service.reload() == true)
        #expect(store.value(key) == 200)

        // Corrupt file with syntax error
        let brokenToml = "[interface\nopenDelayMs = @"
        try brokenToml.write(to: configFile, atomically: true, encoding: .utf8)

        #expect(service.reload() == false)
        #expect(service.lastLoadError != nil)
        // Value in store remains preserved
        #expect(store.value(key) == 200)

        // Fix file
        let fixedToml = """
        [interface]
        openDelayMs = 350
        """
        try fixedToml.write(to: configFile, atomically: true, encoding: .utf8)

        #expect(service.reload() == true)
        #expect(service.lastLoadError == nil)
        #expect(store.value(key) == 350)
    }

    @Test func exportCurrentSettingsMatchesRoundTrip() throws {
        let folder = ScratchFolders.shared.reserve("config-sync-export")
        let configFile = folder.appendingPathComponent("config.toml")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let defaults = makeIsolatedDefaults()
        let store = SettingsStore(defaults: defaults)
        let key1 = SettingKey("interface.openDelayMs", default: 150)
        let key2 = SettingKey("app.showMenuBarIcon", default: true)
        let keyHider = SettingKey("app.menuBarHider.autoCollapseSeconds", default: 10)
        let keyHistory = SettingKey("module.clipboard.historyLimit", default: 500)
        let keyClickAction = SettingKey("module.clipboard.clickAction", default: "paste")
        let keyPair = SettingKey<[String: String]>("module.translation.preferredPair", default: ["first": "vi", "second": "en"])

        store.set(180, for: key1)
        store.set(false, for: key2)
        store.set(25, for: keyHider)
        store.set(750, for: keyHistory)
        store.set("copy", for: keyClickAction)
        store.set(["first": "en", "second": "ja"], for: keyPair)

        let service = ConfigSyncService(
            settings: store,
            configFileURL: configFile,
            scheduler: ManualScheduler()
        )
        let exported = try service.exportCurrentSettings()

        #expect(exported.contains("openDelayMs = 180"))
        #expect(exported.contains("showMenuBarIcon = false"))
        #expect(exported.contains("autoCollapseSeconds = 25"))
        #expect(exported.contains("historyLimit = 750"))
        #expect(exported.contains("clickAction = \"copy\""))
        #expect(exported.contains("[module.clipboard]"))
        #expect(exported.contains("# [interface]"))
        #expect(!exported.contains("[module]\n"))

        // Import into second store
        let defaults2 = makeIsolatedDefaults()
        let store2 = SettingsStore(defaults: defaults2)
        let service2 = ConfigSyncService(
            settings: store2,
            configFileURL: configFile,
            scheduler: ManualScheduler()
        )
        #expect(service2.reload() == true)
        #expect(store2.value(key1) == 180)
        #expect(store2.value(key2) == false)
        #expect(store2.value(keyHider) == 25)
        #expect(store2.value(keyHistory) == 750)
        #expect(store2.value(keyClickAction) == "copy")
        #expect(store2.value(keyPair) == ["first": "en", "second": "ja"])
    }

    @Test func liveReloadsAcrossMultipleAtomicSaves() async throws {
        let folder = ScratchFolders.shared.reserve("config-sync-multi-atomic")
        let configFile = folder.appendingPathComponent("config.toml")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let initialToml = """
        [interface]
        openDelayMs = 100
        """
        try initialToml.write(to: configFile, atomically: true, encoding: .utf8)

        let defaults = makeIsolatedDefaults()
        let store = SettingsStore(defaults: defaults)
        let key = SettingKey("interface.openDelayMs", default: 150)

        nonisolated(unsafe) var reloadCount = 0
        let service = ConfigSyncService(
            settings: store,
            configFileURL: configFile,
            scheduler: TaskScheduler(),
            debounceInterval: .milliseconds(50),
            onReload: { _ in reloadCount += 1 }
        )
        service.bootstrap(startWatching: true)
        #expect(store.value(key) == 100)

        // Helper to wait under heavy parallel test load
        func waitUntil(timeoutMs: Int = 2000, condition: @MainActor () -> Bool) async -> Bool {
            let start = Date()
            while Date().timeIntervalSince(start) < Double(timeoutMs) / 1000.0 {
                if condition() { return true }
                try? await Task.sleep(for: .milliseconds(25))
            }
            return condition()
        }

        // 1st atomic save (100 -> 450)
        let save1 = """
        [interface]
        openDelayMs = 450
        """
        try save1.write(to: configFile, atomically: true, encoding: .utf8)
        let matched1 = await waitUntil { store.value(key) == 450 }
        #expect(matched1 == true)

        // 2nd atomic save (450 -> 750)
        let save2 = """
        [interface]
        openDelayMs = 750
        """
        try save2.write(to: configFile, atomically: true, encoding: .utf8)
        let matched2 = await waitUntil { store.value(key) == 750 }
        #expect(matched2 == true)
        #expect(reloadCount >= 2)

        service.stopWatching()
    }
}
