import Foundation
import MyNotchTestSupport
import Testing
import YouTubeBridgeKit
@testable import MediaModule

/// The installed Chrome bridge follows the app: everything happens in temporary folders (the "bundle", the support folder and the
/// "Chrome" folder), so no test comes near the real ones.
@Suite struct YouTubeBridgeUpdateTests {
    let root = ScratchFolders.shared.reserve("youtube-update")
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
    var manifestURL: URL { locations.manifest }
    var supportFolder: URL { locations.installedExtension.deletingLastPathComponent() }

    /// The app's copy of the bridge, written from nothing: an extension at `version` (nil: a manifest without one) and a host.
    func writeBundle(version: String? = "0.2.2", hostText: String = "#!/bin/sh\necho v1\n", hostExecutable: Bool = true, extraFiles: [String: String] = [:]) throws {
        let locations = locations
        try? fileManager.removeItem(at: locations.bundledExtension)
        try fileManager.createDirectory(at: locations.bundledExtension, withIntermediateDirectories: true)
        let manifest = version.map { "{\"name\":\"x\",\"version\":\"\($0)\"}" } ?? "{\"name\":\"x\"}"
        var files = ["manifest.json": manifest, "background.js": "// background \(version ?? "-")", "EXTENSION_ID": "cccjddkmjjmnnccbgokidgbkpblogbnp"]
        files.merge(extraFiles) { $1 }
        for (name, text) in files { try Data(text.utf8).write(to: locations.bundledExtension.appending(path: name)) }
        try fileManager.createDirectory(at: locations.bundledHost.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? fileManager.removeItem(at: locations.bundledHost)
        try Data(hostText.utf8).write(to: locations.bundledHost)
        try fileManager.setAttributes([.posixPermissions: hostExecutable ? 0o755 : 0o644], ofItemAtPath: locations.bundledHost.path)
    }

    /// What the user did once: pressed "Cài cầu nối cho Chrome" with an app that had this version and this host.
    func installed(version: String? = "0.1.3", hostText: String = "#!/bin/sh\necho v1\n") throws {
        try writeBundle(version: version, hostText: hostText)
        try installer.install()
    }

    func names(in folder: URL) -> [String] {
        ((try? fileManager.contentsOfDirectory(atPath: folder.path)) ?? []).sorted()
    }

    func text(_ url: URL) -> String? { try? String(contentsOf: url, encoding: .utf8) }

    var installedVersion: String? { YouTubeBridgeInstaller.version(ofExtensionIn: locations.installedExtension) }

    /// Everything under the folders the installer may write, with each file's text: to see that nothing changed.
    func snapshot() -> [String: String] {
        var result: [String: String] = [:]
        for folder in [supportFolder, locations.nativeMessagingHosts] {
            guard let paths = fileManager.enumerator(atPath: folder.path) else { continue }
            for case let path as String in paths {
                result[folder.lastPathComponent + "/" + path] = text(folder.appending(path: path)) ?? "<folder>"
            }
        }
        return result
    }

    // MARK: versions

    @Test func aNewerExtensionInTheAppReplacesTheInstalledCopyAndKeepsItsExtensionID() throws {
        try installed(version: "0.1.3")
        try Data("old".utf8).write(to: locations.installedExtension.appending(path: "stale.js"))
        let manifestBefore = try Data(contentsOf: manifestURL)
        try writeBundle(version: "0.2.2")
        let update = try #require(try installer.updateIfNeeded())
        #expect(update == .init(installedVersion: "0.1.3", bundledVersion: "0.2.2", refreshedExtension: true, refreshedHost: false))
        #expect(installedVersion == "0.2.2")
        #expect(names(in: locations.installedExtension) == ["EXTENSION_ID", "background.js", "manifest.json"], "no file of the old version stays")
        #expect(text(locations.installedExtension.appending(path: "EXTENSION_ID")) == "cccjddkmjjmnnccbgokidgbkpblogbnp")
        #expect(text(locations.installedExtension.appending(path: "background.js")) == "// background 0.2.2")
        #expect(try Data(contentsOf: manifestURL) == manifestBefore, "Chrome's manifest is not written")
        #expect(try installer.updateIfNeeded() == nil, "once is enough")
    }

    @Test func anEqualVersionChangesNothing() throws {
        try installed(version: "0.2.2")
        try Data("marker".utf8).write(to: locations.installedExtension.appending(path: "marker.js"))
        let before = snapshot()
        #expect(try installer.updateIfNeeded() == nil)
        #expect(snapshot() == before)
    }

    @Test func anOlderExtensionInTheAppNeverReplacesANewerCopy() throws {
        try installed(version: "0.3.0")
        try Data("marker".utf8).write(to: locations.installedExtension.appending(path: "marker.js"))
        let before = snapshot()
        try writeBundle(version: "0.2.2")
        #expect(try installer.updateIfNeeded() == nil)
        #expect(snapshot() == before)
        #expect(installedVersion == "0.3.0")
    }

    @Test func versionsAreComparedNumberByNumber() {
        let newer: [(String, String)] = [("0.10.0", "0.9.9"), ("0.2.2", "0.2.1"), ("1.0", "0.99.99"), ("1.0.0.1", "1.0"), ("10.0", "9.0"), ("0.2.10", "0.2.9")]
        for (later, earlier) in newer {
            #expect(YouTubeBridgeInstaller.isNewer(later, than: earlier), "\(later) over \(earlier)")
            #expect(!YouTubeBridgeInstaller.isNewer(earlier, than: later), "\(earlier) over \(later)")
        }
        for same in [("1.0", "1.0.0"), ("0.2.2", "0.2.2"), ("1", "1.0.0.0"), ("0.02", "0.2")] {
            #expect(!YouTubeBridgeInstaller.isNewer(same.0, than: same.1) && !YouTubeBridgeInstaller.isNewer(same.1, than: same.0), "\(same)")
        }
        for notAVersion in ["", "1.", ".1", "1..2", "1.2.3.4.5", "a.b", "1.2-beta", "-1", "1.2 ", "１.０", "1.1234567890"] {
            #expect(YouTubeBridgeInstaller.version(ofExtensionIn: root) == nil)
            #expect(!YouTubeBridgeInstaller.isNewer(notAVersion, than: "0.0.1"), "\(notAVersion.debugDescription) is not newer")
            #expect(!YouTubeBridgeInstaller.isNewer("9.9.9", than: notAVersion), "nothing is newer than \(notAVersion.debugDescription)")
        }
    }

    @Test func aVersionIsReadFromTheManifestOnlyWhenItIsOne() throws {
        let folder = root.appending(path: "versions", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        let manifest = folder.appending(path: "manifest.json")
        let cases: [(String, String?)] = [
            ("{\"version\":\"0.2.2\"}", "0.2.2"), ("{\"version\":\"1.2.3.4\"}", "1.2.3.4"), ("{\"version\":\"0.2.2\\n\"}", nil),
            ("{\"version\":5}", nil), ("{\"version\":\"https://x.example/y\"}", nil), ("{\"name\":\"x\"}", nil), ("[1]", nil), ("not json", nil), ("", nil),
        ]
        for (json, expected) in cases {
            try Data(json.utf8).write(to: manifest)
            #expect(YouTubeBridgeInstaller.version(ofExtensionIn: folder) == expected, "\(json.debugDescription)")
        }
        try fileManager.removeItem(at: manifest)
        #expect(YouTubeBridgeInstaller.version(ofExtensionIn: folder) == nil, "no manifest")
    }

    @Test func aCopyWithNoReadableVersionIsTakenForOldAndReplaced() throws {
        for broken in ["{\"name\":\"x\"}", "not json", ""] {
            try installed(version: "0.2.2")
            try Data(broken.utf8).write(to: locations.installedExtension.appending(path: "manifest.json"))
            try writeBundle(version: "0.2.2")
            let update = try #require(try installer.updateIfNeeded(), "\(broken.debugDescription)")
            #expect(update.installedVersion == nil && update.refreshedExtension)
            #expect(installedVersion == "0.2.2")
        }
        // Not even a manifest in it.
        try installed(version: "0.2.2")
        try fileManager.removeItem(at: locations.installedExtension.appending(path: "manifest.json"))
        #expect(try installer.updateIfNeeded()?.refreshedExtension == true)
        #expect(installedVersion == "0.2.2")
    }

    @Test func anAppWhoseExtensionHasNoReadableVersionTouchesNothing() throws {
        try installed(version: "0.1.3", hostText: "old host")
        try writeBundle(version: nil, hostText: "new host")
        let before = snapshot()
        #expect(try installer.updateIfNeeded() == nil)
        #expect(snapshot() == before, "not the extension, and not the host either: the app's copy is not one to trust")
    }

    // MARK: never installed

    @Test func whenTheUserNeverInstalledTheBridgeNothingIsInstalledOrCreated() throws {
        try writeBundle(version: "0.2.2", hostText: "new host")
        #expect(try installer.updateIfNeeded() == nil)
        #expect(!fileManager.fileExists(atPath: supportFolder.path))
        #expect(!fileManager.fileExists(atPath: locations.installedHost.path))
        #expect(!fileManager.fileExists(atPath: locations.nativeMessagingHosts.path))
        #expect(!installer.wasInstalled)
    }

    @Test func halfAnInstallIsNotAnInstallOfOurs() throws {
        try writeBundle(version: "0.2.2", hostText: "new host")
        // Only the extension folder.
        try fileManager.createDirectory(at: locations.installedExtension, withIntermediateDirectories: true)
        try Data("{\"version\":\"0.1.0\"}".utf8).write(to: locations.installedExtension.appending(path: "manifest.json"))
        #expect(try installer.updateIfNeeded() == nil)
        #expect(!fileManager.fileExists(atPath: locations.installedHost.path))
        // Only Chrome's manifest (someone else's, or what is left of one).
        try fileManager.removeItem(at: locations.installedExtension)
        try fileManager.createDirectory(at: locations.nativeMessagingHosts, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: manifestURL)
        #expect(try installer.updateIfNeeded() == nil)
        #expect(!fileManager.fileExists(atPath: locations.installedExtension.path))
        #expect(!fileManager.fileExists(atPath: locations.installedHost.path))
        // The extension "folder" is a file.
        try fileManager.createDirectory(at: supportFolder, withIntermediateDirectories: true)
        try Data("a file".utf8).write(to: locations.installedExtension)
        #expect(try installer.updateIfNeeded() == nil)
        #expect(text(locations.installedExtension) == "a file")
        #expect(!installer.wasInstalled)
    }

    @Test func removingTheBridgeMakesItNeverInstalledAgain() throws {
        try installed()
        #expect(installer.wasInstalled)
        try installer.remove()
        try writeBundle(version: "0.9.9", hostText: "newer host")
        #expect(try installer.updateIfNeeded() == nil)
        #expect(!installer.wasInstalled)
        #expect(!fileManager.fileExists(atPath: locations.installedHost.path))
    }

    // MARK: the host

    @Test func aHostThatDiffersFromTheAppsIsReplacedAndTheExtensionOfTheSameVersionIsLeftAlone() throws {
        try installed(version: "0.2.2", hostText: "#!/bin/sh\necho v1\n")
        try Data("marker".utf8).write(to: locations.installedExtension.appending(path: "marker.js"))
        let manifestBefore = try Data(contentsOf: manifestURL)
        try writeBundle(version: "0.2.2", hostText: "#!/bin/sh\necho v2\n")
        let update = try #require(try installer.updateIfNeeded())
        #expect(update == .init(installedVersion: "0.2.2", bundledVersion: "0.2.2", refreshedExtension: false, refreshedHost: true))
        #expect(text(locations.installedHost) == "#!/bin/sh\necho v2\n")
        #expect(fileManager.isExecutableFile(atPath: locations.installedHost.path), "still runnable: Chrome starts it")
        #expect(text(locations.installedExtension.appending(path: "marker.js")) == "marker", "the extension folder was not touched")
        #expect(try Data(contentsOf: manifestURL) == manifestBefore)
        #expect(names(in: locations.installedHost.deletingLastPathComponent()) == ["mynotch-youtube-host"], "nothing left beside it")
        #expect(try installer.updateIfNeeded() == nil)
    }

    @Test func aHostOfTheSameSizeButOtherBytesIsReplacedToo() throws {
        try installed(version: "0.2.2", hostText: "#!/bin/sh\necho v1\n")
        try writeBundle(version: "0.2.2", hostText: "#!/bin/sh\necho v2\n")
        #expect(try installer.updateIfNeeded()?.refreshedHost == true)
        #expect(text(locations.installedHost) == "#!/bin/sh\necho v2\n")
    }

    @Test func aMissingHostIsPutBack() throws {
        try installed(version: "0.2.2")
        try fileManager.removeItem(at: locations.installedHost)
        let update = try #require(try installer.updateIfNeeded())
        #expect(update.refreshedHost && !update.refreshedExtension)
        #expect(fileManager.isExecutableFile(atPath: locations.installedHost.path))
    }

    @Test func bothAreRefreshedWhenBothAreOld() throws {
        try installed(version: "0.1.3", hostText: "old host")
        try writeBundle(version: "0.2.2", hostText: "new host")
        let update = try #require(try installer.updateIfNeeded())
        #expect(update.refreshedExtension && update.refreshedHost)
        #expect(installedVersion == "0.2.2")
        #expect(text(locations.installedHost) == "new host")
    }

    @Test func aHostTheAppCannotRunIsNotCopiedOverOneThatWorks() throws {
        try installed(version: "0.1.3", hostText: "#!/bin/sh\necho v1\n")
        try writeBundle(version: "0.2.2", hostText: "#!/bin/sh\necho v2\n", hostExecutable: false)
        let update = try #require(try installer.updateIfNeeded())
        #expect(update.refreshedExtension && !update.refreshedHost)
        #expect(text(locations.installedHost) == "#!/bin/sh\necho v1\n")
        #expect(fileManager.isExecutableFile(atPath: locations.installedHost.path))
    }

    // MARK: the swap survives a failed copy

    @Test func aCopyOfTheExtensionThatFailsLeavesTheOldCopyAndNothingBehind() throws {
        try installed(version: "0.1.3")
        try Data("marker".utf8).write(to: locations.installedExtension.appending(path: "marker.js"))
        try writeBundle(version: "0.2.2", extraFiles: ["unreadable.js": "secret"])
        let unreadable = locations.bundledExtension.appending(path: "unreadable.js")
        try fileManager.setAttributes([.posixPermissions: 0o000], ofItemAtPath: unreadable.path)
        defer { try? fileManager.setAttributes([.posixPermissions: 0o644], ofItemAtPath: unreadable.path) }
        let before = snapshot()
        #expect(throws: (any Error).self) { try installer.updateIfNeeded() }
        #expect(snapshot() == before, "the old copy is whole, with its version, and no half copy is left")
        #expect(installedVersion == "0.1.3")
        #expect(names(in: supportFolder) == ["ChromeExtension", "Modules"])
        // Once the app's copy can be read the update goes through.
        try fileManager.setAttributes([.posixPermissions: 0o644], ofItemAtPath: unreadable.path)
        #expect(try installer.updateIfNeeded()?.refreshedExtension == true)
        #expect(installedVersion == "0.2.2")
    }

    @Test func aCopyOfTheHostThatFailsLeavesTheOldHostRunnableAndNothingBehind() throws {
        try installed(version: "0.2.2", hostText: "#!/bin/sh\necho v1\n")
        try writeBundle(version: "0.2.2", hostText: "#!/bin/sh\necho v2\n")
        // Runnable but not readable: the copy fails.
        try fileManager.setAttributes([.posixPermissions: 0o111], ofItemAtPath: locations.bundledHost.path)
        defer { try? fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locations.bundledHost.path) }
        let before = snapshot()
        #expect(throws: (any Error).self) { try installer.updateIfNeeded() }
        #expect(snapshot() == before)
        #expect(text(locations.installedHost) == "#!/bin/sh\necho v1\n")
        #expect(fileManager.isExecutableFile(atPath: locations.installedHost.path))
        #expect(names(in: locations.installedHost.deletingLastPathComponent()) == ["mynotch-youtube-host"])
    }

    @Test func whatAnEarlierRunLeftBesideTheCopyIsCleanedAndOtherFilesAreNot() throws {
        try installed(version: "0.1.3", hostText: "old host")
        let leftovers = [".ChromeExtension.update-AAA", ".mynotch-youtube-host.update-BBB"]
        try fileManager.createDirectory(at: supportFolder.appending(path: leftovers[0]), withIntermediateDirectories: true)
        try Data("half".utf8).write(to: locations.installedHost.deletingLastPathComponent().appending(path: leftovers[1]))
        for name in ["notes.txt", "ChromeExtension.bak", ".other.update-CCC"] { try Data("keep".utf8).write(to: supportFolder.appending(path: name)) }
        try writeBundle(version: "0.2.2", hostText: "new host")
        #expect(try installer.updateIfNeeded() != nil)
        #expect(names(in: supportFolder) == [".other.update-CCC", "ChromeExtension", "ChromeExtension.bak", "Modules", "notes.txt"])
        #expect(names(in: locations.installedHost.deletingLastPathComponent()) == ["mynotch-youtube-host"])
    }

    @Test func installingAndUpdatingLeaveNoTemporaryNameInTheSupportFolder() throws {
        try installed(version: "0.1.3", hostText: "old host")
        #expect(names(in: supportFolder) == ["ChromeExtension", "Modules"])
        try writeBundle(version: "0.2.2", hostText: "new host")
        _ = try installer.updateIfNeeded()
        #expect(names(in: supportFolder) == ["ChromeExtension", "Modules"])
    }
}
