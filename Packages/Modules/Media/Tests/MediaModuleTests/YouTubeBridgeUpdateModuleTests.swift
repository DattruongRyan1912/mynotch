import Foundation
import MyNotchCore
import MyNotchTestSupport
import Testing
import YouTubeBridgeKit
@testable import MediaModule

/// What the module does at its start for a bridge that was installed before, with folders of the test's own.
@Suite final class YouTubeBridgeUpdateModuleTests {
    let root = ScratchFolders.shared.reserve("youtube-update-module")
    let fileManager = FileManager.default
    let log = LogRecorder()

    var locations: YouTubeBridgeInstaller.Locations {
        YouTubeBridgeInstaller.Locations(
            bundledHost: root.appending(path: "App.app/Contents/MacOS/mynotch-youtube-host"),
            bundledExtension: root.appending(path: "App.app/Contents/Resources/ChromeExtension", directoryHint: .isDirectory),
            installedHost: root.appending(path: "support/Modules/media/bin/mynotch-youtube-host"),
            installedExtension: root.appending(path: "support/ChromeExtension", directoryHint: .isDirectory),
            nativeMessagingHosts: root.appending(path: "chrome/NativeMessagingHosts", directoryHint: .isDirectory)
        )
    }

    var installer: YouTubeBridgeInstaller { YouTubeBridgeInstaller(locations: locations) }

    func writeBundle(version: String, host: String = "#!/bin/sh\necho v1\n") throws {
        let locations = locations
        try? fileManager.removeItem(at: locations.bundledExtension)
        try fileManager.createDirectory(at: locations.bundledExtension, withIntermediateDirectories: true)
        try Data("{\"name\":\"x\",\"version\":\"\(version)\"}".utf8).write(to: locations.bundledExtension.appending(path: "manifest.json"))
        try fileManager.createDirectory(at: locations.bundledHost.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? fileManager.removeItem(at: locations.bundledHost)
        try Data(host.utf8).write(to: locations.bundledHost)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locations.bundledHost.path)
    }

    /// The module with the bridge's folders of this test; `updates` is what the app's own module has on and a test's has off.
    func makeModule(updates: Bool = true) -> (module: MediaModule, harness: RegistryHarness) {
        let module = MediaModule(
            source: FakeNowPlayingSource(), spectrum: FakeSpectrumSource(), lyricsClient: FakeHTTPClient(), tokens: FakeTokenStore(),
            signIn: FakeAppleMusicSignIn(), lookUpApp: { _ in nil },
            youtubeSetup: YouTubeBridgeSetup(installer: installer, reveal: { _ in }), youtubeLog: log.log,
            updatesInstalledBridge: updates
        )
        return (module, RegistryHarness([module]))
    }

    func installedVersion() -> String? { YouTubeBridgeInstaller.version(ofExtensionIn: locations.installedExtension) }

    @Test func aBridgeInstalledByAnOlderAppIsUpdatedAtTheStartAndTheUserIsToldOnceInTheToastAndInSettings() async throws {
        try writeBundle(version: "0.1.3")
        try installer.install()
        try writeBundle(version: "0.2.2")
        let (module, harness) = makeModule()
        await harness.registry.bootstrap()
        #expect(installedVersion() == "0.2.2")
        #expect(harness.presenter.toastCount == 1)
        let message = "Đã cập nhật cầu nối Chrome lên 0.2.2 — tải lại extension trong chrome://extensions"
        #expect(YouTubeBridgeModel.updateMessage(version: "0.2.2") == message)
        #expect(module.youtubeBridge.updateNotice == message)
        #expect(log.lines(containing: "bridge updated") == ["bridge updated extension=0.1.3 now=0.2.2 host=same"])
        // The app's own folders and versions only: no path, no address.
        log.expectNothingPrivate([root.path, NSHomeDirectory(), "ChromeExtension", "Application Support"])
        // Starting again changes nothing and says nothing.
        await harness.registry.shutdown()
        await harness.registry.bootstrap()
        #expect(harness.presenter.toastCount == 1)
        #expect(log.lines(containing: "bridge updated").count == 1)
    }

