import Foundation
import MyNotchCore
import Testing
@testable import AgentHookKit
@testable import AIAgentsModule

/// The app finds its socket through `ModuleStorage`, the `mynotch-hook` helper through `AgentSocket.defaultPath`.
/// They share nothing but a bundle identifier and a module id, so these tests are what keeps the two from drifting.
@Suite struct AgentSocketSyncTests {
    let support = URL(filePath: "/Users/example/Library/Application Support", directoryHint: .isDirectory)
    let module = AIAgentsModule(
        fileSystem: FakeAgentFileSystem(), claudeRoot: URL(filePath: "/claude"), codexRoot: URL(filePath: "/codex"), opener: FakeOpener().opener
    )

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
    static func appBundleID(from file: String = #filePath) throws -> String {
        var folder = URL(filePath: file).deletingLastPathComponent()
        while folder.path != "/" {
            if let text = try? String(contentsOf: folder.appending(path: "project.yml"), encoding: .utf8),
               let id = appBundleID(inProjectFile: text) {
                return id
            }
            folder.deleteLastPathComponent()
        }
        throw ProjectFileError(description: "No project.yml with a MyNotch target above \(file)")
    }

    /// What the app does with the support folder: `StorageRoot.standard`'s layout, module storage, then the socket path.
    func appPath(support: URL, bundleID: String, uid: uid_t) -> String {
        let root = StorageRoot(
            applicationSupport: support.appending(path: bundleID, directoryHint: .isDirectory),
            caches: support.appending(path: "Caches", directoryHint: .isDirectory)
        )
        return AgentSocket.path(inStorageDirectory: root.storage(for: module.descriptor.id).directory, uid: uid)
    }

    @Test func theHelperSendsWhereTheAppPutsTheModulesStorage() throws {
        let bundleID = try Self.appBundleID()
        let expected = support.path + "/\(bundleID)/Modules/\(module.descriptor.id.rawValue)/agent.sock"
        #expect(appPath(support: support, bundleID: bundleID, uid: 501) == expected)
        #expect(AgentSocket.defaultPath(applicationSupport: support, uid: 501) == expected)
    }

    @Test func theStandardRootAndTheHelpersDefaultAgree() throws {
        let storage = StorageRoot.standard(bundleID: try Self.appBundleID()).storage(for: module.descriptor.id).directory
        #expect(AgentSocket.defaultPath() == AgentSocket.path(inStorageDirectory: storage))
    }

    @Test func aSupportFolderThatDoesNotFitMakesBothFallBackToTheSameTemporaryPath() throws {
        let long = URL(filePath: "/Users/" + String(repeating: "x", count: 90) + "/Library/Application Support", directoryHint: .isDirectory)
        let fallback = "/tmp/mynotch-501/agent.sock"
        #expect(appPath(support: long, bundleID: try Self.appBundleID(), uid: 501) == fallback)
        #expect(AgentSocket.defaultPath(applicationSupport: long, uid: 501) == fallback)
    }

    @Test func theHelpersBundleIdentifierIsTheAppsOwn() throws {
        #expect(AgentSocket.bundleID == (try Self.appBundleID()))
    }

    @Test func theHelpersModuleIdentifierIsTheModulesOwn() {
        #expect(AgentSocket.moduleID == module.descriptor.id.rawValue)
    }

    @Test func theAppTargetIsFoundInTheProjectFileEvenAfterTheHelpersTarget() {
        let text = """
        targets:
          mynotch-hook:
            settings:
              base:
                PRODUCT_BUNDLE_IDENTIFIER: io.example.app.hook
          MyNotch:
            settings:
              base:
                PRODUCT_BUNDLE_IDENTIFIER: io.example.app
                PRODUCT_NAME: MyNotch
          Other:
            settings:
              base:
                PRODUCT_BUNDLE_IDENTIFIER: io.example.app.other
        """
        #expect(Self.appBundleID(inProjectFile: text) == "io.example.app")
        #expect(Self.appBundleID(inProjectFile: "targets:\n  Other:\n    PRODUCT_BUNDLE_IDENTIFIER: x") == nil)
    }
}
