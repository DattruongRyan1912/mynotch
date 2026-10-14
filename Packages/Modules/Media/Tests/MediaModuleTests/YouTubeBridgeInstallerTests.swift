import Foundation
import MyNotchTestSupport
import Testing
import YouTubeBridgeKit
@testable import MediaModule

/// Everything happens in a temporary folder: the "bundle", the app's support folder and the "Chrome" folder are all
/// made here, so no test comes near the real Chrome folder.
@Suite struct YouTubeBridgeInstallerTests {
    let root = ScratchFolders.shared.reserve("youtube-installer")
    let fileManager = FileManager.default

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
    var manifestURL: URL { locations.nativeMessagingHosts.appending(path: "io.lucasvu.mynotch.youtube.json") }

    static let extensionFiles = ["manifest.json": "{\"name\":\"x\"}", "background.js": "// background", "page.js": "// page"]

    /// A bundle with an executable host and the extension folder; `host` false leaves the host out.
    func makeBundle(host: Bool = true, manifest: Bool = true, hostText: String = "#!/bin/sh\nexit 0\n") throws {
        let locations = locations
        try fileManager.createDirectory(at: locations.bundledExtension, withIntermediateDirectories: true)
        for (name, text) in Self.extensionFiles where manifest || name != "manifest.json" {
            try Data(text.utf8).write(to: locations.bundledExtension.appending(path: name))
        }
        if host {
            try fileManager.createDirectory(at: locations.bundledHost.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(hostText.utf8).write(to: locations.bundledHost)
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locations.bundledHost.path)
        }
    }

    func names(in folder: URL) -> [String] {
        ((try? fileManager.contentsOfDirectory(atPath: folder.path)) ?? []).sorted()
    }

    // MARK: install

