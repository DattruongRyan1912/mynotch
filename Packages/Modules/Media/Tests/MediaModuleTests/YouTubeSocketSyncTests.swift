import Foundation
import MyNotchCore
import Testing
@testable import MediaModule
@testable import YouTubeBridgeKit

/// The app finds its socket through `ModuleStorage`, the `mynotch-youtube-host` helper through `YouTubeSocket.defaultPath`.
/// They share nothing but a bundle identifier and a module id, so these tests are what keeps the two from drifting.
@Suite struct YouTubeSocketSyncTests {
    let support = URL(filePath: "/Users/example/Library/Application Support", directoryHint: .isDirectory)
    let moduleID = MediaModule(adapterScript: nil, adapterFramework: nil).descriptor.id

    struct ProjectFileError: Error, CustomStringConvertible {
        let description: String
    }

    /// The bundle identifier `project.yml` gives the app target, which is what `Bundle.main.bundleIdentifier` is at run time.
    /// Targets are the two-space-indented keys; the first `PRODUCT_BUNDLE_IDENTIFIER` after `MyNotch:` is the app's.
    static func appBundleID(inProjectFile text: String) -> String? {
        var inApp = false
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("  "), !line.hasPrefix("   ") {
                inApp = line.trimmingCharacters(in: .whitespaces) == "MyNotch:"
            } else if inApp, line.contains("PRODUCT_BUNDLE_IDENTIFIER:") {
                return line.split(separator: ":", maxSplits: 1)[1].trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    /// Looks for `project.yml` in the folders above this file, which is where the repository keeps it.
    static func projectFile(from file: String = #filePath) throws -> String {
        var folder = URL(filePath: file).deletingLastPathComponent()
        while folder.path != "/" {
            if let text = try? String(contentsOf: folder.appending(path: "project.yml"), encoding: .utf8) { return text }
            folder.deleteLastPathComponent()
        }
        throw ProjectFileError(description: "No project.yml above \(file)")
    }

    static func appBundleID() throws -> String {
        guard let id = appBundleID(inProjectFile: try projectFile()) else { throw ProjectFileError(description: "No MyNotch target") }
        return id
    }

    /// What the app does with the support folder: `StorageRoot.standard`'s layout, module storage, then the socket path.
    func appPath(support: URL, bundleID: String, uid: uid_t) -> String {
        let root = StorageRoot(
            applicationSupport: support.appending(path: bundleID, directoryHint: .isDirectory),
            caches: support.appending(path: "Caches", directoryHint: .isDirectory)
        )
        return YouTubeSocket.path(inStorageDirectory: root.storage(for: moduleID).directory, uid: uid)
    }

    @Test func theHelperConnectsWhereTheAppPutsTheModulesStorage() throws {
        let bundleID = try Self.appBundleID()
        let expected = support.path + "/\(bundleID)/Modules/\(moduleID.rawValue)/youtube.sock"
        #expect(appPath(support: support, bundleID: bundleID, uid: 501) == expected)
        #expect(YouTubeSocket.defaultPath(applicationSupport: support, uid: 501) == expected)
    }

    @Test func theStandardRootAndTheHelpersDefaultAgree() throws {
        let storage = StorageRoot.standard(bundleID: try Self.appBundleID()).storage(for: moduleID).directory
        #expect(YouTubeSocket.defaultPath() == YouTubeSocket.path(inStorageDirectory: storage))
    }

    @Test func aSupportFolderThatDoesNotFitMakesBothFallBackToTheSameTemporaryPath() throws {
        let long = URL(filePath: "/Users/" + String(repeating: "x", count: 90) + "/Library/Application Support", directoryHint: .isDirectory)
        let fallback = "/tmp/mynotch-501/youtube.sock"
        #expect(appPath(support: long, bundleID: try Self.appBundleID(), uid: 501) == fallback)
        #expect(YouTubeSocket.defaultPath(applicationSupport: long, uid: 501) == fallback)
    }

    @Test func theHelpersBundleIdentifierIsTheAppsOwn() throws {
        #expect(YouTubeSocket.bundleID == (try Self.appBundleID()))
    }

    @Test func theHelpersModuleIdentifierIsTheModulesOwn() {
        #expect(YouTubeSocket.moduleID == moduleID.rawValue)
    }

    @Test func theAppTargetIsFoundInTheProjectFileEvenAfterTheHelpersTarget() {
        let text = """
        targets:
          mynotch-youtube-host:
            settings:
              base:
                PRODUCT_BUNDLE_IDENTIFIER: io.example.app.youtube-host
          MyNotch:
            settings:
              base:
                PRODUCT_BUNDLE_IDENTIFIER: io.example.app
        """
        #expect(Self.appBundleID(inProjectFile: text) == "io.example.app")
    }

    @Test func theProjectBuildsTheHelperAndBundlesTheExtensionWithoutItsTests() throws {
        let project = try Self.projectFile()
        #expect(project.contains("  mynotch-youtube-host:\n    type: tool"))
        #expect(project.contains("- target: mynotch-youtube-host"))
        #expect(project.contains("- path: Extensions/Chrome/MyNotchYouTube"))
        #expect(project.contains("excludes: [\"tests/**\"]"))
        #expect(project.contains("subpath: ChromeExtension"))
    }
}