    @Test func aHostThatDiffersIsUpdatedWithTheSameNotice() async throws {
        try writeBundle(version: "0.2.2", host: "#!/bin/sh\necho v1\n")
        try installer.install()
        try writeBundle(version: "0.2.2", host: "#!/bin/sh\necho v2\n")
        let (module, harness) = makeModule()
        await harness.registry.bootstrap()
        #expect(try String(contentsOf: locations.installedHost, encoding: .utf8) == "#!/bin/sh\necho v2\n")
        #expect(harness.presenter.toastCount == 1)
        #expect(module.youtubeBridge.updateNotice == YouTubeBridgeModel.updateMessage(version: "0.2.2"))
        #expect(log.lines(containing: "bridge updated") == ["bridge updated extension=0.2.2 now=0.2.2 host=refreshed"])
    }

    @Test func aBridgeThatIsUpToDateOrNewerSaysNothing() async throws {
        try writeBundle(version: "0.2.2")
        try installer.install()
        let (module, harness) = makeModule()
        await harness.registry.bootstrap()
        #expect(harness.presenter.toastCount == 0)
        #expect(module.youtubeBridge.updateNotice == nil)
        #expect(log.lines.isEmpty)
        await harness.registry.shutdown()
        try writeBundle(version: "0.1.0")
        await harness.registry.bootstrap()
        #expect(installedVersion() == "0.2.2")
        #expect(harness.presenter.toastCount == 0)
    }

    @Test func forAUserWhoNeverInstalledTheBridgeNothingHappensAndNothingIsCreated() async throws {
        try writeBundle(version: "0.2.2")
        let (module, harness) = makeModule()
        await harness.registry.bootstrap()
        #expect(harness.presenter.toastCount == 0)
        #expect(module.youtubeBridge.updateNotice == nil)
        #expect(log.lines.isEmpty)
        #expect(!fileManager.fileExists(atPath: locations.installedExtension.path))
        #expect(!fileManager.fileExists(atPath: locations.installedHost.path))
        #expect(!fileManager.fileExists(atPath: locations.nativeMessagingHosts.path))
    }

    @Test func aModuleMadeForATestNeverTouchesAnInstallUnlessAskedTo() async throws {
        try writeBundle(version: "0.1.3")
        try installer.install()
        try writeBundle(version: "0.2.2", host: "#!/bin/sh\necho v2\n")
        let (module, harness) = makeModule(updates: false)
        await harness.registry.bootstrap()
        #expect(installedVersion() == "0.1.3")
        #expect(harness.presenter.toastCount == 0)
        #expect(module.youtubeBridge.updateNotice == nil)
        #expect(log.lines.isEmpty)
    }

    @Test func aCopyThatFailsIsLoggedByNumberOnlyAndTheUserIsNotToldOfAnUpdate() async throws {
        try writeBundle(version: "0.1.3")
        try installer.install()
        try writeBundle(version: "0.2.2")
        let unreadable = locations.bundledExtension.appending(path: "unreadable.js")
        try Data("x".utf8).write(to: unreadable)
        try fileManager.setAttributes([.posixPermissions: 0o000], ofItemAtPath: unreadable.path)
        defer { try? fileManager.setAttributes([.posixPermissions: 0o644], ofItemAtPath: unreadable.path) }
        let (module, harness) = makeModule()
        await harness.registry.bootstrap()
        #expect(installedVersion() == "0.1.3", "the old copy is kept")
        #expect(harness.presenter.toastCount == 0)
        #expect(module.youtubeBridge.updateNotice == nil)
        let failures = log.lines(containing: "bridge update failed")
        #expect(failures.count == 1)
        #expect(failures.first?.hasPrefix("bridge update failed code=") == true)
        log.expectNothingPrivate([root.path, "unreadable", "ChromeExtension"])
        // The module still started: its source is running.
        #expect(module.store.state == .empty)
    }

    @Test func updatingNeverTouchesChromesManifestFolder() async throws {
        try writeBundle(version: "0.1.3")
        try installer.install()
        let manifest = locations.manifest
        let before = try Data(contentsOf: manifest)
        let modified = try #require(fileManager.attributesOfItem(atPath: manifest.path)[.modificationDate] as? Date)
        try writeBundle(version: "0.2.2", host: "#!/bin/sh\necho v2\n")
        let (_, harness) = makeModule()
        await harness.registry.bootstrap()
        #expect(try Data(contentsOf: manifest) == before)
        #expect(try fileManager.attributesOfItem(atPath: manifest.path)[.modificationDate] as? Date == modified)
        #expect((try fileManager.contentsOfDirectory(atPath: locations.nativeMessagingHosts.path)).sorted() == ["io.lucasvu.mynotch.youtube.json"])
    }
}