    @Test func installWritesTheExactHostManifest() throws {
        try makeBundle()
        try installer.install()
        let data = try Data(contentsOf: manifestURL)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(object.keys) == ["name", "description", "path", "type", "allowed_origins"])
        #expect(object["name"] as? String == "io.lucasvu.mynotch.youtube")
        #expect(object["description"] as? String == "MyNotch YouTube captions bridge")
        #expect(object["path"] as? String == locations.installedHost.path)
        #expect(object["type"] as? String == "stdio")
        #expect(object["allowed_origins"] as? [String] == ["chrome-extension://cccjddkmjjmnnccbgokidgbkpblogbnp/"])
        #expect(String(decoding: data, as: UTF8.self).contains(locations.installedHost.path), "the path is not JSON-escaped")
    }

    @Test func theManifestNamesTheExtensionIdItWasGiven() throws {
        try makeBundle()
        try YouTubeBridgeInstaller(locations: locations, extensionID: "abcdefghijklmnopabcdefghijklmnop").install()
        let object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any])
        #expect(object["allowed_origins"] as? [String] == ["chrome-extension://abcdefghijklmnopabcdefghijklmnop/"])
    }

    @Test func installCopiesTheExecutableHostToAStablePath() throws {
        try makeBundle(hostText: "#!/bin/sh\necho host\n")
        try installer.install()
        let installed = locations.installedHost
        #expect(try String(contentsOf: installed, encoding: .utf8) == "#!/bin/sh\necho host\n")
        #expect(fileManager.isExecutableFile(atPath: installed.path))
        #expect(installed.path.hasSuffix("/Modules/media/bin/mynotch-youtube-host"))
    }

    @Test func installCopiesTheExtensionFolderAndReplacesAnOlderCopy() throws {
        try makeBundle()
        let target = locations.installedExtension
        try fileManager.createDirectory(at: target, withIntermediateDirectories: true)
        try Data("old".utf8).write(to: target.appending(path: "stale.js"))
        try Data("old".utf8).write(to: target.appending(path: "page.js"))
        try installer.install()
        #expect(names(in: target) == ["background.js", "manifest.json", "page.js"])
        #expect(try String(contentsOf: target.appending(path: "page.js"), encoding: .utf8) == "// page")
    }

    @Test func installCreatesTheChromeFolderWhenMissing() throws {
        try makeBundle()
        #expect(!fileManager.fileExists(atPath: locations.nativeMessagingHosts.path))
        try installer.install()
        #expect(fileManager.fileExists(atPath: manifestURL.path))
    }

    @Test func installLeavesNoTemporaryFileInTheChromeFolder() throws {
        try makeBundle()
        try installer.install()
        #expect(names(in: locations.nativeMessagingHosts) == ["io.lucasvu.mynotch.youtube.json"])
    }

    @Test func installingAgainChangesNothing() throws {
        try makeBundle()
        try installer.install()
        let manifest = try Data(contentsOf: manifestURL)
        let host = try Data(contentsOf: locations.installedHost)
        try installer.install()
        try installer.install()
        #expect(try Data(contentsOf: manifestURL) == manifest)
        #expect(try Data(contentsOf: locations.installedHost) == host)
        #expect(fileManager.isExecutableFile(atPath: locations.installedHost.path))
        #expect(names(in: locations.installedExtension) == ["background.js", "manifest.json", "page.js"])
        #expect(names(in: locations.nativeMessagingHosts) == ["io.lucasvu.mynotch.youtube.json"])
    }

    @Test func installReplacesAnOlderManifestOfTheSameName() throws {
        try makeBundle()
        try fileManager.createDirectory(at: locations.nativeMessagingHosts, withIntermediateDirectories: true)
        try Data("{\"name\":\"io.lucasvu.mynotch.youtube\",\"path\":\"/old\"}".utf8).write(to: manifestURL)
        try installer.install()
        let object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any])
        #expect(object["path"] as? String == locations.installedHost.path)
    }

    @Test func installLeavesTheOtherFilesInTheChromeFolderAlone() throws {
        try makeBundle()
        let other = locations.nativeMessagingHosts.appending(path: "com.example.other.json")
        try fileManager.createDirectory(at: locations.nativeMessagingHosts, withIntermediateDirectories: true)
        try Data("other host".utf8).write(to: other)
        try installer.install()
        #expect(try String(contentsOf: other, encoding: .utf8) == "other host")
        #expect(names(in: locations.nativeMessagingHosts) == ["com.example.other.json", "io.lucasvu.mynotch.youtube.json"])
    }

    @Test func aMissingOrNonExecutableHostWritesNothing() throws {
        try makeBundle(host: false)
        #expect(throws: YouTubeBridgeInstaller.Unavailable.self) { try installer.install() }
        #expect(!fileManager.fileExists(atPath: locations.nativeMessagingHosts.path))
        #expect(!fileManager.fileExists(atPath: locations.installedExtension.path))

        try makeBundle()
        try fileManager.setAttributes([.posixPermissions: 0o644], ofItemAtPath: locations.bundledHost.path)
        #expect(throws: YouTubeBridgeInstaller.Unavailable.self) { try installer.install() }
        #expect(!fileManager.fileExists(atPath: manifestURL.path))
    }

    @Test func anExtensionFolderWithoutAManifestWritesNothing() throws {
        try makeBundle(manifest: false)
        #expect(throws: YouTubeBridgeInstaller.Unavailable.self) { try installer.install() }
        #expect(!fileManager.fileExists(atPath: locations.nativeMessagingHosts.path))
        #expect(!fileManager.fileExists(atPath: locations.installedHost.path))
    }

    @Test func theErrorsNameWhatIsMissing() {
        let error = YouTubeBridgeInstaller.Unavailable(path: "/x/y")
        #expect(error.errorDescription == "Không tìm thấy /x/y trong app, cần để cài cầu nối.")
    }

    // MARK: remove

    @Test func removeDeletesTheManifestTheHostAndTheExtensionCopyAndNothingElse() throws {
        try makeBundle()
        try installer.install()
        let otherManifest = locations.nativeMessagingHosts.appending(path: "com.example.other.json")
        let otherBin = locations.installedHost.deletingLastPathComponent().appending(path: "other-tool")
        let otherSupport = locations.installedExtension.deletingLastPathComponent().appending(path: "notes.txt")
        for url in [otherManifest, otherBin, otherSupport] { try Data("keep".utf8).write(to: url) }

        try installer.remove()

        #expect(!fileManager.fileExists(atPath: manifestURL.path))
        #expect(!fileManager.fileExists(atPath: locations.installedHost.path))
        #expect(!fileManager.fileExists(atPath: locations.installedExtension.path))
        for url in [otherManifest, otherBin, otherSupport] {
            #expect(try String(contentsOf: url, encoding: .utf8) == "keep", "\(url.lastPathComponent)")
        }
    }

    @Test func removeWithNothingInstalledIsFine() throws {
        try installer.remove()
        try makeBundle()
        try installer.install()
        try installer.remove()
        try installer.remove()
    }

    @Test func removeNeverTouchesTheBundledCopies() throws {
        try makeBundle()
        try installer.install()
        try installer.remove()
        #expect(fileManager.fileExists(atPath: locations.bundledHost.path))
        #expect(fileManager.fileExists(atPath: locations.bundledExtension.appending(path: "manifest.json").path))
    }

    // MARK: state

    @Test func isInstalledNeedsTheManifestAndTheHost() throws {
        try makeBundle()
        #expect(!installer.isInstalled)
        try installer.install()
        #expect(installer.isInstalled)
        try fileManager.removeItem(at: locations.installedHost)
        #expect(!installer.isInstalled)
        try installer.install()
        try fileManager.removeItem(at: manifestURL)
        #expect(!installer.isInstalled)
        try installer.install()
        try installer.remove()
        #expect(!installer.isInstalled)
    }

    // MARK: where things go

    @Test func theSystemLocationsFollowTheAppsStorageAndTheBundle() {
        let support = URL(filePath: "/Users/example/Library/Application Support", directoryHint: .isDirectory)
        let storage = support.appending(path: "io.lucasvu.mynotch/Modules/media", directoryHint: .isDirectory)
        let bundle = URL(filePath: "/Applications/MyNotch.app", directoryHint: .isDirectory)
        let locations = YouTubeBridgeInstaller.Locations.system(storageDirectory: storage, applicationSupport: support, bundle: bundle)
        #expect(locations.bundledHost.path == "/Applications/MyNotch.app/Contents/MacOS/mynotch-youtube-host")
        #expect(locations.bundledExtension.path == "/Applications/MyNotch.app/Contents/Resources/ChromeExtension")
        #expect(locations.installedHost.path == "/Users/example/Library/Application Support/io.lucasvu.mynotch/Modules/media/bin/mynotch-youtube-host")
        #expect(locations.installedExtension.path == "/Users/example/Library/Application Support/io.lucasvu.mynotch/ChromeExtension")
        #expect(locations.nativeMessagingHosts.path == "/Users/example/Library/Application Support/Google/Chrome/NativeMessagingHosts")
    }
}
